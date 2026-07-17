#requires -Version 5.1

# Francisney Delmondes
# Email: suporte@inilog.com
# INILOG - Ferramentas Administrativas

$ErrorActionPreference = 'Continue'

try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
    # Mantém a compatibilidade caso TLS 1.2 já esteja configurado.
}

try {
    $Host.UI.RawUI.WindowTitle = 'INILOG - Ferramentas Administrativas'
} catch {
    # Alguns hosts não permitem alterar o título da janela.
}

$script:DiretorioTI = 'C:\ti'
$script:IpPublico = 'Indisponível'
$script:Provedor = 'Indisponível'

$script:CorBorda = 'DarkCyan'
$script:CorTitulo = 'Yellow'
$script:CorSecao = 'Cyan'
$script:CorOpcao = 'White'
$script:CorNumero = 'Green'
$script:CorSucesso = 'Green'
$script:CorAviso = 'Yellow'
$script:CorErro = 'Red'
$script:CorInfo = 'Cyan'

function Write-Line {
    param(
        [char]$Character = '=',
        [ConsoleColor]$Color = 'DarkCyan'
    )

    $width = 72

    try {
        $currentWidth = $Host.UI.RawUI.WindowSize.Width - 1
        if ($currentWidth -ge 50 -and $currentWidth -le 110) {
            $width = $currentWidth
        }
    } catch {
        # Usa a largura padrão.
    }

    Write-Host ($Character.ToString() * $width) -ForegroundColor $Color
}

function Write-Centered {
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [ConsoleColor]$Color = 'White'
    )

    $width = 72

    try {
        $currentWidth = $Host.UI.RawUI.WindowSize.Width - 1
        if ($currentWidth -ge 50 -and $currentWidth -le 110) {
            $width = $currentWidth
        }
    } catch {
        # Usa a largura padrão.
    }

    $padding = [Math]::Max(0, [Math]::Floor(($width - $Text.Length) / 2))
    Write-Host ((' ' * $padding) + $Text) -ForegroundColor $Color
}

function Write-Status {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Type = 'Info'
    )

    switch ($Type) {
        'Success' {
            Write-Host '[OK] ' -NoNewline -ForegroundColor $script:CorSucesso
            Write-Host $Message -ForegroundColor White
        }
        'Warning' {
            Write-Host '[!]  ' -NoNewline -ForegroundColor $script:CorAviso
            Write-Host $Message -ForegroundColor White
        }
        'Error' {
            Write-Host '[ERRO] ' -NoNewline -ForegroundColor $script:CorErro
            Write-Host $Message -ForegroundColor White
        }
        default {
            Write-Host '[i]  ' -NoNewline -ForegroundColor $script:CorInfo
            Write-Host $Message -ForegroundColor White
        }
    }
}

function Write-MenuSection {
    param([Parameter(Mandatory)][string]$Title)

    Write-Host ''
    Write-Host ('  {0}' -f $Title.ToUpperInvariant()) -ForegroundColor $script:CorSecao
}

function Write-MenuItem {
    param(
        [Parameter(Mandatory)][string]$Number,
        [Parameter(Mandatory)][string]$Label
    )

    Write-Host '  [' -NoNewline -ForegroundColor DarkGray
    Write-Host $Number.PadLeft(2, '0') -NoNewline -ForegroundColor $script:CorNumero
    Write-Host '] ' -NoNewline -ForegroundColor DarkGray
    Write-Host $Label -ForegroundColor $script:CorOpcao
}

function ConvertTo-PlainText {
    param([Parameter(Mandatory)][System.Security.SecureString]$SecureString)

    $pointer = [IntPtr]::Zero

    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } finally {
        if ($pointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        }
    }
}

