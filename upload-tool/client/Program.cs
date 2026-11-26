using System;
using System.Drawing;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Reflection;

[assembly: AssemblyTitle("INILOG Upload")]
[assembly: AssemblyDescription("Upload portátil de arquivos para INILOG")]
[assembly: AssemblyCompany("INILOG")]
[assembly: AssemblyProduct("INILOG Upload")]
[assembly: AssemblyCopyright("Francisney Delmondes | INILOG")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

namespace InilogUpload
{
    internal static class Program
    {
        [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();
        [STAThread] private static void Main()
        {
            SetProcessDPIAware();
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
            ServicePointManager.DefaultConnectionLimit = 4;
            Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
            Application.ThreadException += delegate(object sender, ThreadExceptionEventArgs e) { MessageBox.Show("Não foi possível concluir a operação. Tente novamente.","INILOG Upload",MessageBoxButtons.OK,MessageBoxIcon.Information); };
            Application.Run(new UploadWindow());
        }
    }
    public sealed class UploadWindow : Form
    {
        private readonly Label filename = new Label();
        private readonly Label sizeLabel = new Label();
        private readonly Label status = new Label();
        private readonly Label percent = new Label();
        private readonly Button choose = new Button();
        private readonly Button upload = new Button();
        private readonly Button copy = new Button();
        private readonly ProgressBar bar = new ProgressBar();
        private readonly TextBox url = new TextBox();
        private readonly ToolTip tip = new ToolTip();
        private CancellationTokenSource cancellation;
        private string selected;
        public UploadWindow()
        {
            Text="INILOG Upload";ClientSize=new Size(468,306);FormBorderStyle=FormBorderStyle.FixedSingle;MaximizeBox=false;
            StartPosition=FormStartPosition.CenterScreen;BackColor=Color.White;Font=new Font("Segoe UI",9F);AutoScaleDimensions=new SizeF(96,96);AutoScaleMode=AutoScaleMode.Dpi;
            Icon=SystemIcons.Application;
            Label title = new Label { Text="INILOG Upload",Font=new Font("Segoe UI Semibold",15F),ForeColor=Color.FromArgb(23,43,68),AutoSize=true,Location=new Point(20,17) };Controls.Add(title);
            filename.SetBounds(20,62,300,22);filename.Text="Selecione um arquivo";filename.AutoEllipsis=true;filename.ForeColor=Color.FromArgb(35,51,73);Controls.Add(filename);
            sizeLabel.SetBounds(20,86,300,19);sizeLabel.ForeColor=Color.FromArgb(110,124,145);sizeLabel.Font=new Font("Segoe UI",8.5F);Controls.Add(sizeLabel);
            StyleButton(choose,"Escolher…",338,58,110,32,false);choose.Click+=ChooseFile;
            bar.SetBounds(20,118,374,8);bar.Maximum=100;Controls.Add(bar);
            percent.SetBounds(399,110,49,23);percent.Text="0%";percent.TextAlign=ContentAlignment.MiddleRight;percent.ForeColor=Color.FromArgb(38,76,116);Controls.Add(percent);
            status.SetBounds(20,139,428,31);status.Text="Pronto para enviar.";status.AutoEllipsis=true;status.ForeColor=Color.FromArgb(104,119,140);status.Font=new Font("Segoe UI",8.5F);Controls.Add(status);
            StyleButton(upload,"Carregar",20,175,208,35,true);upload.Enabled=false;upload.Click+=UploadFile;
            StyleButton(copy,"Copiar link",240,175,208,35,false);copy.Enabled=false;copy.Click+=CopyLink;
            url.SetBounds(20,222,428,24);url.ReadOnly=true;url.TabStop=true;url.BorderStyle=BorderStyle.FixedSingle;url.BackColor=Color.FromArgb(249,251,254);url.ForeColor=Color.FromArgb(83,103,130);url.Font=new Font("Segoe UI",8F);Controls.Add(url);
            Label footer = new Label {Text="Francisney Delmondes | INILOG\n(61) 99363-0969  ·  suporte@inilog.com\nwww.inilog.com",TextAlign=ContentAlignment.TopCenter,ForeColor=Color.FromArgb(130,143,159),Font=new Font("Segoe UI",8F)};footer.SetBounds(20,257,428,45);Controls.Add(footer);
            FormClosing+=delegate { if(cancellation!=null)cancellation.Cancel(); };
        }
        private void StyleButton(Button b,string text,int x,int y,int w,int h,bool primary)
        {
            b.Text=text;b.SetBounds(x,y,w,h);b.FlatStyle=FlatStyle.Flat;b.FlatAppearance.BorderSize=primary?0:1;b.FlatAppearance.BorderColor=Color.FromArgb(213,223,236);
            b.BackColor=primary?Color.FromArgb(35,92,205):Color.White;b.ForeColor=primary?Color.White:Color.FromArgb(29,50,77);b.Font=new Font("Segoe UI Semibold",9F);b.Cursor=Cursors.Hand;Controls.Add(b);
        }
        private void ChooseFile(object sender,EventArgs args)
        {
            string path=NativePicker.Pick(Handle);
            if(path==null)return;
            try { FileInfo file=new FileInfo(path);selected=path;filename.Text=file.Name;tip.SetToolTip(filename,file.Name);sizeLabel.Text=FormatSize(file.Length);upload.Enabled=true;copy.Enabled=false;url.Text="";bar.Value=0;percent.Text="0%";status.Text="Pronto para enviar."; }
            catch(Exception){status.Text="Não foi possível abrir esse arquivo.";}
        }
        private async void UploadFile(object sender,EventArgs args)
        {
            if(cancellation!=null){cancellation.Cancel();status.Text="Cancelando…";return;}
            if(selected==null)return;
            cancellation=new CancellationTokenSource();choose.Enabled=false;copy.Enabled=false;upload.Text="Cancelar";url.Clear();bar.Value=0;percent.Text="0%";status.Text="Preparando envio…";
            try
            {
                Progress<UploadProgress> progress=new Progress<UploadProgress>(delegate(UploadProgress p){if(IsDisposed||Disposing)return;bar.Value=p.Percent;percent.Text=p.Percent.ToString()+"%";status.Text=p.Verifying?"Confirmando arquivo…":"Enviando "+FormatSize(p.Sent)+" de "+FormatSize(p.Total);});
                UploadResult result=await new UploadClient().UploadAsync(selected,progress,cancellation.Token);
                if(IsDisposed||Disposing)return;
                bar.Value=100;percent.Text="100%";url.Text=result.Url;copy.Enabled=true;status.Text="Concluído. Copie o link para compartilhar.";
            }
            catch(OperationCanceledException){if(!IsDisposed)status.Text="Envio cancelado.";}
            catch(Exception e){if(!IsDisposed){status.Text="Não foi possível concluir o envio.";MessageBox.Show(this,e is IOException?e.Message:"Não foi possível enviar o arquivo. Verifique a conexão e tente novamente.","INILOG Upload",MessageBoxButtons.OK,MessageBoxIcon.Information);}}
            finally
            {
                if(cancellation!=null){cancellation.Dispose();cancellation=null;}
                if(!IsDisposed&&!Disposing){choose.Enabled=true;upload.Enabled=true;upload.Text="Carregar";}
            }
        }
        private void CopyLink(object sender,EventArgs args)
        {
            if(url.Text.Length==0)return;
            try{Clipboard.SetText(url.Text);status.Text="Link copiado.";}
            catch(ExternalException){url.Focus();url.SelectAll();status.Text="Pressione Ctrl+C para copiar o link.";}
        }
        public static string FormatSize(long size)
        {
            if(size>=1073741824)return (size/1073741824.0).ToString("0.00")+" GB";
            if(size>=1048576)return (size/1048576.0).ToString("0.0")+" MB";
            if(size>=1024)return (size/1024.0).ToString("0.0")+" KB";return size.ToString()+" B";
        }
        protected override void Dispose(bool disposing){if(disposing)tip.Dispose();base.Dispose(disposing);}
    }
    internal static class NativePicker
    {
        [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] private sealed class OpenFileName
        {
            public int size;public IntPtr owner;public IntPtr instance;
            public string filter;public IntPtr customFilter;public int maxCustomFilter;public int filterIndex;
            public IntPtr file;public int maxFile;public IntPtr fileTitle;public int maxFileTitle;
            public string initialDir;public string title;public int flags;public short fileOffset;public short extension;
            public string defaultExtension;public IntPtr customData;public IntPtr hook;public IntPtr template;
            public IntPtr reserved;public int reservedCount;public int extendedFlags;
        }
        [DllImport("comdlg32.dll",CharSet=CharSet.Unicode,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] private static extern bool GetOpenFileName([In,Out]OpenFileName ofn);
        public static string Pick(IntPtr owner)
        {
            OpenFileName value=new OpenFileName();value.size=Marshal.SizeOf(typeof(OpenFileName));value.owner=owner;
            value.filter="Todos os arquivos\0*.*\0\0";value.filterIndex=1;value.file=Marshal.AllocHGlobal(32768*2);Marshal.WriteInt16(value.file,0);value.maxFile=32768;value.title="Escolher arquivo";
            const int EXPLORER=0x80000,FILEMUSTEXIST=0x1000,PATHMUSTEXIST=0x800,NOCHANGEDIR=0x8,DONTADDTORECENT=0x02000000;
            value.flags=EXPLORER|FILEMUSTEXIST|PATHMUSTEXIST|NOCHANGEDIR|DONTADDTORECENT;
            try { return GetOpenFileName(value)?Marshal.PtrToStringUni(value.file):null; }
            finally { Marshal.FreeHGlobal(value.file); }
        }
    }
}
