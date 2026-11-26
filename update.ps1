#requires -Version 5.1
<#
    INILOG | Painel de suporte
    Francisney Delmondes - suporte@inilog.com
    Compativel com Windows PowerShell 5.1 e PowerShell no Windows.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$DiretorioDownloads = 'C:\ti'
)

function New-InilogResult {
    param(
        [bool]$Success,
        [string]$Message,
        [string]$Path = ''
    )

    [PSCustomObject]@{
        Success = $Success
        Message = $Message
        Path = $Path
    }
}

function Write-InilogStatus {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Type = 'Info'
    )

    $styles = @{
        Info    = @('[i]', 'Cyan')
        Success = @('[OK]', 'Green')
        Warning = @('[!]', 'Yellow')
        Error   = @('[ERRO]', 'Red')
    }

    $style = $styles[$Type]
    Write-Host (' {0} ' -f $style[0]) -NoNewline -ForegroundColor $style[1]
    Write-Host $Message -ForegroundColor White
}

function Get-InilogConsoleWidth {
    $width = 96
    try {
        $available = [int]$Host.UI.RawUI.WindowSize.Width - 1
        if ($available -ge 32) {
            $width = [Math]::Min(118, $available)
        }
    } catch {
        # Hosts sem RawUI usam a largura padrão.
    }
    return $width
}

function Get-InilogFitText {
    param([string]$Text, [int]$Width)

    if ($Width -le 0) { return '' }
    if ($null -eq $Text) { return '' }
    if ($Text.Length -le $Width) { return $Text }
    if ($Width -le 3) { return $Text.Substring(0, $Width) }
    return $Text.Substring(0, $Width - 3) + '...'
}

function Write-InilogRule {
    param([char]$Character = '-', [ConsoleColor]$Color = 'DarkCyan')
    Write-Host ($Character.ToString() * (Get-InilogConsoleWidth)) -ForegroundColor $Color
}

function Test-InilogAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Initialize-InilogState {
    param([string]$DownloadDirectory)

    $script:InilogState = [PSCustomObject]@{
        Version = '2.0'
        DownloadDirectory = $DownloadDirectory
        PublicIP = 'Indisponível'
        Provider = 'Indisponível'
        Filter = ''
        IsAdministrator = (Test-InilogAdministrator)
    }

    $script:InilogActions = @(Get-InilogActions)
    $script:InilogActionMap = @{}
    foreach ($action in $script:InilogActions) {
        if ($script:InilogActionMap.ContainsKey($action.Id)) {
            throw "Número de opção duplicado: $($action.Id)."
        }
        $script:InilogActionMap[$action.Id] = $action
    }
}

function Update-InilogNetworkInfo {
    try {
        $network = Invoke-RestMethod -Uri 'https://ipinfo.io/json' -TimeoutSec 8 -ErrorAction Stop
        $script:InilogState.PublicIP = 'Indisponível'
        $script:InilogState.Provider = 'Indisponível'
        if ($network.ip) { $script:InilogState.PublicIP = [string]$network.ip }
        if ($network.org) { $script:InilogState.Provider = [string]$network.org }
    } catch {
        $script:InilogState.PublicIP = 'Indisponível'
        $script:InilogState.Provider = 'Sem consulta de rede'
    }
}

function Show-InilogHeader {
    try { Clear-Host } catch {}

    $width = Get-InilogConsoleWidth
    Write-InilogRule '='
    Write-Host ' INILOG' -NoNewline -ForegroundColor Cyan
    Write-Host '  |  PAINEL DE SUPORTE' -NoNewline -ForegroundColor White
    Write-Host ('  v{0}' -f $script:InilogState.Version) -ForegroundColor DarkGray

    $mode = 'Usuário padrão'
    if ($script:InilogState.IsAdministrator) { $mode = 'Administrador' }
    Write-Host (' {0}  |  {1}' -f (Get-Date -Format 'dd/MM/yyyy HH:mm'), $mode) -ForegroundColor DarkGray
    Write-InilogRule '='

    $networkLine = ' IP: {0}  |  {1}' -f $script:InilogState.PublicIP, $script:InilogState.Provider
    Write-Host (Get-InilogFitText $networkLine $width) -ForegroundColor Gray
    $directoryLine = ' Downloads: {0}' -f $script:InilogState.DownloadDirectory
    Write-Host (Get-InilogFitText $directoryLine $width) -ForegroundColor DarkGray
}

