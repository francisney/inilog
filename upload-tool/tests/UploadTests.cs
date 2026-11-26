using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Threading;
using System.Windows.Forms;
using System.Drawing;
using System.Reflection;
using InilogUpload;
public static class UploadTests
{
 private static int checks;
 private static void Check(bool result,string label){if(!result)throw new Exception("FAILED: "+label);checks++;Console.WriteLine("OK "+label);}
 private static string Digest(byte[] bytes){using(SHA256 sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();}
 private sealed class Recording:IProgress<UploadProgress>{public int Count;public bool Verifying;public bool Invalid;public void Report(UploadProgress p){Count++;Verifying|=p.Verifying;if(p.Percent<0||p.Percent>99)Invalid=true;}}
 [STAThread] public static int Main(string[] args)
 {
  string folder=Path.Combine(Path.GetTempPath(),"inilog-upload-test-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
  try
  {
   Uri endpoint=new Uri(args[0]);UploadClient client=new UploadClient(endpoint);
   foreach(string name in new string[]{"arquivo vazio.txt","Ação e coração.bin","retry-sem-duplicar.exe","qualquer-formato.php"})
   {
    byte[] bytes=name.StartsWith("arquivo vazio")?new byte[0]:new byte[360321];new Random(41).NextBytes(bytes);string path=Path.Combine(folder,name);File.WriteAllBytes(path,bytes);
    Recording progress=new Recording();UploadResult result=client.UploadAsync(path,progress,CancellationToken.None).GetAwaiter().GetResult();
    Check(result.Sha256==Digest(bytes),"SHA-256 "+name);Check(result.Size==bytes.Length,"size "+name);Check(!progress.Invalid,"progress below 100 until confirmation "+name);Check(progress.Verifying,"final verification reported "+name);
    using(WebClient web=new WebClient())Check(Digest(web.DownloadData(result.Url))==Digest(bytes),"public URL preserves bytes "+name);
   }
   string cancelFile=Path.Combine(folder,"slow-cancelar.bin");File.WriteAllBytes(cancelFile,new byte[900000]);
   using(CancellationTokenSource cancel=new CancellationTokenSource(150)){bool canceled=false;try{client.UploadAsync(cancelFile,null,cancel.Token).GetAwaiter().GetResult();}catch(OperationCanceledException){canceled=true;}Check(canceled,"upload cancellation aborts transfer");}
   bool reject=false;try{new UploadClient(new Uri("http://example.com/upload.php"));}catch(ArgumentException){reject=true;}Check(reject,"unencrypted remote endpoint rejected");
   Type picker=typeof(UploadWindow).Assembly.GetType("InilogUpload.NativePicker+OpenFileName");Check(System.Runtime.InteropServices.Marshal.SizeOf(picker)==(IntPtr.Size==8?152:88),"native file dialog layout is correct");
   Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
   using(UploadWindow window=new UploadWindow())
   {
    window.Show();Application.DoEvents();Check(!window.MaximizeBox,"mini window is fixed size");Check(window.ClientSize.Width<=600,"small desktop window");
    bool contacts=false;foreach(Control c in window.Controls){if(c.Text.Contains("suporte@inilog.com"))contacts=true;Check(c.Bottom<=window.ClientSize.Height&&c.Right<=window.ClientSize.Width,"control fits: "+c.GetType().Name);}
    Check(contacts,"footer contains owner contact");
    using(Bitmap image=new Bitmap(window.Width,window.Height)){window.DrawToBitmap(image,new Rectangle(0,0,window.Width,window.Height));image.Save(args[1],System.Drawing.Imaging.ImageFormat.Png);}
    window.Close();Application.DoEvents();
   }
   File.WriteAllText(args[2],"{\"passed\":true,\"checks\":"+checks+",\"runtime\":\""+Environment.Version+"\"}");Console.WriteLine("VALIDATION_OK "+checks);return 0;
  }
  catch(Exception e){Console.Error.WriteLine(e.ToString());return 1;}
  finally{Directory.Delete(folder,true);}
 }
}
