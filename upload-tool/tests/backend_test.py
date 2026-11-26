import os,sys,json,subprocess,socket,time,secrets,hashlib,urllib.request,urllib.error,urllib.parse,http.cookiejar,re
from pathlib import Path
stage=Path(sys.argv[1]);root=stage/'public';private=stage/'private';private.mkdir(mode=0o700,exist_ok=True);php='/opt/cpanel/ea-php85/root/usr/bin/php';env=dict(os.environ,INILOG_UPLOAD_STORAGE=str(private));checks=[]
def check(value,message):
 if not value:raise AssertionError(message)
 checks.append(message)
sock=socket.socket();sock.bind(('127.0.0.1',0));port=sock.getsockname()[1];sock.close();base='http://127.0.0.1:'+str(port)
test_password='test-'+secrets.token_hex(16)
test_hash=subprocess.run([php,'-r','echo password_hash(stream_get_contents(STDIN), PASSWORD_DEFAULT);'],input=test_password,text=True,capture_output=True,check=True).stdout
(private/'config.php').write_text("<?php return ['chunk_bytes'=>4194304,'max_file_bytes'=>21474836480,'public_base'=>'"+base+"/backup/uploads/','web_password_hash'=>'"+test_hash+"'];");os.chmod(private/'config.php',0o600)
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
cookies=http.cookiejar.CookieJar();browser=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookies))
def web(path='index.php',fields=None,headers=None,body=None):
 if fields is not None:body=urllib.parse.urlencode(fields).encode()
 req=urllib.request.Request(base+'/backup/'+path,data=body,headers=headers or {})
 try:
  with browser.open(req,timeout=15) as r:return r.status,dict(r.headers),r.read().decode()
 except urllib.error.HTTPError as e:return e.code,dict(e.headers),e.read().decode()
