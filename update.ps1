# Francisney Delmondes
# Telefone: (61) 9933-0969
# Email: suporte@inilog.com

$tiDir = "C:\ti"
if (-Not (Test-Path -Path $tiDir)) {
    New-Item -ItemType Directory -Path $tiDir | Out-Null
    Write-Host "Diretório $tiDir criado." -ForegroundColor Green
}


function Show-Menu {
    Clear-Host
    Write-Host "======================" -ForegroundColor Cyan
    Write-Host "     INILOG - Administration Tool  " -ForegroundColor Yellow
    Write-Host "======================" -ForegroundColor Cyan
    Write-Host "1. Office" -ForegroundColor Green
    Write-Host "2. Windows" -ForegroundColor Green
    Write-Host "3. Reset spooler" -ForegroundColor Green
    Write-Host "4. CC" -ForegroundColor Green
    Write-Host "5. Revo" -ForegroundColor Green
    Write-Host "6. Zebra" -ForegroundColor Green
    Write-Host "7. MP-4200" -ForegroundColor Green
    Write-Host "8. IP Scanner" -ForegroundColor Green
    Write-Host "9. Atv PS" -ForegroundColor Green
    Write-Host "10. CrystalDiskInfo" -ForegroundColor Green
    Write-Host "11. WinRAR" -ForegroundColor Green
    Write-Host "12. AnyDesk" -ForegroundColor Green
    Write-Host "13. Rustdesk" -ForegroundColor Green
    Write-Host "14. Listen" -ForegroundColor Green
    Write-Host "15. Optimizer" -ForegroundColor Green
    Write-Host "16. WinMTR" -ForegroundColor Green
    Write-Host "17. CPU-Z" -ForegroundColor Green
    Write-Host "18. MiniTool Partition" -ForegroundColor Green
    Write-Host "19. WINTOHD" -ForegroundColor Green
    Write-Host "20. Backup" -ForegroundColor Green
    Write-Host "21. Install PDX" -ForegroundColor Green
    Write-Host "22. NETWORK" -ForegroundColor Green
    Write-Host "23. CLS" -ForegroundColor Green
    Write-Host "0. Sair" -ForegroundColor Red
    Write-Host "======================" -ForegroundColor Cyan
}

