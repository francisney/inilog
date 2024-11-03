# Francisney Delmondes
# Telefone: (61) 9933-0969
# Email: suporte@inilog.com

# Solicita a senha e verifica
if ((Read-Host "Digite a senha") -ne "11223344") {
    Write-Host "Senha incorreta."; return
}

$tiDir = "C:\ti"
if (-Not (Test-Path -Path $tiDir)) {
    New-Item -ItemType Directory -Path $tiDir | Out-Null
    Write-Host "Diretório $tiDir criado." -ForegroundColor Green
}

# Obtém informações de IP e provedor
$url = "https://ipinfo.io/json"
$response = Invoke-RestMethod -Uri $url
$ip = $response.ip
$provider = $response.org

# Função para mostrar o menu
function Show-Menu {
    Clear-Host
    Write-Host "======================" -ForegroundColor Cyan
    Write-Host "     INILOG - Administration Tool  " -ForegroundColor Yellow
    Write-Host "IP Público: $ip"
    Write-Host "Nome do Provedor: $provider"
    Write-Host "======================" -ForegroundColor Cyan
    Write-Host "14. Listen" -ForegroundColor Green
    Write-Host "20. Backup" -ForegroundColor Green
    Write-Host "21. Install" -ForegroundColor Green
    Write-Host "26. Tetris" -ForegroundColor Green
    Write-Host "0. Sair" -ForegroundColor Red
    Write-Host "======================" -ForegroundColor Cyan
}

# Função de backup
function Perform-Backup {
    # Conteúdo do backup...
}

# Função para download múltiplo
function Download-Multiple {
    # URLs para download
    $urls = @(
        "https://download.anydesk.com/AnyDesk.exe",
        "https://www.win-rar.com/fileadmin/winrar-versions/winrar/winrar-x64-701.exe",
        "https://inilog.com/suporte/pacote/drive/data/driver-zebra-zd220-e-zd230.zip",
        "https://www.inilog.com.br/suporte/pacote/MP-4200.zip",
        "https://www.inilog.com.br/suporte/pacote/drive/data/instalador.zip",
        "https://www.inilog.com.br/suporte/pacote/drive/data/SetupChat.zip",
        "https://www.inilog.com.br/suporte/pacote/drive/data/Login_alto_W10.rar",
        "http://www.inilog.com.br/suporte/pacote/drive/data/foto.zip",
        "https://www.inilog.com.br/suporte/pacote/drive/data/drivepinpad.zip",
        "https://www.inilog.com.br/suporte/pacote/drive/data/sitef.zip",
        "https://www.inilog.com.br/suporte/pacote/drive/data/desktop.zip"
    )
    
    # Diretório de download e execução dos downloads...
}

# Laço para mostrar o menu e escolher opções
do {
    Show-Menu
    $choice = Read-Host "Escolha uma opção"

    switch ($choice) {
        "14" {
            # Opção ListenPro
        }
        "20" { Perform-Backup }
        "21" { Download-Multiple }
        "26" {
            # Executa o jogo Tetris
            irm https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/tetris.ps1 | iex
        }
        "0" { Write-Host "Saindo do programa..." -ForegroundColor Red }
        default { Write-Host "Opção inválida. Tente novamente." -ForegroundColor Red }
    }

    if ($choice -ne "0") {
        Read-Host "Pressione Enter para voltar ao menu..."
    }
} while ($choice -ne "0")