function Get-PublicNetworkInfo {
    try {
        $networkInfo = Invoke-RestMethod -Uri 'https://ipinfo.io/json' -TimeoutSec 10 -ErrorAction Stop

        if ($networkInfo.ip) {
            $script:IpPublico = [string]$networkInfo.ip
        }

        if ($networkInfo.org) {
            $script:Provedor = [string]$networkInfo.org
        }
    } catch {
        $script:IpPublico = 'Não foi possível consultar'
        $script:Provedor = 'Não foi possível consultar'
    }
}

function Initialize-WorkingDirectory {
    try {
        if (-not (Test-Path -LiteralPath $script:DiretorioTI)) {
            New-Item -ItemType Directory -Path $script:DiretorioTI -Force | Out-Null
            Write-Status "Diretório $script:DiretorioTI criado." 'Success'
        }
    } catch {
        Write-Status "Não foi possível criar $script:DiretorioTI. $($_.Exception.Message)" 'Error'
    }
}

function Save-RemoteFile {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Description,
        [switch]$Run,
        [switch]$RunAsAdministrator
    )

    try {
        $parentDirectory = Split-Path -Parent $Destination

        if ($parentDirectory -and -not (Test-Path -LiteralPath $parentDirectory)) {
            New-Item -ItemType Directory -Path $parentDirectory -Force | Out-Null
        }

        Write-Status "Baixando $Description..." 'Info'
        Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -ErrorAction Stop
        Write-Status "$Description salvo em: $Destination" 'Success'

        if ($Run) {
            if ($RunAsAdministrator) {
                Start-Process -FilePath $Destination -Verb RunAs
            } else {
                Start-Process -FilePath $Destination
            }

            Write-Status "$Description iniciado." 'Success'
        }
    } catch {
        Write-Status "Falha em $Description. $($_.Exception.Message)" 'Error'
    }
}

function Open-WebAddress {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Description
    )

    try {
        Start-Process $Uri
        Write-Status "$Description aberto no navegador." 'Success'
    } catch {
        Write-Status "Não foi possível abrir $Description. $($_.Exception.Message)" 'Error'
    }
}

function Invoke-RemoteScript {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Description
    )

    try {
        Write-Status "Carregando $Description..." 'Info'
        $remoteCode = Invoke-RestMethod -Uri $Uri -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace([string]$remoteCode)) {
            throw 'O servidor retornou um script vazio.'
        }

        Invoke-Expression ([string]$remoteCode)
    } catch {
        Write-Status "Falha ao executar $Description. $($_.Exception.Message)" 'Error'
    }
}

function Show-Header {
    Clear-Host
    Write-Line '=' $script:CorBorda
    Write-Centered 'INILOG' $script:CorTitulo
    Write-Centered 'FERRAMENTAS ADMINISTRATIVAS' White
    Write-Line '=' $script:CorBorda
}

function Show-Login {
    Show-Header
    Write-Host ''
    Write-Centered 'ACESSO RESTRITO' $script:CorAviso
    Write-Host ''

    $expectedPassword = (Get-Date).ToString('ddMMyyyy')
    $securePassword = Read-Host -Prompt 'Informe a senha de acesso' -AsSecureString
    $typedPassword = ConvertTo-PlainText -SecureString $securePassword

    if ($typedPassword -ne $expectedPassword) {
        Write-Host ''
        Write-Centered 'ACESSO NEGADO' $script:CorErro
        Write-Centered 'Senha incorreta.' DarkRed
        Write-Host ''
        Start-Sleep -Seconds 1

        try {
            Invoke-RemoteScript `
                -Uri 'https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/tetris.ps1' `
                -Description 'Tetris'
        } catch {
            # A mensagem de erro já é tratada pela função.
        }

        return $false
    }

    Write-Host ''
    Write-Centered 'ACESSO LIBERADO' $script:CorSucesso
    Start-Sleep -Milliseconds 600
    return $true
}

