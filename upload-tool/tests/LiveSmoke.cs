using System;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Collections.Generic;
using InilogUpload;
public static class LiveSmoke
{
 private static string Digest(byte[] bytes){using(SHA256 sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();}
 public static int Main(string[] args)
 {
  ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;
  string folder=Path.Combine(Path.GetTempPath(),"inilog-live-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
  try
  {
   List<object> results=new List<object>();
   foreach(string ext in new string[]{"bin","php"})
   {
    string name="INILOG-verificacao-"+Guid.NewGuid().ToString("N")+"."+ext;byte[] bytes;
    if(ext=="bin"){bytes=new byte[5*1024*1024+17];new Random(2026).NextBytes(bytes);}else bytes=Encoding.UTF8.GetBytes("<?php echo 'INILOG_EXECUTION_PROBE'; ?>");
    string file=Path.Combine(folder,name);File.WriteAllBytes(file,bytes);
    UploadResult result=new UploadClient().UploadAsync(file,null,CancellationToken.None).GetAwaiter().GetResult();
    byte[] received;using(WebClient web=new WebClient()){web.Headers[HttpRequestHeader.UserAgent]="INILOG-Upload-Test/1.0 (Windows)";received=web.DownloadData(result.Url);}
    if(Digest(received)!=Digest(bytes)||result.Sha256!=Digest(bytes))throw new Exception("O arquivo recebido diverge do original.");
    results.Add(new {name=name,url=result.Url,bytes=bytes.Length,sha256=result.Sha256});
   }
   File.WriteAllText(args[0],new JavaScriptSerializer().Serialize(new {passed=true,files=results}));Console.WriteLine("LIVE_UPLOAD_OK");return 0;
  }
  catch(Exception e){Console.Error.WriteLine(e.ToString());return 1;}
  finally{Directory.Delete(folder,true);}
 }
}
