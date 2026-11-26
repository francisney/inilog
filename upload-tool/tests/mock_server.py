import argparse,json,hashlib,secrets,threading,time,urllib.parse
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
sessions={};guard=threading.RLock()
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def reply(self,data,status=200):
  body=json.dumps(data).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
 def do_GET(self):
  if self.path.startswith('/backup/uploads/'):
   key=self.path.split('/')[3]
   with guard:item=next((x for x in sessions.values() if x['download']==key),None)
   if item is None:self.reply({'ok':False},404);return
   body=bytes(item['bytes']);self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body);return
  self.reply({'ok':False},404)
 def do_POST(self):
  query=urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query);action=query.get('api',[''])[0];body=self.rfile.read(int(self.headers.get('Content-Length','0')))
  with guard:
   if action=='init':
    data=json.loads(body);key=secrets.token_hex(16);token=secrets.token_hex(32);sessions[key]={'name':data['name'],'size':data['size'],'token':token,'bytes':bytearray(),'download':secrets.token_hex(16),'retry':False}
    self.reply({'ok':True,'id':key,'token':token,'chunk_bytes':65536});return
   key=query.get('id',[''])[0];item=sessions.get(key)
   if item is None or self.headers.get('X-Inilog-Token')!=item['token']:self.reply({'ok':False,'error':'Sessão inválida'},403);return
   if action=='chunk':
    offset=int(query['offset'][0]);digest=self.headers['X-Inilog-Chunk-SHA256'];assert hashlib.sha256(body).hexdigest()==digest
    if item['name'].startswith('slow'):time.sleep(.4)
    if len(item['bytes'])==offset:item['bytes'].extend(body)
    else:assert bytes(item['bytes'][offset:offset+len(body)])==body
    # Simula resposta perdida depois de o servidor já ter gravado um bloco.
    if item['name'].startswith('retry') and not item['retry']:
     item['retry']=True;self.reply({'ok':False,'error':'retry'},503);return
    self.reply({'ok':True,'offset':len(item['bytes'])});return
   if action=='finish':
    digest=hashlib.sha256(item['bytes']).hexdigest();assert digest==json.loads(body)['sha256'];assert len(item['bytes'])==item['size']
    url='http://127.0.0.1:'+str(self.server.server_address[1])+'/backup/uploads/'+item['download']+'/'+urllib.parse.quote(item['name'])
    self.reply({'ok':True,'url':url,'sha256':digest,'size':item['size']});return
   if action=='cancel':sessions.pop(key,None);self.reply({'ok':True});return
   self.reply({'ok':False},400)
p=argparse.ArgumentParser();p.add_argument('--ready',required=True);args=p.parse_args();server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
Path(args.ready).write_text(json.dumps({'endpoint':'http://127.0.0.1:'+str(server.server_address[1])+'/backup/index.php'}));server.serve_forever()
