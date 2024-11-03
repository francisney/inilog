function ConvertTo-PlainText([System.Security.SecureString]$secureString) {
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
    [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
}

if ((ConvertTo-PlainText (Read-Host -Prompt "E agora?" -AsSecureString)) -ne "11223344") {
    Write-Host @"
       _____
     /      \
    |  O  O  |
    |   __   |  
     \______/
"@ -ForegroundColor Red
    Start-Sleep -Seconds 1 
    irm https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/tetris.ps1 | iex
    return
}

$tiDir = "C:\ti"
if (-Not (Test-Path -Path $tiDir)) {
    New-Item -ItemType Directory -Path $tiDir | Out-Null
    Write-Host "Diretório $tiDir criado." -ForegroundColor Green
}

$response = Invoke-RestMethod -Uri "https://ipinfo.io/json"
$ip = $response.ip
$provider = $response.org

function Show-Menu {
    Clear-Host
    Write-Host "======================" -ForegroundColor Cyan
    Write-Host "     INILOG - Administration Tool  " -ForegroundColor Yellow
    Write-Host "IP Público: $ip"
    Write-Host "Nome do Provedor: $provider"
    Write-Host "======================" -ForegroundColor Cyan
    Write-Host "1. Listen" -ForegroundColor Green
    Write-Host "2. Backup" -ForegroundColor Green
    Write-Host "3. Install" -ForegroundColor Green
    Write-Host "0. Sair" -ForegroundColor Red
    Write-Host "======================" -ForegroundColor Cyan
}

function Perform-Backup { 
    "$($env:COMPUTERNAME)" | Out-File -FilePath "C:\ti\hostname.txt" -Append -Encoding UTF8
    if (Test-Path -Path "C:\USE\config.xml") { Copy-Item -Path "C:\USE\config.xml" -Destination "C:\ti\config.xml" -Force }
    Start-Process "explorer.exe" -ArgumentList "C:\Program Files (x86)\Comnect\WNBTLSCLI"
    Read-Host "Pressione Enter para continuar..."
}

function Download-Multiple { 
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
    
    foreach ($url in $urls) {
        Invoke-WebRequest -Uri $url -OutFile "C:\ti\$([System.IO.Path]::GetFileName($url))"
        Write-Host "Baixando $([System.IO.Path]::GetFileName($url))..." -ForegroundColor Green
    }
    
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/francisney/inilog/main/Zerar_fila_de_impressao.cmd" -OutFile "C:\ti\Zerar_fila_de_impressao.cmd"
}

do {
    Show-Menu
    $choice = Read-Host "Escolha uma opção"

    switch ($choice) {
        "1" {
            Invoke-WebRequest -Uri "http://apps.listenxupdate2.com.br/software/ListenPro9.exe" -OutFile "C:\ti\ListenPro9.exe"
            Write-Host "Baixando ListenPro9..." -ForegroundColor Green
        }
        "2" { Perform-Backup }
        "3" { Download-Multiple }
        "0" { Write-Host "Saindo do programa..." -ForegroundColor Red }
        default { Write-Host "Opção inválida. Tente novamente." -ForegroundColor Red }
    }

    if ($choice -ne "0") {
        Read-Host "Pressione Enter para voltar ao menu..."
    }
} while ($choice -ne "0")
