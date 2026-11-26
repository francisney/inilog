<?php
declare(strict_types=1);
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
$backup=$argv[1]??'';$private=$argv[2]??'';$live=$argv[3]??'';
if(!$backup||!$private||!$live)throw new RuntimeException('Uso: setup.php BACKUP PRIVATE_DIR LIVE_SUPORTE');
if(!is_dir($private))mkdir($private,0700,true);chmod($private,0700);
if(!is_file($private.'/config.php')) {
    $tokens=token_get_all(file_get_contents($backup.'/public_html/suporte/628/index.php'));$password=null;
    foreach($tokens as $i=>$token){
        if(!is_array($token)||!in_array($token[0],[T_IS_EQUAL,T_IS_IDENTICAL],true))continue;
        $context='';for($j=max(0,$i-8);$j<$i;$j++)$context.=is_array($tokens[$j])?$tokens[$j][1]:$tokens[$j];
        if(!str_contains($context,'senha'))continue;
        for($j=$i+1;$j<count($tokens);$j++){
            if(is_array($tokens[$j])&&$tokens[$j][0]===T_WHITESPACE)continue;
            if(is_array($tokens[$j])&&$tokens[$j][0]===T_CONSTANT_ENCAPSED_STRING)$password=eval('return '.$tokens[$j][1].';');
            break;
        }
        if($password!==null)break;
    }
    if(!is_string($password)||$password==='')throw new RuntimeException('A senha anterior não pôde ser preservada.');
    require $backup.'/public_html/suporte/geral/dbcontroller.php';
    $defaults=(new ReflectionClass('DBController'))->getDefaultProperties();
    $config=['password_hash'=>password_hash($password,PASSWORD_DEFAULT),'database'=>array_intersect_key($defaults,array_flip(['host','user','password','database']))];
    $output="<?php\nreturn ".var_export($config,true).";\n";
    if(file_put_contents($private.'/config.php',$output,LOCK_EX)!==strlen($output))throw new RuntimeException('Não foi possível salvar a configuração.');
    chmod($private.'/config.php',0600);unset($password,$defaults,$config,$output);
}
$notes=[];$sources=[];
foreach(['mensagens.txt'=>'current','old.txt'=>'old'] as $file=>$origin){
    $raw=file_get_contents($live.'/notas/'.$file);
    if(!mb_check_encoding($raw,'UTF-8'))$raw=mb_convert_encoding($raw,'UTF-8','Windows-1252');
    if($origin==='current'){
        $parts=preg_split('/<p\s+align\s*=\s*left>\s*<font\s+color\s*=\s*#000000>\s*_{5,}\s*<\/font>/i',$raw);
    }else $parts=preg_split('/(?:\r?\n)?[\t ]*_{5,}[\t ]*(?:\r?\n)?/',$raw);
    $texts=[];
    foreach($parts as $part){
        $text=$origin==='current'?html_entity_decode(strip_tags(preg_replace('/<br\s*\/?\s*>/i',"\n",$part)),ENT_QUOTES|ENT_HTML5,'UTF-8'):$part;
        $text=trim(str_replace(["\r\n","\r"],"\n",$text));
        if($text==='')continue;
        $texts[]=$text;$id=substr(hash('sha256',$file.'|'.count($texts).'|'.$text),0,24);
        $notes[]=['id'=>$id,'title'=>'','body'=>$text,'origin'=>$origin,'favorite'=>false,'created_at'=>null,'updated_at'=>null,'revision'=>1];
    }
    $sources[$file]=['hash'=>hash('sha256',$raw),'notes'=>count($texts),'body_hash'=>hash('sha256',implode("\n",$texts))];
}
if(!is_file($private.'/notes.json')){
    $out=json_encode(['version'=>1,'notes'=>$notes,'trash'=>[],'legacy_import'=>$sources],JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);
    file_put_contents($private.'/notes.json',$out,LOCK_EX);chmod($private.'/notes.json',0600);
}
echo json_encode(['configured'=>true,'notes'=>count($notes),'sources'=>$sources],JSON_UNESCAPED_UNICODE)."\n";
