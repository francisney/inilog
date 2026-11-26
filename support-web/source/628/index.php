<?php
declare(strict_types=1);
require dirname(__DIR__).'/_inilog/app.php';
require_auth('files');
$root=__DIR__.'/files';$error='';$edit=null;$editText='';
$extensions=['txt','ps1','cmd','bat','json','ini','cfg','md','log','xml','yaml','yml','css','js','html','htm','csv','url'];
function managed_file(string $name): string {
    global $root;
    if ($name===''||basename($name)!==$name||str_contains($name,'\\')||str_starts_with($name,'.')||preg_match('/[\x00-\x1f\x7f]/',$name)||text_length($name)>220) throw new RuntimeException('Nome de arquivo não permitido.');
    if (preg_match('/\.(?:php\d*|phtml|phar|cgi|pl|py|sh|htaccess|htpasswd)(?:\.|$)/i',$name)) throw new RuntimeException('Este tipo de arquivo não é permitido no diretório de downloads.');
    $path=$root.'/'.$name;
    if(is_link($path)||is_dir($path))throw new RuntimeException('Este caminho não é um arquivo gerenciado.');
    return $path;
}
function text_file(string $path): bool {
    global $extensions;
    return basename($path)==='LICENSE'||in_array(strtolower(pathinfo($path,PATHINFO_EXTENSION)),$extensions,true);
}
function file_revision(string $path): string {
    $s=stat($path);
    return fingerprint([basename($path),$s['size'],$s['mtime'],$s['ctime'],$s['ino']]);
}
function backup_file(string $path,string $reason): string {
    $dir=private_dir().'/file-backups';if(!is_dir($dir))mkdir($dir,0700,true);
    $key=uid();$dest=$dir.'/'.$key.'.data';
    if(!copy($path,$dest))throw new RuntimeException('Não foi possível criar uma cópia de segurança. Nenhuma alteração foi feita.');
    chmod($dest,0600);write_json($dir.'/'.$key.'.json',['name'=>basename($path),'reason'=>$reason,'created_at'=>gmdate('c'),'hash'=>hash_file('sha256',$path)]);
    return $key;
}
try {
    if ($_SERVER['REQUEST_METHOD']==='POST') {
        check_csrf();$action=$_POST['action']??'';
        if ($action==='upload') {
            $upload=$_FILES['arquivo']??null;
            if(!$upload||$upload['error']!==UPLOAD_ERR_OK)throw new RuntimeException('O envio não foi concluído. Confira o tamanho do arquivo e o limite da hospedagem.');
            $name=$upload['name'];if(!is_string($name))throw new RuntimeException('Nome de arquivo inválido.');
            $path=managed_file($name);
            if(is_file($path)&&empty($_POST['overwrite']))throw new RuntimeException('Já existe um arquivo com esse nome. Marque a opção para substituí-lo.');
            if(is_file($path))backup_file($path,'overwrite');
            if(!move_uploaded_file($upload['tmp_name'],$path))throw new RuntimeException('Não foi possível salvar o arquivo enviado.');
            chmod($path,0644);flash('Arquivo enviado: '.$name);
        } elseif ($action==='delete') {
            $name=is_string($_POST['name']??null)?$_POST['name']:'';$path=managed_file($name);
            if(!is_file($path))throw new RuntimeException('Arquivo não encontrado.');
            $expected=$_POST['revision']??'';
            if(!is_string($expected)||!hash_equals(file_revision($path),$expected))throw new RuntimeException('O arquivo mudou em outra janela. Recarregue antes de excluir.');
            $key=backup_file($path,'deleted');
            if(!unlink($path))throw new RuntimeException('Não foi possível excluir o arquivo.');
            mutate_json(private_dir().'/file-trash.json',function (&$items)use($key,$name){$items[$key]=['name'=>$name,'deleted_at'=>gmdate('c')];});
            flash('Arquivo movido para a lixeira. Você pode restaurá-lo.');
        } elseif ($action==='restore') {
            $key=$_POST['key']??'';if(!is_string($key)||!preg_match('/^[a-f0-9]{24}$/',$key))throw new RuntimeException('Cópia não encontrada.');
            mutate_json(private_dir().'/file-trash.json',function (&$items)use($key){
                if(!isset($items[$key]))throw new RuntimeException('Esta cópia não está mais na lixeira.');
                $path=managed_file($items[$key]['name']);if(file_exists($path))throw new RuntimeException('Já existe um arquivo com esse nome. Renomeie ou exclua a cópia atual antes de restaurar.');
                if(!copy(private_dir().'/file-backups/'.$key.'.data',$path))throw new RuntimeException('Não foi possível restaurar.');
                chmod($path,0644);unset($items[$key]);
            });flash('Arquivo restaurado.');
        } elseif ($action==='edit') {
            $name=is_string($_POST['name']??null)?$_POST['name']:'';$path=managed_file($name);
            if(!is_file($path)||!text_file($path)||filesize($path)>2*1024*1024)throw new RuntimeException('Este arquivo não pode ser editado como texto no painel.');
            if(!is_string($_POST['revision']??null)||!hash_equals(hash_file('sha256',$path),$_POST['revision']))throw new RuntimeException('O arquivo mudou em outra janela. Recarregue para evitar sobrescrever uma versão mais recente.');
            $body=$_POST['body']??null;
            if(!is_string($body)||strlen($body)>2*1024*1024||str_contains($body,"\0")||!preg_match('//u',$body))throw new RuntimeException('O conteúdo precisa ser texto UTF-8 com até 2 MB.');
            backup_file($path,'edit');$tmp=tempnam($root,'.edit-');
            try {if(file_put_contents($tmp,$body,LOCK_EX)!==strlen($body))throw new RuntimeException('O arquivo não foi salvo por completo.');chmod($tmp,0644);if(!rename($tmp,$path))throw new RuntimeException('Não foi possível concluir o salvamento.');}
            finally {if(is_file($tmp))unlink($tmp);}
            flash('Alterações salvas: '.$name);
        } else throw new RuntimeException('Ação não reconhecida.');
        redirect('index.php'.($action==='restore'?'?trash=1':''));
    }
    if(isset($_GET['read'])) {
        $path=managed_file(is_string($_GET['read'])?$_GET['read']:'');
        if(!is_file($path)||!text_file($path)||filesize($path)>2*1024*1024)throw new RuntimeException('Visualização de texto indisponível para este arquivo.');
        header('Content-Type: text/plain; charset=UTF-8');readfile($path);exit;
    }
    if(isset($_GET['edit'])) {
        $path=managed_file(is_string($_GET['edit'])?$_GET['edit']:'');
        if(!is_file($path)||!text_file($path)||filesize($path)>2*1024*1024)throw new RuntimeException('Este arquivo não pode ser editado como texto no painel.');
        $edit=['name'=>basename($path),'revision'=>hash_file('sha256',$path)];$editText=(string)file_get_contents($path);
        if(!preg_match('//u',$editText)||str_contains($editText,"\0"))throw new RuntimeException('Este conteúdo não é texto UTF-8. Faça o download para editá-lo.');
    }
} catch(Throwable $e) { $error=fail_message($e);if(($_POST['action']??'')==='edit'){$edit=['name'=>$_POST['name']??'','revision'=>$_POST['revision']??''];$editText=is_string($_POST['body']??null)?$_POST['body']:'';} }
$files=[];$totalSize=0;$scripts=0;
foreach(new DirectoryIterator($root) as $entry) {
    if(!$entry->isFile()||$entry->isLink()||str_starts_with($entry->getFilename(),'.'))continue;
    $name=$entry->getFilename();if(in_array(strtolower($name),['index.php','index.html','index.htm'],true))continue;
    $ext=strtolower(pathinfo($name,PATHINFO_EXTENSION));$totalSize+=$entry->getSize();if(in_array($ext,['ps1','cmd','bat'],true))$scripts++;
    $files[]=['name'=>$name,'bytes'=>$entry->getSize(),'mtime'=>$entry->getMTime(),'ext'=>$ext,'text'=>text_file($entry->getPathname())&&$entry->getSize()<=2*1024*1024,'revision'=>file_revision($entry->getPathname())];
}
$q=is_string($_GET['q']??null)?trim($_GET['q']):'';$type=is_string($_GET['type']??null)?$_GET['type']:'';
$filtered=array_values(array_filter($files,function($file)use($q,$type){
    if($q!==''&&mb_stripos($file['name'],$q,0,'UTF-8')===false)return false;
    return match($type){'scripts'=>in_array($file['ext'],['ps1','cmd','bat'],true),'apps'=>in_array($file['ext'],['exe','msi'],true),'archives'=>in_array($file['ext'],['zip','rar','7z'],true),default=>true};
}));
usort($filtered,fn($a,$b)=>strnatcasecmp($a['name'],$b['name']));
$trash=read_json(private_dir().'/file-trash.json');
$ip=$_SERVER['REMOTE_ADDR']??'';$city='';
if(filter_var($ip,FILTER_VALIDATE_IP)&&!isset($_SESSION['inilog_city'][$ip])) {
    $context=stream_context_create(['http'=>['timeout'=>1.3,'ignore_errors'=>true]]);
    $info=json_decode((string)@file_get_contents('https://ipinfo.io/'.rawurlencode($ip).'/json',false,$context),true);
    $_SESSION['inilog_city'][$ip]=is_array($info)?($info['city']??''):'';
}
$city=$_SESSION['inilog_city'][$ip]??'';
$canonical='https://inilog.com/suporte/628/files/';
page_head('Arquivos de suporte','files');
?>
<section class="hero"><div><span class="eyebrow">FERRAMENTAS E DOWNLOADS</span><h1>Arquivos de suporte</h1><p>Os arquivos que você usa no dia a dia, organizados e prontos para compartilhar.</p></div><a class="button primary" href="#upload">+ Enviar arquivo</a></section>
<div class="stats"><div class="stat"><strong><?=count($files)?></strong><span>arquivos disponíveis</span></div><div class="stat"><strong><?=h(size_label($totalSize))?></strong><span>armazenados</span></div><div class="stat"><strong><?=$scripts?></strong><span>scripts de suporte</span></div></div>
<p class="connection">Sua conexão: <?=h($ip)?><?=$city?' · '.h($city):''?></p>
<?php error_notice($error);if($edit): ?>
<section class="card editor"><h2>Editar <?=h($edit['name'])?></h2><p class="muted small">Uma cópia da versão anterior será guardada antes do salvamento.</p><form method="post" class="stack"><?php csrf_field(); ?><input type="hidden" name="action" value="edit"><input type="hidden" name="name" value="<?=h($edit['name'])?>"><input type="hidden" name="revision" value="<?=h($edit['revision'])?>"><label>Conteúdo<textarea name="body" class="code" rows="18" spellcheck="false"><?=h($editText)?></textarea></label><div class="actions"><button class="button primary" type="submit">Salvar alterações</button><a class="button" href="index.php">Cancelar</a></div></form></section>
<?php endif; ?>
<details class="card upload-box" id="upload"><summary>Enviar um arquivo para a central</summary><form method="post" enctype="multipart/form-data" class="stack"><?php csrf_field(); ?><input type="hidden" name="action" value="upload"><input type="hidden" name="MAX_FILE_SIZE" value="314572800"><label>Selecione o arquivo<input type="file" name="arquivo" required><span class="hint">Limites da hospedagem: envio <?=h(ini_get('upload_max_filesize'))?> / requisição <?=h(ini_get('post_max_size'))?>.</span></label><label><input type="checkbox" name="overwrite" value="1">Substituir se já existir um arquivo com o mesmo nome</label><div><button class="button primary" type="submit">Enviar arquivo</button></div></form></details>
<form method="get" class="toolbar"><label class="search">Buscar arquivo<input type="search" name="q" value="<?=h($q)?>" placeholder="Nome ou extensão do arquivo"></label><label>Tipo<select name="type"><?php foreach([''=>'Todos os arquivos','apps'=>'Aplicativos','scripts'=>'Scripts','archives'=>'Compactados'] as $key=>$label): ?><option value="<?=h($key)?>" <?=$type===$key?'selected':''?>><?=h($label)?></option><?php endforeach; ?></select></label><button class="button primary" type="submit">Buscar</button><a class="button" href="index.php">Limpar</a></form>
<div class="section-head"><h2><?=isset($_GET['trash'])?'Lixeira de arquivos':'Seus arquivos'?> <span class="muted small">(<?=isset($_GET['trash'])?count($trash):count($filtered)?>)</span></h2><a class="button" href="<?=isset($_GET['trash'])?'index.php':'?trash=1'?>"><?=isset($_GET['trash'])?'Voltar aos arquivos':'Lixeira ('.count($trash).')'?></a></div>
<?php if(isset($_GET['trash'])): ?><div class="table-wrap"><table><thead><tr><th>ARQUIVO</th><th>EXCLUÍDO EM</th><th>AÇÃO</th></tr></thead><tbody><?php foreach($trash as $key=>$item): ?><tr><td><?=h($item['name'])?></td><td><?=h(stamp_label($item['deleted_at']))?></td><td><form method="post"><?php csrf_field(); ?><input type="hidden" name="action" value="restore"><input type="hidden" name="key" value="<?=h($key)?>"><button class="button tiny" type="submit">Restaurar</button></form></td></tr><?php endforeach;if(!$trash): ?><tr><td colspan="3" class="empty">Nenhum arquivo na lixeira.</td></tr><?php endif; ?></tbody></table></div>
<?php else: ?>
<div class="table-wrap"><table class="file-table"><thead><tr><th>ARQUIVO</th><th>TAMANHO</th><th>ATUALIZADO</th><th>AÇÕES</th></tr></thead><tbody>
<?php foreach($filtered as $file):$name=$file['name'];$url=$canonical.rawurlencode($name); ?><tr><td><div class="file-cell"><span class="file-icon"><?=h($file['ext']?:'TXT')?></span><span class="filename"><?=h($name)?></span></div></td><td class="small"><?=h(size_label($file['bytes']))?></td><td class="small muted"><?=date('d/m/Y H:i',$file['mtime'])?></td><td><div class="actions"><a class="button tiny primary" href="files/<?=rawurlencode($name)?>" download>Baixar</a><a class="button tiny" href="<?=$file['text']?'?read=':'files/'?><?=rawurlencode($name)?>" target="_blank" rel="noopener">Ver</a><?php if($file['text']): ?><a class="button tiny" href="?edit=<?=rawurlencode($name)?>">Editar</a><?php endif; ?><button class="button tiny" type="button" data-copy="<?=h($url)?>">Copiar link</button><form method="post" data-confirm="Mover este arquivo para a lixeira? Os links de download ficarão indisponíveis até a restauração."><?php csrf_field(); ?><input type="hidden" name="action" value="delete"><input type="hidden" name="name" value="<?=h($name)?>"><input type="hidden" name="revision" value="<?=h($file['revision'])?>"><button class="button tiny danger" type="submit">Excluir</button></form></div></td></tr><?php endforeach;if(!$filtered): ?><tr><td class="empty" colspan="4"><h2>Nenhum arquivo encontrado</h2><p>Experimente outra busca ou envie um arquivo para começar.</p></td></tr><?php endif; ?>
</tbody></table></div>
<?php endif;page_foot(); ?>
