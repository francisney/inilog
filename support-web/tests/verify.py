import os,sys,json,subprocess,secrets,socket,time,re,html,urllib.request,urllib.parse,urllib.error,http.cookiejar,hashlib
from pathlib import Path
stage=Path(sys.argv[1]);docroot=stage/'public';private=stage/'private';php='/opt/cpanel/ea-php85/root/usr/bin/php'
env=dict(os.environ,INILOG_PRIVATE_DIR=str(private))
checks=[]
def check(value,label):
    if not value:raise AssertionError(label)
    checks.append(label)
def runphp(code,args=(),input=None):
    r=subprocess.run([php,'-r',code,*map(str,args)],input=input,text=True,capture_output=True,env=env,timeout=30)
    if r.returncode:raise RuntimeError('PHP test failed: '+r.stderr[-1000:])
    return r.stdout
# Dados reais ficam apenas neste servidor. Somente totais e hashes saem dos testes.
imported=json.loads((private/'notes.json').read_text())
check(len(imported['notes'])==67,'67 legacy notes imported')
check(sum(n['origin']=='old' for n in imported['notes'])==46,'46 old notes imported')
for source,metadata in imported['legacy_import'].items():
    origin='old' if source=='old.txt' else 'current'
    body='\n'.join(n['body'] for n in imported['notes'] if n['origin']==origin)
    check(hashlib.sha256(body.encode()).hexdigest()==metadata['body_hash'],'Legacy text preserved: '+source)
(private/'notes.imported.json').write_text(json.dumps(imported,ensure_ascii=False));os.chmod(private/'notes.imported.json',0o600)
password=secrets.token_hex(18)
runphp("$p=$argv[1];$c=require $p;$c['password_hash']=password_hash(trim(stream_get_contents(STDIN)),PASSWORD_DEFAULT);$c['section_password_hashes']=[];file_put_contents($p,'<?php return '.var_export($c,true).';');chmod($p,0600);",[private/'config.php'],password)
fixture=[{'id':'a'*24,'title':'Checklist da loja','body':'Conferir impressora e acesso remoto.\nRegistrar o nome do computador após o atendimento.','origin':'current','favorite':True,'created_at':'2026-11-26T18:00:00Z','updated_at':'2026-11-26T18:00:00Z','revision':1},{'id':'b'*24,'title':'Anotação antiga','body':'Informações preservadas do old.txt.\nAgora também é possível editar e excluir cada nota.','origin':'old','favorite':False,'created_at':None,'updated_at':None,'revision':1}]
(private/'notes.json').write_text(json.dumps({'version':1,'notes':fixture,'trash':[]}));os.chmod(private/'notes.json',0o600)
files=docroot/'suporte/628/files';files.mkdir(exist_ok=True)
(files/'update.ps1').write_text("Write-Output 'Arquivo de demonstração'\n");(files/'Guia-de-suporte.txt').write_text('Passo a passo de suporte para as lojas.\n');(files/'Inilog_Cloud.exe').write_bytes(b'MZDEMO')
marker='_INILOG_QA_'+secrets.token_hex(8)
dbcode="require $argv[1].'/suporte/geral/dbcontroller.php';$d=(new DBController)->connectDB();"
def digest():return json.loads(runphp(dbcode+"$r=$d->query('SELECT * FROM toy ORDER BY id')->fetch_all(MYSQLI_ASSOC);echo json_encode(['count'=>count($r),'hash'=>hash('sha256',json_encode($r))]);",[docroot]))
before=digest();check(before['count']==281,'281 original computers available')
sock=socket.socket();sock.bind(('127.0.0.1',0));port=sock.getsockname()[1];sock.close()
log=open(stage/'test-server.log','w');server=subprocess.Popen([php,'-S','127.0.0.1:'+str(port),'-t',str(docroot)],env=env,stdout=log,stderr=log)
jar=http.cookiejar.CookieJar();client=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar));base='http://127.0.0.1:'+str(port)
def get(path):
    try:
        with client.open(base+path,timeout=12) as response:return response.status,response.read().decode('utf8')
    except urllib.error.HTTPError as e:return e.code,e.read().decode('utf8')
