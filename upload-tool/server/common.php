<?php
declare(strict_types=1);
ini_set('display_errors','0');
function storage(): string { return getenv('INILOG_UPLOAD_STORAGE')?:dirname(__DIR__,2).'/.inilog-upload'; }
function config(): array {
    $file=storage().'/config.php';
    return is_file($file)?require $file:['chunk_bytes'=>4*1024*1024,'max_file_bytes'=>20*1024*1024*1024,'public_base'=>'https://inilog.com/backup/uploads/'];
}
function directories(): void {foreach(['','sessions','files'] as $part){$p=storage().($part?'/'.$part:'');if(!is_dir($p)&&!mkdir($p,0700,true)&&!is_dir($p))throw new RuntimeException('Não foi possível preparar o recebimento.');}}
function json_reply(array $value,int $code=200): never {http_response_code($code);header('Content-Type: application/json; charset=UTF-8');header('Cache-Control: no-store');header('X-Content-Type-Options: nosniff');echo json_encode($value,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);exit;}
function read_json(string $file): array {$value=json_decode((string)file_get_contents($file),true,512,JSON_THROW_ON_ERROR);if(!is_array($value))throw new RuntimeException('Dados indisponíveis.');return $value;}
function write_json(string $file,array $data): void {
    $body=json_encode($data,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);$temp=tempnam(dirname($file),'.write-');
    if($temp===false)throw new RuntimeException('Não foi possível preparar o salvamento.');
    try{if(file_put_contents($temp,$body,LOCK_EX)!==strlen($body))throw new RuntimeException('Não foi possível salvar. Verifique o espaço disponível.');chmod($temp,0600);if(!rename($temp,$file))throw new RuntimeException('Não foi possível concluir o salvamento.');}finally{if(is_file($temp))unlink($temp);}
}
function request_json(): array {$body=file_get_contents('php://input',false,null,0,16385);if($body===false||strlen($body)>16384)throw new InvalidArgumentException('Requisição inválida.');$data=json_decode($body,true,32,JSON_THROW_ON_ERROR);if(!is_array($data))throw new InvalidArgumentException('Requisição inválida.');return $data;}
function clean_name(mixed $value): string {
    if(!is_string($value)||$value===''||strlen($value)>1000||!preg_match('//u',$value)||preg_match('/[\x00-\x1F\x7F]/',$value)||str_contains($value,'/')||str_contains($value,'\\')||in_array($value,['.','..'],true))throw new InvalidArgumentException('Nome de arquivo inválido.');
    return $value;
}
function cleanup(): void {
    $now=time();$files=glob(storage().'/sessions/*.json')?:[];$count=0;
    foreach($files as $file){if(++$count>500)break;if(filemtime($file)>$now-86400)continue;
        $id=basename($file,'.json');$lock=fopen(storage().'/sessions/'.$id.'.lock','c');if(!$lock)continue;
        if(flock($lock,LOCK_EX|LOCK_NB)){try{if(is_file($file)&&filemtime($file)<$now-86400){$data=read_json($file);if(($data['status']??'')!=='complete')@unlink(storage().'/sessions/'.$id.'.part');@unlink($file);}}finally{flock($lock,LOCK_UN);}}
        fclose($lock);
    }
}
function session_action(callable $callback): array {
    $id=$_GET['id']??'';$token=$_SERVER['HTTP_X_INILOG_TOKEN']??'';
    if(!is_string($id)||!preg_match('/^[a-f0-9]{32}$/',$id)||!is_string($token)||!preg_match('/^[a-f0-9]{64}$/',$token))throw new InvalidArgumentException('Envio inválido.');
    $file=storage().'/sessions/'.$id.'.json';$lock=fopen(storage().'/sessions/'.$id.'.lock','c');if(!$lock||!flock($lock,LOCK_EX))throw new RuntimeException('Este envio está ocupado. Tente novamente.');
    try{
        if(!is_file($file))throw new OutOfBoundsException('O envio expirou. Selecione o arquivo novamente.');
        $data=read_json($file);if(!hash_equals($data['token_hash'],hash('sha256',$token)))throw new DomainException('Envio não autorizado.');
        return $callback($data,$file,storage().'/sessions/'.$id.'.part');
    }finally{flock($lock,LOCK_UN);fclose($lock);}
}
function upload_init(array $request): array {
    directories();cleanup();$name=clean_name($request['name']??null);$size=$request['size']??null;
    if(!is_int($size)||$size<0)throw new InvalidArgumentException('Tamanho de arquivo inválido.');
    $cfg=config();if($size>$cfg['max_file_bytes'])throw new LengthException('O arquivo excede o limite de 20 GB por envio.');
    $free=disk_free_space(storage());if($free!==false&&$size+128*1024*1024>$free)throw new LengthException('A hospedagem não tem espaço suficiente para este arquivo.');
    $id=bin2hex(random_bytes(16));$token=bin2hex(random_bytes(32));$download=bin2hex(random_bytes(16));
    $data=['id'=>$id,'name'=>$name,'size'=>$size,'download_id'=>$download,'token_hash'=>hash('sha256',$token),'status'=>'pending','created_at'=>time()];
    $part=storage().'/sessions/'.$id.'.part';if(file_put_contents($part,'')===false)throw new RuntimeException('Não foi possível iniciar o envio.');chmod($part,0600);
    try{write_json(storage().'/sessions/'.$id.'.json',$data);}catch(Throwable $e){@unlink($part);throw $e;}
    return ['ok'=>true,'id'=>$id,'token'=>$token,'chunk_bytes'=>$cfg['chunk_bytes'],'offset'=>0];
}
function upload_chunk(array &$data,string $meta,string $part): array {
    if($data['status']==='complete')return ['ok'=>true,'offset'=>$data['size']];
    $offset=filter_var($_GET['offset']??null,FILTER_VALIDATE_INT);$length=filter_var($_SERVER['CONTENT_LENGTH']??null,FILTER_VALIDATE_INT);$expected=$_SERVER['HTTP_X_INILOG_CHUNK_SHA256']??'';
    if($offset===false||$offset<0||$length===false||$length<=0||$length>config()['chunk_bytes']||$offset+$length>$data['size']||!is_string($expected)||!preg_match('/^[a-f0-9]{64}$/',$expected))throw new InvalidArgumentException('Bloco de envio inválido.');
    $input=fopen('php://input','rb');$bytes=stream_get_contents($input,$length+1);fclose($input);
    if($bytes===false||strlen($bytes)!==$length||!hash_equals($expected,hash('sha256',$bytes)))throw new UnexpectedValueException('O bloco chegou incompleto. Tente novamente.');
    clearstatcache(true,$part);$current=filesize($part);
    if($current!==$offset){
        if($current===$offset+$length){$check=fopen($part,'rb');fseek($check,$offset);$old=stream_get_contents($check,$length);fclose($check);if(hash_equals($expected,hash('sha256',$old)))return ['ok'=>true,'offset'=>$current];}
        throw new UnexpectedValueException('O envio está fora de sequência. Selecione o arquivo novamente.');
    }
    $file=fopen($part,'c+b');if(!$file)throw new RuntimeException('Não foi possível receber o arquivo.');
    try{fseek($file,$offset);$written=0;while($written<$length){$n=fwrite($file,substr($bytes,$written));if($n===false||$n===0)throw new RuntimeException('Não foi possível gravar o bloco. Verifique o espaço disponível.');$written+=$n;}if(!fflush($file))throw new RuntimeException('Não foi possível confirmar a gravação.');}
    catch(Throwable $e){ftruncate($file,$offset);throw $e;}finally{fclose($file);}
    touch($meta);return ['ok'=>true,'offset'=>$offset+$length];
}
function upload_finish(array &$data,string $meta,string $part,string $expected): array {
    if($expected!==''&&!preg_match('/^[a-f0-9]{64}$/',$expected))throw new InvalidArgumentException('Verificação do arquivo inválida.');
    if($data['status']==='complete'){
        if($expected!==''&&!hash_equals($data['sha256'],$expected))throw new UnexpectedValueException('Este envio já foi concluído com outro conteúdo.');
        return ['ok'=>true,'url'=>$data['url'],'sha256'=>$data['sha256'],'size'=>$data['size']];
    }
    clearstatcache(true,$part);if(filesize($part)!==$data['size'])throw new UnexpectedValueException('O envio ainda não está completo.');
    @set_time_limit(180);$hash=hash_file('sha256',$part);if($expected!==''&&!hash_equals($expected,$hash))throw new UnexpectedValueException('O arquivo recebido não corresponde ao original. Tente enviá-lo novamente.');
    $id=$data['download_id'];$target=storage().'/files/'.$id.'.blob';$metadata=storage().'/files/'.$id.'.json';
    $url=rtrim(config()['public_base'],'/').'/'.$id;
    $published=['id'=>$id,'name'=>$data['name'],'size'=>$data['size'],'sha256'=>$hash,'created_at'=>time()];
    if(!rename($part,$target))throw new RuntimeException('Não foi possível concluir o envio.');
    try{chmod($target,0600);write_json($metadata,$published);$data['status']='complete';$data['url']=$url;$data['sha256']=$hash;write_json($meta,$data);}
    catch(Throwable $e){@unlink($metadata);@rename($target,$part);throw $e;}
    return ['ok'=>true,'url'=>$url,'sha256'=>$hash,'size'=>$data['size']];
}
function upload_cancel(array &$data,string $meta,string $part): array {if($data['status']!=='complete'){@unlink($part);@unlink($meta);}return ['ok'=>true];}
