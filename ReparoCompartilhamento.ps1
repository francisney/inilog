[CmdletBinding()]
param(
    [ValidateSet("Menu", "Diagnostico", "Servidor", "Cliente", "Ambos")]
    [string]$Modo = "Menu",

    [string]$Servidor,

    [string]$ImpressoraCompartilhada,

    [string]$CaminhoImpressora,

    [string]$ImpressoraLocal,

    [string]$NomeCompartilhamento,

    [switch]$InstalarImpressora,
    [switch]$ReinstalarImpressora,

    [switch]$NaoDesativarFirewall,

    [switch]$CompartilharImpressorasVirtuais,

    [switch]$NaoAplicarCompatibilidadeRpc,

    [switch]$ManterProtecaoSenha,

    [switch]$NaoReiniciarSpooler,

    [switch]$NaoDescobrirServidores,

    [switch]$Detalhado,

    [switch]$NaoPausar
)

if ($PSVersionTable.PSVersion -lt [version]'5.1') {
    throw 'Este script requer PowerShell 5.1 ou superior.'
}

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Continue"

$script:Modo = $Modo
$script:Servidor = $Servidor
$script:ImpressoraCompartilhada = $ImpressoraCompartilhada
$script:CaminhoImpressora = $CaminhoImpressora
$script:ImpressoraLocal = $ImpressoraLocal
$script:NomeCompartilhamento = $NomeCompartilhamento
$script:InstalarImpressora = $InstalarImpressora
$script:ReinstalarImpressora = $ReinstalarImpressora
$script:NaoDesativarFirewall = $NaoDesativarFirewall
$script:CompartilharImpressorasVirtuais = $CompartilharImpressorasVirtuais
$script:NaoAplicarCompatibilidadeRpc = $NaoAplicarCompatibilidadeRpc
$script:ManterProtecaoSenha = $ManterProtecaoSenha
$script:NaoReiniciarSpooler = $NaoReiniciarSpooler
$script:NaoDescobrirServidores = $NaoDescobrirServidores
$script:Detalhado = $Detalhado
$script:NaoPausar = $NaoPausar
$script:Resultados = New-Object System.Collections.Generic.List[object]
$script:CaminhosCompartilhados = New-Object System.Collections.Generic.List[string]

function Write-Section {
    param([Parameter(Mandatory)][string]$Texto)

    Write-Host ""
    Write-Host ("=" * 72) -ForegroundColor DarkCyan
    Write-Host $Texto -ForegroundColor Cyan
    Write-Host ("=" * 72) -ForegroundColor DarkCyan
}

function Add-Result {
    param(
        [Parameter(Mandatory)][string]$Etapa,
        [Parameter(Mandatory)][ValidateSet("OK", "AVISO", "ERRO", "INFO")][string]$Status,
        [Parameter(Mandatory)][string]$Detalhe
    )

    [void]$script:Resultados.Add([PSCustomObject]@{
        Etapa   = $Etapa
        Status  = $Status
        Detalhe = $Detalhe
    })

    switch ($Status) {
        "OK"    { Write-Host "[OK] $Etapa - $Detalhe" -ForegroundColor Green }
        "AVISO" { Write-Host "[AVISO] $Etapa - $Detalhe" -ForegroundColor Yellow }
        "ERRO"  { Write-Host "[ERRO] $Etapa - $Detalhe" -ForegroundColor Red }
        default { Write-Host "[INFO] $Etapa - $Detalhe" -ForegroundColor Gray }
    }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Start-AsAdministrator {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$BoundParameters,
        [Parameter(Mandatory)][string]$ScriptPath
    )

    try {
        if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
            $remoteBaseUrl = 'https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/ReparoCompartilhamento.ps1'
            $remoteUrl = "${remoteBaseUrl}?nocache=$([guid]::NewGuid().ToString('N'))"
            $remoteCommand = `
                "Invoke-RestMethod -Uri '$remoteUrl' | Invoke-Expression"
            $encodedCommand = [Convert]::ToBase64String(
                [Text.Encoding]::Unicode.GetBytes($remoteCommand)
            )
            $arguments = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand"
        }
        else {
            $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

            foreach ($key in $BoundParameters.Keys) {
                $value = $BoundParameters[$key]

                if ($value -is [System.Management.Automation.SwitchParameter]) {
                    if ($value.IsPresent) {
                        $arguments += " -$key"
                    }
                    continue
                }

                $escapedValue = ([string]$value).Replace('"', '\"')
                $arguments += " -$key `"$escapedValue`""
            }
        }

        Start-Process `
            -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -ArgumentList $arguments `
            -Verb RunAs `
            -ErrorAction Stop | Out-Null

        return $true
    }
    catch {
        Write-Host "Não foi possível solicitar elevação: $($_.Exception.Message)" `
            -ForegroundColor Red
        return $false
    }
}

function Select-MenuItem {
    param(
        [Parameter(Mandatory)][string]$Titulo,
        [Parameter(Mandatory)][object[]]$Itens,
        [Parameter(Mandatory)][scriptblock]$TextoItem,
        [switch]$PermitirCancelar
    )

    if ($Itens.Count -eq 0) {
        return $null
    }

    Write-Host ""
    Write-Host $Titulo -ForegroundColor Yellow

    for ($i = 0; $i -lt $Itens.Count; $i++) {
        $texto = & $TextoItem $Itens[$i]
        Write-Host ("[{0}] {1}" -f ($i + 1), $texto)
    }

    if ($PermitirCancelar) {
        Write-Host "[0] Cancelar"
    }

    while ($true) {
        $resposta = Read-Host "Escolha"
        $numero = 0

        if ([int]::TryParse($resposta, [ref]$numero)) {
            if ($PermitirCancelar -and $numero -eq 0) {
                return $null
            }

            if ($numero -ge 1 -and $numero -le $Itens.Count) {
                return $Itens[$numero - 1]
            }
        }

        Write-Host "Opção inválida." -ForegroundColor Yellow
    }
}