function Show-Menu {
    Show-Header

    Write-Host ''
    Write-Host '  Rede pública' -ForegroundColor DarkGray
    Write-Host '  IP:       ' -NoNewline -ForegroundColor DarkGray
    Write-Host $script:IpPublico -ForegroundColor White
    Write-Host '  Provedor: ' -NoNewline -ForegroundColor DarkGray
    Write-Host $script:Provedor -ForegroundColor White

    Write-MenuSection 'Sistemas e produtividade'
    Write-MenuItem '1'  'Office'
    Write-MenuItem '2'  'Download do Windows 10'
    Write-MenuItem '9'  'Ativação oficial do Windows'
    Write-MenuItem '18' 'MiniTool Partition Wizard'
    Write-MenuItem '19' 'WinToHDD'
    Write-MenuItem '20' 'GodMode'
    Write-MenuItem '21' 'Ferramentas administrativas'
    Write-MenuItem '25' 'WinUtil'

    Write-MenuSection 'Manutenção e diagnóstico'
    Write-MenuItem '3'  'Limpar fila de impressão'
    Write-MenuItem '4'  'CCleaner Portable'
    Write-MenuItem '5'  'Revo Uninstaller Portable'
    Write-MenuItem '8'  'Advanced IP Scanner'
    Write-MenuItem '10' 'CrystalDiskInfo'
    Write-MenuItem '15' 'Optimizer'
    Write-MenuItem '16' 'WinMTR'
    Write-MenuItem '17' 'CPU-Z'
    Write-MenuItem '22' 'Teste de velocidade'
    Write-MenuItem '23' 'CLS'
    Write-MenuItem '24' 'IP Scanner PowerShell'
    Write-MenuItem '27' 'Fake Failover / MudaLink'
    Write-MenuItem '30' 'HWiNFO64'
    Write-MenuItem '31' 'Snappy Driver Installer Origin'

    Write-MenuSection 'Impressoras e acesso remoto'
    Write-MenuItem '6'  'Driver Zebra ZD220/ZD230'
    Write-MenuItem '7'  'Driver MP-4200'
    Write-MenuItem '11' 'WinRAR'
    Write-MenuItem '12' 'AnyDesk'
    Write-MenuItem '13' 'RustDesk'
    Write-MenuItem '26' 'WinRAR (download alternativo)'
    Write-MenuItem '28' 'Reset do AnyDesk'
    Write-MenuItem '29' 'Web Control'
    Write-MenuItem '32' 'Gerenciador Zebra N2'

    Write-Host ''
    Write-Line '-' DarkGray
    Write-MenuItem '0' 'Sair'
    Write-Line '=' $script:CorBorda
    Write-Host ''
}

if (-not (Show-Login)) {
    return
}

Initialize-WorkingDirectory
Get-PublicNetworkInfo

$choice = $null

