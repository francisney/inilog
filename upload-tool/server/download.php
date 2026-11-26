<?php
declare(strict_types=1);
require __DIR__.'/common.php';
$id=$_GET['file']??'';
if(!is_string($id)||!preg_match('/^[a-f0-9]{32}$/',$id)){http_response_code(404);exit('Arquivo não encontrado.');}
$meta=storage().'/files/'.$id.'.json';$blob=storage().'/files/'.$id.'.blob';
if(!is_file($meta)||!is_file($blob)){http_response_code(404);exit('Arquivo não encontrado.');}
try{$info=read_json($meta);}catch(Throwable){http_response_code(404);exit('Arquivo indisponível.');}
$size=(int)$info['size'];$start=0;$end=$size-1;$range=$_SERVER['HTTP_RANGE']??'';
if($range!==''){
    if(!is_string($range)||!preg_match('/^bytes=(\d*)-(\d*)$/',$range,$m)||($m[1]===''&&$m[2]==='')){http_response_code(416);header('Content-Range: bytes */'.$size);exit;}
    if($m[1]===''){$suffix=(int)$m[2];$start=max(0,$size-$suffix);}else{$start=(int)$m[1];if($m[2]!=='')$end=min($end,(int)$m[2]);}
    if($start>$end||$start>=$size){http_response_code(416);header('Content-Range: bytes */'.$size);exit;}
    http_response_code(206);header('Content-Range: bytes '.$start.'-'.$end.'/'.$size);
}
$name=$info['name'];$safe=preg_replace('/[^a-zA-Z0-9 ._()-]/','_',$name);$ext=strtolower(pathinfo($name,PATHINFO_EXTENSION));
$text=in_array($ext,['ps1','cmd','bat','txt','json','xml','csv','ini','cfg','md','html','htm','php','phtml','sh','py','js','css','htaccess'],true);
header('Content-Type: '.($text?'text/plain; charset=UTF-8':'application/octet-stream'));
header('Content-Disposition: attachment; filename="'.$safe.'"; filename*=UTF-8\'\''.rawurlencode($name));
header('Content-Length: '.($size===0?0:$end-$start+1));header('X-Content-Type-Options: nosniff');header("Content-Security-Policy: sandbox; default-src 'none'");header('Referrer-Policy: no-referrer');header('Accept-Ranges: bytes');header('ETag: "'.$info['sha256'].'"');header('Cache-Control: public, max-age=86400, immutable');
if(($_SERVER['REQUEST_METHOD']??'GET')==='HEAD'||$size===0)exit;
$file=fopen($blob,'rb');if(!$file){http_response_code(404);exit;}
fseek($file,$start);$remaining=$end-$start+1;@set_time_limit(0);
while($remaining>0&&!connection_aborted()){$chunk=fread($file,min(1024*1024,$remaining));if($chunk===false||$chunk==='')break;echo $chunk;$remaining-=strlen($chunk);}
fclose($file);
