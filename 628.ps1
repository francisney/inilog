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
    Write-Host "1. ListenX" -ForegroundColor Green
    Write-Host "2. Backup" -ForegroundColor Green
    Write-Host "3. Install Full" -ForegroundColor Green
    Write-Host "4. Instalador" -ForegroundColor Green
    Write-Host "5. SetupChat" -ForegroundColor Green
    Write-Host "6. Login_alto_W10" -ForegroundColor Green
    Write-Host "7. Wallpaper" -ForegroundColor Green
    Write-Host "8. Drives Pin Pad" -ForegroundColor Green
    Write-Host "9. Sitef" -ForegroundColor Green
    Write-Host "10. Desktop" -ForegroundColor Green
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
    "4" {
        Invoke-WebRequest -Uri "https://www.inilog.com.br/suporte/pacote/drive/data/instalador.zip" -OutFile "C:\ti\instalador.zip"
        Write-Host "Baixando instalador.zip..." -ForegroundColor Green
    }
    "5" {
        Invoke-WebRequest -Uri "https://www.inilog.com.br/suporte/pacote/drive/data/SetupChat.zip" -OutFile "C:\ti\SetupChat.zip"
        Write-Host "Baixando SetupChat.zip..." -ForegroundColor Green
    }
    "6" {
        Invoke-WebRequest -Uri "https://www.inilog.com.br/suporte/pacote/drive/data/Login_alto_W10.rar" -OutFile "C:\ti\Login_alto_W10.rar"
        Write-Host "Baixando Login_alto_W10.rar..." -ForegroundColor Green
    }
    "7" {
        Invoke-WebRequest -Uri "http://www.inilog.com.br/suporte/pacote/drive/data/foto.zip" -OutFile "C:\ti\foto.zip"
        Write-Host "Baixando foto.zip..." -ForegroundColor Green
    }
    "8" {
        Invoke-WebRequest -Uri "https://www.inilog.com.br/suporte/pacote/drive/data/drivepinpad.zip" -OutFile "C:\ti\drivepinpad.zip"
        Write-Host "Baixando drivepinpad.zip..." -ForegroundColor Green
    }
    "9" {
        Invoke-WebRequest -Uri "https://www.inilog.com.br/suporte/pacote/drive/data/sitef.zip" -OutFile "C:\ti\sitef.zip"
        Write-Host "Baixando sitef.zip..." -ForegroundColor Green
    }
    "10" {
        Invoke-WebRequest -Uri "https://www.inilog.com.br/suporte/pacote/drive/data/desktop.zip" -OutFile "C:\ti\desktop.zip"
        Write-Host "Baixando desktop.zip..." -ForegroundColor Green
    }
    "0" { Write-Host "Saindo do programa..." -ForegroundColor Red }
    default { Write-Host "Opção inválida. Tente novamente." -ForegroundColor Red }
}


    if ($choice -ne "0") {
        Read-Host "Pressione Enter para voltar ao menu..."
    }
} while ($choice -ne "0")
