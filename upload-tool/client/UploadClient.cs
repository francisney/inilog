using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace InilogUpload
{
    public sealed class UploadProgress
    {
        public long Sent { get; set; }
        public long Total { get; set; }
        public bool Verifying { get; set; }
        public int Percent { get { return Verifying ? 99 : (int)Math.Min(99, Total == 0 ? 0 : (100.0 * Sent / Total)); } }
    }
    public sealed class UploadResult
    {
        public string Url { get; set; }
        public string Sha256 { get; set; }
        public long Size { get; set; }
    }
    public sealed class UploadClient
    {
        public const string ProductionEndpoint = "https://inilog.com/backup/index.php";
        private readonly Uri endpoint;
        private readonly JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength = 65536 };
        public UploadClient() : this(new Uri(ProductionEndpoint)) { }
        public UploadClient(Uri endpoint)
        {
            if (endpoint == null || (endpoint.Scheme != "https" && !(endpoint.Scheme == "http" && endpoint.IsLoopback)))
                throw new ArgumentException("O endereço de envio precisa usar HTTPS.");
            this.endpoint = endpoint;
        }
        private static string Hash(byte[] bytes, int count)
        {
            using (SHA256 hash = SHA256.Create()) return Hex(hash.ComputeHash(bytes, 0, count));
        }
        private static string Hex(byte[] value) { return BitConverter.ToString(value).Replace("-", "").ToLowerInvariant(); }
        private Uri Action(string action) { return new Uri(endpoint.AbsoluteUri + "?api=" + action); }
        private async Task<Dictionary<string, object>> Request(string action, byte[] bytes, int count, string token, string chunkHash, CancellationToken cancellation, Action<int> sent, bool retry)
        {
            int attempts = retry ? 3 : 1;
            for (int attempt = 0; ; attempt++)
            {
                cancellation.ThrowIfCancellationRequested();
                HttpWebRequest request = (HttpWebRequest)WebRequest.Create(Action(action));
                request.Method = "POST"; request.AllowAutoRedirect = false;
                request.UserAgent = "INILOG-Upload/1.0 (Windows)";
                request.Accept = "application/json";
                request.ContentType = chunkHash == null ? "application/json; charset=utf-8" : "application/octet-stream";
                request.ContentLength = count; request.AllowWriteStreamBuffering = false; request.SendChunked = false;
                request.Timeout = 180000; request.ReadWriteTimeout = 180000;
                request.ServicePoint.Expect100Continue = false;
                if (token != null) request.Headers["X-Inilog-Token"] = token;
                if (chunkHash != null) request.Headers["X-Inilog-Chunk-SHA256"] = chunkHash;
                using (cancellation.Register(delegate { request.Abort(); }))
                using (Timer timeout = new Timer(delegate { try { request.Abort(); } catch (Exception) { } }, null, 180000, Timeout.Infinite))
                {
                    try
                    {
                        using (Stream output = await request.GetRequestStreamAsync().ConfigureAwait(false))
                        {
                            int offset = 0;
                            while (offset < count)
                            {
                                int length = Math.Min(65536, count - offset);
                                await output.WriteAsync(bytes, offset, length, cancellation).ConfigureAwait(false);
                                offset += length; if (sent != null) sent(offset);
                            }
                        }
                        using (HttpWebResponse response = (HttpWebResponse)await request.GetResponseAsync().ConfigureAwait(false))
                        {
                            if ((int)response.StatusCode < 200 || (int)response.StatusCode >= 300) throw new IOException("A hospedagem recusou o envio.");
                            using (StreamReader input = new StreamReader(response.GetResponseStream(), Encoding.UTF8))
                            {
                                string text = await input.ReadToEndAsync().ConfigureAwait(false);
                                if (text.Length > 65536) throw new IOException("Resposta inválida da hospedagem.");
                                Dictionary<string, object> value;
                                try { value = json.Deserialize<Dictionary<string, object>>(text); }
                                catch (Exception) { throw new IOException("A hospedagem não respondeu como esperado. Tente novamente."); }
                                if (value == null || !value.ContainsKey("ok") || !Convert.ToBoolean(value["ok"], CultureInfo.InvariantCulture))
                                    throw new IOException(value != null && value.ContainsKey("error") ? Convert.ToString(value["error"], CultureInfo.InvariantCulture) : "Não foi possível concluir o envio.");
                                return value;
                            }
                        }
                    }
                    catch (WebException error)
                    {
                        if (cancellation.IsCancellationRequested) throw new OperationCanceledException(cancellation);
                        HttpWebResponse response = error.Response as HttpWebResponse;
                        int status = response == null ? 0 : (int)response.StatusCode;
                        bool transient = response == null || status == 408 || status == 429 || status >= 500;
                        if (transient && attempt + 1 < attempts)
                        {
                            if (response != null) response.Dispose();
                            await Task.Delay(1000 * (attempt + 1), cancellation).ConfigureAwait(false); continue;
                        }
                        string message = "Não foi possível conectar à hospedagem. Verifique a conexão e tente novamente.";
                        if (response != null)
                        {
                            try
                            {
                                using (StreamReader reader = new StreamReader(response.GetResponseStream(), Encoding.UTF8))
                                {
                                    string text = await reader.ReadToEndAsync().ConfigureAwait(false);
                                    if (text.Length < 65536)
                                    {
                                        Dictionary<string, object> value = json.Deserialize<Dictionary<string, object>>(text);
                                        if (value != null && value.ContainsKey("error")) message = Convert.ToString(value["error"], CultureInfo.InvariantCulture);
                                    }
                                }
                            }
                            catch (Exception) { message = "A hospedagem recusou o envio. Tente novamente mais tarde."; }
                            finally { response.Dispose(); }
                        }
                        throw new IOException(message, error);
                    }
                }
            }
        }
        private Task<Dictionary<string, object>> JsonRequest(string action, object value, string token, CancellationToken cancellation, bool retry)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(json.Serialize(value));
            return Request(action, bytes, bytes.Length, token, null, cancellation, null, retry);
        }
        public async Task<UploadResult> UploadAsync(string filePath, IProgress<UploadProgress> progress, CancellationToken cancellation)
        {
            string id = null, token = null; bool completed = false;
            try
            {
                using (FileStream file = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read, 65536, FileOptions.SequentialScan | FileOptions.Asynchronous))
                using (SHA256 fullHash = SHA256.Create())
                {
                    long total = file.Length;
                    Dictionary<string, object> init = await JsonRequest("init", new { name = Path.GetFileName(filePath), size = total }, null, cancellation, false).ConfigureAwait(false);
                    id = Convert.ToString(init["id"], CultureInfo.InvariantCulture); token = Convert.ToString(init["token"], CultureInfo.InvariantCulture);
                    if (!Regex.IsMatch(id, "\\A[a-f0-9]{32}\\z") || !Regex.IsMatch(token, "\\A[a-f0-9]{64}\\z")) throw new IOException("A hospedagem retornou um envio inválido.");
                    int chunkBytes = Convert.ToInt32(init["chunk_bytes"], CultureInfo.InvariantCulture);
                    if (chunkBytes < 65536 || chunkBytes > 8 * 1024 * 1024) throw new IOException("O tamanho dos blocos retornado pela hospedagem é inválido.");
                    byte[] buffer = new byte[chunkBytes]; long offset = 0;
                    while (offset < total)
                    {
                        int read = 0; int need = (int)Math.Min(chunkBytes, total - offset);
                        while (read < need)
                        {
                            int n = await file.ReadAsync(buffer, read, need - read, cancellation).ConfigureAwait(false);
                            if (n == 0) throw new IOException("O arquivo original mudou durante o envio. Selecione-o novamente.");
                            read += n;
                        }
                        long start = offset; int length = read;
                        Dictionary<string, object> result = await Request("chunk&id=" + id + "&offset=" + offset.ToString(CultureInfo.InvariantCulture), buffer, read, token, Hash(buffer, read), cancellation,
                            delegate(int sent) { if (progress != null) progress.Report(new UploadProgress { Sent = start + sent, Total = total }); }, true).ConfigureAwait(false);
                        long next = Convert.ToInt64(result["offset"], CultureInfo.InvariantCulture);
                        if (next != offset + read) throw new IOException("O servidor não confirmou todos os dados enviados.");
                        fullHash.TransformBlock(buffer, 0, read, buffer, 0); offset = next;
                    }
                    fullHash.TransformFinalBlock(new byte[0], 0, 0);
                    string digest = Hex(fullHash.Hash);
                    if (progress != null) progress.Report(new UploadProgress { Sent = total, Total = total, Verifying = true });
                    Dictionary<string, object> finish = await JsonRequest("finish&id=" + id, new { sha256 = digest }, token, cancellation, true).ConfigureAwait(false);
                    string url = Convert.ToString(finish["url"], CultureInfo.InvariantCulture); Uri share;
                    if (!Uri.TryCreate(url, UriKind.Absolute, out share) || share.Host != endpoint.Host || share.Scheme != endpoint.Scheme || !share.AbsolutePath.StartsWith(new Uri(endpoint, ".").AbsolutePath + "uploads/", StringComparison.Ordinal))
                        throw new IOException("A hospedagem retornou um link inválido.");
                    if (!String.Equals(digest, Convert.ToString(finish["sha256"], CultureInfo.InvariantCulture), StringComparison.OrdinalIgnoreCase))
                        throw new IOException("A verificação do arquivo recebido falhou. Envie novamente.");
                    completed = true; return new UploadResult { Url = url, Sha256 = digest, Size = total };
                }
            }
            finally
            {
                if (!completed && id != null && token != null)
                {
                    using (CancellationTokenSource cleanup = new CancellationTokenSource(2000))
                    {
                        try { await JsonRequest("cancel&id=" + id, new { }, token, cleanup.Token, false).ConfigureAwait(false); }
                        catch (Exception) { }
                    }
                }
            }
        }
    }
}
