'use strict';
const fileInput=document.getElementById('file'),send=document.getElementById('send'),copy=document.getElementById('copy'),status=document.getElementById('status'),progress=document.getElementById('progress'),percent=document.getElementById('percent'),link=document.getElementById('url');
let current=null,controller=null,session=null;
const format=n=>n>=1073741824?(n/1073741824).toFixed(2)+' GB':n>=1048576?(n/1048576).toFixed(1)+' MB':n>=1024?(n/1024).toFixed(1)+' KB':n+' B';
function display(value,message){progress.value=value;percent.textContent=value+'%';status.textContent=message;}
function sha(bytes){return crypto.subtle.digest('SHA-256',bytes).then(hash=>Array.from(new Uint8Array(hash),x=>x.toString(16).padStart(2,'0')).join(''));}
async function call(action,body,headers={}){const response=await fetch('index.php?api='+action,{method:'POST',headers,body,signal:controller.signal});let data;try{data=await response.json();}catch{throw Error('A hospedagem recusou o envio. Tente novamente.');}if(!response.ok||!data.ok)throw Error(data.error||'Não foi possível concluir o envio.');return data;}
fileInput.addEventListener('change',()=>{current=fileInput.files[0]||null;document.getElementById('filename').textContent=current?current.name:'Escolher arquivo';document.getElementById('size').textContent=current?format(current.size):'Qualquer formato de arquivo';send.disabled=!current;copy.disabled=true;link.value='';display(0,current?'Pronto para enviar.':'Selecione um arquivo para começar.');});
send.addEventListener('click',async()=>{
 if(controller){controller.abort();return;}if(!current)return;
 controller=new AbortController();send.textContent='Cancelar';fileInput.disabled=true;copy.disabled=true;link.value='';session=null;
 try{
  display(0,'Preparando envio…');session=await call('init',JSON.stringify({name:current.name,size:current.size}),{'Content-Type':'application/json'});
  let offset=0;
  while(offset<current.size){const bytes=await current.slice(offset,offset+session.chunk_bytes).arrayBuffer();const chunkHash=await sha(bytes);const result=await call('chunk&id='+session.id+'&offset='+offset,bytes,{'Content-Type':'application/octet-stream','X-Inilog-Token':session.token,'X-Inilog-Chunk-SHA256':chunkHash});offset=result.offset;display(Math.min(99,Math.floor(100*offset/Math.max(1,current.size))),'Enviando '+format(offset)+' de '+format(current.size));}
  display(99,'Confirmando arquivo…');const result=await call('finish&id='+session.id,JSON.stringify({}),{'Content-Type':'application/json','X-Inilog-Token':session.token});
  link.value=result.url;copy.disabled=false;display(100,'Upload concluído. Copie o link para compartilhar.');
 }catch(error){display(progress.value,error.name==='AbortError'?'Envio cancelado.':error.message);if(session)fetch('index.php?api=cancel&id='+session.id,{method:'POST',headers:{'X-Inilog-Token':session.token},keepalive:true}).catch(()=>{});}
 finally{controller=null;session=null;fileInput.disabled=false;send.disabled=!current;send.textContent='Carregar';}
});
copy.addEventListener('click',async()=>{try{await navigator.clipboard.writeText(link.value);status.textContent='Link copiado.';}catch{link.select();document.execCommand('copy');status.textContent='Link selecionado para copiar.';}});
