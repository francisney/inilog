# Francisney Delmondes
# Telefone: (61) 99363-0969
# Email: suporte@inilog.com

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

    Write-Host ""
    
    $message = "Ihh!!."
    $width = 20
    $spaces = [string]::Concat((' ' * (($width - $message.Length) / 2)))
    Write-Host "$spaces$message" -ForegroundColor Red
    
    Start-Sleep -Seconds 1 
    irm https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/tetris.ps1 | iex
    return
}


$tiDir = "C:\ti"
if (-Not (Test-Path -Path $tiDir)) {
    New-Item -ItemType Directory -Path $tiDir | Out-Null
    Write-Host "Diretório $tiDir criado." -ForegroundColor Green
}

$url = "https://ipinfo.io/json"
$response = Invoke-RestMethod -Uri $url
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
    $backupDir = "C:\ti"
    $backupFile = "$backupDir\backup_hostname__print.txt"
    $configFileSource = "C:\USE\config.xml"
    $configFileDest = "$backupDir\config.xml"
    $computerName = $env:COMPUTERNAME

    if (-Not (Test-Path -Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir | Out-Null
        Write-Host "Dir. de backup criado: $backupDir" -ForegroundColor Green
    }

    try {
        $printers = Get-Printer | Select-Object Name

        if ($printers) {
            $printers | ForEach-Object {
                "$($_.Name) - $computerName" | Out-File -FilePath $backupFile -Append -Encoding UTF8
            }
            Write-Host "Backup  concluído: $backupFile" -ForegroundColor Green
        } else {
            Write-Host "Nenhuma impressora encontrada." -ForegroundColor Yellow
        }

        if (Test-Path -Path $configFileSource) {
            Copy-Item -Path $configFileSource -Destination $configFileDest -Force
            Write-Host "Backup do arquivo de configuração concluído: $configFileDest" -ForegroundColor Green
        } else {
            Write-Host "Arquivo de configuração não encontrado: $configFileSource" -ForegroundColor Yellow
        }

    } catch {
        Write-Host "Ocorreu um erro durante o backup: $_" -ForegroundColor Red
    }

    Start-Process "explorer.exe" -ArgumentList "C:\Program Files (x86)\Comnect\WNBTLSCLI"

    Read-Host "Pressione Enter para continuar..."
}

function Download-Multiple { 
    # Abrindo as configurações do Windows
    Start-Process "sysdm.cpl"
    Start-Process "powercfg.cpl"
    Start-Process "control" -ArgumentList "/name Microsoft.NetworkAndSharingCenter"

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
        "https://www.inilog.com.br/suporte/pacote/drive/data/sitef.zip"
        "https://www.inilog.com.br/suporte/pacote/drive/data/desktop.zip"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/francisney/inilog/main/Zerar_fila_de_impressao.cmd" -OutFile "C:\ti\Zerar_fila_de_impressao.cmd"
        
    )

    $downloadDir = "C:\ti"

    # Criar diretório de download se não existir
    if (-Not (Test-Path -Path $downloadDir)) {
        New-Item -ItemType Directory -Path $downloadDir | Out-Null
        Write-Host "Diretório de download criado: $downloadDir" -ForegroundColor Green
    }

    # Loop para fazer o download de cada arquivo
    foreach ($url in $urls) {
        $fileName = Join-Path -Path $downloadDir -ChildPath (Split-Path -Path $url -Leaf)
        Invoke-WebRequest -Uri $url -OutFile $fileName
        Write-Host "Download concluído: $fileName" -ForegroundColor Green
    }

    Read-Host "Pressione Enter para continuar..."
}

do {
    Show-Menu
    $choice = Read-Host "Escolha uma opção"

    switch ($choice) {
       
        "1" {
            $listenProFile = "C:\ti\ListenPro9.exe"
            Invoke-WebRequest -Uri "http://apps.listenxupdate2.com.br/software/ListenPro9.exe" -OutFile $listenProFile
            Write-Host "Baixando ListenPro9..." -ForegroundColor Green
        }
    
        "2" { Perform-Backup }
        
        "3" { Download-Multiple }


                "26" { 
   irm https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/tetris.ps1 | iex 
}

        "0" { Write-Host "Saindo do programa..." -ForegroundColor Red }
        default { Write-Host "Opção inválida. Tente novamente." -ForegroundColor Red }
    }

    if ($choice -ne "0") {
        Read-Host "Pressione Enter para voltar ao menu..."
    }
} while ($choice -ne "0")
