"""Executar somente na HostGator, com payload JSON por stdin; não contém segredos."""
import os,sys,json,subprocess,hashlib,shutil,datetime
from pathlib import Path
payload=json.load(sys.stdin)
stage=Path(payload['stage']);backup=Path(payload['backup']);live=Path('/home2/inilogco/public_html/suporte');private=Path('/home2/inilogco/.inilog-support')
php='/opt/cpanel/ea-php85/root/usr/bin/php'
allowed={key[len('source/'):]:value for key,value in payload['files'].items() if key.startswith('source/')}
for rel,content in allowed.items():
    path=Path(rel)
    if path.is_absolute() or '..' in path.parts or path.parts[:2]==('628','files'):raise RuntimeError('Destino não permitido: '+rel)
    source=stage/'public/suporte'/path
    if source.read_text()!=content:raise RuntimeError('Staging divergente: '+rel)
    if path.suffix=='.php':subprocess.run([php,'-l',str(source)],check=True,stdout=subprocess.DEVNULL)
ht=live/'geral/.htaccess';ht_hash=hashlib.sha256(ht.read_bytes()).hexdigest()
# Configuração e migração são preparadas antes de trocar qualquer página.
setup=subprocess.run([php,str(stage/'tools/setup.php'),str(backup),str(private),str(live)],capture_output=True,text=True,check=True,timeout=30)
authcode="""$p=$argv[1];$cfg=require $p;$in=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR);if(!str_starts_with($in['hash'],'$2'))throw new Exception('Hash inválido');$cfg['section_password_hashes']['notes']=$in['hash'];$tmp=$p.'.new';file_put_contents($tmp,'<?php return '.var_export($cfg,true).';',LOCK_EX);chmod($tmp,0600);rename($tmp,$p);echo json_encode(['notes_auth_configured'=>true]);"""
auth=subprocess.run([php,'-r',authcode,str(private/'config.php')],input=json.dumps({'hash':payload['notes_hash']}),text=True,capture_output=True,check=True,timeout=15)
# Guarda exatamente a versão que está no ar antes das substituições.
release=backup/('release-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ'));release.mkdir(mode=0o700)
changed=[]
try:
    ordered=sorted(allowed,key=lambda name:(not name.startswith('_inilog/'),name.endswith('index.php'),name))
    for rel in ordered:
        dst=live/rel;src=stage/'public/suporte'/rel
        old=release/rel
        if dst.exists():old.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(dst,old)
        dst.parent.mkdir(parents=True,exist_ok=True)
        tmp=dst.with_name('.inilog-release-'+dst.name)
        shutil.copyfile(src,tmp);os.chmod(tmp,0o644);os.replace(tmp,dst);changed.append(rel)
    for rel,content in allowed.items():
        assert hashlib.sha256((live/rel).read_bytes()).hexdigest()==hashlib.sha256(content.encode()).hexdigest(),rel
    assert hashlib.sha256(ht.read_bytes()).hexdigest()==ht_hash,'Proteção cPanel foi alterada'
except Exception:
    for rel in reversed(changed):
        dst=live/rel;old=release/rel
        if old.exists():shutil.copy2(old,dst)
        elif dst.exists():dst.unlink()
    raise
notes=json.loads((private/'notes.json').read_text())
result={'deployed':True,'files':len(changed),'release_backup':str(release),'cpanel_htaccess_preserved':True,'private_notes':len(notes['notes']),'old_notes':sum(n['origin']=='old' for n in notes['notes']),'migration':json.loads(setup.stdout),'notes_auth_configured':True,'direct_download_auth_added':False}
(private/'last-release.json').write_text(json.dumps(result,indent=2));os.chmod(private/'last-release.json',0o600)
print(json.dumps(result,ensure_ascii=False))