function ConvertFrom-InilogSecureString {
    param([Security.SecureString]$SecureString)

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

function Format-InilogSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    return ('{0} B' -f $Bytes)
}

function Test-InilogDownloadedFile {
    param([string]$Path, [string]$Destination, [string]$ContentType)

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.Length -eq 0) { throw 'O servidor retornou um arquivo vazio.' }

    $extension = [IO.Path]::GetExtension($Destination).ToLowerInvariant()
    if ($ContentType -match 'text/html' -and $extension -in @('.exe', '.zip', '.cmd', '.ps1')) {
        throw 'O endereço retornou uma página HTML em vez do arquivo solicitado.'
    }

    if ($extension -in @('.exe', '.zip')) {
        $stream = [IO.File]::OpenRead($Path)
        try {
            $first = $stream.ReadByte()
            $second = $stream.ReadByte()
        } finally {
            $stream.Dispose()
        }
        if ($extension -eq '.exe' -and ($first -ne 0x4D -or $second -ne 0x5A)) {
            throw 'O conteúdo recebido não tem o cabeçalho de um executável Windows.'
        }
        if ($extension -eq '.zip' -and ($first -ne 0x50 -or $second -ne 0x4B)) {
            throw 'O conteúdo recebido não tem o cabeçalho de um arquivo ZIP.'
        }
    }
}

function Save-InilogFile {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $temporary = $null
    $response = $null
    $sourceStream = $null
    $fileStream = $null
    $activity = 'INILOG | ' + $Description

    try {
        $address = [Uri]$Uri
        if (-not $address.IsAbsoluteUri -or $address.Scheme -notin @('http', 'https')) {
            throw 'O endereço de download precisa usar HTTP ou HTTPS.'
        }

        $parent = Split-Path -Parent $Destination
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
        }

        $temporaryName = '.inilog-' + [Guid]::NewGuid().ToString('N') + '.download'
        $temporary = Join-Path $parent $temporaryName
        Write-InilogStatus ('Baixando {0}...' -f $Description)

        $request = [Net.HttpWebRequest]::Create($address)
        $request.UserAgent = 'INILOG-Suporte/2.0'
        $request.Timeout = 30000
        $request.ReadWriteTimeout = 30000
        $request.AllowAutoRedirect = $true
        $response = $request.GetResponse()
        $total = [long]$response.ContentLength
        $contentType = [string]$response.ContentType
        $sourceStream = $response.GetResponseStream()
        $fileStream = [IO.File]::Create($temporary)
        $buffer = New-Object byte[] 65536
        $received = [long]0
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $lastUpdate = [long]-250

        while (($readCount = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fileStream.Write($buffer, 0, $readCount)
            $received += $readCount

            if (($clock.ElapsedMilliseconds - $lastUpdate) -ge 200) {
                $percent = -1
                $status = Format-InilogSize $received
                if ($total -gt 0) {
                    $percent = [int][Math]::Min(100, [Math]::Floor(100.0 * $received / $total))
                    $status = '{0}% | {1} / {2}' -f $percent, (Format-InilogSize $received), (Format-InilogSize $total)
                }
                Write-Progress -Id 1 -Activity $activity -Status $status -PercentComplete $percent
                $lastUpdate = $clock.ElapsedMilliseconds
            }
        }

        $fileStream.Dispose()
        $fileStream = $null
        $sourceStream.Dispose()
        $sourceStream = $null

        if ($total -ge 0 -and $received -ne $total) {
            throw 'O download terminou antes de receber todos os dados.'
        }

        Test-InilogDownloadedFile -Path $temporary -Destination $Destination -ContentType $contentType
        Move-Item -LiteralPath $temporary -Destination $Destination -Force -ErrorAction Stop
        $temporary = $null
        return (New-InilogResult $true ('Arquivo salvo: {0}' -f $Destination) $Destination)
    } catch {
        return (New-InilogResult $false ('Falha no download de {0}: {1}' -f $Description, $_.Exception.Message))
    } finally {
        if ($fileStream) { $fileStream.Dispose() }
        if ($sourceStream) { $sourceStream.Dispose() }
        if ($response) { $response.Dispose() }
        if ($temporary -and (Test-Path -LiteralPath $temporary)) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
        Write-Progress -Id 1 -Activity $activity -Completed
    }
}

