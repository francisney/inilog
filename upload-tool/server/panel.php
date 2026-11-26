<?php
declare(strict_types=1);

function panel_session(): void {
    if (session_status() === PHP_SESSION_ACTIVE) return;
    directories();
    $path = storage().'/web-sessions';
    if (!is_dir($path) && !mkdir($path, 0700, true) && !is_dir($path)) throw new RuntimeException('Não foi possível abrir o painel.');
    ini_set('session.use_strict_mode', '1');
    ini_set('session.use_only_cookies', '1');
    ini_set('session.gc_maxlifetime', '28800');
    session_save_path($path);
    session_name('INILOG_UPLOAD_WEB');
    $cookiePath = rtrim(dirname($_SERVER['SCRIPT_NAME'] ?? '/backup/index.php'), '/').'/';
    session_set_cookie_params(['lifetime'=>0, 'path'=>$cookiePath, 'secure'=>!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off', 'httponly'=>true, 'samesite'=>'Lax']);
    if (!session_start()) throw new RuntimeException('Não foi possível abrir o painel.');
    if (!isset($_SESSION['csrf'])) $_SESSION['csrf'] = bin2hex(random_bytes(32));
}

function panel_password_hash(): string {
    $hash = config()['web_password_hash'] ?? '';
    return is_string($hash) ? $hash : '';
}

function panel_authenticated(): bool {
    $hash = panel_password_hash();
    $valid = $hash !== '' && isset($_SESSION['password_stamp'], $_SESSION['last_seen'])
        && hash_equals(hash('sha256', $hash), (string)$_SESSION['password_stamp'])
        && (int)$_SESSION['last_seen'] >= time() - 28800;
    if ($valid) $_SESSION['last_seen'] = time();
    return $valid;
}

function panel_csrf_valid(mixed $token): bool {
    return is_string($token) && hash_equals((string)($_SESSION['csrf'] ?? ''), $token);
}

// O aplicativo nativo mantém seu protocolo sem senha. Solicitações do navegador
// usam sessão e CSRF, além do token próprio de cada upload.
function panel_browser_request(): bool {
    return isset($_GET['web']) || isset($_SERVER['HTTP_X_INILOG_WEB'])
        || isset($_SERVER['HTTP_SEC_FETCH_MODE']) || isset($_SERVER['HTTP_ORIGIN']);
}

function panel_require_api(bool $csrf = true): void {
    panel_session();
    if (!panel_authenticated()) { session_write_close(); json_reply(['ok'=>false, 'error'=>'Entre no painel para enviar pelo navegador.'], 401); }
    if ($csrf && !panel_csrf_valid($_SERVER['HTTP_X_INILOG_WEB_CSRF'] ?? null)) {
        session_write_close(); json_reply(['ok'=>false, 'error'=>'A sessão do painel mudou. Atualize a página e tente novamente.'], 403);
    }
    session_write_close();
}

function panel_escape(mixed $value): string { return htmlspecialchars((string)$value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); }

function panel_page_access(): string {
    panel_session();
    $error = '';
    $action = $_POST['panel_action'] ?? '';
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST' && in_array($action, ['login','logout'], true)) {
        if (!panel_csrf_valid($_POST['csrf'] ?? null)) { http_response_code(403); $error = 'A página expirou. Atualize e tente novamente.'; }
        elseif ($action === 'logout') {
            $_SESSION = [];
            session_regenerate_id(true);
            $_SESSION['csrf'] = bin2hex(random_bytes(32));
            session_write_close(); header('Location: index.php', true, 303); exit;
        } else {
            $password = $_POST['password'] ?? null;
            $hash = panel_password_hash();
            if (is_string($password) && strlen($password) <= 1024 && $hash !== '' && password_verify($password, $hash)) {
                session_regenerate_id(true);
                $_SESSION = ['csrf'=>bin2hex(random_bytes(32)), 'password_stamp'=>hash('sha256', $hash), 'last_seen'=>time()];
                session_write_close(); header('Location: index.php', true, 303); exit;
            }
            http_response_code(401); $error = 'Senha incorreta.';
        }
    }
    if (panel_authenticated()) { $csrf = (string)$_SESSION['csrf']; session_write_close(); return $csrf; }
    if (panel_password_hash() === '') { http_response_code(503); $error = 'O acesso web ainda precisa ser configurado pelo administrador.'; }
    $csrf = (string)$_SESSION['csrf']; session_write_close();
    header("Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; base-uri 'self'; frame-ancestors 'self'; form-action 'self'");
    ?><!doctype html><html lang="pt-BR"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>Entrar · INILOG Upload</title><link rel="stylesheet" href="upload.css?v=4"></head><body><main class="login-panel"><h1>INILOG <span>Upload</span></h1><p class="intro">Digite a senha para enviar e consultar os arquivos.</p><?php if ($error !== ''): ?><p class="login-error" role="alert"><?=panel_escape($error)?></p><?php endif; ?><form method="post" action="index.php" class="login-form"><input type="hidden" name="panel_action" value="login"><input type="hidden" name="csrf" value="<?=panel_escape($csrf)?>"><label for="password">Senha</label><input type="password" id="password" name="password" autocomplete="current-password" required autofocus><button type="submit" class="primary">Entrar</button></form><footer>Francisney Delmondes | INILOG<br>(61) 99363-0969 · suporte@inilog.com<br>www.inilog.com</footer></main></body></html><?php
    exit;
}

function panel_public_file(string $name): bool {
    return $name !== '' && $name[0] !== '.' && !str_contains($name, '/') && !str_contains($name, '\\')
        && is_file(__DIR__.'/'.$name) && !is_link(__DIR__.'/'.$name)
        && !in_array(strtolower(pathinfo($name, PATHINFO_EXTENSION)), ['php','phtml','phar','css','js','json','ini','log','bak'], true);
}

function panel_files(): array {
    $files = [];
    foreach (glob(storage().'/files/*.json') ?: [] as $metadata) {
        $id = basename($metadata, '.json');
        if (!preg_match('/^[a-f0-9]{32}$/', $id) || !is_file(storage().'/files/'.$id.'.blob')) continue;
        try { $item = read_json($metadata); } catch (Throwable) { continue; }
        if (!is_string($item['name'] ?? null)) continue;
        $files[] = ['key'=>'upload:'.$id, 'name'=>$item['name'], 'size'=>(int)($item['size'] ?? 0), 'created_at'=>(int)($item['created_at'] ?? 0), 'url'=>rtrim(config()['public_base'], '/').'/'.$id, 'deletable'=>true];
    }
    // Inclui os downloads já existentes na raiz do backup, sem expor os
    // componentes e configurações do próprio sistema.
    $base = preg_replace('~/uploads/?$~', '/', rtrim(config()['public_base'], '/').'/');
    foreach (scandir(__DIR__) ?: [] as $name) {
        $path = __DIR__.'/'.$name;
        if (!panel_public_file($name)) continue;
        $files[] = ['key'=>'public:'.$name, 'name'=>$name, 'size'=>(int)filesize($path), 'created_at'=>(int)filemtime($path), 'url'=>$base.rawurlencode($name), 'deletable'=>strtolower($name) !== 'upload.exe'];
    }
    usort($files, fn($a,$b)=>($b['created_at'] <=> $a['created_at']) ?: strnatcasecmp($a['name'],$b['name']));
    return $files;
}

function panel_delete(array $request): array {
    $key = $request['key'] ?? null;
    if (!is_string($key)) throw new InvalidArgumentException('Arquivo inválido.');
    if (preg_match('/^upload:([a-f0-9]{32})$/', $key, $match)) {
        $id = $match[1]; $meta = storage().'/files/'.$id.'.json'; $blob = storage().'/files/'.$id.'.blob';
        if (!is_file($meta) || !is_file($blob)) throw new OutOfBoundsException('O arquivo já foi removido. Atualize a lista.');
        $name = read_json($meta)['name']; $moves = ['metadata.json'=>$meta, 'content.blob'=>$blob];
    } elseif (str_starts_with($key, 'public:')) {
        $name = substr($key, 7);
        if (strtolower($name) === 'upload.exe') throw new DomainException('O aplicativo de upload faz parte do sistema.');
        if (!panel_public_file($name)) throw new OutOfBoundsException('Arquivo não encontrado.');
        $moves = ['content.blob'=>__DIR__.'/'.$name];
    } else throw new InvalidArgumentException('Arquivo inválido.');
    $trash = storage().'/trash/'.gmdate('Ymd-His').'-'.bin2hex(random_bytes(8));
    if (!mkdir($trash, 0700, true)) throw new RuntimeException('Não foi possível preparar a exclusão.');
    $done = [];
    try {
        write_json($trash.'/restore.json', ['key'=>$key, 'name'=>$name, 'deleted_at'=>time(), 'files'=>$moves]);
        foreach ($moves as $target=>$source) {
            if (!rename($source, $trash.'/'.$target)) throw new RuntimeException('Não foi possível apagar o arquivo.');
            $done[$target] = $source;
        }
    } catch (Throwable $error) {
        foreach (array_reverse($done, true) as $target=>$source) @rename($trash.'/'.$target, $source);
        throw $error;
    }
    return ['ok'=>true, 'name'=>$name, 'message'=>'Arquivo enviado à lixeira.'];
}