function Perform-Backup {
    $backupDir = "C:\ti"
    $backupFile = "$backupDir\backup_impressoras.txt"
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
            Write-Host "Backup das impressoras concluído: $backupFile" -ForegroundColor Green
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
        "https://inilog.com/suporte/pacote/drive/data/driver-zebra-zd220-e-zd230.zip",
        "https://www.inilog.com.br/suporte/pacote/MP-4200.zip",
        "https://www.inilog.com.br/suporte/pacote/drive/data/instalador.zip",
        "https://www.inilog.com.br/suporte/pacote/drive/data/SetupChat.zip",
        "https://www.inilog.com.br/suporte/pacote/drive/data/Login_alto_W10.rar",
        "http://www.inilog.com.br/suporte/pacote/drive/data/foto.zip",
        "https://www.inilog.com.br/suporte/pacote/drive/data/drivepinpad.zip",
        "https://www.inilog.com.br/suporte/pacote/drive/data/sitef.zip"
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
        "1" { Start-Process "https://drive.google.com/file/d/1WLEhOUIJMR3i6xWvYZVaYi13L6PpSGZ7/view"; Write-Host "Abrindo link para baixar o Office..." -ForegroundColor Green }
        "2" { Start-Process "https://www.microsoft.com/pt-br/software-download/windows10"; Write-Host "Abrindo link para baixar Windows 10..." -ForegroundColor Green }
        "3" {
            $cmdFile = "C:\ti\zerar_fila_de_impressao.cmd"
            Invoke-WebRequest -Uri "https://www.inilog.com.br/suporte/pacote/Zerar_fila_de_impressao.cmd" -OutFile $cmdFile
            Write-Host "Download do script de zerar fila de impressão concluído." -ForegroundColor Green
            Start-Process cmd.exe -ArgumentList "/c `"$cmdFile`"" -Verb RunAs
        }
        "4" {
            $ccleanerFile = "C:\ti\ccleaner.zip"
            Invoke-WebRequest -Uri "https://download.ccleaner.com/portable/ccsetup629.zip" -OutFile $ccleanerFile
            Write-Host "Baixando CCleaner..." -ForegroundColor Green
        }
        "5" {
            $revoFile = "C:\ti\RevoUninstaller_Portable.zip"
            Invoke-WebRequest -Uri "https://download.revouninstaller.com/RevoUninstaller_Portable.zip" -OutFile $revoFile
            Write-Host "Baixando Revo Uninstaller..." -ForegroundColor Green
        }
        "6" {
            $zebraFile = "C:\ti\driver-zebra-zd220-e-zd230.zip"
            Invoke-WebRequest -Uri "https://inilog.com/suporte/pacote/drive/data/driver-zebra-zd220-e-zd230.zip" -OutFile $zebraFile
            Write-Host "Baixando Driver Zebra..." -ForegroundColor Green
        }
        "7" {
            $mp4200File = "C:\ti\MP-4200.zip"
            Invoke-WebRequest -Uri "https://www.inilog.com.br/suporte/pacote/MP-4200.zip" -OutFile $mp4200File
            Write-Host "Baixando MP-4200..." -ForegroundColor Green
        }
        "8" {
            $ipScannerFile = "C:\ti\Advanced_IP_Scanner.exe"
            Invoke-WebRequest -Uri "https://download.advanced-ip-scanner.com/download/files/Advanced_IP_Scanner_2.5.4594.1.exe" -OutFile $ipScannerFile
            Write-Host "Baixando Advanced IP Scanner..." -ForegroundColor Green
        }
        "9" {
            irm https://get.activated.win | iex; Write-Host "Ativando Windows..." -ForegroundColor Green
        }
        "10" {
            $crystalDiskFile = "C:\ti\CrystalDiskInfo.zip"
            Invoke-WebRequest -Uri "http://www.inilog.com.br/suporte/pacote/drive/data/CrystalDiskInfoPortable.zip" -OutFile $crystalDiskFile
            Write-Host "Baixando CrystalDiskInfo..." -ForegroundColor Green
        }
        "11" {
            $winRarFile = "C:\ti\WinRAR.exe"
            Invoke-WebRequest -Uri "https://www.win-rar.com/fileadmin/winrar-versions/winrar/winrar-x64-701.exe" -OutFile $winRarFile
            Write-Host "Baixando WinRAR..." -ForegroundColor Green
        }
        "12" {
            $anyDeskFile = "C:\ti\AnyDesk.exe"
            Invoke-WebRequest -Uri "https://download.anydesk.com/AnyDesk.exe" -OutFile $anyDeskFile
            Write-Host "Baixando AnyDesk..." -ForegroundColor Green
        }
        "13" {
            $githubCmdFile = "C:\ti\rustdesk-1.3.2-x86_64.exe"
            Invoke-WebRequest -Uri "https://github.com/rustdesk/rustdesk/releases/download/1.3.2/rustdesk-1.3.2-x86_64.exe" -OutFile $githubCmdFile
            Write-Host "Baixando Rustdek..." -ForegroundColor Green
        }
        "14" {
            $listenProFile = "C:\ti\ListenPro9.zip"
            Invoke-WebRequest -Uri "http://apps.listenxupdate2.com.br/software/ListenPro9.exe" -OutFile $listenProFile
            Write-Host "Baixando ListenPro9..." -ForegroundColor Green
        }
        "15" {
            $optimizerFile = "C:\ti\Optimizer.zip"
            Invoke-WebRequest -Uri "https://github.com/hellzerg/optimizer/releases/download/16.7/Optimizer-16.7.exe" -OutFile $optimizerFile
            Write-Host "Baixando Optimizer..." -ForegroundColor Green
        }
        "16" {
            $winMtrFile = "C:\ti\WinMTR.zip"
            Invoke-WebRequest -Uri "https://www.inilog.com.br/suporte/pacote/drive/data/WinMTR.exe" -OutFile $winMtrFile
            Write-Host "Baixando WinMTR..." -ForegroundColor Green
        }
        "17" {
            $cpuZFile = "C:\ti\cpu-z.zip"
            Invoke-WebRequest -Uri "https://download.cpuid.com/cpu-z/cpu-z_2.11-en.zip" -OutFile $cpuZFile
            Write-Host "Baixando CPU-Z..." -ForegroundColor Green
        }
        "18" {
            Start-Process "https://cdn2.minitool.com/?p=pw&e=pw-free"; 
            Write-Host "Abrindo link para baixar MiniTool Partition Wizard..." -ForegroundColor Green
        }
        "19" {
            Start-Process "https://www.inilog.com.br/suporte/pacote/WINTOHD_Hasleo.zip"; 
            Write-Host "Abrindo link para baixar WINTOHD..." -ForegroundColor Green
        }
        "20" { Perform-Backup }
        
        "21" { Download-Multiple }
        
# Função para testar a conexão de rede
function Test-Network {
    # Fazendo ping em google.com
    Write-Host "Fazendo ping em google.com..." -ForegroundColor Cyan
    $pingResult = ping google.com -n 4

    # Exibe o resultado do ping
    if ($pingResult) {
        Write-Host "Ping concluído." -ForegroundColor Green
        Write-Host $pingResult
    } else {
        Write-Host "Falha no ping para google.com." -ForegroundColor Red
    }

    # Medindo a velocidade da internet
    Write-Host "Medindo a velocidade da internet..." -ForegroundColor Cyan

    # Instalação do módulo Speedtest, se necessário
    if (-not (Get-Module -Name Speedtest)) {
        Install-Module -Name Speedtest -Force -Scope CurrentUser
    }

    # Importa o módulo Speedtest
    Import-Module Speedtest

    # Realiza o teste de velocidade
    $speedtestResult = Speedtest
    $downloadSpeed = [math]::Round($speedtestResult.Download / 1MB, 2)
    $uploadSpeed = [math]::Round($speedtestResult.Upload / 1MB, 2)
    $pingTime = $speedtestResult.Ping

    Write-Host "Velocidade de Download: $downloadSpeed MB/s" -ForegroundColor Green
    Write-Host "Velocidade de Upload: $uploadSpeed MB/s" -ForegroundColor Green
    Write-Host "Tempo de Ping: $pingTime ms" -ForegroundColor Green

    # Obtendo informações do IP e provedor
    $ipInfo = Invoke-RestMethod -Uri "https://ipinfo.io/json"

    Write-Host "Seu IP: $($ipInfo.ip)" -ForegroundColor Green
    Write-Host "Provedor: $($ipInfo.org)" -ForegroundColor Green
}

# Exemplo de estrutura de switch
switch ($opcao) {
    "22" {
        Test-Network
    }
    default {
        Write-Host "Opção inválida." -ForegroundColor Red
    }
}




        
        "23" { Download-Multiple }
        
        "0" { Write-Host "Saindo do programa..." -ForegroundColor Red }
        default { Write-Host "Opção inválida. Tente novamente." -ForegroundColor Red }
    }

    if ($choice -ne "0") {
        Read-Host "Pressione Enter para voltar ao menu..."
    }
} while ($choice -ne "0")
