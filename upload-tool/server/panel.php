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
    ?><!doctype html><html lang="pt-BR"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>Entrar · INILOG Upload</title><link rel="stylesheet" href="upload.css?v=3"></head><body><main class="login-panel"><h1>INILOG <span>Upload</span></h1><p class="intro">Digite a senha para enviar e consultar os arquivos.</p><?php if ($error !== ''): ?><p class="login-error" role="alert"><?=panel_escape($error)?></p><?php endif; ?><form method="post" action="index.php" class="login-form"><input type="hidden" name="panel_action" value="login"><input type="hidden" name="csrf" value="<?=panel_escape($csrf)?>"><label for="password">Senha</label><input type="password" id="password" name="password" autocomplete="current-password" required autofocus><button type="submit" class="primary">Entrar</button></form><footer>Francisney Delmondes | INILOG<br>(61) 99363-0969 · suporte@inilog.com<br>www.inilog.com</footer></main></body></html><?php
    exit;
}

function panel_files(): array {
    $files = [];
    foreach (glob(storage().'/files/*.json') ?: [] as $metadata) {
        $id = basename($metadata, '.json');
        if (!preg_match('/^[a-f0-9]{32}$/', $id) || !is_file(storage().'/files/'.$id.'.blob')) continue;
        try { $item = read_json($metadata); } catch (Throwable) { continue; }
        if (!is_string($item['name'] ?? null)) continue;
        $files[] = ['name'=>$item['name'], 'size'=>(int)($item['size'] ?? 0), 'created_at'=>(int)($item['created_at'] ?? 0), 'url'=>rtrim(config()['public_base'], '/').'/'.$id];
    }
    // Inclui os downloads já existentes na raiz do backup, sem expor os
    // componentes e configurações do próprio sistema.
    $base = preg_replace('~/uploads/?$~', '/', rtrim(config()['public_base'], '/').'/');
    foreach (scandir(__DIR__) ?: [] as $name) {
        $path = __DIR__.'/'.$name;
        if ($name === '' || $name[0] === '.' || !is_file($path) || is_link($path)
            || in_array(strtolower(pathinfo($name, PATHINFO_EXTENSION)), ['php','phtml','phar','css','js','json','ini','log','bak'], true)) continue;
        $files[] = ['name'=>$name, 'size'=>(int)filesize($path), 'created_at'=>(int)filemtime($path), 'url'=>$base.rawurlencode($name)];
    }
    usort($files, fn($a,$b)=>($b['created_at'] <=> $a['created_at']) ?: strnatcasecmp($a['name'],$b['name']));
    return $files;
}