do {
    Show-Menu
    $choice = (Read-Host 'Escolha uma opção').Trim()
    Write-Host ''

    switch ($choice) {
        '1' {
            Open-WebAddress `
                -Uri 'https://drive.google.com/file/d/1WLEhOUIJMR3i6xWvYZVaYi13L6PpSGZ7/view' `
                -Description 'instruções do Office'

            Open-WebAddress `
                -Uri 'https://c2rsetup.officeapps.live.com/c2r/download.aspx?ProductreleaseID=O365BusinessRetail&platform=x64&language=pt-br&version=O16GA' `
                -Description 'instalador do Office'
        }

        '2' {
            Open-WebAddress `
                -Uri 'https://www.microsoft.com/pt-br/software-download/windows10' `
                -Description 'download oficial do Windows 10'
        }

        '3' {
            Save-RemoteFile `
                -Uri 'https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/Zerar_fila_de_impressao.cmd' `
                -Destination "$script:DiretorioTI\zerar_fila_de_impressao.cmd" `
                -Description 'script de limpeza da fila de impressão'

            $cmdFile = "$script:DiretorioTI\zerar_fila_de_impressao.cmd"
            if (Test-Path -LiteralPath $cmdFile) {
                try {
                    Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$cmdFile`"" -Verb RunAs
                    Write-Status 'Limpeza da fila de impressão iniciada.' 'Success'
                } catch {
                    Write-Status "Não foi possível iniciar a limpeza. $($_.Exception.Message)" 'Error'
                }
            }
        }

        '4' {
            Save-RemoteFile `
                -Uri 'https://download.ccleaner.com/portable/ccsetup629.zip' `
                -Destination "$script:DiretorioTI\ccleaner.zip" `
                -Description 'CCleaner Portable'
        }

        '5' {
            Save-RemoteFile `
                -Uri 'https://download.revouninstaller.com/RevoUninstaller_Portable.zip' `
                -Destination "$script:DiretorioTI\RevoUninstaller_Portable.zip" `
                -Description 'Revo Uninstaller Portable'
        }

        '6' {
            Save-RemoteFile `
                -Uri 'https://inilog.com/suporte/628/files/driver-zebra-zd220-e-zd230.zip' `
                -Destination "$script:DiretorioTI\driver-zebra-zd220-e-zd230.zip" `
                -Description 'driver Zebra ZD220/ZD230'
        }

        '7' {
            Save-RemoteFile `
                -Uri 'https://www.inilog.com/suporte/628/files/MP-4200.zip' `
                -Destination "$script:DiretorioTI\MP-4200.zip" `
                -Description 'driver MP-4200'
        }

        '8' {
            Save-RemoteFile `
                -Uri 'https://download.advanced-ip-scanner.com/download/files/Advanced_IP_Scanner_2.5.4594.1.exe' `
                -Destination "$script:DiretorioTI\Advanced_IP_Scanner.exe" `
                -Description 'Advanced IP Scanner'
        }

        '9' {
            try {
                Start-Process 'ms-settings:activation'
                Write-Status 'Configurações oficiais de ativação do Windows abertas.' 'Success'
            } catch {
                try {
                    Start-Process -FilePath 'slui.exe' -ArgumentList '3'
                    Write-Status 'Assistente oficial de ativação aberto.' 'Success'
                } catch {
                    Write-Status "Não foi possível abrir a ativação do Windows. $($_.Exception.Message)" 'Error'
                }
            }
        }

        '10' {
            Save-RemoteFile `
                -Uri 'https://www.inilog.com/suporte/628/files/CrystalDiskInfoPortable.zip' `
                -Destination "$script:DiretorioTI\CrystalDiskInfo.zip" `
                -Description 'CrystalDiskInfo Portable'
        }

        '11' {
            Save-RemoteFile `
                -Uri 'https://www.win-rar.com/fileadmin/winrar-versions/winrar/winrar-x64-701.exe' `
                -Destination "$script:DiretorioTI\WinRAR.exe" `
                -Description 'WinRAR'
        }

        '12' {
            Save-RemoteFile `
                -Uri 'https://download.anydesk.com/AnyDesk.exe' `
                -Destination "$script:DiretorioTI\AnyDesk.exe" `
                -Description 'AnyDesk'
        }

        '13' {
            Save-RemoteFile `
                -Uri 'https://github.com/rustdesk/rustdesk/releases/download/1.3.2/rustdesk-1.3.2-x86_64.exe' `
                -Destination "$script:DiretorioTI\rustdesk-1.3.2-x86_64.exe" `
                -Description 'RustDesk'
        }

        # Opção reservada para serviço específico. Não é exibida no menu.
        '14' {
            Invoke-RemoteScript `
                -Uri 'https://inilog.com/suporte/628/files/628.ps1' `
                -Description 'serviço específico 628'
        }

        '15' {
            Save-RemoteFile `
                -Uri 'https://github.com/hellzerg/optimizer/releases/download/16.7/Optimizer-16.7.exe' `
                -Destination "$script:DiretorioTI\Optimizer.exe" `
                -Description 'Optimizer'
        }

        '16' {
            Save-RemoteFile `
                -Uri 'https://www.inilog.com/suporte/628/files/WinMTR.exe' `
                -Destination "$script:DiretorioTI\WinMTR.exe" `
                -Description 'WinMTR'
        }

        '17' {
            Save-RemoteFile `
                -Uri 'https://download.cpuid.com/cpu-z/cpu-z_2.11-en.zip' `
                -Destination "$script:DiretorioTI\cpu-z.zip" `
                -Description 'CPU-Z'
        }

        '18' {
            Open-WebAddress `
                -Uri 'https://cdn2.minitool.com/?p=pw&e=pw-free' `
                -Description 'MiniTool Partition Wizard'
        }

        '19' {
            Open-WebAddress `
                -Uri 'https://www.inilog.com/suporte/628/files/WINTOHD_Hasleo.zip' `
                -Description 'WinToHDD'
        }

        '20' {
            Invoke-RemoteScript `
                -Uri 'https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/godmode' `
                -Description 'GodMode'
        }

        '21' {
            Invoke-RemoteScript `
                -Uri 'https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/adm.ps1' `
                -Description 'ferramentas administrativas'
        }

        '22' {
            Invoke-RemoteScript `
                -Uri 'https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/speedtest.ps1' `
                -Description 'teste de velocidade'
        }

        '23' {
            Invoke-RemoteScript `
                -Uri 'https://raw.githubusercontent.com/francisney/inilog/main/cls.ps1' `
                -Description 'CLS'
        }

        '24' {
            $ipScannerDestination = "$script:DiretorioTI\IP_Scanner.exe"

            Save-RemoteFile `
                -Uri 'https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/IP_Scanner.exe' `
                -Destination $ipScannerDestination `
                -Description 'IP Scanner PowerShell' `
                -Run
        }

        '25' {
            Invoke-RemoteScript `
                -Uri 'https://raw.githubusercontent.com/francisney/winutil/refs/heads/main/windev.ps1' `
                -Description 'WinUtil'
        }

        '26' {
            Save-RemoteFile `
                -Uri 'https://www.win-rar.com/fileadmin/winrar-versions/winrar/winrar-x64-701.exe' `
                -Destination "$script:DiretorioTI\winrar-x64-701.exe" `
                -Description 'WinRAR alternativo'
        }

        '27' {
            Save-RemoteFile `
                -Uri 'https://inilog.com/suporte/628/files/MudaLink.exe' `
                -Destination "$script:DiretorioTI\MudaLink.exe" `
                -Description 'MudaLink / Fake Failover'
        }

        '28' {
            # Apesar da extensão .exe no repositório, este endereço retorna código PowerShell em texto.
            Invoke-RemoteScript `
                -Uri 'https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/anydesk.exe' `
                -Description 'reset do AnyDesk'
        }

        '29' {
            Invoke-RemoteScript `
                -Uri 'https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/webcontrol.ps1' `
                -Description 'Web Control'
        }

        '30' {
            Save-RemoteFile `
                -Uri 'https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/HWiNFO64.exe' `
                -Destination "$script:DiretorioTI\HWiNFO64.exe" `
                -Description 'HWiNFO64'
        }

        '31' {
            Open-WebAddress `
                -Uri 'https://www.glenn.delahoy.com/snappy-driver-installer-origin/' `
                -Description 'Snappy Driver Installer Origin'
        }

        '32' {
            Invoke-RemoteScript `
                -Uri 'https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/zebra.ps1' `
                -Description 'Gerenciador Zebra N2'
        }

        '0' {
            Write-Centered 'Encerrando o INILOG...' $script:CorAviso
            Start-Sleep -Milliseconds 500
        }

        default {
            Write-Status "Opção '$choice' inválida. Tente novamente." 'Warning'
        }
    }

    if ($choice -ne '0') {
        Write-Host ''
        [void](Read-Host 'Pressione Enter para voltar ao menu')
    }
} while ($choice -ne '0')

Clear-Host
Write-Centered 'INILOG encerrado.' $script:CorSucesso
Write-Host ''