function Start-InilogProcess {
    param(
        [string]$Path,
        [string]$Description,
        [string]$Arguments = '',
        [switch]$AsAdministrator
    )

    try {
        $parameters = @{ FilePath = $Path; ErrorAction = 'Stop' }
        if ($Arguments) { $parameters.ArgumentList = $Arguments }
        if ($AsAdministrator) { $parameters.Verb = 'RunAs' }
        Start-Process @parameters | Out-Null
        return (New-InilogResult $true ('{0} iniciado.' -f $Description) $Path)
    } catch {
        return (New-InilogResult $false ('Não foi possível iniciar {0}: {1}' -f $Description, $_.Exception.Message))
    }
}

function Open-InilogLinks {
    param([string[]]$Uris, [string]$Description)

    try {
        foreach ($address in $Uris) {
            Start-Process -FilePath $address -ErrorAction Stop | Out-Null
        }
        return (New-InilogResult $true ('{0} aberto no navegador.' -f $Description))
    } catch {
        return (New-InilogResult $false ('Não foi possível abrir {0}: {1}' -f $Description, $_.Exception.Message))
    }
}

function Get-InilogPowerShellPath {
    foreach ($name in @('powershell.exe', 'pwsh.exe', 'pwsh')) {
        $candidate = Join-Path $PSHOME $name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw 'Não foi possível localizar o executável do PowerShell.'
}

function Invoke-InilogRemoteScript {
    param([string]$Uri, [string]$Description, [string]$FileName)

    $destination = Join-Path $script:InilogState.DownloadDirectory $FileName
    $download = Save-InilogFile -Uri $Uri -Destination $destination -Description $Description
    if (-not $download.Success) { return $download }

    $process = $null
    try {
        $tokens = $null
        $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($destination, [ref]$tokens, [ref]$parseErrors)
        if (@($parseErrors).Count -gt 0) {
            throw 'O script recebido contém erro de sintaxe.'
        }

        $engine = Get-InilogPowerShellPath
        $escapedPath = $destination.Replace("'", "''")
        $command = "& ([ScriptBlock]::Create([IO.File]::ReadAllText('$escapedPath')))"
        Write-InilogStatus ('Executando {0}...' -f $Description)

        # Compartilha o console, sem capturar a entrada/saída das ferramentas interativas.
        # O processo filho mantém o menu aberto mesmo se a ferramenta usar exit.
        $parameters = @{
            FilePath = $engine
            ArgumentList = ('-NoLogo -NoProfile -Command "{0}"' -f $command)
            NoNewWindow = $true
            Wait = $true
            PassThru = $true
            ErrorAction = 'Stop'
        }
        $process = Start-Process @parameters
        if ($process.ExitCode -ne 0) {
            throw ('A ferramenta encerrou com o código {0}.' -f $process.ExitCode)
        }
        return (New-InilogResult $true ('{0} finalizado.' -f $Description) $destination)
    } catch {
        return (New-InilogResult $false ('Falha ao executar {0}: {1}' -f $Description, $_.Exception.Message))
    } finally {
        if ($process) { $process.Dispose() }
    }
}

function Show-InilogLogin {
    Show-InilogHeader
    Write-Host ''
    Write-Host ' ACESSO RESTRITO' -ForegroundColor Yellow
    Write-Host ''
    $securePassword = $null
    $typedPassword = $null
    $expectedPassword = $null
    $authenticated = $false

    try {
        $expectedPassword = (Get-Date).ToString('ddMMyyyy')
        $securePassword = Read-Host 'Informe a senha de acesso' -AsSecureString
        $typedPassword = ConvertFrom-InilogSecureString $securePassword
        $authenticated = $typedPassword -eq $expectedPassword
    } finally {
        $typedPassword = $null
        $expectedPassword = $null
        if ($securePassword) { $securePassword.Dispose() }
    }

    if (-not $authenticated) {
        Write-InilogStatus 'Acesso negado. Senha incorreta.' 'Error'
        Start-Sleep -Milliseconds 700
        $game = @{
            Uri = 'https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/tetris.ps1'
            Description = 'Tetris'
            FileName = 'Scripts\tetris.ps1'
        }
        [void](Invoke-InilogRemoteScript @game)
        return $false
    }

    Write-InilogStatus 'Acesso liberado.' 'Success'
    return $true
}

function New-InilogAction {
    param(
        [int]$Id,
        [string]$Category,
        [string]$Label,
        [ValidateSet('Download', 'Links', 'Script', 'PrintQueue')]
        [string]$Kind,
        [string[]]$Uri,
        [string]$FileName = '',
        [switch]$Run,
        [switch]$Hidden
    )

    [PSCustomObject]@{
        Id = $Id
        Category = $Category
        Label = $Label
        Kind = $Kind
        Uris = @($Uri)
        FileName = $FileName
        Run = [bool]$Run
        Visible = (-not [bool]$Hidden)
    }
}

function Get-InilogActions {
    $system = 'Sistema e manutenção'
    $diagnostics = 'Diagnóstico e rede'
    $support = 'Impressoras e suporte'

    # Os IDs são estáveis. Remover uma entrada retira também seu comando.
    # Visible controla tanto o menu quanto a busca; os reservados aceitam o ID direto.
    @(
        New-InilogAction -Id 1 -Category $system -Label 'Microsoft Office' -Kind Links -Uri @(
            'https://drive.google.com/file/d/1WLEhOUIJMR3i6xWvYZVaYi13L6PpSGZ7/view',
            'https://c2rsetup.officeapps.live.com/c2r/download.aspx?ProductreleaseID=O365BusinessRetail&platform=x64&language=pt-br&version=O16GA'
        )
        New-InilogAction -Id 3 -Category $system -Label 'Limpar fila de impressão' -Kind PrintQueue -Uri 'https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/Zerar_fila_de_impressao.cmd' -FileName 'zerar_fila_de_impressao.cmd'
        New-InilogAction -Id 5 -Category $system -Label 'Revo Uninstaller Portable' -Kind Download -Uri 'https://download.revouninstaller.com/RevoUninstaller_Portable.zip' -FileName 'RevoUninstaller_Portable.zip'
        New-InilogAction -Id 6 -Category $support -Label 'Driver Zebra ZD220/ZD230' -Kind Download -Uri 'https://inilog.com/suporte/628/files/driver-zebra-zd220-e-zd230.zip' -FileName 'driver-zebra-zd220-e-zd230.zip'
        New-InilogAction -Id 7 -Category $support -Label 'Driver MP-4200' -Kind Download -Uri 'https://www.inilog.com/suporte/628/files/MP-4200.zip' -FileName 'MP-4200.zip'
        New-InilogAction -Id 8 -Category $diagnostics -Label 'Advanced IP Scanner' -Kind Download -Uri 'https://download.advanced-ip-scanner.com/download/files/Advanced_IP_Scanner_2.5.4594.1.exe' -FileName 'Advanced_IP_Scanner.exe'
        New-InilogAction -Id 9 -Category 'Reservado' -Label 'Ativação Windows/Office' -Kind Script -Uri 'https://get.activated.win/' -FileName 'Scripts\reservado-09.ps1' -Hidden
        New-InilogAction -Id 10 -Category $diagnostics -Label 'CrystalDiskInfo Portable' -Kind Download -Uri 'https://www.inilog.com/suporte/628/files/CrystalDiskInfoPortable.zip' -FileName 'CrystalDiskInfo.zip'
        New-InilogAction -Id 13 -Category $support -Label 'RustDesk' -Kind Download -Uri 'https://github.com/rustdesk/rustdesk/releases/download/1.3.2/rustdesk-1.3.2-x86_64.exe' -FileName 'rustdesk-1.3.2-x86_64.exe'
        New-InilogAction -Id 14 -Category 'Reservado' -Label 'Serviço específico 628' -Kind Script -Uri 'https://inilog.com/suporte/628/files/628.ps1' -FileName 'Scripts\628.ps1' -Hidden
        New-InilogAction -Id 15 -Category $system -Label 'Optimizer' -Kind Download -Uri 'https://github.com/hellzerg/optimizer/releases/download/16.7/Optimizer-16.7.exe' -FileName 'Optimizer.exe'
        New-InilogAction -Id 16 -Category $diagnostics -Label 'WinMTR' -Kind Download -Uri 'https://www.inilog.com/suporte/628/files/WinMTR.exe' -FileName 'WinMTR.exe'
        New-InilogAction -Id 17 -Category $diagnostics -Label 'CPU-Z' -Kind Download -Uri 'https://download.cpuid.com/cpu-z/cpu-z_2.11-en.zip' -FileName 'cpu-z.zip'
        New-InilogAction -Id 18 -Category $system -Label 'MiniTool Partition Wizard' -Kind Links -Uri 'https://cdn2.minitool.com/?p=pw&e=pw-free'
        New-InilogAction -Id 19 -Category $system -Label 'WinToHDD' -Kind Links -Uri 'https://www.inilog.com/suporte/628/files/WINTOHD_Hasleo.zip'
        New-InilogAction -Id 20 -Category $system -Label 'GodMode' -Kind Script -Uri 'https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/godmode' -FileName 'Scripts\godmode.ps1'
        New-InilogAction -Id 22 -Category $diagnostics -Label 'Teste de velocidade' -Kind Script -Uri 'https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/speedtest.ps1' -FileName 'Scripts\speedtest.ps1'
        New-InilogAction -Id 24 -Category $diagnostics -Label 'Microsoft Sysinternals' -Kind Script -Uri 'https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/sysinternals.ps1' -FileName 'Scripts\sysinternals.ps1'
        New-InilogAction -Id 25 -Category $system -Label 'WinUtil' -Kind Script -Uri 'https://raw.githubusercontent.com/francisney/winutil/refs/heads/main/windev.ps1' -FileName 'Scripts\windev.ps1'
        New-InilogAction -Id 27 -Category $diagnostics -Label 'MudaLink / Fake Failover' -Kind Download -Uri 'https://inilog.com/suporte/628/files/MudaLink.exe' -FileName 'MudaLink.exe'
        New-InilogAction -Id 29 -Category $support -Label 'Web Control / InilogWeb' -Kind Download -Uri 'https://inilog.com/suporte/628/files/InilogWeb.exe' -FileName 'InilogWeb.exe'
        New-InilogAction -Id 30 -Category $diagnostics -Label 'HWiNFO64' -Kind Download -Uri 'https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/HWiNFO64.exe' -FileName 'HWiNFO64.exe'
        New-InilogAction -Id 31 -Category $system -Label 'Snappy Driver Installer Origin' -Kind Links -Uri 'https://www.glenn.delahoy.com/snappy-driver-installer-origin/'
        New-InilogAction -Id 34 -Category $support -Label 'Auditoria INILOG' -Kind Download -Uri 'https://inilog.com/upload/INILOG_Auditoria.exe' -FileName 'Auditoria\INILOG_Downloader.exe' -Run
    )
}

function Get-InilogVisibleActions {
    param([object[]]$Actions, [string]$Filter = '')

    $compare = [Globalization.CultureInfo]::CurrentCulture.CompareInfo
    $options = [Globalization.CompareOptions]::IgnoreCase -bor [Globalization.CompareOptions]::IgnoreNonSpace
    foreach ($action in $Actions) {
        if (-not $action.Visible) { continue }
        $searchText = '{0} {1} {2}' -f $action.Id, $action.Label, $action.Category
        if ([string]::IsNullOrWhiteSpace($Filter) -or
            $compare.IndexOf($searchText, $Filter, $options) -ge 0) {
            $action
        }
    }
}

function Write-InilogMenuCell {
    param([object]$Action, [int]$Width)

    $labelWidth = [Math]::Max(1, $Width - 7)
    $label = Get-InilogFitText $Action.Label $labelWidth
    Write-Host '  [' -NoNewline -ForegroundColor DarkGray
    Write-Host ($Action.Id.ToString('00')) -NoNewline -ForegroundColor Green
    Write-Host '] ' -NoNewline -ForegroundColor DarkGray
    Write-Host ($label.PadRight($labelWidth)) -NoNewline -ForegroundColor White
}

function Show-InilogMenu {
    Show-InilogHeader
    $width = Get-InilogConsoleWidth
    $items = @(Get-InilogVisibleActions -Actions $script:InilogActions -Filter $script:InilogState.Filter)
    $categories = @('Sistema e manutenção', 'Diagnóstico e rede', 'Impressoras e suporte')
    $twoColumns = $width -ge 90
    $cellWidth = $width
    if ($twoColumns) { $cellWidth = [int][Math]::Floor(($width - 2) / 2) }

    if ($script:InilogState.Filter) {
        Write-Host ''
        $filterLine = ' Busca: {0} | {1} resultado(s)' -f $script:InilogState.Filter, $items.Count
        Write-Host (Get-InilogFitText $filterLine $width) -ForegroundColor Yellow
    }

    foreach ($category in $categories) {
        $group = @($items | Where-Object { $_.Category -eq $category } | Sort-Object Id)
        if ($group.Count -eq 0) { continue }
        Write-Host ''
        Write-Host (' {0}' -f $category.ToUpperInvariant()) -ForegroundColor Cyan

        $step = 1
        if ($twoColumns) { $step = 2 }
        for ($index = 0; $index -lt $group.Count; $index += $step) {
            Write-InilogMenuCell -Action $group[$index] -Width $cellWidth
            if ($twoColumns -and ($index + 1) -lt $group.Count) {
                Write-Host '  ' -NoNewline
                Write-InilogMenuCell -Action $group[$index + 1] -Width $cellWidth
            }
            Write-Host ''
        }
    }

    if ($items.Count -eq 0) {
        Write-Host ''
        Write-InilogStatus 'Nenhuma ferramenta encontrada. Use T para mostrar todas.' 'Warning'
    }

    Write-Host ''
    Write-InilogRule
    if ($width -ge 80) {
        Write-Host ' B Buscar  |  T Todas  |  R Atualizar rede  |  P Downloads  |  0 Sair' -ForegroundColor Gray
    } else {
        Write-Host ' B Buscar | T Todas | R Atualizar rede' -ForegroundColor Gray
        Write-Host ' P Downloads | 0 Sair' -ForegroundColor Gray
    }
    Write-InilogRule
}

function Invoke-InilogAction {
    param([object]$Action)

    try {
        switch ($Action.Kind) {
            'Links' {
                return (Open-InilogLinks -Uris $Action.Uris -Description $Action.Label)
            }
            'Script' {
                return (Invoke-InilogRemoteScript -Uri $Action.Uris[0] -Description $Action.Label -FileName $Action.FileName)
            }
            'Download' {
                $destination = Join-Path $script:InilogState.DownloadDirectory $Action.FileName
                $result = Save-InilogFile -Uri $Action.Uris[0] -Destination $destination -Description $Action.Label
                if (-not $result.Success) { return $result }
                if ($Action.Run) {
                    return (Start-InilogProcess -Path $result.Path -Description $Action.Label)
                }
                return $result
            }
            'PrintQueue' {
                $destination = Join-Path $script:InilogState.DownloadDirectory $Action.FileName
                $result = Save-InilogFile -Uri $Action.Uris[0] -Destination $destination -Description $Action.Label
                if (-not $result.Success) { return $result }
                $arguments = '/d /c ""{0}""' -f $result.Path
                return (Start-InilogProcess -Path 'cmd.exe' -Description $Action.Label -Arguments $arguments -AsAdministrator)
            }
            default {
                return (New-InilogResult $false 'Tipo de ferramenta não reconhecido.')
            }
        }
    } catch {
        return (New-InilogResult $false ('Falha em {0}: {1}' -f $Action.Label, $_.Exception.Message))
    }
}

function Wait-InilogMenu {
    Write-Host ''
    [void](Read-Host 'Pressione Enter para voltar ao menu')
}

function Start-InilogConsole {
    param([string]$DownloadDirectory)

    Initialize-InilogState -DownloadDirectory $DownloadDirectory
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $Host.UI.RawUI.WindowTitle = 'INILOG | Painel de suporte'
    } catch {}

    if (-not (Show-InilogLogin)) { return }

    Write-InilogStatus 'Consultando informações da conexão...'
    Update-InilogNetworkInfo

    while ($true) {
        Show-InilogMenu
        Write-Host ''
        $choiceText = Read-Host 'Opção ou comando'
        if ($null -eq $choiceText) { break }
        $choiceText = $choiceText.Trim()
        if (-not $choiceText) { continue }
        $commandName = $choiceText.ToUpperInvariant()

        if ($commandName -eq '0') { break }
        if ($commandName -eq 'B') {
            $filterText = Read-Host 'Buscar por nome ou número (Enter mostra tudo)'
            $script:InilogState.Filter = [string]$filterText
            $script:InilogState.Filter = $script:InilogState.Filter.Trim()
            continue
        }
        if ($commandName -eq 'T') {
            $script:InilogState.Filter = ''
            continue
        }
        if ($commandName -eq 'R') {
            Write-InilogStatus 'Atualizando informações da conexão...'
            Update-InilogNetworkInfo
            continue
        }
        if ($commandName -eq 'P') {
            try {
                $directory = $script:InilogState.DownloadDirectory
                if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
                    New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
                }
                $opened = Start-InilogProcess -Path $directory -Description 'Pasta de downloads'
                if (-not $opened.Success) { Write-InilogStatus $opened.Message 'Error'; Wait-InilogMenu }
            } catch {
                Write-InilogStatus $_.Exception.Message 'Error'
                Wait-InilogMenu
            }
            continue
        }

        $selectedId = 0
        if (-not [int]::TryParse($choiceText, [ref]$selectedId) -or
            -not $script:InilogActionMap.ContainsKey($selectedId)) {
            Write-InilogStatus 'Opção inválida. Digite um número do menu ou um dos comandos exibidos.' 'Warning'
            Wait-InilogMenu
            continue
        }

        Write-Host ''
        $result = Invoke-InilogAction -Action $script:InilogActionMap[$selectedId]
        if ($result.Success) {
            Write-InilogStatus $result.Message 'Success'
        } else {
            Write-InilogStatus $result.Message 'Error'
        }
        Wait-InilogMenu
    }

    Write-Host ''
    Write-InilogStatus 'INILOG encerrado.' 'Success'
}

if ($env:OS -ne 'Windows_NT') {
    Write-InilogStatus 'Este painel precisa ser executado no Windows com PowerShell 5.1 ou superior.' 'Error'
    return
}

Start-InilogConsole -DownloadDirectory $DiretorioDownloads
