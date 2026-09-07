#requires -Version 5.1

# ============================================================
# INILOG - Microsoft Sysinternals
# Francisney Delmondes
# Email: suporte@inilog.com
#
# Fonte oficial:
# https://live.sysinternals.com/tools/
#
# Compatível com Windows PowerShell 5.1+
# ============================================================

$ErrorActionPreference = 'Continue'

# ------------------------------------------------------------
# TLS 1.2
# ------------------------------------------------------------

try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor
        [Net.SecurityProtocolType]::Tls12
} catch {
    # Mantém compatibilidade com hosts onde TLS já está configurado.
}

# ------------------------------------------------------------
# Configuração
# ------------------------------------------------------------

$script:SysinternalsBaseUrl = 'https://live.sysinternals.com/tools'
$script:SysinternalsDirectory = 'C:\ti\Sysinternals'

# Quantidade de horas durante as quais uma ferramenta já baixada
# será reutilizada sem consultar novamente o servidor.
$script:SysinternalsCacheHours = 24

# Cores
$script:SysCorBorda   = 'DarkCyan'
$script:SysCorTitulo  = 'Yellow'
$script:SysCorSecao   = 'Cyan'
$script:SysCorOpcao   = 'White'
$script:SysCorNumero  = 'Green'
$script:SysCorSucesso = 'Green'
$script:SysCorAviso   = 'Yellow'
$script:SysCorErro    = 'Red'
$script:SysCorInfo    = 'Cyan'

# Guarda o título anterior para restaurar ao voltar ao INILOG.
$script:SysTituloAnterior = $null

try {
    $script:SysTituloAnterior = $Host.UI.RawUI.WindowTitle
    $Host.UI.RawUI.WindowTitle = 'INILOG - Microsoft Sysinternals'
} catch {
    # Alguns hosts não permitem alterar o título.
}

# ------------------------------------------------------------
# Funções visuais
# ------------------------------------------------------------

function Write-SysLine {
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
        # Mantém largura padrão.
    }

    Write-Host ($Character.ToString() * $width) -ForegroundColor $Color
}

function Write-SysCentered {
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
        # Mantém largura padrão.
    }

    $padding = [Math]::Max(
        0,
        [Math]::Floor(($width - $Text.Length) / 2)
    )

    Write-Host ((' ' * $padding) + $Text) -ForegroundColor $Color
}

function Write-SysStatus {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Type = 'Info'
    )

    switch ($Type) {

        'Success' {
            Write-Host '[OK] ' -NoNewline -ForegroundColor $script:SysCorSucesso
            Write-Host $Message -ForegroundColor White
        }

        'Warning' {
            Write-Host '[!]  ' -NoNewline -ForegroundColor $script:SysCorAviso
            Write-Host $Message -ForegroundColor White
        }

        'Error' {
            Write-Host '[ERRO] ' -NoNewline -ForegroundColor $script:SysCorErro
            Write-Host $Message -ForegroundColor White
        }

        default {
            Write-Host '[i]  ' -NoNewline -ForegroundColor $script:SysCorInfo
            Write-Host $Message -ForegroundColor White
        }
    }
}

