<?php
declare(strict_types=1);
require dirname(__DIR__).'/_inilog/app.php';
require_auth('notes');
$path=private_dir().'/notes.json';
$error='';
$scopes=['all'=>'Todas','current'=>'Atuais','old'=>'Antigas','favorites'=>'Favoritas','trash'=>'Lixeira'];
$scope=is_string($_GET['scope']??null)&&isset($scopes[$_GET['scope']])?$_GET['scope']:'all';
$q=is_string($_GET['q']??null)?trim($_GET['q']):'';
function note_body(array $input): array {
    $body=is_string($input['body']??null)?trim($input['body']):'';
    $title=is_string($input['title']??null)?trim($input['title']):'';
    if ($body==='') throw new RuntimeException('Escreva o conteúdo da nota antes de salvar.');
    if (text_length($body)>50000||text_length($title)>140) throw new RuntimeException('Use até 140 caracteres no título e 50.000 no conteúdo.');
    if (!preg_match('//u',$body.$title)) throw new RuntimeException('O texto precisa estar em UTF-8.');
    return ['title'=>$title,'body'=>$body];
}
function sync_note_exports(string $path): void {
    $data=read_json($path);
    foreach (['old.txt'=>'old','mensagens.txt'=>'current'] as $name=>$origin) {
        $notes=array_filter($data['notes'],fn($n)=>$origin==='old'?$n['origin']==='old':$n['origin']!=='old');
        $body=implode("\n\n______\n\n",array_map(fn($n)=>($n['title']!==''?$n['title']."\n\n":'').$n['body'],$notes));
        $temp=tempnam(__DIR__,'.note-');
        try {
            if(file_put_contents($temp,$body,LOCK_EX)!==strlen($body))throw new RuntimeException('As notas foram salvas, mas a cópia em texto não foi concluída.');
            chmod($temp,0644);
            if(!rename($temp,__DIR__.'/'.$name))throw new RuntimeException('Não foi possível atualizar a cópia em texto.');
        } finally {if(is_file($temp))unlink($temp);}
    }
}
try {
    if ($_SERVER['REQUEST_METHOD']==='POST') {
        check_csrf();
        $action=$_POST['action']??'';
        mutate_json($path,function (&$data) use($action) {
            if (!isset($data['notes'],$data['trash'])) throw new RuntimeException('As notas não estão disponíveis. Nenhum dado foi alterado.');
            if ($action==='create') {
                $input=note_body($_POST);
                array_unshift($data['notes'],['id'=>uid()]+$input+['origin'=>'current','favorite'=>false,'created_at'=>gmdate('c'),'updated_at'=>gmdate('c'),'revision'=>1]);return;
            }
            if (!in_array($action,['update','trash','restore','favorite'],true)) throw new RuntimeException('Ação não reconhecida.');
            $group=$action==='restore'?'trash':'notes';
            foreach ($data[$group] as $key=>$note) {
                if ($note['id']!==($_POST['id']??'')) continue;
                if ((string)$note['revision']!==(string)($_POST['revision']??'')) throw new RuntimeException('Esta nota mudou em outra janela. Recarregue para ver a versão mais recente.');
                $note['revision']++;$note['updated_at']=gmdate('c');
                if ($action==='update') $note=array_replace($note,note_body($_POST));
                if ($action==='favorite') $note['favorite']=!$note['favorite'];
                if ($action==='trash'||$action==='restore') {
                    $target=$action==='trash'?'trash':'notes';
                    array_unshift($data[$target],$note);array_splice($data[$group],$key,1);
                } else $data[$group][$key]=$note;
                return;
            }
            throw new RuntimeException('Esta nota não foi encontrada. Recarregue a página.');
        });
        sync_note_exports($path);
        flash(match($action){'create'=>'Nota criada.','update'=>'Nota atualizada.','trash'=>'Nota movida para a lixeira. Você pode restaurá-la.','restore'=>'Nota restaurada.',default=>'Favorito atualizado.'});
        redirect('index.php?scope='.rawurlencode($scope));
    }
    $data=read_json($path,['notes'=>[],'trash'=>[]]);
} catch(Throwable $e) { $error=fail_message($e);$data=read_json($path,['notes'=>[],'trash'=>[]]); }
if (isset($_GET['export'])) {
    $source=$_GET['export'];$notes=$source==='old'?array_filter($data['notes'],fn($n)=>$n['origin']==='old'):array_filter($data['notes'],fn($n)=>$n['origin']!=='old');
    header('Content-Type: text/plain; charset=UTF-8');
    header('Content-Disposition: inline; filename="'.($source==='old'?'old.txt':'mensagens.txt').'"');
    echo implode("\n\n______\n\n",array_map(fn($n)=>($n['title']!==''?$n['title']."\n\n":'').$n['body'],$notes));exit;
}
$all=$data['notes'];$items=$scope==='trash'?$data['trash']:$all;
$items=array_values(array_filter($items,function ($note) use($scope,$q) {
    if ($scope==='old'&&$note['origin']!=='old') return false;
    if ($scope==='current'&&$note['origin']==='old') return false;
    if ($scope==='favorites'&&!$note['favorite']) return false;
    return $q===''||mb_stripos($note['title']."\n".$note['body'],$q,0,'UTF-8')!==false;
}));
$edit=null;
if (isset($_GET['edit'])) foreach($all as $note) if ($note['id']===$_GET['edit']) {$edit=$note;break;}
$new=isset($_GET['new']);
if ($error&&isset($_POST['body'])) { $edit=['id'=>$_POST['id']??'','revision'=>$_POST['revision']??1,'title'=>$_POST['title']??'','body'=>$_POST['body'],'origin'=>'current'];$new=($_POST['action']??'')==='create'; }
page_head('Notas de suporte','notes');
?>
<section class="hero"><div><span class="eyebrow">SEU BLOCO DE ANOTAÇÕES</span><h1>Notas de suporte</h1><p>Guarde informações, encontre rápido e continue de onde parou.</p></div><a class="button primary" href="?new=1">+ Nova nota</a></section>
<div class="stats"><div class="stat"><strong><?=count($all)?></strong><span>notas salvas</span></div><div class="stat"><strong><?=count(array_filter($all,fn($n)=>$n['origin']==='old'))?></strong><span>notas antigas</span></div><div class="stat"><strong><?=count(array_filter($all,fn($n)=>$n['favorite']))?></strong><span>favoritas</span></div></div>
<?php error_notice($error); if ($new||$edit): ?>
<section class="card editor" id="editor"><h2><?=$new?'Nova nota':'Editar nota'?></h2><p class="muted small"><?=$edit&&$edit['origin']==='old'?'Esta nota veio do old.txt. A edição também aparece no acesso ao arquivo antigo.':'O conteúdo é salvo no servidor e pode ser acessado em outros dispositivos.'?></p><form method="post" class="stack"><?php csrf_field(); ?><input type="hidden" name="action" value="<?=$new?'create':'update'?>"><input type="hidden" name="id" value="<?=h($edit['id']??'')?>"><input type="hidden" name="revision" value="<?=h($edit['revision']??1)?>"><label>Título <span class="muted">(opcional)</span><input name="title" maxlength="140" value="<?=h($edit['title']??'')?>" placeholder="Ex.: Pendências da loja" autofocus></label><label>Nota<textarea name="body" rows="8" maxlength="50000" placeholder="Escreva ou cole sua anotação…" required><?=h($edit['body']??'')?></textarea></label><div class="actions"><button type="submit" class="button primary">Salvar nota</button><a class="button" href="?scope=<?=h($scope)?>">Cancelar</a></div></form></section>
<?php endif; ?>
<form class="toolbar" method="get"><label class="search">Buscar nas notas<input type="search" name="q" value="<?=h($q)?>" placeholder="Título, conteúdo ou informação da loja"></label><input type="hidden" name="scope" value="<?=h($scope)?>"><button type="submit" class="button primary">Buscar</button><?php if ($q!==''): ?><a class="button" href="?scope=<?=h($scope)?>">Limpar</a><?php endif; ?></form>
<div class="section-head"><div class="subnav" aria-label="Filtrar notas"><?php foreach($scopes as $key=>$label): ?><a class="button <?=$scope===$key?'selected':''?>" href="?scope=<?=h($key)?>&amp;q=<?=rawurlencode($q)?>"><?=$label?><?=$key==='trash'?' ('.count($data['trash']).')':''?></a><?php endforeach; ?></div><a class="small" href="old.txt" target="_blank" rel="noopener">Abrir notas antigas em texto</a></div>
<div class="notes-grid">
<?php foreach ($items as $note): $id=$note['id'];$title=$note['title']!==''?$note['title']:(preg_split('/\R/',$note['body'])[0]??'Sem título');if(text_length($title)>85)$title=mb_substr($title,0,85,'UTF-8').'…'; ?>
<article class="card note <?=$note['origin']==='old'?'old':''?>"><div class="note-top"><span class="tag <?=$note['origin']==='old'?'legacy':''?>"><?=$note['origin']==='old'?'ANTIGA · OLD.TXT':'NOTA'?></span><?php if($scope!=='trash'): ?><form method="post"><?php csrf_field(); ?><input type="hidden" name="action" value="favorite"><input type="hidden" name="id" value="<?=h($id)?>"><input type="hidden" name="revision" value="<?=$note['revision']?>"><button class="favorite" aria-label="<?=$note['favorite']?'Remover dos favoritos':'Adicionar aos favoritos'?>" title="Favorito"><?=$note['favorite']?'★':'☆'?></button></form><?php endif; ?></div><h2><?=h($title)?></h2><div class="note-time"><?=empty($note['created_at'])?'Importada do sistema anterior':'Atualizada em '.h(stamp_label($note['updated_at']))?></div><pre class="note-text" id="note-<?=h($id)?>"><?=h($note['body'])?></pre><div class="actions"><?php if ($scope==='trash'): ?><form method="post"><?php csrf_field(); ?><input type="hidden" name="action" value="restore"><input type="hidden" name="id" value="<?=h($id)?>"><input type="hidden" name="revision" value="<?=$note['revision']?>"><button type="submit" class="button tiny">Restaurar</button></form><?php else: ?><a class="button tiny" href="?edit=<?=h($id)?>&amp;scope=<?=h($scope)?>">Editar</a><button type="button" class="button tiny" data-copy-target="note-<?=h($id)?>">Copiar</button><form method="post" data-confirm="Mover esta nota para a lixeira? Você poderá restaurá-la depois."><?php csrf_field(); ?><input type="hidden" name="action" value="trash"><input type="hidden" name="id" value="<?=h($id)?>"><input type="hidden" name="revision" value="<?=$note['revision']?>"><button type="submit" class="button tiny danger">Excluir</button></form><?php endif; ?></div></article>
<?php endforeach; if (!$items): ?><div class="card empty"><h2><?=$q?'Nenhuma nota encontrada':'Tudo em ordem por aqui.'?></h2><p><?=$scope==='trash'?'As notas excluídas aparecerão aqui e poderão ser restauradas.':'Crie uma nota ou escolha outro filtro para continuar.'?></p></div><?php endif; ?>
</div>
<?php page_foot(); ?>