def post(path,data,file=None):
    if file:
        boundary='inilog'+secrets.token_hex(10);parts=[]
        for name,value in data.items():parts.append(('--'+boundary+'\r\nContent-Disposition: form-data; name="'+name+'"\r\n\r\n'+str(value)+'\r\n').encode())
        name,body=file;parts.append(('--'+boundary+'\r\nContent-Disposition: form-data; name="arquivo"; filename="'+name+'"\r\nContent-Type: text/plain\r\n\r\n').encode()+body+b'\r\n');parts.append(('--'+boundary+'--\r\n').encode());payload=b''.join(parts);kind='multipart/form-data; boundary='+boundary
    else:payload=urllib.parse.urlencode(data).encode();kind='application/x-www-form-urlencoded'
    request=urllib.request.Request(base+path,data=payload,headers={'Content-Type':kind})
    try:
        with client.open(request,timeout=12) as response:return response.status,response.read().decode('utf8')
    except urllib.error.HTTPError as e:return e.code,e.read().decode('utf8')
def field(page,name):
    match=re.search(r'name="'+re.escape(name)+r'" value="([^"]*)"',page)
    if not match:raise AssertionError('Missing form field '+name)
    return html.unescape(match.group(1))
rendered=stage/'rendered';rendered.mkdir(exist_ok=True)
try:
    for _ in range(30):
        try:status,page=get('/suporte/628/');break
        except (urllib.error.URLError,ConnectionError):time.sleep(.1)
    check(status==200 and 'type="password"' in page,'File manager requires login')
    status,_=post('/suporte/628/',{'action':'delete','name':'update.ps1'})
    check((files/'update.ps1').exists(),'Anonymous write cannot remove files')
    token=field(page,'csrf');status,page=post('/suporte/628/',{'action':'login','senha':'wrong','csrf':token});check('Senha incorreta' in page,'Wrong password rejected')
    status,page=post('/suporte/628/',{'action':'login','senha':password,'csrf':token});check(status==200 and 'Seus arquivos' in page,'Authenticated file listing works');token=field(page,'csrf')
    status,_=post('/suporte/628/',{'action':'delete','name':'update.ps1','csrf':'wrong'});check(status==403 and (files/'update.ps1').exists(),'CSRF rejects writes')
    name="teste ' &.txt";body='Olá, loja!\n<script>texto, não código</script>\n'
    status,page=post('/suporte/628/',{'action':'upload','csrf':token},(name,body.encode()));check((files/name).read_text()==body,'UTF-8 upload with special filename')
    status,page=get('/suporte/628/?edit='+urllib.parse.quote(name));rev=field(page,'revision')
    status,page=post('/suporte/628/',{'action':'edit','name':name,'body':body+'Editado.','revision':rev,'csrf':token});check((files/name).read_text().endswith('Editado.'),'Text editor saves contents')
    status,page=post('/suporte/628/',{'action':'edit','name':name,'body':'stale overwrite','revision':rev,'csrf':token});check('mudou em outra janela' in page and (files/name).read_text().endswith('Editado.'),'Stale file edit rejected')
    status,page=post('/suporte/628/',{'action':'delete','name':'../notas/old.txt','revision':'x','csrf':token});check('Nome de arquivo não permitido' in page,'Path traversal rejected')
    status,page=post('/suporte/628/',{'action':'upload','csrf':token},('bad.php',b'<?php echo 1;'));check(not(files/'bad.php').exists() and 'tipo de arquivo' in page,'Executable PHP upload rejected')
    status,page=get('/suporte/628/');row=re.search(r'<tr>.*?'+re.escape(html.escape(name,quote=True))+r'.*?</tr>',page,re.S)
    # Busca a revisão diretamente do formulário da linha que contém o nome exato.
    rows=re.findall(r'<tr>.*?</tr>',page,re.S);row=next(row for row in rows if 'name="name" value="'+html.escape(name,quote=True).replace('&#x27;','&#039;')+'"' in row)
    rev=field(row,'revision');status,page=post('/suporte/628/',{'action':'delete','name':name,'revision':rev,'csrf':token});check(not(files/name).exists(),'File deletion moves to trash')
    trash=json.loads((private/'file-trash.json').read_text());key=next(k for k,v in trash.items() if v['name']==name)
    status,page=post('/suporte/628/',{'action':'restore','key':key,'csrf':token});check((files/name).exists(),'File trash restores content')
    status,page=get('/suporte/notas/');check(status==200 and 'Anotação antiga' in page,'Notes display current and old content')
    status,page=post('/suporte/notas/',{'action':'create','title':'Nota de teste','body':'Conteúdo <script>alert(1)</script>','csrf':token});check('&lt;script&gt;alert(1)&lt;/script&gt;' in page,'Notes escape markup')
    current=json.loads((private/'notes.json').read_text());note=next(n for n in current['notes'] if n['title']=='Nota de teste')
    status,page=post('/suporte/notas/',{'action':'update','id':note['id'],'revision':note['revision'],'title':'Nota atualizada','body':'Edição concluída com acentos.','csrf':token});check('Nota atualizada' in page,'Note editing works')
    status,page=post('/suporte/notas/',{'action':'update','id':note['id'],'revision':note['revision'],'title':'Erro','body':'stale','csrf':token});check('mudou em outra janela' in page,'Concurrent note edits protected')
    current=json.loads((private/'notes.json').read_text());note=next(n for n in current['notes'] if n['id']==note['id'])
    status,page=post('/suporte/notas/',{'action':'trash','id':note['id'],'revision':note['revision'],'csrf':token});check('movida para a lixeira' in page,'Notes move to trash')
    note=next(n for n in json.loads((private/'notes.json').read_text())['trash'] if n['id']==note['id'])
    status,page=post('/suporte/notas/',{'action':'restore','id':note['id'],'revision':note['revision'],'csrf':token});check('Nota restaurada' in page,'Notes restore from trash')
    status,page=get('/suporte/notas/index.php?export=old');check('old.txt' in page,'Old text export is integrated')
    status,page=get('/suporte/geral/');check(status==200 and 'computadores' in page and '281' in page,'Computer inventory reads existing data')
    values={'name':marker,'code':"PC-D'ÁGUA",'category':'192.0.2.22','price':'Teste automático com acentos','stock_count':'000 000 000'}
    status,page=post('/suporte/geral/',dict(action='save',id='',revision='',csrf=token,**values));check('Computador cadastrado' in page,'Computer creation via prepared query')
    status,page=get('/suporte/geral/?q='+urllib.parse.quote(marker));check(marker in page and 'PC-D&#039;ÁGUA' in page,'Computer search and escaped apostrophes')
    match=re.search(r'href="\?edit=(\d+)"',page);check(match is not None,'New computer is editable');record_id=match.group(1)
    status,page=get('/suporte/geral/?edit='+record_id);rev=field(page,'revision');values['price']='Observação atualizada'
    status,page=post('/suporte/geral/',dict(action='save',id=record_id,revision=rev,csrf=token,**values));check('Computador atualizado' in page,'Computer update works')
    status,page=post('/suporte/geral/',dict(action='save',id=record_id,revision=rev,csrf=token,**values));check('mudou em outra janela' in page,'Stale computer update rejected')
    status,page=get('/suporte/geral/?edit='+record_id);rev=field(page,'revision')
    status,page=post('/suporte/geral/',{'action':'delete','id':record_id,'revision':rev,'csrf':token});check('Computador excluído' in page,'Computer deletion creates private backup')
    status,page=get('/suporte/geral/?q='+urllib.parse.quote("' OR 1=1 --"));check('Nenhum computador encontrado' in page,'SQL-like search remains a literal prepared value')
    status,page=get('/suporte/geral/?export=1&q='+urllib.parse.quote(marker));check('Loja / unidade' in page,'CSV export works')
    check(digest()==before,'All 281 original computer records preserved byte for byte')
    # Renderizações de QA contêm exclusivamente dados sintéticos.
    (files/name).unlink();(private/'notes.json').write_text(json.dumps({'version':1,'notes':fixture,'trash':[]}))
    status,page=get('/suporte/notas/');(rendered/'notas.html').write_text(page)
    status,page=get('/suporte/628/');(rendered/'628.html').write_text(page)
    print(json.dumps({'passed':True,'checks':len(checks),'checks_list':checks,'database_original':before['count'],'migration_notes':67,'migration_old':46},ensure_ascii=False))
finally:
    try:runphp(dbcode+"$name=trim(stream_get_contents(STDIN));$s=$d->prepare('DELETE FROM toy WHERE name=?');$s->bind_param('s',$name);$s->execute();",[docroot],marker)
    except Exception:pass
    server.terminate();server.wait(timeout=10);log.close()