function Write-SysSection {
    param(
        [Parameter(Mandatory)]
        [string]$Title
    )

    Write-Host ''
    Write-Host ('  {0}' -f $Title.ToUpperInvariant()) `
        -ForegroundColor $script:SysCorSecao
}

function Write-SysMenuItem {
    param(
        [Parameter(Mandatory)]
        [string]$Number,

        [Parameter(Mandatory)]
        [string]$Label
    )

    Write-Host '  [' -NoNewline -ForegroundColor DarkGray
    Write-Host $Number.PadLeft(2, '0') `
        -NoNewline `
        -ForegroundColor $script:SysCorNumero
    Write-Host '] ' -NoNewline -ForegroundColor DarkGray
    Write-Host $Label -ForegroundColor $script:SysCorOpcao
}

# ------------------------------------------------------------
# Privilégio administrativo
# ------------------------------------------------------------

function Test-SysAdministrator {

    try {
        $identity =
            [Security.Principal.WindowsIdentity]::GetCurrent()

        $principal =
            New-Object Security.Principal.WindowsPrincipal($identity)

        return $principal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )
    } catch {
        return $false
    }
}

# ------------------------------------------------------------
# Informações do computador
# ------------------------------------------------------------

function Get-SysComputerInfo {

    $computerName = $env:COMPUTERNAME
    $windowsName = 'Windows'
    $build = 'Desconhecido'

    try {

        $os = Get-CimInstance `
            -ClassName Win32_OperatingSystem `
            -ErrorAction Stop

        if ($os.Caption) {
            $windowsName =
                ([string]$os.Caption -replace '^Microsoft\s+', '').Trim()
        }

        if ($os.BuildNumber) {
            $build = [string]$os.BuildNumber
        }

    } catch {

        try {

            $os = Get-WmiObject `
                -Class Win32_OperatingSystem `
                -ErrorAction Stop

            if ($os.Caption) {
                $windowsName =
                    ([string]$os.Caption -replace '^Microsoft\s+', '').Trim()
            }

            if ($os.BuildNumber) {
                $build = [string]$os.BuildNumber
            }

        } catch {
            # Continua com informações básicas.
        }
    }

    $architecture = $env:PROCESSOR_ARCHITEW6432

    if ([string]::IsNullOrWhiteSpace($architecture)) {
        $architecture = $env:PROCESSOR_ARCHITECTURE
    }

    if ([string]::IsNullOrWhiteSpace($architecture)) {
        if ([Environment]::Is64BitOperatingSystem) {
            $architecture = 'x64'
        } else {
            $architecture = 'x86'
        }
    }

    if (Test-SysAdministrator) {
        $administrator = 'SIM'
    } else {
        $administrator = 'NÃO'
    }

    return [PSCustomObject]@{
        Computer     = $computerName
        Windows      = $windowsName
        Build        = $build
        Architecture = $architecture
        Administrator = $administrator
    }
}

# ------------------------------------------------------------
# Pasta de trabalho
# ------------------------------------------------------------

function Initialize-SysinternalsDirectory {

    try {

        if (-not (Test-Path -LiteralPath $script:SysinternalsDirectory)) {

            New-Item `
                -ItemType Directory `
                -Path $script:SysinternalsDirectory `
                -Force `
                -ErrorAction Stop | Out-Null
        }

        return $true

    } catch {

        # Caso C:\ti não possa ser usado, utiliza TEMP como contingência.

        try {

            $fallback =
                Join-Path $env:TEMP 'INILOG\Sysinternals'

            if (-not (Test-Path -LiteralPath $fallback)) {

                New-Item `
                    -ItemType Directory `
                    -Path $fallback `
                    -Force `
                    -ErrorAction Stop | Out-Null
            }

            $script:SysinternalsDirectory = $fallback

            Write-SysStatus `
                "C:\ti não está disponível. Usando $fallback" `
                'Warning'

            return $true

        } catch {

            Write-SysStatus `
                "Não foi possível criar a pasta das ferramentas. $($_.Exception.Message)" `
                'Error'

            return $false
        }
    }
}

# ------------------------------------------------------------
# Verificação de assinatura Microsoft
# ------------------------------------------------------------

function Test-SysinternalsSignature {

    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    try {

        $signature =
            Get-AuthenticodeSignature `
                -FilePath $Path `
                -ErrorAction Stop

        if ($signature.Status -ne 'Valid') {
            return $false
        }

        if ($null -eq $signature.SignerCertificate) {
            return $false
        }

        $subject =
            [string]$signature.SignerCertificate.Subject

        if ($subject -notmatch 'Microsoft') {
            return $false
        }

        return $true

    } catch {
        return $false
    }
}

# ------------------------------------------------------------
# Nome correto x86 / x64
# ------------------------------------------------------------

function Get-SysinternalsFileName {

    param(
        [Parameter(Mandatory)]
        $Tool
    )

    if (
        [Environment]::Is64BitOperatingSystem -and
        -not [string]::IsNullOrWhiteSpace([string]$Tool.File64)
    ) {
        return [string]$Tool.File64
    }

    return [string]$Tool.File32
}

# ------------------------------------------------------------
# Download seguro
# ------------------------------------------------------------

function Get-SysinternalsTool {

    param(
        [Parameter(Mandatory)]
        $Tool,

        [switch]$Force
    )

    if (-not (Initialize-SysinternalsDirectory)) {
        return $null
    }

    $fileName =
        Get-SysinternalsFileName -Tool $Tool

    if ([string]::IsNullOrWhiteSpace($fileName)) {

        Write-SysStatus `
            "Executável não definido para $($Tool.Name)." `
            'Error'

        return $null
    }

    $destination =
        Join-Path $script:SysinternalsDirectory $fileName

    # --------------------------------------------------------
    # Cache local
    # --------------------------------------------------------

    if (
        (-not $Force) -and
        (Test-Path -LiteralPath $destination)
    ) {

        try {

            $file = Get-Item `
                -LiteralPath $destination `
                -ErrorAction Stop

            $age =
                (Get-Date) - $file.LastWriteTime

            if (
                $age.TotalHours -lt $script:SysinternalsCacheHours -and
                (Test-SysinternalsSignature -Path $destination)
            ) {

                Write-SysStatus `
                    "$($Tool.Name) já está atualizado e verificado." `
                    'Success'

                return $destination
            }

        } catch {
            # Tenta atualizar normalmente.
        }
    }

    $uri =
        '{0}/{1}' -f $script:SysinternalsBaseUrl, $fileName

    $temporary =
        "$destination.download.exe"

    try {

        if (Test-Path -LiteralPath $temporary) {
            Remove-Item `
                -LiteralPath $temporary `
                -Force `
                -ErrorAction SilentlyContinue
        }

        Write-SysStatus `
            "Baixando $($Tool.Name) da Microsoft..." `
            'Info'

        Invoke-WebRequest `
            -Uri $uri `
            -OutFile $temporary `
            -UseBasicParsing `
            -TimeoutSec 90 `
            -ErrorAction Stop

        if (-not (Test-Path -LiteralPath $temporary)) {
            throw 'O arquivo não foi recebido.'
        }

        Write-SysStatus `
            'Verificando assinatura digital...' `
            'Info'

        if (-not (Test-SysinternalsSignature -Path $temporary)) {

            Remove-Item `
                -LiteralPath $temporary `
                -Force `
                -ErrorAction SilentlyContinue

            throw 'A assinatura digital Microsoft não pôde ser validada.'
        }

        Move-Item `
            -LiteralPath $temporary `
            -Destination $destination `
            -Force `
            -ErrorAction Stop

        Write-SysStatus `
            "$($Tool.Name) atualizado e validado." `
            'Success'

        return $destination

    } catch {

        if (Test-Path -LiteralPath $temporary) {

            Remove-Item `
                -LiteralPath $temporary `
                -Force `
                -ErrorAction SilentlyContinue
        }

        # ----------------------------------------------------
        # Fallback:
        # se a Internet falhar, tenta usar versão anterior
        # devidamente assinada.
        # ----------------------------------------------------

        if (
            (Test-Path -LiteralPath $destination) -and
            (Test-SysinternalsSignature -Path $destination)
        ) {

            Write-SysStatus `
                "Não foi possível atualizar $($Tool.Name)." `
                'Warning'

            Write-SysStatus `
                'Usando a cópia local verificada.' `
                'Warning'

            return $destination
        }

        Write-SysStatus `
            "Falha ao obter $($Tool.Name). $($_.Exception.Message)" `
            'Error'

        return $null
    }
}

# ------------------------------------------------------------
# Iniciar ferramenta gráfica
# ------------------------------------------------------------

function Start-SysinternalsGUI {

    param(
        [Parameter(Mandatory)]
        $Tool
    )

    $path =
        Get-SysinternalsTool -Tool $Tool

    if ([string]::IsNullOrWhiteSpace($path)) {
        return
    }

    try {

        Write-SysStatus `
            "Iniciando $($Tool.Name)..." `
            'Info'

        Start-Process `
            -FilePath $path `
            -ErrorAction Stop

        Write-SysStatus `
            "$($Tool.Name) iniciado." `
            'Success'

    } catch {

        Write-SysStatus `
            "Não foi possível iniciar $($Tool.Name). $($_.Exception.Message)" `
            'Error'
    }
}

# ------------------------------------------------------------
# Coreinfo
# ------------------------------------------------------------

function Start-SysinternalsCoreinfo {

    param(
        [Parameter(Mandatory)]
        $Tool
    )

    $path =
        Get-SysinternalsTool -Tool $Tool

    if (-not $path) {
        return
    }

    Write-Host ''
    Write-SysLine '-' DarkGray
    Write-SysCentered 'COREINFO - PROCESSADOR E RECURSOS' Cyan
    Write-SysLine '-' DarkGray
    Write-Host ''

    try {

        & $path

    } catch {

        Write-SysStatus `
            "Erro ao executar Coreinfo. $($_.Exception.Message)" `
            'Error'
    }
}

# ------------------------------------------------------------
# PsPing
# ------------------------------------------------------------

function Start-SysinternalsPsPing {

    param(
        [Parameter(Mandatory)]
        $Tool
    )

    $path =
        Get-SysinternalsTool -Tool $Tool

    if (-not $path) {
        return
    }

    Write-Host ''

    $target =
        (Read-Host 'Digite o IP ou host para testar').Trim()

    if ([string]::IsNullOrWhiteSpace($target)) {

        Write-SysStatus `
            'Teste cancelado.' `
            'Warning'

        return
    }

    Write-Host ''
    Write-SysLine '-' DarkGray
    Write-SysCentered "PSPING - $target" Cyan
    Write-SysLine '-' DarkGray
    Write-Host ''

    try {

        & $path $target

    } catch {

        Write-SysStatus `
            "Erro ao executar PsPing. $($_.Exception.Message)" `
            'Error'
    }
}

# ------------------------------------------------------------
# Sigcheck
# ------------------------------------------------------------

function Start-SysinternalsSigcheck {

    param(
        [Parameter(Mandatory)]
        $Tool
    )

    $path =
        Get-SysinternalsTool -Tool $Tool

    if (-not $path) {
        return
    }

    Write-Host ''

    $target =
        (Read-Host 'Digite o caminho do arquivo que deseja verificar').Trim()

    $target =
        $target.Trim('"')

    if ([string]::IsNullOrWhiteSpace($target)) {

        Write-SysStatus `
            'Verificação cancelada.' `
            'Warning'

        return
    }

    if (-not (Test-Path -LiteralPath $target)) {

        Write-SysStatus `
            "Arquivo não encontrado: $target" `
            'Error'

        return
    }

    Write-Host ''
    Write-SysLine '-' DarkGray
    Write-SysCentered 'SIGCHECK - ASSINATURA DIGITAL' Cyan
    Write-SysLine '-' DarkGray
    Write-Host ''

    try {

        & $path $target

    } catch {

        Write-SysStatus `
            "Erro ao executar Sigcheck. $($_.Exception.Message)" `
            'Error'
    }
}

# ------------------------------------------------------------
# Whois
# ------------------------------------------------------------

function Start-SysinternalsWhois {

    param(
        [Parameter(Mandatory)]
        $Tool
    )

    $path =
        Get-SysinternalsTool -Tool $Tool

    if (-not $path) {
        return
    }

    Write-Host ''

    $target =
        (Read-Host 'Digite um domínio ou endereço IP').Trim()

    if ([string]::IsNullOrWhiteSpace($target)) {

        Write-SysStatus `
            'Consulta cancelada.' `
            'Warning'

        return
    }

    Write-Host ''
    Write-SysLine '-' DarkGray
    Write-SysCentered "WHOIS - $target" Cyan
    Write-SysLine '-' DarkGray
    Write-Host ''

    try {

        & $path $target

    } catch {

        Write-SysStatus `
            "Erro ao executar Whois. $($_.Exception.Message)" `
            'Error'
    }
}

# ------------------------------------------------------------
# Ferramentas disponíveis
# ------------------------------------------------------------

$script:SysTools = @{

    '1' = [PSCustomObject]@{
        Name   = 'Process Explorer'
        File32 = 'procexp.exe'
        File64 = 'procexp64.exe'
        Mode   = 'GUI'
    }

    '2' = [PSCustomObject]@{
        Name   = 'Process Monitor'
        File32 = 'Procmon.exe'
        File64 = 'Procmon64.exe'
        Mode   = 'GUI'
    }

    '3' = [PSCustomObject]@{
        Name   = 'Autoruns'
        File32 = 'Autoruns.exe'
        File64 = 'Autoruns64.exe'
        Mode   = 'GUI'
    }

    '4' = [PSCustomObject]@{
        Name   = 'TCPView'
        File32 = 'tcpview.exe'
        File64 = 'tcpview64.exe'
        Mode   = 'GUI'
    }

    '5' = [PSCustomObject]@{
        Name   = 'RAMMap'
        File32 = 'RAMMap.exe'
        File64 = 'RAMMap64.exe'
        Mode   = 'GUI'
    }

    '6' = [PSCustomObject]@{
        Name   = 'Coreinfo'
        File32 = 'Coreinfo.exe'
        File64 = 'Coreinfo64.exe'
        Mode   = 'COREINFO'
    }

    '7' = [PSCustomObject]@{
        Name   = 'Disk2VHD'
        File32 = 'disk2vhd.exe'
        File64 = 'disk2vhd64.exe'
        Mode   = 'GUI'
    }

    '8' = [PSCustomObject]@{
        Name   = 'BgInfo'
        File32 = 'Bginfo.exe'
        File64 = 'Bginfo64.exe'
        Mode   = 'GUI'
    }

    '9' = [PSCustomObject]@{
        Name   = 'ZoomIt'
        File32 = 'ZoomIt.exe'
        File64 = 'ZoomIt64.exe'
        Mode   = 'GUI'
    }

    '10' = [PSCustomObject]@{
        Name   = 'PsPing'
        File32 = 'psping.exe'
        File64 = 'psping64.exe'
        Mode   = 'PSPING'
    }

    '11' = [PSCustomObject]@{
        Name   = 'Sigcheck'
        File32 = 'sigcheck.exe'
        File64 = 'sigcheck64.exe'
        Mode   = 'SIGCHECK'
    }

    '12' = [PSCustomObject]@{
        Name   = 'Whois'
        File32 = 'whois.exe'
        File64 = 'whois64.exe'
        Mode   = 'WHOIS'
    }
}

# ------------------------------------------------------------
# Atualizar todas as ferramentas
# ------------------------------------------------------------

function Update-AllSysinternalsTools {

    Write-Host ''

    Write-SysStatus `
        'Atualizando o conjunto de ferramentas INILOG Sysinternals...' `
        'Info'

    Write-Host ''

    $keys =
        $script:SysTools.Keys |
        Sort-Object { [int]$_ }

    $total = 0
    $success = 0

    foreach ($key in $keys) {

        $tool =
            $script:SysTools[$key]

        $total++

        Write-SysLine '-' DarkGray

        Write-Host (
            '  [{0}/{1}] {2}' -f
            $total,
            $script:SysTools.Count,
            $tool.Name
        ) -ForegroundColor Cyan

        $path =
            Get-SysinternalsTool `
                -Tool $tool `
                -Force

        if ($path) {
            $success++
        }

        Write-Host ''
    }

    Write-SysLine '-' DarkGray

    if ($success -eq $total) {

        Write-SysStatus `
            "Todas as $total ferramentas foram atualizadas." `
            'Success'

    } else {

        Write-SysStatus `
            "$success de $total ferramentas foram atualizadas." `
            'Warning'
    }
}

# ------------------------------------------------------------
# Cabeçalho
# ------------------------------------------------------------

function Show-SysinternalsHeader {

    param(
        [Parameter(Mandatory)]
        $ComputerInfo
    )

    Clear-Host

    Write-SysLine '=' $script:SysCorBorda

    Write-SysCentered `
        'INILOG' `
        $script:SysCorTitulo

    Write-SysCentered `
        'MICROSOFT SYSINTERNALS' `
        White

    Write-SysLine '=' $script:SysCorBorda

    Write-Host ''

    Write-Host '  Computador:   ' `
        -NoNewline `
        -ForegroundColor DarkGray

    Write-Host $ComputerInfo.Computer `
        -ForegroundColor White

    Write-Host '  Windows:      ' `
        -NoNewline `
        -ForegroundColor DarkGray

    Write-Host (
        '{0} - Build {1}' -f
        $ComputerInfo.Windows,
        $ComputerInfo.Build
    ) -ForegroundColor White

    Write-Host '  Arquitetura:  ' `
        -NoNewline `
        -ForegroundColor DarkGray

    Write-Host $ComputerInfo.Architecture `
        -ForegroundColor White

    Write-Host '  Administrador:' `
        -NoNewline `
        -ForegroundColor DarkGray

    if ($ComputerInfo.Administrator -eq 'SIM') {

        Write-Host ' SIM' `
            -ForegroundColor Green

    } else {

        Write-Host ' NÃO' `
            -ForegroundColor Yellow
    }

    Write-Host '  Diretório:    ' `
        -NoNewline `
        -ForegroundColor DarkGray

    Write-Host $script:SysinternalsDirectory `
        -ForegroundColor White

    Write-Host '  Fonte:        ' `
        -NoNewline `
        -ForegroundColor DarkGray

    Write-Host 'Microsoft Sysinternals Live' `
        -ForegroundColor Cyan
}

# ------------------------------------------------------------
# Menu
# ------------------------------------------------------------

function Show-SysinternalsMenu {

    param(
        [Parameter(Mandatory)]
        $ComputerInfo
    )

    Show-SysinternalsHeader `
        -ComputerInfo $ComputerInfo

    Write-SysSection 'Processos e inicialização'

    Write-SysMenuItem '1' 'Process Explorer'
    Write-SysMenuItem '2' 'Process Monitor'
    Write-SysMenuItem '3' 'Autoruns'

    Write-SysSection 'Rede'

    Write-SysMenuItem '4' 'TCPView'
    Write-SysMenuItem '10' 'PsPing'

    Write-SysSection 'Sistema e hardware'

    Write-SysMenuItem '5' 'RAMMap'
    Write-SysMenuItem '6' 'Coreinfo'
    Write-SysMenuItem '7' 'Disk2VHD'
    Write-SysMenuItem '8' 'BgInfo'

    Write-SysSection 'Suporte'

    Write-SysMenuItem '9' 'ZoomIt'

    Write-SysSection 'Diagnóstico avançado'

    Write-SysMenuItem '11' 'Sigcheck'
    Write-SysMenuItem '12' 'Whois'

    Write-SysSection 'Gerenciamento'

    Write-SysMenuItem '90' 'Abrir pasta das ferramentas'
    Write-SysMenuItem '91' 'Abrir catálogo oficial Microsoft'
    Write-SysMenuItem '92' 'Atualizar todas as ferramentas'

    Write-Host ''

    Write-SysLine '-' DarkGray

    Write-SysMenuItem '0' 'Voltar ao INILOG'

    Write-SysLine '=' $script:SysCorBorda

    Write-Host ''
}

# ------------------------------------------------------------
# Executar ferramenta selecionada
# ------------------------------------------------------------

function Invoke-SysinternalsTool {

    param(
        [Parameter(Mandatory)]
        $Tool
    )

    switch ($Tool.Mode) {

        'GUI' {
            Start-SysinternalsGUI `
                -Tool $Tool
        }

        'COREINFO' {
            Start-SysinternalsCoreinfo `
                -Tool $Tool
        }

        'PSPING' {
            Start-SysinternalsPsPing `
                -Tool $Tool
        }

        'SIGCHECK' {
            Start-SysinternalsSigcheck `
                -Tool $Tool
        }

        'WHOIS' {
            Start-SysinternalsWhois `
                -Tool $Tool
        }

        default {

            Write-SysStatus `
                "Modo desconhecido para $($Tool.Name)." `
                'Error'
        }
    }
}

# ------------------------------------------------------------
# Execução principal
# ------------------------------------------------------------

try {

    Initialize-SysinternalsDirectory | Out-Null

    $computerInfo =
        Get-SysComputerInfo

    $choice = $null

    do {

        Show-SysinternalsMenu `
            -ComputerInfo $computerInfo

        $choice =
            (Read-Host 'Escolha uma opção').Trim()

        # Permite digitar tanto 01 quanto 1.
        if ($choice -match '^\d+$') {

            try {
                $choice =
                    ([int]$choice).ToString()
            } catch {
                # Mantém a entrada original.
            }
        }

        Write-Host ''

        if ($script:SysTools.ContainsKey($choice)) {

            Invoke-SysinternalsTool `
                -Tool $script:SysTools[$choice]

        } else {

            switch ($choice) {

                '90' {

                    try {

                        Initialize-SysinternalsDirectory | Out-Null

                        Start-Process `
                            -FilePath 'explorer.exe' `
                            -ArgumentList "`"$script:SysinternalsDirectory`"" `
                            -ErrorAction Stop

                        Write-SysStatus `
                            'Pasta das ferramentas aberta.' `
                            'Success'

                    } catch {

                        Write-SysStatus `
                            "Não foi possível abrir a pasta. $($_.Exception.Message)" `
                            'Error'
                    }
                }

                '91' {

                    try {

                        Start-Process `
                            'https://live.sysinternals.com/tools/'

                        Write-SysStatus `
                            'Catálogo oficial aberto no navegador.' `
                            'Success'

                    } catch {

                        Write-SysStatus `
                            "Não foi possível abrir o catálogo. $($_.Exception.Message)" `
                            'Error'
                    }
                }

                '92' {

                    Write-Host ''

                    Write-SysStatus `
                        'Essa opção baixará/atualizará todas as ferramentas listadas.' `
                        'Info'

                    $confirmation =
                        (Read-Host 'Deseja continuar? [S/N]').Trim()

                    if (
                        $confirmation -match '^(s|sim|y|yes)$'
                    ) {

                        Update-AllSysinternalsTools

                    } else {

                        Write-SysStatus `
                            'Atualização cancelada.' `
                            'Warning'
                    }
                }

                '0' {

                    Write-SysCentered `
                        'Voltando ao INILOG...' `
                        $script:SysCorAviso

                    Start-Sleep `
                        -Milliseconds 400
                }

                default {

                    Write-SysStatus `
                        "Opção '$choice' inválida." `
                        'Warning'
                }
            }
        }

        if ($choice -ne '0') {

            Write-Host ''

            [void](
                Read-Host 'Pressione Enter para voltar ao Sysinternals'
            )
        }

    } while ($choice -ne '0')

} finally {

    # --------------------------------------------------------
    # Restaura o título da janela do INILOG
    # --------------------------------------------------------

    if (
        -not [string]::IsNullOrWhiteSpace(
            [string]$script:SysTituloAnterior
        )
    ) {

        try {

            $Host.UI.RawUI.WindowTitle =
                $script:SysTituloAnterior

        } catch {
            # Host não permite alteração do título.
        }
    }

    Clear-Host
}
