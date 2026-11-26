'use strict';
const fileInput=document.getElementById('file'),send=document.getElementById('send'),copy=document.getElementById('copy'),status=document.getElementById('status'),progress=document.getElementById('progress'),percent=document.getElementById('percent'),link=document.getElementById('url');
let current=null,controller=null,session=null;
const webCsrf=document.querySelector('meta[name="inilog-web-csrf"]').content;
const webHeaders={'X-Inilog-Web':'1','X-Inilog-Web-CSRF':webCsrf};
const format=n=>n>=1073741824?(n/1073741824).toFixed(2)+' GB':n>=1048576?(n/1048576).toFixed(1)+' MB':n>=1024?(n/1024).toFixed(1)+' KB':n+' B';
function display(value,message){progress.value=value;percent.textContent=value+'%';status.textContent=message;}
function sha(bytes){return crypto.subtle.digest('SHA-256',bytes).then(hash=>Array.from(new Uint8Array(hash),x=>x.toString(16).padStart(2,'0')).join(''));}
async function call(action,body,headers={}){const response=await fetch('index.php?web=1&api='+action,{method:'POST',headers:{...headers,...webHeaders},body,signal:controller.signal});let data;try{data=await response.json();}catch{throw Error('A hospedagem recusou o envio. Tente novamente.');}if(!response.ok||!data.ok)throw Error(data.error||'Não foi possível concluir o envio.');return data;}
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
  if(document.getElementById('files-panel').open)loadFiles();
 }catch(error){display(progress.value,error.name==='AbortError'?'Envio cancelado.':error.message);if(session)fetch('index.php?web=1&api=cancel&id='+session.id,{method:'POST',headers:{'X-Inilog-Token':session.token,...webHeaders},keepalive:true}).catch(()=>{});}
 finally{controller=null;session=null;fileInput.disabled=false;send.disabled=!current;send.textContent='Carregar';}
});
copy.addEventListener('click',async()=>{try{await navigator.clipboard.writeText(link.value);status.textContent='Link copiado.';}catch{link.select();document.execCommand('copy');status.textContent='Link selecionado para copiar.';}});

const filesPanel=document.getElementById('files-panel'),filesList=document.getElementById('files-list'),filesStatus=document.getElementById('files-status'),filesSearch=document.getElementById('files-search');
let listedFiles=[],filesLoading=false;
const searchKey=value=>value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
function renderFiles(){
 const term=searchKey(filesSearch.value),visible=listedFiles.filter(file=>searchKey(file.name).includes(term));filesList.replaceChildren();
 document.getElementById('files-count').textContent='('+listedFiles.length+')';
 filesStatus.textContent=visible.length?visible.length+' arquivo'+(visible.length===1?'':'s')+(term?' encontrado'+(visible.length===1?'':'s'):'')+'.':term?'Nenhum arquivo corresponde à busca.':'Nenhum arquivo disponível.';
 for(const file of visible){
  const row=document.createElement('div');row.className='listed-file';
  const info=document.createElement('div');info.className='listed-info';
  const name=document.createElement('strong');name.textContent=file.name;
  const details=document.createElement('small');details.textContent=format(file.size)+' · '+new Date(file.created_at*1000).toLocaleDateString('pt-BR');
  info.append(name,details);
  const actions=document.createElement('div');actions.className='listed-actions';
  const download=document.createElement('a');download.href=file.url;download.textContent='Baixar';download.download='';
  const copyLink=document.createElement('button');copyLink.type='button';copyLink.textContent='Copiar link';copyLink.dataset.copyUrl=file.url;
  actions.append(download,copyLink);
  if(file.deletable){const remove=document.createElement('button');remove.type='button';remove.textContent='Apagar';remove.className='delete-file';remove.dataset.deleteKey=file.key;remove.dataset.filename=file.name;actions.append(remove);}
  row.append(info,actions);filesList.append(row);
 }
}
async function loadFiles(){
 if(filesLoading)return;filesLoading=true;filesStatus.textContent='Carregando arquivos…';document.getElementById('files-refresh').disabled=true;
 try{const response=await fetch('index.php?panel=files',{headers:{Accept:'application/json',...webHeaders},cache:'no-store'});const data=await response.json();if(!response.ok||!data.ok)throw Error(data.error||'Não foi possível carregar a lista.');listedFiles=data.files;renderFiles();}
 catch(error){filesStatus.textContent=error.message;}
 finally{filesLoading=false;document.getElementById('files-refresh').disabled=false;}
}
filesPanel.addEventListener('toggle',()=>{if(filesPanel.open)loadFiles();});
document.getElementById('files-refresh').addEventListener('click',loadFiles);
filesSearch.addEventListener('input',renderFiles);
filesList.addEventListener('click',async event=>{
 const remove=event.target.closest('[data-delete-key]');
 if(remove){
  if(!window.confirm('Apagar o arquivo "'+remove.dataset.filename+'"?\nEle sairá da lista e o link deixará de estar disponível no servidor.'))return;
  remove.disabled=true;
  try{const response=await fetch('index.php?panel=delete',{method:'POST',headers:{'Content-Type':'application/json',...webHeaders},body:JSON.stringify({key:remove.dataset.deleteKey})});const data=await response.json();if(!response.ok||!data.ok)throw Error(data.error||'Não foi possível apagar o arquivo.');listedFiles=listedFiles.filter(file=>file.key!==remove.dataset.deleteKey);renderFiles();filesStatus.textContent=data.message;}
  catch(error){filesStatus.textContent=error.message;remove.disabled=false;}
  return;
 }
 const button=event.target.closest('[data-copy-url]');if(!button)return;
 try{await navigator.clipboard.writeText(button.dataset.copyUrl);filesStatus.textContent='Link copiado.';}catch{link.value=button.dataset.copyUrl;link.select();filesStatus.textContent='Link selecionado no campo acima. Use Ctrl+C para copiar.';}
});
