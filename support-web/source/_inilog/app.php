<?php
declare(strict_types=1);
/* Código compartilhado. Configuração e dados ficam fora de public_html. */
function private_dir(): string { return getenv('INILOG_PRIVATE_DIR') ?: dirname(__DIR__, 3).'/.inilog-support'; }
function config(): array {
    static $config;
    if ($config === null) {
        $file=private_dir().'/config.php';
        if (!is_file($file)) { http_response_code(503); exit('O painel está em manutenção. Tente novamente em instantes.'); }
        $config=require $file;
    }
    return $config;
}
function h(mixed $s): string { return htmlspecialchars((string)$s, ENT_QUOTES|ENT_SUBSTITUTE, 'UTF-8'); }
function text_length(string $s): int { return function_exists('mb_strlen') ? mb_strlen($s,'UTF-8') : preg_match_all('/./us',$s); }
function uid(): string { return bin2hex(random_bytes(12)); }
function fingerprint(array $value): string { return hash('sha256',json_encode($value,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR)); }
function read_json(string $path, array $default=[]): array {
    if (!is_file($path)) return $default;
    $data=json_decode((string)file_get_contents($path),true,512,JSON_THROW_ON_ERROR);
    if (!is_array($data)) throw new RuntimeException('O arquivo de dados não pôde ser lido. Nenhuma alteração foi feita.');
    return $data;
}
function write_json(string $path, array $data): void {
    $json=json_encode($data,JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE|JSON_INVALID_UTF8_SUBSTITUTE|JSON_THROW_ON_ERROR);
    $tmp=tempnam(dirname($path),'.inilog-');
    if ($tmp===false) throw new RuntimeException('Não foi possível preparar o salvamento.');
    try {
        if (file_put_contents($tmp,$json,LOCK_EX)!==strlen($json)) throw new RuntimeException('O salvamento não foi concluído.');
        chmod($tmp,0600);
        if (!rename($tmp,$path)) throw new RuntimeException('Não foi possível concluir o salvamento.');
    } finally { if (is_file($tmp)) unlink($tmp); }
}
function mutate_json(string $path, callable $callback): mixed {
    $lock=fopen($path.'.lock','c');
    if (!$lock || !flock($lock,LOCK_EX)) throw new RuntimeException('Os dados estão ocupados. Tente novamente.');
    try { $data=read_json($path); $result=$callback($data); write_json($path,$data); return $result; }
    finally { flock($lock,LOCK_UN); fclose($lock); }
}
function csrf(): string { return $_SESSION['inilog_csrf'] ??= bin2hex(random_bytes(24)); }
function csrf_field(): void { echo '<input type="hidden" name="csrf" value="'.h(csrf()).'">'; }
function check_csrf(): void {
    if (!is_string($_POST['csrf']??null) || !hash_equals(csrf(),$_POST['csrf'])) { http_response_code(403); throw new RuntimeException('Esta página expirou. Recarregue antes de tentar novamente.'); }
}
function redirect(string $to='index.php'): never { header('Location: '.$to,true,303); exit; }
function flash(string $message): void { $_SESSION['inilog_flash']=$message; }
function begin_app(): void {
    ini_set('display_errors','0');
    date_default_timezone_set('America/Sao_Paulo');
    if (session_status()!==PHP_SESSION_ACTIVE) {
        session_set_cookie_params(['httponly'=>true,'secure'=>(!empty($_SERVER['HTTPS'])&&$_SERVER['HTTPS']!=='off'),'samesite'=>'Lax','path'=>'/']);
        session_start();
    }
    header('Content-Type: text/html; charset=UTF-8');
    header('Cache-Control: no-store, max-age=0');
    header('X-Content-Type-Options: nosniff');
    header('Referrer-Policy: same-origin');
    header("Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; base-uri 'self'; frame-ancestors 'self'; form-action 'self'");
}
function page_head(string $title, string $section): void {
    $nav=['files'=>['/suporte/628/','Arquivos'],'computers'=>['/suporte/geral/','Computadores'],'notes'=>['/suporte/notas/','Notas']];
    echo '<!doctype html><html lang="pt-BR"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>'.h($title).' · INILOG</title><link rel="stylesheet" href="/suporte/_inilog/support.css?v=1.0.0"><script src="/suporte/_inilog/support.js?v=1.0.0" defer></script></head><body><a class="skip" href="#main">Pular para o conteúdo</a><header class="topbar"><div class="shell top-inner"><a class="brand" href="/suporte/628/"><span class="brand-icon">i</span><span>INILOG<small>Central de suporte</small></span></a><nav aria-label="Principal">';
    foreach ($nav as $key=>[$href,$label]) echo '<a href="'.$href.'"'.($key===$section?' aria-current="page"':'').'>'.$label.'</a>';
    echo '</nav><form method="post" class="logout">';csrf_field();echo '<input type="hidden" name="action" value="logout"><button class="button quiet" type="submit">Sair</button></form></div></header><main id="main" class="shell">';
    if (!empty($_SESSION['inilog_flash'])) { echo '<div class="notice success" role="status">'.h($_SESSION['inilog_flash']).'</div>';unset($_SESSION['inilog_flash']); }
}
function page_foot(): void { echo '</main><div id="toast" class="toast" role="status" hidden></div><footer class="shell footer">INILOG · Central de suporte</footer></body></html>'; }
function require_auth(string $section, bool $basic=false): void {
    if ($basic && !empty($_SERVER['REMOTE_USER'])) $_SESSION['inilog_ok']=true;
    if (!empty($_SESSION['logado'])) $_SESSION['inilog_ok']=true;
    $error='';
    if ($_SERVER['REQUEST_METHOD']==='POST' && ($_POST['action']??'')==='logout') {
        check_csrf(); $_SESSION=[]; session_regenerate_id(true); redirect(strtok($_SERVER['REQUEST_URI'],'?'));
    }
    if (($_POST['action']??'')==='login' && $_SERVER['REQUEST_METHOD']==='POST') {
        try {
            check_csrf();
            $path=private_dir().'/login-attempts.json';
            $key=hash('sha256',$_SERVER['REMOTE_ADDR']??'unknown');
            $allowed=mutate_json($path,function (&$data) use($key) {
                $now=time(); foreach ($data as $k=>$v) if (($v['since']??0)<$now-900) unset($data[$k]);
                $item=$data[$key]??['since'=>$now,'count'=>0]; $item['count']++;$data[$key]=$item;
                return $item['count']<=15;
            });
            if (!$allowed) throw new RuntimeException('Muitas tentativas. Aguarde 15 minutos para tentar novamente.');
            $value=$_POST['senha']??'';
            if (!is_string($value)||!password_verify($value,config()['section_password_hashes'][$section]??config()['password_hash'])) throw new RuntimeException('Senha incorreta. Tente novamente.');
            mutate_json($path,function (&$data) use($key) {unset($data[$key]);});
            session_regenerate_id(true);$_SESSION['inilog_ok']=true;redirect(strtok($_SERVER['REQUEST_URI'],'?'));
        } catch(Throwable $e) {$error=$e->getMessage();}
    }
    if (!empty($_SESSION['inilog_ok'])) return;
    page_head('Acesso ao suporte',$section);
    echo '<section class="login card"><span class="eyebrow">ACESSO AO PAINEL</span><h1>Bem-vindo de volta.</h1><p class="muted">Informe a senha de acesso a este painel.</p>';
    if ($error) echo '<div class="notice error" role="alert">'.h($error).'</div>';
    echo '<form method="post" class="stack">';csrf_field();echo '<input type="hidden" name="action" value="login"><label>Senha<input type="password" name="senha" autocomplete="current-password" required autofocus></label><button class="button primary" type="submit">Entrar</button></form><p class="small muted">IP desta conexão: '.h($_SERVER['REMOTE_ADDR']??'local').'</p></section>';page_foot();exit;
}
function fail_message(Throwable $e): string {
    if ($e instanceof RuntimeException && !($e instanceof mysqli_sql_exception)) return $e->getMessage();
    error_log('INILOG: '.$e->getMessage());
    return 'Não foi possível concluir a operação. Seus dados foram preservados. Tente novamente.';
}
function error_notice(string $error): void { if ($error) echo '<div class="notice error" role="alert">'.h($error).'</div>'; }
function size_label(int $bytes): string { foreach (['B','KB','MB','GB'] as $u) {if ($bytes<1024 || $u==='GB') return number_format($bytes,$u==='B'?0:1,',','.').' '.$u;$bytes/=1024;}return ''; }
function stamp_label(string $stamp): string { $ts=strtotime($stamp); return $ts?date('d/m/Y H:i',$ts):'Importada'; }
begin_app();