def form_csrf(page):return re.search(r'name="csrf" value="([a-f0-9]{64})"',page).group(1)
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
 check(info['web_password_required'] is True,'web password is distinct from native API')
 status,headers,page=web();check(status==200 and 'name="password"' in page and 'id="file"' not in page,'web panel requires login')
 csrf=form_csrf(page);old_cookie=next(iter(cookies)).value
 check('HttpOnly' in headers.get('Set-Cookie','') and 'SameSite=Lax' in headers.get('Set-Cookie',''),'session cookie has HttpOnly and SameSite')
 status,headers,data=web('index.php?panel=files');check(status==401 and json.loads(data)['ok'] is False,'file list denied without login')
 for extra in [{'X-Inilog-Web':'1'},{'Sec-Fetch-Mode':'cors'},{'Origin':'https://inilog.com'}]:
  status,result=request('init',{'name':'blocked.txt','size':0},extra=extra);check(status==401,'anonymous browser API upload denied')
 status,headers,page=web(fields={'panel_action':'login','password':test_password});check(status==403,'login requires CSRF')
 status,headers,page=web(fields={'panel_action':'login','csrf':csrf,'password':'incorrect'});check(status==401 and 'Senha incorreta' in page,'wrong web password rejected')
 status,headers,page=web(fields={'panel_action':'login','csrf':csrf,'password':test_password});check(status==200 and 'id="file"' in page and 'Listar arquivos' in page,'correct password opens upload and listing')
 check(next(iter(cookies)).value!=old_cookie,'login rotates session identifier')
 web_csrf=re.search(r'name="inilog-web-csrf" content="([a-f0-9]{64})"',page).group(1)
 for token in ['', '0'*64]:
  status,headers,data=web('index.php?web=1&api=init',headers={'Content-Type':'application/json','X-Inilog-Web-CSRF':token},body=b'{"name":"blocked.txt","size":0}');check(status==403,'authenticated browser upload requires valid CSRF')
 status,headers,data=web('index.php?web=1&api=init',headers={'Content-Type':'application/json','X-Inilog-Web-CSRF':web_csrf},body=b'{"name":"web-test.txt","size":0}');w=json.loads(data);check(status==200 and w['ok'],'authenticated browser upload init works')
 status,headers,data=web('index.php?web=1&api=finish&id='+w['id'],headers={'Content-Type':'application/json','X-Inilog-Web-CSRF':web_csrf,'X-Inilog-Token':w['token']},body=b'{}');finished=json.loads(data);check(status==200 and finished['ok'],'authenticated browser upload finishes')
 status,headers,received=download(finished['url']);check(status==200 and received==b'','web-generated download remains public')
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
 payload=('--'+boundary+'\r\nContent-Disposition: form-data; name="csrf"\r\n\r\n'+web_csrf+'\r\n--'+boundary+'\r\nContent-Disposition: form-data; name="file"; filename="legado.txt"\r\nContent-Type: text/plain\r\n\r\n').encode()+content+('\r\n--'+boundary+'--\r\n').encode()
 status,headers,legacy=web(headers={'Content-Type':'multipart/form-data; boundary='+boundary},body=payload)
 check(legacy.startswith('OK:'),'authenticated legacy multipart upload preserved')
 status,headers,received=download(legacy.splitlines()[-1]);check(received==content,'legacy response includes valid public URL')
 status,headers,data=web('index.php?panel=files');listed=json.loads(data);check(status==200 and any(x['name']=='legado.txt' for x in listed['files']),'authenticated listing includes completed uploads')
 check(not any(x['name'] in ['index.php','common.php','panel.php','config.php','upload.js','upload.css'] for x in listed['files']),'listing excludes application code and private configuration')
 check(all('/backup/' in x['url'] for x in listed['files']),'listed links use backup only')
 delete_target=next(x for x in listed['files'] if x['name']=='legado.txt')
 public_headers={'Content-Type':'application/json','X-Inilog-Web-CSRF':web_csrf}
 def delete(key,csrf=web_csrf):return web('index.php?panel=delete',headers={'Content-Type':'application/json','X-Inilog-Web-CSRF':csrf},body=json.dumps({'key':key}).encode())
 try:
  urllib.request.urlopen(urllib.request.Request(base+'/backup/index.php?panel=delete',data=json.dumps({'key':delete_target['key']}).encode(),headers=public_headers),timeout=15)
  raise AssertionError('Anonymous deletion was accepted')
 except urllib.error.HTTPError as e:check(e.code==401,'deletion requires authenticated panel session')
 status,headers,data=delete(delete_target['key'],'0'*64);check(status==403,'deletion requires CSRF')
 status,headers,data=delete('public:../config.php');check(status==404,'deletion rejects path traversal')
 protected_hash=hashlib.sha256((root/'backup/index.php').read_bytes()).hexdigest()
 status,headers,data=delete('public:index.php');check(status==404 and hashlib.sha256((root/'backup/index.php').read_bytes()).hexdigest()==protected_hash,'application PHP cannot be deleted')
 (root/'backup/upload.exe').write_bytes(b'MZ-TEST-ONLY')
 status,headers,data=delete('public:upload.exe');check(status==403 and (root/'backup/upload.exe').is_file(),'application executable cannot be deleted through panel')
 status,headers,data=delete(delete_target['key']);check(status==200 and json.loads(data)['ok'],'completed upload can be moved to private trash')
 deleted_id=delete_target['key'].split(':',1)[1];check(not(private/'files'/(deleted_id+'.json')).exists() and not(private/'files'/(deleted_id+'.blob')).exists(),'deleted metadata and content leave active storage')
 records=[p for p in (private/'trash').glob('*/restore.json') if json.loads(p.read_text())['key']==delete_target['key']]
 check(len(records)==1 and (records[0].parent/'content.blob').read_bytes()==content and (records[0].parent/'metadata.json').is_file(),'trash preserves exact content and metadata for recovery')
 try:download(delete_target['url']);raise AssertionError('Deleted download was still served')
 except urllib.error.HTTPError as e:check(e.code==404,'deleted share URL returns 404')
 status,headers,data=delete(delete_target['key']);check(status==404,'repeated deletion does not remove other files')
 (root/'backup/lista-teste.txt').write_bytes(b'PUBLIC-TEST-ONLY')
 status,headers,data=delete('public:lista-teste.txt');check(status==200 and not(root/'backup/lista-teste.txt').exists(),'existing public download can be moved to private trash')
 status,headers,data=web('index.php?panel=files');remaining=json.loads(data)['files'];check(not any(x['key']==delete_target['key'] for x in remaining),'deleted file disappears from listing')
 check(any(x['name']=='pagina.php' for x in remaining),'unrelated uploaded files are preserved')
 status,headers,page=web(fields={'panel_action':'logout','csrf':web_csrf});check(status==200 and 'name="password"' in page and 'id="file"' not in page,'logout returns to login')
 status,headers,data=web('index.php?panel=files');check(status==401,'file listing is protected after logout')
 status,info=request('info',method='GET');check(status==200 and info['password_required'] is False,'native API remains public after web logout')
 report={'passed':True,'checks':len(checks),'cases':checks,'files_published':len(list((private/'files').glob('*.blob')))}
 (stage/'backend-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False))
finally:server.terminate();server.wait(timeout=10);log.close()