function Resolve-PrinterTarget {
    if (-not [string]::IsNullOrWhiteSpace($CaminhoImpressora)) {
        $unc = $CaminhoImpressora.Trim()

        if ($unc -notmatch '^\\\\([^\\]+)\\([^\\]+)$') {
            throw "Caminho inválido. Use o formato \\servidor\impressora."
        }

        $script:Servidor = $Matches[1]
        $script:ImpressoraCompartilhada = $Matches[2]
    }

    if (-not [string]::IsNullOrWhiteSpace($script:Servidor)) {
        $script:Servidor = $script:Servidor.Trim().TrimStart('\').TrimEnd('\')
    }

    if (-not [string]::IsNullOrWhiteSpace($script:ImpressoraCompartilhada)) {
        $script:ImpressoraCompartilhada =
            $script:ImpressoraCompartilhada.Trim().Trim('\')
    }
}

function Disable-WindowsFirewallAllProfiles {
    Write-Section "Desativando o Firewall em qualquer rede"

    try {
        if (Get-Command Set-NetFirewallProfile -ErrorAction SilentlyContinue) {
            Set-NetFirewallProfile `
                -Profile @('Domain', 'Private', 'Public') `
                -Enabled False `
                -ErrorAction Stop
        }
        else {
            & netsh.exe advfirewall set allprofiles state off | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "O comando netsh não conseguiu desativar todos os perfis."
            }
        }

        $stillEnabled = @(
            Get-NetFirewallProfile -ErrorAction SilentlyContinue |
                Where-Object { $_.Enabled }
        )

        if ($stillEnabled.Count -gt 0) {
            $names = ($stillEnabled.Name -join ', ')
            Add-Result "Firewall" "AVISO" `
                "Uma política externa manteve estes perfis ligados: $names."
        }
        else {
            Add-Result "Firewall" "OK" `
                "Desativado nos perfis Domínio, Privado e Público."
        }
    }
    catch {
        Add-Result "Firewall" "ERRO" $_.Exception.Message
    }
}

function Ensure-Service {
    param(
        [Parameter(Mandatory)][string]$Nome,
        [ValidateSet("Automatic", "Manual")][string]$Inicializacao = "Automatic"
    )

    $service = Get-Service -Name $Nome -ErrorAction SilentlyContinue

    if (-not $service) {
        Add-Result "Serviço $Nome" "INFO" "Não existe nesta versão do Windows."
        return
    }

    try {
        Set-Service -Name $Nome -StartupType $Inicializacao -ErrorAction Stop
        $service.Refresh()

        if ($service.Status -ne "Running") {
            Start-Service -Name $Nome -ErrorAction Stop
        }

        Add-Result "Serviço $Nome" "OK" "Em execução; início $Inicializacao."
    }
    catch {
        Add-Result "Serviço $Nome" "ERRO" $_.Exception.Message
    }
}

function Enable-RequiredServices {
    param(
        [switch]$ServidorLocal,
        [switch]$ClienteLocal
    )

    Write-Section "Configurando serviços"

    Ensure-Service -Nome "MpsSvc" -Inicializacao Automatic
    Ensure-Service -Nome "Spooler" -Inicializacao Automatic

    if ($ServidorLocal) {
        Ensure-Service -Nome "LanmanServer" -Inicializacao Automatic
        Ensure-Service -Nome "FDResPub" -Inicializacao Automatic
        Ensure-Service -Nome "fdPHost" -Inicializacao Automatic
        Ensure-Service -Nome "SSDPSRV" -Inicializacao Manual
        Ensure-Service -Nome "upnphost" -Inicializacao Manual
    }

    if ($ClienteLocal) {
        Ensure-Service -Nome "LanmanWorkstation" -Inicializacao Automatic
    }
}

function Enable-FileAndPrinterBindings {
    Write-Section "Ativando compartilhamento nos adaptadores de rede"

    if (-not (Get-Command Get-NetAdapterBinding -ErrorAction SilentlyContinue) -or
        -not (Get-Command Enable-NetAdapterBinding -ErrorAction SilentlyContinue)) {
        Add-Result "Vínculos de rede" "INFO" `
            "Cmdlets de adaptador indisponíveis nesta edição do Windows."
        return
    }

    foreach ($componentId in @('ms_server', 'ms_msclient')) {
        try {
            $bindings = @(
                Get-NetAdapterBinding `
                    -ComponentID $componentId `
                    -ErrorAction SilentlyContinue
            )

            foreach ($binding in $bindings) {
                if (-not $binding.Enabled) {
                    Enable-NetAdapterBinding `
                        -Name $binding.Name `
                        -ComponentID $componentId `
                        -ErrorAction Stop | Out-Null
                }
            }

            $description = if ($componentId -eq 'ms_server') {
                'Compartilhamento de Arquivos e Impressoras'
            }
            else {
                'Cliente para Redes Microsoft'
            }

            Add-Result "Vínculo $description" "OK" `
                "Habilitado nos adaptadores disponíveis."
        }
        catch {
            Add-Result "Vínculo $componentId" "AVISO" $_.Exception.Message
        }
    }
}

function Enable-FirewallRuleFamily {
    param(
        [Parameter(Mandatory)][string]$Padrao,
        [Parameter(Mandatory)][string]$Descricao
    )

    try {
        $rules = @(Get-NetFirewallRule -Name $Padrao -ErrorAction SilentlyContinue)

        if ($rules.Count -eq 0) {
            Add-Result "Firewall: $Descricao" "AVISO" "Regras internas não encontradas."
            return
        }

        $rules | Set-NetFirewallRule `
            -Enabled True `
            -Profile Any `
            -ErrorAction Stop

        Add-Result "Firewall: $Descricao" "OK" "Regras habilitadas."
    }
    catch {
        Add-Result "Firewall: $Descricao" "ERRO" $_.Exception.Message
    }
}

function New-OrReplaceFirewallRule {
    param(
        [Parameter(Mandatory)][string]$Nome,
        [Parameter(Mandatory)][string]$Descricao,
        [Parameter(Mandatory)][hashtable]$Parametros
    )

    try {
        Get-NetFirewallRule -Name $Nome -ErrorAction SilentlyContinue |
            Remove-NetFirewallRule -ErrorAction SilentlyContinue

        $base = @{
            Name        = $Nome
            DisplayName = $Descricao
            Direction   = "Inbound"
            Action      = "Allow"
            Enabled     = "True"
            Profile     = "Any"
        }

        foreach ($key in $Parametros.Keys) {
            $base[$key] = $Parametros[$key]
        }

        New-NetFirewallRule @base -ErrorAction Stop | Out-Null
        Add-Result "Firewall: $Descricao" "OK" "Regra criada."
    }
    catch {
        Add-Result "Firewall: $Descricao" "ERRO" $_.Exception.Message
    }
}

function Enable-NetworkAndPrinterFirewall {
    param([switch]$ServidorLocal)

    Write-Section "Preparando compartilhamento em todos os perfis de rede"

    Enable-FirewallRuleFamily -Padrao "NETDIS-*" -Descricao "Descoberta de rede"

    if ($ServidorLocal) {
        Enable-FirewallRuleFamily `
            -Padrao "FPS-*" `
            -Descricao "Compartilhamento de arquivos e impressoras"

        New-OrReplaceFirewallRule `
            -Nome "ReparoImpressora-SMB-In" `
            -Descricao "Reparo de impressora - SMB TCP 445" `
            -Parametros @{ Protocol = "TCP"; LocalPort = 445 }

        New-OrReplaceFirewallRule `
            -Nome "ReparoImpressora-RPC-In" `
            -Descricao "Reparo de impressora - RPC TCP 135" `
            -Parametros @{ Protocol = "TCP"; LocalPort = 135 }

        New-OrReplaceFirewallRule `
            -Nome "ReparoImpressora-Spooler-In" `
            -Descricao "Reparo de impressora - Spooler RPC" `
            -Parametros @{
                Protocol = "TCP"
                Program  = "$env:SystemRoot\System32\spoolsv.exe"
                Service  = "Spooler"
            }
    }
}

function Set-ModernSmb {
    param(
        [switch]$ServidorLocal,
        [switch]$ClienteLocal
    )

    Write-Section "Configurando SMB moderno"

    if ($ServidorLocal -and
        (Get-Command Set-SmbServerConfiguration -ErrorAction SilentlyContinue)) {
        try {
            $smbServerArgs = @{
                EnableSMB1Protocol = $false
                EnableSMB2Protocol = $true
                Force              = $true
                ErrorAction        = 'Stop'
            }

            Set-SmbServerConfiguration @smbServerArgs

            Add-Result "Servidor SMB" "OK" "SMB1 desabilitado; SMB2/SMB3 habilitado."
        }
        catch {
            Add-Result "Servidor SMB" "ERRO" $_.Exception.Message
        }
    }

    try {
        $feature = Get-WindowsOptionalFeature `
            -Online `
            -FeatureName SMB1Protocol `
            -ErrorAction SilentlyContinue

        if ($feature -and $feature.State -eq "Enabled") {
            Disable-WindowsOptionalFeature `
                -Online `
                -FeatureName SMB1Protocol `
                -NoRestart `
                -ErrorAction Stop | Out-Null

            Add-Result "Componente SMB1" "OK" "Desabilitado."
        }
        elseif ($feature) {
            Add-Result "Componente SMB1" "OK" "Já estava desabilitado."
        }
    }
    catch {
        Add-Result "Componente SMB1" "AVISO" $_.Exception.Message
    }

    if ($ClienteLocal) {
        Add-Result "Cliente SMB" "INFO" "Mantido com suporte a SMB2/SMB3."
    }
}

function Get-BuiltInGuestAccount {
    try {
        return Get-CimInstance Win32_UserAccount -ErrorAction Stop |
            Where-Object { $_.LocalAccount -eq $true -and $_.SID -match '-501$' } |
            Select-Object -First 1
    }
    catch {
        return $null
    }
}

function Update-PrivilegeLine {
    param(
        [Parameter(Mandatory)][string[]]$Conteudo,
        [Parameter(Mandatory)][string]$Privilegio,
        [string[]]$Adicionar = @(),
        [string[]]$Remover = @()
    )

    $index = -1
    $pattern = '^\s*' + [regex]::Escape($Privilegio) + '\s*='

    for ($i = 0; $i -lt $Conteudo.Count; $i++) {
        if ($Conteudo[$i] -match $pattern) {
            $index = $i
            break
        }
    }

    $values = New-Object System.Collections.Generic.List[string]

    if ($index -ge 0) {
        $parts = $Conteudo[$index] -split '=', 2

        if ($parts.Count -eq 2 -and -not [string]::IsNullOrWhiteSpace($parts[1])) {
            foreach ($value in ($parts[1] -split ',')) {
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    [void]$values.Add($value.Trim())
                }
            }
        }
    }

    foreach ($removeValue in $Remover) {
        for ($i = $values.Count - 1; $i -ge 0; $i--) {
            if ($values[$i].TrimStart('*') -ieq $removeValue.TrimStart('*')) {
                $values.RemoveAt($i)
            }
        }
    }

    foreach ($addValue in $Adicionar) {
        $normalized = $addValue.TrimStart('*')
        $exists = $false

        foreach ($current in $values) {
            if ($current.TrimStart('*') -ieq $normalized) {
                $exists = $true
                break
            }
        }

        if (-not $exists) {
            if ($normalized -match '^S-\d-') {
                [void]$values.Add("*$normalized")
            }
            else {
                [void]$values.Add($normalized)
            }
        }
    }

    $newLine = "$Privilegio = " + ($values -join ',')

    if ($index -ge 0) {
        $Conteudo[$index] = $newLine
        return $Conteudo
    }

    $list = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Conteudo) { [void]$list.Add($line) }

    $sectionIndex = -1
    for ($i = 0; $i -lt $list.Count; $i++) {
        if ($list[$i] -match '^\s*\[Privilege Rights\]\s*$') {
            $sectionIndex = $i
            break
        }
    }

    if ($sectionIndex -lt 0) {
        [void]$list.Add('')
        [void]$list.Add('[Privilege Rights]')
        [void]$list.Add($newLine)
    }
    else {
        $list.Insert($sectionIndex + 1, $newLine)
    }

    return $list.ToArray()
}

function Enable-GuestNetworkRights {
    param(
        [Parameter(Mandatory)][string]$GuestSid,
        [Parameter(Mandatory)][string]$GuestName
    )

    $inf = Join-Path $env:TEMP "ReparoImpressora-$([guid]::NewGuid()).inf"
    $db  = Join-Path $env:TEMP "ReparoImpressora-$([guid]::NewGuid()).sdb"

    try {
        & secedit.exe /export /cfg $inf /areas USER_RIGHTS | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Falha ao exportar a política de direitos de usuário."
        }

        $content = @(Get-Content -Path $inf -Encoding Unicode -ErrorAction Stop)
        $guestsGroupSid = 'S-1-5-32-546'

        $content = @(Update-PrivilegeLine `
            -Conteudo $content `
            -Privilegio 'SeNetworkLogonRight' `
            -Adicionar @($guestsGroupSid, $GuestSid))

        $content = @(Update-PrivilegeLine `
            -Conteudo $content `
            -Privilegio 'SeDenyNetworkLogonRight' `
            -Remover @($guestsGroupSid, $GuestSid, $GuestName))

        Set-Content -Path $inf -Value $content -Encoding Unicode -Force -ErrorAction Stop

        & secedit.exe /configure /db $db /cfg $inf /areas USER_RIGHTS | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Falha ao aplicar os direitos de logon em rede."
        }

        Add-Result "Direitos da conta Convidado" "OK" "Logon em rede permitido."
    }
    catch {
        Add-Result "Direitos da conta Convidado" "ERRO" $_.Exception.Message
    }
    finally {
        Remove-Item $inf, $db -Force -ErrorAction SilentlyContinue
    }
}

function Disable-PasswordProtectedSharing {
    param(
        [switch]$ServidorLocal,
        [switch]$ClienteLocal
    )

    Write-Section "Configurando compartilhamento sem senha"

    if ($ServidorLocal) {
        $guest = Get-BuiltInGuestAccount

        if ($guest) {
            try {
                & net.exe user "$($guest.Name)" /active:yes | Out-Null

                if ($LASTEXITCODE -eq 0) {
                    Add-Result "Conta Convidado" "OK" "Conta interna habilitada."
                }
                else {
                    Add-Result "Conta Convidado" "AVISO" "Ativação não confirmada pelo Windows."
                }
            }
            catch {
                Add-Result "Conta Convidado" "ERRO" $_.Exception.Message
            }

            Enable-GuestNetworkRights -GuestSid $guest.SID -GuestName $guest.Name
        }
        else {
            Add-Result "Conta Convidado" "ERRO" "Conta interna com SID final 501 não encontrada."
        }

        try {
            $lsa = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
            New-Item -Path $lsa -Force -ErrorAction Stop | Out-Null
            New-ItemProperty `
                -Path $lsa `
                -Name ForceGuest `
                -PropertyType DWord `
                -Value 1 `
                -Force `
                -ErrorAction Stop | Out-Null

            Add-Result "Proteção por senha" "OK" "Modelo de acesso definido como Convidado."
        }
        catch {
            Add-Result "Proteção por senha" "ERRO" $_.Exception.Message
        }

        if (Get-Command Set-SmbServerConfiguration -ErrorAction SilentlyContinue) {
            try {
                $cmd = Get-Command Set-SmbServerConfiguration
                $args = @{
                    RequireSecuritySignature = $false
                    Force                    = $true
                    ErrorAction              = 'Stop'
                }

                if ($cmd.Parameters.ContainsKey('EncryptData')) {
                    $args.EncryptData = $false
                }

                Set-SmbServerConfiguration @args
                Add-Result "Servidor SMB convidado" "OK" `
                    "Assinatura obrigatória e criptografia obrigatória desativadas."
            }
            catch {
                Add-Result "Servidor SMB convidado" "ERRO" $_.Exception.Message
            }
        }
    }

    if ($ClienteLocal) {
        try {
            $cmd = Get-Command Set-SmbClientConfiguration -ErrorAction Stop
            $args = @{
                EnableInsecureGuestLogons = $true
                RequireSecuritySignature  = $false
                Force                     = $true
                ErrorAction               = 'Stop'
            }

            if ($cmd.Parameters.ContainsKey('RequireEncryption')) {
                $args.RequireEncryption = $false
            }

            Set-SmbClientConfiguration @args

            Add-Result "Cliente SMB convidado" "OK" `
                "Acesso de convidado sem senha habilitado."
        }
        catch {
            Add-Result "Cliente SMB convidado" "ERRO" $_.Exception.Message
        }

        try {
            $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
            New-Item -Path $path -Force -ErrorAction Stop | Out-Null
            New-ItemProperty `
                -Path $path `
                -Name AllowInsecureGuestAuth `
                -PropertyType DWord `
                -Value 1 `
                -Force `
                -ErrorAction Stop | Out-Null

            Add-Result "Registro SMB convidado" "OK" "AllowInsecureGuestAuth habilitado."
        }
        catch {
            Add-Result "Registro SMB convidado" "ERRO" $_.Exception.Message
        }
    }
}

function Set-RegistryDwordValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Value
    )

    New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    New-ItemProperty `
        -Path $Path `
        -Name $Name `
        -PropertyType DWord `
        -Value $Value `
        -Force `
        -ErrorAction Stop | Out-Null
}

function Set-PrinterRpcCompatibility {
    param(
        [switch]$ServidorLocal,
        [switch]$ClienteLocal
    )

    Write-Section "Aplicando compatibilidade de impressão em rede"

    $printersPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers'
    $rpcPolicy = Join-Path $printersPolicy 'RPC'
    $printControl = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print'

    try {
        if ($ClienteLocal) {
            Set-RegistryDwordValue `
                -Path $rpcPolicy `
                -Name 'RpcUseNamedPipeProtocol' `
                -Value 1

            Add-Result "RPC do cliente" "OK" `
                "RPC sobre pipes nomeados habilitado para impressoras compartilhadas."
        }

        if ($ServidorLocal) {
            Set-RegistryDwordValue `
                -Path $rpcPolicy `
                -Name 'RpcProtocols' `
                -Value 7

            Set-RegistryDwordValue `
                -Path $printersPolicy `
                -Name 'RegisterSpoolerRemoteRpcEndPoint' `
                -Value 1

            Set-RegistryDwordValue `
                -Path $printControl `
                -Name 'RpcAuthnLevelPrivacyEnabled' `
                -Value 0

            Add-Result "RPC do servidor" "OK" `
                "Spooler aceitando RPC por TCP e pipes; privacidade RPC relaxada."
        }

        if ($ServidorLocal -or $ClienteLocal) {
            Set-RegistryDwordValue `
                -Path (Join-Path $printersPolicy 'WPP') `
                -Name 'WindowsProtectedPrintGroupPolicyState' `
                -Value 0

            Set-RegistryDwordValue `
                -Path $printersPolicy `
                -Name 'EnableDeviceControl' `
                -Value 0

            Add-Result "Compatibilidade de drivers" "OK" `
                "Modo protegido e restrição por tipo de conexão desativados por política local."
        }

        if (-not $NaoReiniciarSpooler) {
            Restart-Service -Name Spooler -Force -ErrorAction Stop
            Add-Result "Aplicar políticas de impressão" "OK" `
                "Spooler reiniciado antes do compartilhamento/conexão."
        }
        else {
            Add-Result "Aplicar políticas de impressão" "AVISO" `
                "Reinicie o computador para que todas as políticas RPC entrem em vigor."
        }
    }
    catch {
        Add-Result "Compatibilidade RPC" "ERRO" $_.Exception.Message
    }
}

function Get-LocalPrinters {
    if (-not (Get-Command Get-Printer -ErrorAction SilentlyContinue)) {
        return @()
    }

    try {
        return @(
            Get-Printer -ErrorAction Stop |
                Where-Object { $_.Name -notmatch '^\\\\' } |
                Sort-Object Name
        )
    }
    catch {
        return @()
    }
}

function Get-SafeShareName {
    param([Parameter(Mandatory)][string]$Nome)

    $safe = ($Nome -replace '[\\/:*?"<>|,\s]+', '-').Trim('-')

    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = 'IMPRESSORA'
    }

    if ($safe.Length -gt 31) {
        $safe = $safe.Substring(0, 31).Trim('-')
    }

    return $safe
}

function Test-IsVirtualPrinter {
    param([Parameter(Mandatory)][object]$Printer)

    $port = [string]$Printer.PortName
    $name = [string]$Printer.Name
    $driver = [string]$Printer.DriverName

    return (
        $port -match '^(PORTPROMPT:|FILE:|SHRFAX:|NUL:|XPSPORT:)' -or
        $name -match '(?i)(PDF|XPS|OneNote|Fax|Document Writer)' -or
        $driver -match '(?i)(PDF|XPS|OneNote|Fax)'
    )
}

function Get-UniquePrinterShareName {
    param(
        [Parameter(Mandatory)][string]$PrinterName,
        [Parameter(Mandatory)][string]$RequestedName
    )

    $baseName = Get-SafeShareName -Nome $RequestedName
    $existingNames = @(
        Get-Printer -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -ine $PrinterName -and $_.Shared -and $_.ShareName
            } |
            ForEach-Object { [string]$_.ShareName }
    )

    if ($existingNames -notcontains $baseName) {
        return $baseName
    }

    for ($index = 2; $index -lt 1000; $index++) {
        $suffix = "-$index"
        $maxBaseLength = 31 - $suffix.Length
        $prefix = $baseName.Substring(
            0,
            [Math]::Min($baseName.Length, $maxBaseLength)
        ).TrimEnd('-')
        $candidate = "$prefix$suffix"

        if ($existingNames -notcontains $candidate) {
            return $candidate
        }
    }

    return ("IMP-{0}" -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
}

function Select-AndShareLocalPrinter {
    $printers = @(Get-LocalPrinters)

    if ($printers.Count -eq 0) {
        Add-Result "Impressora local" "ERRO" "Nenhuma impressora local foi encontrada."
        return
    }

    $targets = @()

    if (-not [string]::IsNullOrWhiteSpace($script:ImpressoraLocal)) {
        $selected = $printers |
            Where-Object { $_.Name -ieq $script:ImpressoraLocal } |
            Select-Object -First 1

        if (-not $selected) {
            Add-Result "Impressora local" "ERRO" `
                "A impressora '$script:ImpressoraLocal' não foi encontrada."
            return
        }

        $targets = @($selected)
    }
    else {
        if ($CompartilharImpressorasVirtuais) {
            $targets = @($printers)
        }
        else {
            $targets = @(
                $printers | Where-Object { -not (Test-IsVirtualPrinter -Printer $_) }
            )
        }

        if ($targets.Count -eq 0) {
            Add-Result "Impressoras físicas" "AVISO" `
                "Só foram encontradas impressoras virtuais. Use -CompartilharImpressorasVirtuais para incluí-las."
            return
        }
    }

    Write-Section "Compartilhando impressoras locais"

    foreach ($printer in $targets) {
        $requestedName = if (
            $targets.Count -eq 1 -and
            -not [string]::IsNullOrWhiteSpace($script:NomeCompartilhamento)
        ) {
            $script:NomeCompartilhamento
        }
        elseif ($printer.Shared -and $printer.ShareName) {
            [string]$printer.ShareName
        }
        else {
            [string]$printer.Name
        }

        $shareName = Get-UniquePrinterShareName `
            -PrinterName $printer.Name `
            -RequestedName $requestedName

        try {
            Set-Printer `
                -Name $printer.Name `
                -Shared $true `
                -ShareName $shareName `
                -ErrorAction Stop

            $unc = "\\$env:COMPUTERNAME\$shareName"
            [void]$script:CaminhosCompartilhados.Add($unc)
            Add-Result "Compartilhar: $($printer.Name)" "OK" $unc

            if ($targets.Count -eq 1) {
                $script:ImpressoraLocal = $printer.Name
                $script:NomeCompartilhamento = $shareName
            }
        }
        catch {
            Add-Result "Compartilhar: $($printer.Name)" "ERRO" `
                $_.Exception.Message
        }
    }
}

function Test-TcpPortFast {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutMilliseconds = 700
    )

    $client = New-Object System.Net.Sockets.TcpClient

    try {
        $async = $client.BeginConnect($ComputerName, $Port, $null, $null)
        $connected = $async.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)

        if (-not $connected) {
            return $false
        }

        $client.EndConnect($async)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Get-CandidatePrintServers {
    $names = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    try {
        foreach ($connection in @(Get-SmbConnection -ErrorAction SilentlyContinue)) {
            if ($connection.ServerName) {
                [void]$names.Add([string]$connection.ServerName)
            }
        }
    }
    catch { }

    try {
        foreach ($mapping in @(Get-SmbMapping -ErrorAction SilentlyContinue)) {
            if ($mapping.RemotePath -match '^\\\\([^\\]+)\\') {
                [void]$names.Add($Matches[1])
            }
        }
    }
    catch { }

    try {
        $view = & net.exe view 2>$null
        foreach ($line in $view) {
            if ($line -match '^\\\\([^\s]+)') {
                [void]$names.Add($Matches[1])
            }
        }
    }
    catch { }

    try {
        $neighbors = Get-NetNeighbor `
            -AddressFamily IPv4 `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.State -in @('Reachable', 'Stale', 'Delay', 'Probe') -and
                $_.IPAddress -notlike '127.*' -and
                $_.IPAddress -notlike '169.254.*' -and
                $_.IPAddress -notlike '224.*' -and
                $_.IPAddress -ne '255.255.255.255'
            } |
            Select-Object -ExpandProperty IPAddress -Unique

        foreach ($ip in $neighbors) {
            [void]$names.Add([string]$ip)
        }
    }
    catch { }

    $available = New-Object System.Collections.Generic.List[object]

    foreach ($name in $names) {
        if ($name -ieq $env:COMPUTERNAME) {
            continue
        }

        try {
            $port445 = Test-TcpPortFast -ComputerName $name -Port 445

            if ($port445) {
                [void]$available.Add([PSCustomObject]@{
                    Servidor = $name
                    Porta445 = $true
                })
            }
        }
        catch { }
    }

    return @($available | Sort-Object Servidor)
}

function Request-Server {
    if (-not [string]::IsNullOrWhiteSpace($script:Servidor)) {
        return
    }

    if (-not $NaoDescobrirServidores) {
        Write-Section "Procurando possíveis servidores já visíveis na rede"
        $candidates = @(Get-CandidatePrintServers)

        if ($candidates.Count -gt 0) {
            $selected = Select-MenuItem `
                -Titulo "Selecione um servidor ou escolha 0 para digitar outro:" `
                -Itens $candidates `
                -TextoItem { param($item) "$($item.Servidor) | SMB 445 disponível" } `
                -PermitirCancelar

            if ($selected) {
                $script:Servidor = $selected.Servidor
                return
            }
        }
        else {
            Add-Result "Descoberta de servidores" "INFO" `
                "Nenhum servidor foi identificado automaticamente."
        }
    }

    while ([string]::IsNullOrWhiteSpace($script:Servidor)) {
        $value = Read-Host "Digite o nome, FQDN ou IP do computador servidor"

        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $script:Servidor = $value.Trim().Trim('\')
        }
    }
}

function Test-PrintServer {
    param([Parameter(Mandatory)][string]$Nome)

    Write-Section "Diagnosticando servidor: $Nome"

    try {
        $addresses = @([System.Net.Dns]::GetHostAddresses($Nome) |
            ForEach-Object { $_.IPAddressToString })

        Add-Result "Resolução de nome" "OK" ($addresses -join ', ')
    }
    catch {
        Add-Result "Resolução de nome" "AVISO" `
            "O nome não foi resolvido; um IPv4 ainda pode funcionar diretamente."
    }

    foreach ($port in @(445, 135)) {
        try {
            $ok = Test-NetConnection `
                -ComputerName $Nome `
                -Port $port `
                -InformationLevel Quiet `
                -WarningAction SilentlyContinue

            if ($ok) {
                Add-Result "Porta TCP $port" "OK" "Acessível."
            }
            else {
                Add-Result "Porta TCP $port" "ERRO" "Bloqueada ou serviço indisponível."
            }
        }
        catch {
            Add-Result "Porta TCP $port" "ERRO" $_.Exception.Message
        }
    }

    if ($Detalhado) {
        try {
            Test-NetConnection -ComputerName $Nome -Port 445 | Format-List | Out-Host
        }
        catch { }
    }
}

function Get-RemoteSharedPrinters {
    param([Parameter(Mandatory)][string]$NomeServidor)

    if (-not (Get-Command Get-Printer -ErrorAction SilentlyContinue)) {
        return @()
    }

    try {
        return @(
            Get-Printer -ComputerName $NomeServidor -ErrorAction Stop |
                Where-Object { $_.Shared -and $_.ShareName } |
                Sort-Object ShareName
        )
    }
    catch {
        Add-Result "Consultar impressoras remotas" "AVISO" $_.Exception.Message
        return @()
    }
}

function Request-RemotePrinterShare {
    if (-not [string]::IsNullOrWhiteSpace($script:ImpressoraCompartilhada)) {
        return
    }

    $remotePrinters = @(Get-RemoteSharedPrinters -NomeServidor $script:Servidor)

    if ($remotePrinters.Count -gt 0) {
        $selected = Select-MenuItem `
            -Titulo "Selecione a impressora compartilhada:" `
            -Itens $remotePrinters `
            -TextoItem {
                param($printer)
                "{0} | Driver: {1}" -f $printer.ShareName, $printer.DriverName
            } `
            -PermitirCancelar

        if ($selected) {
            $script:ImpressoraCompartilhada = $selected.ShareName
            return
        }
    }

    while ([string]::IsNullOrWhiteSpace($script:ImpressoraCompartilhada)) {
        $value = Read-Host "Digite o nome compartilhado da impressora"

        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $script:ImpressoraCompartilhada = $value.Trim().Trim('\')
        }
    }
}

function Install-SharedPrinter {
    param(
        [Parameter(Mandatory)][string]$NomeServidor,
        [Parameter(Mandatory)][string]$NomeCompartilhado,
        [switch]$Reinstalar
    )

    $unc = "\\$NomeServidor\$NomeCompartilhado"
    Write-Section "Instalando impressora: $unc"

    try {
        $existing = Get-Printer -Name $unc -ErrorAction SilentlyContinue

        if ($Reinstalar -and $existing) {
            Remove-Printer -Name $existing.Name -ErrorAction Stop
            Add-Result "Remover conexão anterior" "OK" $unc
            $existing = $null
        }

        if ($existing) {
            Add-Result "Instalar impressora" "OK" "A conexão já existe: $unc"
            return
        }
    }
    catch {
        Add-Result "Preparar instalação" "ERRO" $_.Exception.Message
        return
    }

    $firstError = $null

    try {
        Add-Printer -ConnectionName $unc -ErrorAction Stop
        Add-Result "Instalar impressora" "OK" "Conectada em $unc"
        return
    }
    catch {
        $firstError = $_.Exception.Message
        Add-Result "Primeira tentativa de instalação" "AVISO" $firstError
    }

    $pointAndPrint = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint'
    $valueName = 'RestrictDriverInstallationToAdministrators'
    $valueExisted = $false
    $previousValue = $null

    try {
        if (Test-Path $pointAndPrint) {
            $current = Get-ItemProperty `
                -Path $pointAndPrint `
                -Name $valueName `
                -ErrorAction SilentlyContinue

            if ($current -and $current.PSObject.Properties.Name -contains $valueName) {
                $valueExisted = $true
                $previousValue = [int]$current.$valueName
            }
        }

        Set-RegistryDwordValue `
            -Path $pointAndPrint `
            -Name $valueName `
            -Value 0

        Add-Printer -ConnectionName $unc -ErrorAction Stop
        Add-Result "Instalar impressora" "OK" `
            "Conectada em $unc após liberação temporária do driver."
    }
    catch {
        Add-Result "Instalar impressora" "ERRO" `
            ("{0} | Erro inicial: {1}" -f $_.Exception.Message, $firstError)

        Write-Host ""
        Write-Host "Causas que o script não consegue corrigir sozinho:" `
            -ForegroundColor Yellow
        Write-Host "- Driver incompatível ou ausente no servidor."
        Write-Host "- Nome do compartilhamento incorreto."
        Write-Host "- Permissão de impressão removida no servidor."
        Write-Host "- Política de domínio/empresa substituindo a configuração local."
        Write-Host "- Modo de impressão protegida imposto por política corporativa."
    }
    finally {
        try {
            if ($valueExisted) {
                Set-RegistryDwordValue `
                    -Path $pointAndPrint `
                    -Name $valueName `
                    -Value $previousValue
            }
            else {
                Remove-ItemProperty `
                    -Path $pointAndPrint `
                    -Name $valueName `
                    -ErrorAction SilentlyContinue
            }
        }
        catch {
            Add-Result "Restaurar proteção de driver" "AVISO" `
                $_.Exception.Message
        }
    }
}

function Reset-NetworkCaches {
    Write-Section "Atualizando caches de rede"

    try {
        Clear-DnsClientCache -ErrorAction Stop
        Add-Result "Cache DNS" "OK" "Limpo."
    }
    catch {
        Add-Result "Cache DNS" "AVISO" $_.Exception.Message
    }

    try {
        & nbtstat.exe -R | Out-Null
        & nbtstat.exe -RR | Out-Null
        Add-Result "Cache NetBIOS" "OK" "Atualizado."
    }
    catch {
        Add-Result "Cache NetBIOS" "INFO" "Comando indisponível ou não necessário."
    }
}

function Restart-RepairServices {
    param(
        [switch]$ServidorLocal,
        [switch]$ClienteLocal
    )

    Write-Section "Reiniciando serviços alterados"

    $names = New-Object System.Collections.Generic.List[string]

    if ($ServidorLocal) {
        [void]$names.Add('LanmanServer')
        [void]$names.Add('FDResPub')
    }

    if ($ClienteLocal) {
        [void]$names.Add('LanmanWorkstation')
    }

    if (-not $NaoReiniciarSpooler) {
        [void]$names.Add('Spooler')
    }

    foreach ($name in ($names | Select-Object -Unique)) {
        try {
            Restart-Service -Name $name -Force -ErrorAction Stop
            Add-Result "Reiniciar $name" "OK" "Serviço reiniciado."
        }
        catch {
            Add-Result "Reiniciar $name" "AVISO" $_.Exception.Message
        }
    }
}

function Show-LocalInformation {
    Write-Section "Informações deste computador"

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        Write-Host "Computador : $env:COMPUTERNAME"
        Write-Host "Windows    : $($os.Caption)"
        Write-Host "Versão     : $($os.Version)"
        Write-Host "Build      : $($os.BuildNumber)"
    }
    catch {
        Write-Host "Computador : $env:COMPUTERNAME"
    }

    Write-Host ""
    Write-Host "Redes:" -ForegroundColor Yellow
    Get-NetConnectionProfile -ErrorAction SilentlyContinue |
        Select-Object -Property @(
            'Name', 'InterfaceAlias', 'NetworkCategory', 'IPv4Connectivity'
        ) |
        Format-Table -AutoSize | Out-Host

    Write-Host "Endereços IPv4:" -ForegroundColor Yellow
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike '127.*' -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.InterfaceAlias -notlike '*Loopback*'
        } |
        Select-Object -Property @('InterfaceAlias', 'IPAddress', 'PrefixLength') |
        Format-Table -AutoSize | Out-Host

    Write-Host "Impressoras instaladas:" -ForegroundColor Yellow
    if (Get-Command Get-Printer -ErrorAction SilentlyContinue) {
        Get-Printer -ErrorAction SilentlyContinue |
            Select-Object -Property @(
                'Name', 'Shared', 'ShareName', 'DriverName', 'PortName'
            ) |
            Format-Table -AutoSize | Out-Host
    }
}

function Show-RecentPrintErrors {
    Write-Section "Erros recentes do serviço de impressão"

    try {
        $events = @(Get-WinEvent -FilterHashtable @{
            LogName   = 'Microsoft-Windows-PrintService/Admin'
            StartTime = (Get-Date).AddDays(-7)
            Level     = 2, 3
        } -MaxEvents 10 -ErrorAction Stop)

        if ($events.Count -eq 0) {
            Add-Result "Eventos de impressão" "OK" "Nenhum erro recente."
            return
        }

        foreach ($event in $events) {
            $message = ($event.Message -replace '\s+', ' ').Trim()
            if ($message.Length -gt 180) {
                $message = $message.Substring(0, 180) + '...'
            }

            Write-Host ("{0} | Evento {1} | {2}" -f `
                $event.TimeCreated, $event.Id, $message) -ForegroundColor Yellow
        }
    }
    catch {
        Add-Result "Eventos de impressão" "INFO" `
            "Log sem eventos ou indisponível."
    }
}

function Select-OperationMode {
    if ($script:Modo -ne 'Menu') {
        return
    }

    Write-Section "Selecione o que este computador fará"
    Write-Host "[1] Servidor - compartilha automaticamente as impressoras deste PC"
    Write-Host "[2] Cliente - este PC acessa uma impressora de outro PC"
    Write-Host "[3] Ambos - compartilha as locais e também acessa impressoras"
    Write-Host "[4] Diagnóstico - apenas verifica as configurações"

    while ($true) {
        switch (Read-Host 'Escolha') {
            '1' { $script:Modo = 'Servidor'; return }
            '2' { $script:Modo = 'Cliente'; return }
            '3' { $script:Modo = 'Ambos'; return }
            '4' { $script:Modo = 'Diagnostico'; return }
            default { Write-Host 'Opção inválida.' -ForegroundColor Yellow }
        }
    }
}

if (-not (Test-Administrator)) {
    if (Start-AsAdministrator `
        -BoundParameters $PSBoundParameters `
        -ScriptPath $PSCommandPath) {
        Write-Host "Solicitando permissão de Administrador..." -ForegroundColor Yellow
        return
    }

    Write-Host "Não foi possível abrir como Administrador." -ForegroundColor Red
    return
}

try {
    Resolve-PrinterTarget
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    return
}

Select-OperationMode

$serverRole = $script:Modo -in @('Servidor', 'Ambos')
$clientRole = $script:Modo -in @('Cliente', 'Ambos')
$diagnosticOnly = $script:Modo -eq 'Diagnostico'

Show-LocalInformation

if (-not $diagnosticOnly) {
    Enable-RequiredServices -ServidorLocal:$serverRole -ClienteLocal:$clientRole
    Enable-FileAndPrinterBindings
    Enable-NetworkAndPrinterFirewall -ServidorLocal:$serverRole

    if (-not $NaoDesativarFirewall) {
        Disable-WindowsFirewallAllProfiles
    }

    Set-ModernSmb -ServidorLocal:$serverRole -ClienteLocal:$clientRole

    if (-not $ManterProtecaoSenha) {
        Disable-PasswordProtectedSharing `
            -ServidorLocal:$serverRole `
            -ClienteLocal:$clientRole
    }

    if (-not $NaoAplicarCompatibilidadeRpc) {
        Set-PrinterRpcCompatibility `
            -ServidorLocal:$serverRole `
            -ClienteLocal:$clientRole
    }

    Reset-NetworkCaches
}

if ($serverRole) {
    Select-AndShareLocalPrinter
}

if ($clientRole) {
    Request-Server
    Test-PrintServer -Nome $script:Servidor
    Request-RemotePrinterShare

    if ($InstalarImpressora -or $ReinstalarImpressora) {
        Install-SharedPrinter `
            -NomeServidor $script:Servidor `
            -NomeCompartilhado $script:ImpressoraCompartilhada `
            -Reinstalar:$ReinstalarImpressora
    }
    else {
        Write-Host ""
        Write-Host "Caminho pronto para testar:" -ForegroundColor Green
        Write-Host "\\$script:Servidor\$script:ImpressoraCompartilhada" `
            -ForegroundColor Cyan

        $answer = Read-Host "Deseja instalar essa impressora agora? (S/N)"
        if ($answer -match '^[SsYy]') {
            Install-SharedPrinter `
                -NomeServidor $script:Servidor `
                -NomeCompartilhado $script:ImpressoraCompartilhada
        }
    }
}
elseif ($diagnosticOnly -and -not [string]::IsNullOrWhiteSpace($script:Servidor)) {
    Test-PrintServer -Nome $script:Servidor
}

if (-not $diagnosticOnly) {
    Restart-RepairServices -ServidorLocal:$serverRole -ClienteLocal:$clientRole
}

Show-RecentPrintErrors

Write-Section "Resumo"
$script:Resultados |
    Format-Table -Property @('Etapa', 'Status', 'Detalhe') -AutoSize -Wrap |
    Out-Host

if ($serverRole) {
    Write-Host ""
    Write-Host "Este computador pode ser aberto por:" -ForegroundColor Green
    Write-Host "\\$env:COMPUTERNAME" -ForegroundColor Cyan

    foreach ($sharedPath in $script:CaminhosCompartilhados) {
        Write-Host $sharedPath -ForegroundColor Cyan
    }
}

if (-not $NaoDesativarFirewall -and -not $diagnosticOnly) {
    Write-Host ""
    Write-Warning `
        "O Firewall do Windows ficou DESATIVADO em redes de Domínio, Privadas e Públicas."
}

if (-not $ManterProtecaoSenha -and -not $diagnosticOnly) {
    Write-Host ""
    Write-Warning `
        "O acesso SMB sem senha/convidado reduz a segurança. Use somente em rede confiável."
}

if (-not $NaoAplicarCompatibilidadeRpc -and $serverRole) {
    Write-Warning `
        "A privacidade RPC do Spooler foi reduzida para compatibilidade com impressoras antigas."
}

Write-Host ""
Write-Host "Finalizado." -ForegroundColor Green
if (-not $NaoPausar) {
    [void](Read-Host "Pressione ENTER para sair")
}
