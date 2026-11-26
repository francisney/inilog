import os,sys,json,subprocess,socket,time,secrets,hashlib,urllib.request,urllib.error,urllib.parse
from pathlib import Path
stage=Path(sys.argv[1]);root=stage/'public';private=stage/'private';private.mkdir(mode=0o700,exist_ok=True);php='/opt/cpanel/ea-php85/root/usr/bin/php';env=dict(os.environ,INILOG_UPLOAD_STORAGE=str(private));checks=[]
def check(value,message):
 if not value:raise AssertionError(message)
 checks.append(message)
sock=socket.socket();sock.bind(('127.0.0.1',0));port=sock.getsockname()[1];sock.close();base='http://127.0.0.1:'+str(port)
(private/'config.php').write_text("<?php return ['chunk_bytes'=>4194304,'max_file_bytes'=>21474836480,'public_base'=>'"+base+"/backup/uploads/'];");os.chmod(private/'config.php',0o600)
router=stage/'router.php';router.write_text("<?php $p=parse_url($_SERVER['REQUEST_URI'],PHP_URL_PATH);if(preg_match('~^/backup/uploads/([a-f0-9]{32})/?$~',$p,$m)){$_GET['file']=$m[1];require __DIR__.'/public/backup/download.php';return true;}return false;")
log=open(stage/'php-test.log','w');server=subprocess.Popen([php,'-S','127.0.0.1:'+str(port),'-t',str(root),str(router)],env=env,stdout=log,stderr=log)
def request(action,data=None,token=None,raw=None,extra=None,method='POST'):
 headers=extra or {};headers=dict(headers)
 if token:headers['X-Inilog-Token']=token
 if raw is None and method=='POST':payload=json.dumps(data or {}).encode();headers['Content-Type']='application/json'
 else:payload=raw
 req=urllib.request.Request(base+'/backup/index.php?api='+action,data=payload,headers=headers,method=method)
 try:
  with urllib.request.urlopen(req,timeout=15) as response:return response.status,json.loads(response.read())
 except urllib.error.HTTPError as e:return e.code,json.loads(e.read())
def download(url,headers=None,method='GET'):
 with urllib.request.urlopen(urllib.request.Request(url,headers=headers or {},method=method),timeout=15) as response:return response.status,dict(response.headers),response.read()
def send(name,body,replay=False):
 status,s=request('init',{'name':name,'size':len(body)});check(status==200 and s['ok'],'init '+name)
 offset=0
 while offset<len(body):
  block=body[offset:offset+s['chunk_bytes']];action='chunk&id='+s['id']+'&offset='+str(offset);headers={'Content-Type':'application/octet-stream','X-Inilog-Chunk-SHA256':hashlib.sha256(block).hexdigest()}
  status,result=request(action,token=s['token'],raw=block,extra=headers);check(status==200 and result['offset']==offset+len(block),'chunk '+name)
  if replay:status,r=request(action,token=s['token'],raw=block,extra=headers);check(status==200 and r['offset']==result['offset'],'replay is idempotent');replay=False
  offset=result['offset']
 status,result=request('finish&id='+s['id'],{'sha256':hashlib.sha256(body).hexdigest()},s['token']);check(status==200 and result['sha256']==hashlib.sha256(body).hexdigest(),'finish SHA256 '+name)
 status,headers,received=download(result['url']);check(status==200 and received==body,'public bytes preserved '+name);check('attachment;' in headers['Content-Disposition'],'download disposition '+name)
 status,headers,received=download(result['url'],method='HEAD');check(status==200 and received==b'' and int(headers['Content-Length'])==len(body),'HEAD '+name)
 if len(body)>=2:status,headers,received=download(result['url'],{'Range':'bytes=0-1'});check(status==206 and received==body[:2],'range '+name)
 status,repeated=request('finish&id='+s['id'],{'sha256':hashlib.sha256(body).hexdigest()},s['token']);check(status==200 and repeated['url']==result['url'],'finish replay '+name)
 return s,result
try:
 for _ in range(40):
  try:status,info=request('info',method='GET');break
  except (urllib.error.URLError,ConnectionError):time.sleep(.1)
 check(status==200 and info['password_required'] is False,'public upload without password')
 cases=[('vazio.txt',b''),('Ação e coração #1.bin',bytes(range(256))*18000),('programa.exe',b'MZ\0DEMO\xff\0'),('script.ps1',b"Write-Output 'ola'\r\n"),('arquivo.zip',b'PK\x03\x04\0DEMO'),('pagina.php',b'<?php echo "EXECUTION_PROBE"; ?>'),('.htaccess',b'RewriteEngine On\n'),('sem_extensao',b'any-format\x00\xff')]
 for name,body in cases:send(name,body,replay=name.endswith('.bin'))
 for name in ['../escape.txt','a\\b.exe','x\ny.txt','..']:
  status,result=request('init',{'name':name,'size':1});check(status==400,'unsafe name rejected')
 status,s=request('init',{'name':'incompleto.bin','size':5});status,r=request('finish&id='+s['id'],{'sha256':hashlib.sha256(b'12345').hexdigest()},s['token']);check(status==409,'incomplete file not published')
 status,r=request('chunk&id='+s['id']+'&offset=0',token='0'*64,raw=b'12345',extra={'Content-Type':'application/octet-stream','X-Inilog-Chunk-SHA256':hashlib.sha256(b'12345').hexdigest()});check(status==403,'session token enforced')
 status,r=request('chunk&id='+s['id']+'&offset=0',token=s['token'],raw=b'12345',extra={'Content-Type':'application/octet-stream','X-Inilog-Chunk-SHA256':'0'*64});check(status==409,'corrupted chunk rejected')
 status,r=request('cancel&id='+s['id'],{},s['token']);check(status==200 and not(private/'sessions'/str(s['id']+'.part')).exists(),'cancel removes partial upload')
 status,s=request('init',{'name':'wrong-hash.bin','size':2});request('chunk&id='+s['id']+'&offset=0',token=s['token'],raw=b'xx',extra={'Content-Type':'application/octet-stream','X-Inilog-Chunk-SHA256':hashlib.sha256(b'xx').hexdigest()});status,r=request('finish&id='+s['id'],{'sha256':'0'*64},s['token']);check(status==409,'wrong complete digest rejected')
 status,r=request('finish&id='+s['id'],{},s['token']);check(status==200,'browser completion uses verified chunks')
 status,r=request('init',{'name':'huge.bin','size':21474836481});check(status==413,'server size limit reported')
 boundary='inilog'+secrets.token_hex(10);content=b'LEGACY_UPLOAD_DEMO'
 payload=('--'+boundary+'\r\nContent-Disposition: form-data; name="file"; filename="legado.txt"\r\nContent-Type: text/plain\r\n\r\n').encode()+content+('\r\n--'+boundary+'--\r\n').encode()
 with urllib.request.urlopen(urllib.request.Request(base+'/backup/index.php',data=payload,headers={'Content-Type':'multipart/form-data; boundary='+boundary}),timeout=15) as response:legacy=response.read().decode()
 check(legacy.startswith('OK:'),'legacy multipart upload preserved')
 status,headers,received=download(legacy.splitlines()[-1]);check(received==content,'legacy response includes valid public URL')
 report={'passed':True,'checks':len(checks),'cases':checks,'files_published':len(list((private/'files').glob('*.blob')))}
 (stage/'backend-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False))
finally:server.terminate();server.wait(timeout=10);log.close()
