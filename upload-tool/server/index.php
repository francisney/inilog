<?php
declare(strict_types=1);
require __DIR__.'/common.php';
require __DIR__.'/panel.php';
header('X-Content-Type-Options: nosniff');header('Referrer-Policy: same-origin');header('Cache-Control: no-store');
$api=$_GET['api']??'';
if($api!==''){
    try{
        $origin=$_SERVER['HTTP_ORIGIN']??'';
        if($origin!==''&&!in_array($origin,['https://inilog.com','https://www.inilog.com'],true))throw new DomainException('Origem não autorizada.');
        if(panel_browser_request())panel_require_api(($_SERVER['REQUEST_METHOD']??'GET')!=='GET');
        if($api==='info')json_reply(['ok'=>true,'password_required'=>false,'web_password_required'=>true,'chunk_bytes'=>config()['chunk_bytes'],'max_file_bytes'=>config()['max_file_bytes']]);
        if(($_SERVER['REQUEST_METHOD']??'GET')!=='POST'){header('Allow: POST');json_reply(['ok'=>false,'error'=>'Use o método POST para enviar.'],405);}
        $result=match($api){
            'init'=>upload_init(request_json()),
            'chunk'=>session_action(fn(&$data,$meta,$part)=>upload_chunk($data,$meta,$part)),
            'finish'=>session_action(function(&$data,$meta,$part){$input=request_json();return upload_finish($data,$meta,$part,is_string($input['sha256']??null)?$input['sha256']:'');}),
            'cancel'=>session_action(fn(&$data,$meta,$part)=>upload_cancel($data,$meta,$part)),
            default=>throw new InvalidArgumentException('Operação não reconhecida.')
        };json_reply($result);
    }catch(Throwable $e){$code=match(true){$e instanceof DomainException=>403,$e instanceof OutOfBoundsException=>404,$e instanceof LengthException=>413,$e instanceof InvalidArgumentException,$e instanceof JsonException=>400,$e instanceof UnexpectedValueException=>409,default=>500};if($code===500)error_log('INILOG Upload: '.$e->getMessage());json_reply(['ok'=>false,'error'=>$code===500?'Não foi possível concluir o envio. Tente novamente.':$e->getMessage()],$code);}
}
if(($_GET['panel']??'')==='files'){panel_require_api(false);json_reply(['ok'=>true,'files'=>panel_files()]);}
$webCsrf=panel_page_access();
// Compatibilidade com envios antigos multipart no campo file.
if(($_SERVER['REQUEST_METHOD']??'GET')==='POST'){
    try{
        if(!panel_csrf_valid($_POST['csrf']??null))throw new DomainException('Atualize a página e tente novamente.');
        $upload=$_FILES['file']??null;
        if(!$upload||$upload['error']!==UPLOAD_ERR_OK)throw new RuntimeException('Nenhum arquivo válido foi recebido. Use o aplicativo para arquivos maiores.');
        $init=upload_init(['name'=>$upload['name'],'size'=>(int)$upload['size']]);
        $meta=storage().'/sessions/'.$init['id'].'.json';$part=storage().'/sessions/'.$init['id'].'.part';
        if(!move_uploaded_file($upload['tmp_name'],$part))throw new RuntimeException('Não foi possível receber o arquivo.');
        chmod($part,0600);$data=read_json($meta);$result=upload_finish($data,$meta,$part,hash_file('sha256',$part));
        header('Content-Type: text/plain; charset=UTF-8');echo 'OK: '.$data['name']." enviado com sucesso.\n".$result['url'];exit;
    }catch(Throwable $e){http_response_code(400);header('Content-Type: text/plain; charset=UTF-8');echo 'ERRO: '.$e->getMessage();exit;}
}
header("Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; base-uri 'self'; frame-ancestors 'self'; form-action 'self'");
?><!doctype html><html lang="pt-BR"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><meta name="inilog-web-csrf" content="<?=panel_escape($webCsrf)?>"><title>INILOG Upload</title><link rel="stylesheet" href="upload.css?v=3"><script src="upload.js?v=3" defer></script></head><body><main><header class="panel-header"><h1>INILOG <span>Upload</span></h1><form method="post" action="index.php"><input type="hidden" name="panel_action" value="logout"><input type="hidden" name="csrf" value="<?=panel_escape($webCsrf)?>"><button type="submit" class="logout">Sair</button></form></header><label class="file"><input type="file" id="file"><span id="filename">Escolher arquivo</span><small id="size">Qualquer formato de arquivo</small></label><div class="progress-row"><progress id="progress" value="0" max="100"></progress><strong id="percent">0%</strong></div><p id="status" role="status">Selecione um arquivo para começar.</p><div class="actions"><button id="send" disabled>Carregar</button><button id="copy" disabled>Copiar link</button></div><input id="url" readonly aria-label="Link para compartilhar" placeholder="O link aparecerá aqui"><details id="files-panel"><summary>Listar arquivos <span id="files-count"></span></summary><div class="files-toolbar"><input type="search" id="files-search" aria-label="Buscar arquivo" placeholder="Buscar arquivo…"><button type="button" id="files-refresh">Atualizar</button></div><p id="files-status" role="status">Abra a lista para consultar os arquivos.</p><div id="files-list"></div></details><footer>Francisney Delmondes | INILOG<br>(61) 99363-0969 · suporte@inilog.com<br>www.inilog.com</footer></main></body></html>
