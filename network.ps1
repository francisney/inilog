<#
.SYNOPSIS
    LanScout Network - Scanner de Rede Local para Windows 10/11

.DESCRIPTION
    Use assim no PowerShell:

    irm https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/network.ps1 | iex

    O script:
    - Detecta a rede local automaticamente
    - Verifica se o Nmap está instalado
    - Se não estiver, tenta instalar automaticamente via winget
    - Se winget falhar, baixa o instalador oficial do Nmap com progresso
    - Executa scan da rede local
    - Gera relatórios TXT, CSV e HTML na Área de Trabalho

.NOTES
    Use somente em redes suas ou redes onde você tem autorização.
#>

$ErrorActionPreference = "Stop"

# Mantém barra de progresso visível em downloads próprios
$ProgressPreference = "Continue"

# ============================================================
# Configurações padrão
# ============================================================

$DefaultPorts = "21,22,23,53,80,135,139,443,445,3389,5357,8080,8443,9100"
$UseDeepScan = $false
$OpenResults = $true
$AutoInstallNmap = $true

# ============================================================
# Visual
# ============================================================

function Write-Title {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " LanScout Network - Scanner de Rede Local Windows 10/11" -ForegroundColor Cyan
    Write-Host " Auto download Nmap + scan + relatorios" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Info {
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Yellow
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-Bad {
    param([string]$Message)
    Write-Host "[X] $Message" -ForegroundColor Red
}

# ============================================================
# Admin
# ============================================================

function Test-Admin {
    try {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

# ============================================================
# TLS
# ============================================================

function Enable-Tls12 {
    try {
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.SecurityProtocolType]::Tls12 -bor `
            [Net.SecurityProtocolType]::Tls11 -bor `
            [Net.SecurityProtocolType]::Tls
    }
    catch {}
}

# ============================================================
# Detectar Nmap
# ============================================================

function Get-NmapCommand {
    $cmd = Get-Command nmap.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $possiblePaths = @(
        "$env:ProgramFiles\Nmap\nmap.exe",
        "${env:ProgramFiles(x86)}\Nmap\nmap.exe",
        "$env:LOCALAPPDATA\Programs\Nmap\nmap.exe"
    )

    foreach ($path in $possiblePaths) {
        if ($path -and (Test-Path $path)) {
            return $path
        }
    }

    return $null
}

function Update-CurrentPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# ============================================================
# Instalar Nmap via winget
# ============================================================

function Test-Winget {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    return [bool]$cmd
}

function Install-NmapWinget {
    if (-not (Test-Winget)) {
        return $false
    }

    Write-Info "Instalando Nmap via winget..."
    Write-Host "    winget install -e --id Insecure.Nmap" -ForegroundColor DarkGray
    Write-Host ""

    try {
        & winget install -e --id Insecure.Nmap --accept-source-agreements --accept-package-agreements

        Update-CurrentPath
        Start-Sleep -Seconds 2

        $nmap = Get-NmapCommand
        if ($nmap) {
            Write-Ok "Nmap instalado via winget: $nmap"
            return $true
        }

        return $false
    }
    catch {
        Write-Warn "Falha ao instalar via winget: $($_.Exception.Message)"
        return $false
    }
}

# ============================================================
# Baixar instalador oficial do Nmap
# ============================================================

function Get-NmapInstallerUrl {
    Enable-Tls12

    Write-Info "Procurando instalador oficial do Nmap..."

    $downloadPageUrl = "https://nmap.org/download.html"
    $page = Invoke-WebRequest -Uri $downloadPageUrl -UseBasicParsing

    $absoluteMatches = [regex]::Matches(
        $page.Content,
        'https://nmap\.org/dist/nmap-[0-9\.]+-setup\.exe'
    )

    if ($absoluteMatches.Count -gt 0) {
        return $absoluteMatches[0].Value
    }

    $relativeMatches = [regex]::Matches(
        $page.Content,
        'href="(/dist/nmap-[0-9\.]+-setup\.exe)"'
    )

    if ($relativeMatches.Count -gt 0) {
        return "https://nmap.org" + $relativeMatches[0].Groups[1].Value
    }

    throw "Nao consegui encontrar o instalador do Nmap na pagina oficial."
}

function Download-FileWithProgress {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$Destination
    )

    Enable-Tls12

    if (Test-Path $Destination) {
        Remove-Item $Destination -Force
    }

    Write-Info "Baixando Nmap..."
    Write-Host "    $Url" -ForegroundColor DarkGray

    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.UserAgent = "LanScout-Network"
    $response = $request.GetResponse()

    $totalBytes = $response.ContentLength
    $responseStream = $response.GetResponseStream()

    $fileStream = [System.IO.File]::Create($Destination)

    try {
        $buffer = New-Object byte[] 8192
        $totalRead = 0
        $read = 0

        do {
            $read = $responseStream.Read($buffer, 0, $buffer.Length)

            if ($read -gt 0) {
                $fileStream.Write($buffer, 0, $read)
                $totalRead += $read

                if ($totalBytes -gt 0) {
                    $percent = [math]::Round(($totalRead / $totalBytes) * 100, 0)
                    $mbRead = [math]::Round($totalRead / 1MB, 2)
                    $mbTotal = [math]::Round($totalBytes / 1MB, 2)

                    Write-Progress `
                        -Activity "Baixando Nmap" `
                        -Status "$mbRead MB de $mbTotal MB" `
                        -PercentComplete $percent
                }
                else {
                    $mbRead = [math]::Round($totalRead / 1MB, 2)

                    Write-Progress `
                        -Activity "Baixando Nmap" `
                        -Status "$mbRead MB baixados" `
                        -PercentComplete 0
                }
            }
        } while ($read -gt 0)
    }
    finally {
        $fileStream.Close()
        $responseStream.Close()
        $response.Close()
        Write-Progress -Activity "Baixando Nmap" -Completed
    }

    if (-not (Test-Path $Destination)) {
        throw "Download falhou: arquivo nao encontrado."
    }

    $sizeMb = [math]::Round((Get-Item $Destination).Length / 1MB, 2)
    Write-Ok "Download concluido: $sizeMb MB"
}

function Install-NmapOfficial {
    $url = Get-NmapInstallerUrl
    $installerName = [IO.Path]::GetFileName($url)
    $installerPath = Join-Path $env:TEMP $installerName

    Download-FileWithProgress -Url $url -Destination $installerPath

    Write-Info "Executando instalador do Nmap..."
    Write-Host "    Se aparecer a tela do instalador, avance normalmente." -ForegroundColor DarkGray
    Write-Host "    Recomendo manter o Npcap marcado." -ForegroundColor DarkGray
    Write-Host ""

    $process = Start-Process -FilePath $installerPath -Wait -PassThru

    Write-Info "Instalador finalizado com codigo: $($process.ExitCode)"

    Update-CurrentPath
    Start-Sleep -Seconds 2

    $nmap = Get-NmapCommand
    if ($nmap) {
        Write-Ok "Nmap instalado: $nmap"
        return $true
    }

    return $false
}

function Ensure-Nmap {
    $nmap = Get-NmapCommand
    if ($nmap) {
        Write-Ok "Nmap encontrado: $nmap"
        return $nmap
    }

    if (-not $AutoInstallNmap) {
        throw "Nmap nao encontrado."
    }

    Write-Warn "Nmap nao encontrado. Vou baixar/instalar automaticamente."

    $installedByWinget = Install-NmapWinget

    if (-not $installedByWinget) {
        Write-Warn "Winget nao instalou o Nmap. Vou tentar download oficial."
        $installedOfficial = Install-NmapOfficial

        if (-not $installedOfficial) {
            throw "Nmap nao foi encontrado depois da instalacao. Feche e abra o PowerShell e rode novamente."
        }
    }

    Update-CurrentPath
    Start-Sleep -Seconds 2

    $nmap = Get-NmapCommand
    if (-not $nmap) {
        throw "Nmap ainda nao foi encontrado. Feche e abra o PowerShell e rode novamente."
    }

    return $nmap
}

# ============================================================
# Detectar rede local sem UInt64
# ============================================================

function Get-PrimaryIPv4 {
    $configs = Get-CimInstance Win32_NetworkAdapterConfiguration |
        Where-Object {
            $_.IPEnabled -eq $true -and
            $_.DefaultIPGateway -and
            $_.IPAddress
        }

    foreach ($cfg in $configs) {
        $ipv4 = @($cfg.IPAddress | Where-Object {
            $_ -match '^\d{1,3}(\.\d{1,3}){3}$' -and
            $_ -notmatch '^169\.254\.'
        })[0]

        if ($ipv4) {
            return $ipv4
        }
    }

    throw "Nao encontrei uma placa de rede ativa com IPv4 e gateway."
}

function Get-DefaultRange24 {
    $ip = Get-PrimaryIPv4
    $parts = $ip.Split(".")

    if ($parts.Count -ne 4) {
        throw "IPv4 invalido: $ip"
    }

    return "$($parts[0]).$($parts[1]).$($parts[2]).0/24"
}

function Convert-IPToSortNumber {
    param([string]$IP)

    try {
        $p = $IP.Split(".")
        if ($p.Count -ne 4) {
            return 0
        }

        return ([int]$p[0] * 16777216) + ([int]$p[1] * 65536) + ([int]$p[2] * 256) + [int]$p[3]
    }
    catch {
        return 0
    }
}

# ============================================================
# Parse XML Nmap
# ============================================================

function Get-HostsFromDiscoveryXml {
    param([string]$XmlPath)

    $map = @{}

    if (-not (Test-Path $XmlPath)) {
        return $map
    }

    [xml]$xml = Get-Content $XmlPath

    foreach ($hostNode in $xml.nmaprun.host) {
        if ($hostNode.status.state -ne "up") {
            continue
        }

        $ipv4Node = $hostNode.address | Where-Object { $_.addrtype -eq "ipv4" } | Select-Object -First 1
        if (-not $ipv4Node) {
            continue
        }

        $ip = $ipv4Node.addr

        $macNode = $hostNode.address | Where-Object { $_.addrtype -eq "mac" } | Select-Object -First 1
        $hostnameNode = $hostNode.hostnames.hostname | Select-Object -First 1

        $map[$ip] = [PSCustomObject]@{
            IP = $ip
            Hostname = if ($hostnameNode.name) { $hostnameNode.name } else { "" }
            MAC = if ($macNode.addr) { $macNode.addr } else { "" }
            Fabricante = if ($macNode.vendor) { $macNode.vendor } else { "" }
            Status = "Online"
            PortasAbertas = ""
            SistemaProvavel = ""
            Tipo = ""
        }
    }

    return $map
}

function Merge-PortScanXml {
    param(
        [hashtable]$Hosts,
        [string]$XmlPath
    )

    if (-not (Test-Path $XmlPath)) {
        return $Hosts
    }

    [xml]$xml = Get-Content $XmlPath

    foreach ($hostNode in $xml.nmaprun.host) {
        if ($hostNode.status.state -ne "up") {
            continue
        }

        $ipv4Node = $hostNode.address | Where-Object { $_.addrtype -eq "ipv4" } | Select-Object -First 1
        if (-not $ipv4Node) {
            continue
        }

        $ip = $ipv4Node.addr

        if (-not $Hosts.ContainsKey($ip)) {
            $Hosts[$ip] = [PSCustomObject]@{
                IP = $ip
                Hostname = ""
                MAC = ""
                Fabricante = ""
                Status = "Online"
                PortasAbertas = ""
                SistemaProvavel = ""
                Tipo = ""
            }
        }

        $hostnameNode = $hostNode.hostnames.hostname | Select-Object -First 1
        if ($hostnameNode.name -and -not $Hosts[$ip].Hostname) {
            $Hosts[$ip].Hostname = $hostnameNode.name
        }

        $macNode = $hostNode.address | Where-Object { $_.addrtype -eq "mac" } | Select-Object -First 1
        if ($macNode.addr -and -not $Hosts[$ip].MAC) {
            $Hosts[$ip].MAC = $macNode.addr
        }

        if ($macNode.vendor -and -not $Hosts[$ip].Fabricante) {
            $Hosts[$ip].Fabricante = $macNode.vendor
        }

        $openPorts = @()

        foreach ($portNode in $hostNode.ports.port) {
            if ($portNode.state.state -eq "open") {
                $port = $portNode.portid
                $proto = $portNode.protocol
                $service = $portNode.service.name
                $product = $portNode.service.product
                $version = $portNode.service.version

                $label = "$port/$proto"

                if ($service) {
                    $label += " $service"
                }

                if ($product) {
                    $label += " $product"
                }

                if ($version) {
                    $label += " $version"
                }

                $openPorts += $label
            }
        }

        if ($openPorts.Count -gt 0) {
            $Hosts[$ip].PortasAbertas = ($openPorts -join "; ")
        }

        if ($hostNode.os.osmatch) {
            $osGuess = ($hostNode.os.osmatch | Select-Object -First 1).name
            if ($osGuess) {
                $Hosts[$ip].SistemaProvavel = $osGuess
            }
        }
    }

    return $Hosts
}

# ============================================================
# HTML
# ============================================================

function New-HtmlReport {
    param(
        [array]$Rows,
        [string]$Range,
        [string]$Path
    )

    $date = Get-Date -Format "dd/MM/yyyy HH:mm:ss"

    $style = @"
<style>
body {
    font-family: Segoe UI, Arial, sans-serif;
    background: #0f172a;
    color: #e5e7eb;
    margin: 24px;
}
h1 {
    color: #38bdf8;
}
.card {
    background: #111827;
    border: 1px solid #334155;
    border-radius: 12px;
    padding: 16px;
    margin-bottom: 18px;
}
table {
    border-collapse: collapse;
    width: 100%;
    background: #020617;
}
th {
    background: #1e293b;
    color: #f8fafc;
    padding: 10px;
    text-align: left;
}
td {
    border-bottom: 1px solid #334155;
    padding: 9px;
    vertical-align: top;
}
tr:hover {
    background: #111827;
}
.badge {
    display: inline-block;
    background: #16a34a;
    color: white;
    border-radius: 999px;
    padding: 2px 8px;
    font-size: 12px;
}
.small {
    color: #94a3b8;
}
</style>
"@

    $rowsHtml = ""

    foreach ($r in $Rows) {
        $rowsHtml += "<tr>"
        $rowsHtml += "<td>$($r.IP)</td>"
        $rowsHtml += "<td>$($r.Hostname)</td>"
        $rowsHtml += "<td>$($r.MAC)</td>"
        $rowsHtml += "<td>$($r.Fabricante)</td>"
        $rowsHtml += "<td><span class='badge'>$($r.Status)</span></td>"
        $rowsHtml += "<td>$($r.PortasAbertas)</td>"
        $rowsHtml += "<td>$($r.SistemaProvavel)</td>"
        $rowsHtml += "</tr>"
    }

    $html = @"
<!doctype html>
<html lang="pt-br">
<head>
<meta charset="utf-8">
<title>LanScout Network</title>
$style
</head>
<body>
<h1>LanScout Network</h1>

<div class="card">
    <p><b>Rede:</b> $Range</p>
    <p><b>Data:</b> $date</p>
    <p><b>Dispositivos online:</b> $($Rows.Count)</p>
</div>

<table>
<thead>
<tr>
    <th>IP</th>
    <th>Hostname</th>
    <th>MAC</th>
    <th>Fabricante</th>
    <th>Status</th>
    <th>Portas abertas</th>
    <th>Sistema provável</th>
</tr>
</thead>
<tbody>
$rowsHtml
</tbody>
</table>

<p class="small">Use somente em redes onde você tem autorização.</p>
</body>
</html>
"@

    $html | Set-Content -Path $Path -Encoding UTF8
}

# ============================================================
# Scan
# ============================================================

function Invoke-LanScoutScan {
    param(
        [Parameter(Mandatory=$true)][string]$NmapPath,
        [Parameter(Mandatory=$true)][string]$TargetRange,
        [Parameter(Mandatory=$true)][string]$Ports,
        [bool]$DeepScan
    )

    $desktop = [Environment]::GetFolderPath("Desktop")

    if (-not $desktop -or -not (Test-Path $desktop)) {
        $desktop = $env:USERPROFILE
    }

    $outDir = Join-Path $desktop "LanScout_Results"
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"

    $discoveryXml = Join-Path $outDir "lanscout_discovery_$stamp.xml"
    $scanXml = Join-Path $outDir "lanscout_scan_$stamp.xml"
    $txtPath = Join-Path $outDir "lanscout_$stamp.txt"
    $csvPath = Join-Path $outDir "lanscout_$stamp.csv"
    $htmlPath = Join-Path $outDir "lanscout_$stamp.html"

    Write-Info "Rede alvo: $TargetRange"
    Write-Info "Fase 1/2: descobrindo dispositivos online..."
    Write-Host ""

    $discoveryArgs = @(
        "-sn",
        "-T4",
        "-oX", $discoveryXml,
        $TargetRange
    )

    Write-Host "    $NmapPath $($discoveryArgs -join ' ')" -ForegroundColor DarkGray
    Write-Host ""

    $p1 = Start-Process `
        -FilePath $NmapPath `
        -ArgumentList $discoveryArgs `
        -NoNewWindow `
        -Wait `
        -PassThru

    if ($p1.ExitCode -ne 0) {
        Write-Warn "A descoberta retornou codigo $($p1.ExitCode). Vou tentar continuar."
    }

    $hosts = Get-HostsFromDiscoveryXml -XmlPath $discoveryXml

    Write-Info "Fase 2/2: verificando portas comuns..."
    Write-Host ""

    if ($DeepScan) {
        $scanArgs = @(
            "-A",
            "-T4",
            "--open",
            "-p", $Ports,
            "-oX", $scanXml,
            "-oN", $txtPath,
            $TargetRange
        )
    }
    else {
        $scanArgs = @(
            "-sV",
            "-T4",
            "--open",
            "-p", $Ports,
            "-oX", $scanXml,
            "-oN", $txtPath,
            $TargetRange
        )
    }

    Write-Host "    $NmapPath $($scanArgs -join ' ')" -ForegroundColor DarkGray
    Write-Host ""

    $p2 = Start-Process `
        -FilePath $NmapPath `
        -ArgumentList $scanArgs `
        -NoNewWindow `
        -Wait `
        -PassThru

    if ($p2.ExitCode -ne 0) {
        Write-Warn "O scan de portas retornou codigo $($p2.ExitCode). Vou tentar ler os resultados."
    }

    $hosts = Merge-PortScanXml -Hosts $hosts -XmlPath $scanXml

    $rows = @($hosts.Values) | Sort-Object @{ Expression = { Convert-IPToSortNumber $_.IP } }

    if ($rows.Count -eq 0) {
        Write-Warn "Nenhum dispositivo encontrado. Tente executar como Administrador."
    }
    else {
        Write-Host ""
        Write-Ok "Dispositivos encontrados:"
        Write-Host ""

        $rows | Format-Table IP, Hostname, MAC, Fabricante, Status, PortasAbertas -AutoSize
    }

    $rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

    New-HtmlReport -Rows $rows -Range $TargetRange -Path $htmlPath

    Write-Host ""
    Write-Ok "Total encontrados: $($rows.Count)"
    Write-Ok "Relatorios gerados:"
    Write-Host "    TXT : $txtPath" -ForegroundColor Green
    Write-Host "    CSV : $csvPath" -ForegroundColor Green
    Write-Host "    HTML: $htmlPath" -ForegroundColor Green

    if ($OpenResults -and (Test-Path $htmlPath)) {
        Start-Process $htmlPath
    }
}

# ============================================================
# Main
# ============================================================

try {
    Write-Title

    Write-Warn "Use somente em redes suas ou onde voce tem autorizacao."
    Write-Host ""

    if (-not (Test-Admin)) {
        Write-Warn "Recomendo executar o PowerShell como Administrador para detectar melhor MAC/fabricante."
        Write-Host ""
    }

    $range = Get-DefaultRange24
    Write-Info "Rede detectada automaticamente: $range"

    $nmapPath = Ensure-Nmap

    Write-Host ""
    Invoke-LanScoutScan `
        -NmapPath $nmapPath `
        -TargetRange $range `
        -Ports $DefaultPorts `
        -DeepScan $UseDeepScan

    Write-Host ""
    Write-Ok "Concluido."
}
catch {
    Write-Host ""
    Write-Bad $_.Exception.Message
    Write-Host ""
    Write-Host "Dicas:" -ForegroundColor Yellow
    Write-Host "1. Execute o PowerShell como Administrador."
    Write-Host "2. Verifique sua internet para baixar o Nmap."
    Write-Host "3. Se o Nmap instalou agora e nao foi detectado, feche e abra o PowerShell."
    Write-Host "4. Depois rode novamente:"
    Write-Host "   irm https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/network.ps1 | iex"
    exit 1
}
