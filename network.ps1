<#
.SYNOPSIS
    LanScout Pro - Scanner de rede local para Windows 10/11 usando Nmap quando disponivel.

.DESCRIPTION
    Estilo Advanced IP Scanner no terminal: instala/verifica Nmap, detecta a rede local,
    descobre dispositivos online, identifica MAC/fabricante/hostname e opcionalmente portas/servicos.

    Uso seguro: execute apenas na sua rede ou onde voce tem permissao.

.EXAMPLES
    powershell -ExecutionPolicy Bypass -File .\LanScout-Pro.ps1 -InstallNmap
    powershell -ExecutionPolicy Bypass -File .\LanScout-Pro.ps1
    powershell -ExecutionPolicy Bypass -File .\LanScout-Pro.ps1 -Range 192.168.0.0/24 -Deep
    powershell -ExecutionPolicy Bypass -File .\LanScout-Pro.ps1 -Range 192.168.1.0/24 -Ports "80,443,445,3389,8080"
#>

[CmdletBinding()]
param(
    [string]$Range,
    [switch]$InstallNmap,
    [switch]$Deep,
    [string]$Ports = "21,22,23,53,80,135,139,443,445,3389,5357,5900,8080,8443,9100",
    [string]$ExportDir = "$env:USERPROFILE\Desktop\LanScout_Results",
    [switch]$OpenResults,
    [switch]$NoHtml,
    [switch]$FallbackOnly
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host " LanScout Pro - Scanner de Rede Local para Windows 10/11" -ForegroundColor Cyan
    Write-Host " Descoberta de PCs/dispositivos + portas + relatorios" -ForegroundColor Gray
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host ""
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-Nmap {
    $cmd = Get-Command nmap.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        "$env:ProgramFiles\Nmap\nmap.exe",
        "${env:ProgramFiles(x86)}\Nmap\nmap.exe",
        "$env:LOCALAPPDATA\Programs\Nmap\nmap.exe"
    )

    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }

    return $null
}

function Install-NmapWinget {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "winget nao foi encontrado. Atualize o 'App Installer' pela Microsoft Store ou instale o Nmap manualmente em https://nmap.org/download.html"
    }

    if (-not (Test-IsAdmin)) {
        Write-Host "[*] A instalacao do Nmap/Npcap pode precisar de Administrador. Abrindo janela elevada..." -ForegroundColor Yellow
        $args = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$PSCommandPath`"",
            "-InstallNmap"
        )
        if ($Range) { $args += @("-Range", $Range) }
        if ($Deep) { $args += "-Deep" }
        if ($Ports) { $args += @("-Ports", $Ports) }
        if ($OpenResults) { $args += "-OpenResults" }
        Start-Process powershell.exe -Verb RunAs -ArgumentList ($args -join " ")
        exit
    }

    Write-Host "[*] Instalando Nmap via winget..." -ForegroundColor Cyan
    & winget install -e --id Insecure.Nmap --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "A instalacao pelo winget falhou. Tente instalar manualmente pelo site oficial do Nmap."
    }

    $env:Path += ";$env:ProgramFiles\Nmap"
    Write-Host "[+] Nmap instalado/verificado." -ForegroundColor Green
}

function Get-PrimaryNetworkCidr {
    try {
        $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop |
            Where-Object { $_.NextHop -and $_.NextHop -ne "0.0.0.0" } |
            Sort-Object RouteMetric, InterfaceMetric |
            Select-Object -First 1

        if ($route) {
            $ipInfo = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object { $_.IPAddress -notlike "169.254.*" -and $_.IPAddress -ne "127.0.0.1" } |
                Select-Object -First 1
            if ($ipInfo) {
                return ConvertTo-NetworkCidr -IPAddress $ipInfo.IPAddress -PrefixLength $ipInfo.PrefixLength
            }
        }
    } catch {}

    $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "169.254.*" -and $_.IPAddress -ne "127.0.0.1" -and $_.PrefixLength -le 30 } |
        Sort-Object PrefixLength -Descending |
        Select-Object -First 1)

    if ($ip) { return ConvertTo-NetworkCidr -IPAddress $ip.IPAddress -PrefixLength $ip.PrefixLength }

    throw "Nao consegui detectar automaticamente sua rede. Use -Range, exemplo: -Range 192.168.0.0/24"
}

function ConvertTo-NetworkCidr {
    param([string]$IPAddress, [int]$PrefixLength)
    $bytes = ([System.Net.IPAddress]::Parse($IPAddress)).GetAddressBytes()
    [Array]::Reverse($bytes)
    $ipInt = [BitConverter]::ToUInt32($bytes, 0)

    $mask = if ($PrefixLength -eq 0) { [uint32]0 } else { [uint32]([uint64]0xffffffff -shl (32 - $PrefixLength)) }
    $networkInt = $ipInt -band $mask
    $netBytes = [BitConverter]::GetBytes($networkInt)
    [Array]::Reverse($netBytes)
    $network = ([System.Net.IPAddress]::new($netBytes)).ToString()
    return "$network/$PrefixLength"
}

function Get-VendorFromMac {
    param([string]$Mac)
    if (-not $Mac) { return "" }
    $prefix = ($Mac -replace "[:-]", "").ToUpper()
    if ($prefix.Length -lt 6) { return "" }
    $oui = $prefix.Substring(0,6)

    $vendors = @{
        "001A11"="Google/Nest"; "3C5A37"="Google"; "F4F5D8"="Google";
        "B827EB"="Raspberry Pi"; "DCA632"="Raspberry Pi"; "E45F01"="Raspberry Pi";
        "F0D5BF"="Intelbras"; "001B11"="D-Link"; "00195B"="D-Link";
        "F8D111"="TP-Link"; "50C7BF"="TP-Link"; "14CC20"="TP-Link"; "D8EB97"="TP-Link";
        "A4CA A0"="Huawei"; "F4F1E1"="Huawei"; "001E10"="Samsung"; "5C0A5B"="Samsung";
        "001A79"="Apple"; "F0D1A9"="Apple"; "3C0754"="Apple"; "A4D18C"="Apple";
        "00155D"="Microsoft Hyper-V"; "000C29"="VMware"; "005056"="VMware"; "080027"="VirtualBox";
        "001E8C"="ASUSTek"; "10BF48"="ASUSTek"; "2C56DC"="ASUSTek";
        "001E06"="Wistron"; "B0A7B9"="HP"; "3C52A1"="HP"; "F40343"="Dell"; "001422"="Dell";
        "FC3497"="Lenovo"; "60A44C"="ASRock"; "D05099"="ASRock";
        "FCF528"="Zyxel"; "C83A35"="Tenda"; "E8DE27"="Tenda"; "A0F3C1"="Ubiquiti"; "788A20"="Ubiquiti"
    }

    if ($vendors.ContainsKey($oui)) { return $vendors[$oui] }
    return ""
}

function Parse-NmapXml {
    param([string]$XmlPath)
    [xml]$xml = Get-Content $XmlPath -Raw
    $items = @()

    foreach ($host in $xml.nmaprun.host) {
        $state = $host.status.state
        if ($state -ne "up") { continue }

        $ipv4Node = @($host.address | Where-Object { $_.addrtype -eq "ipv4" } | Select-Object -First 1)
        $macNode  = @($host.address | Where-Object { $_.addrtype -eq "mac" } | Select-Object -First 1)
        $nameNode = @($host.hostnames.hostname | Select-Object -First 1)

        $openPorts = @()
        if ($host.ports.port) {
            foreach ($p in $host.ports.port) {
                if ($p.state.state -eq "open") {
                    $svc = $p.service.name
                    $product = $p.service.product
                    $version = $p.service.version
                    $desc = "$($p.protocol)/$($p.portid)"
                    if ($svc) { $desc += " $svc" }
                    if ($product) { $desc += " - $product" }
                    if ($version) { $desc += " $version" }
                    $openPorts += $desc
                }
            }
        }

        $osGuess = ""
        if ($host.os.osmatch) {
            $osGuess = (@($host.os.osmatch | Select-Object -First 1).name)
        }

        $ip = if ($ipv4Node) { $ipv4Node.addr } else { "" }
        $mac = if ($macNode) { $macNode.addr } else { "" }
        $vendor = if ($macNode.vendor) { $macNode.vendor } else { Get-VendorFromMac -Mac $mac }
        $hostname = if ($nameNode.name) { $nameNode.name } else { "" }

        $sharesHint = if (($openPorts -join ",") -match "445|139") { "\\$ip" } else { "" }
        $rdpHint = if (($openPorts -join ",") -match "3389") { "mstsc /v:$ip" } else { "" }
        $webHint = ""
        if (($openPorts -join ",") -match "tcp/80\b") { $webHint = "http://$ip" }
        elseif (($openPorts -join ",") -match "tcp/443\b") { $webHint = "https://$ip" }
        elseif (($openPorts -join ",") -match "tcp/8080\b") { $webHint = "http://$ip`:8080" }

        $items += [pscustomobject]@{
            IP = $ip
            Hostname = $hostname
            MAC = $mac
            Fabricante = $vendor
            PortasAbertas = ($openPorts -join "; ")
            SistemaProvavel = $osGuess
            Web = $webHint
            Compartilhamento = $sharesHint
            RDP = $rdpHint
            Status = "Online"
        }
    }

    return $items | Sort-Object { [version]$_.IP }
}

function Invoke-NmapScan {
    param([string]$NmapPath, [string]$TargetRange, [bool]$DeepScan, [string]$PortsCsv, [string]$XmlOut)

    if ($DeepScan) {
        $args = @(
            "-sV", "-O", "--osscan-guess",
            "--open",
            "--top-ports", "100",
            "-T4",
            "-oX", $XmlOut,
            $TargetRange
        )
        if ($PortsCsv) {
            $args = @("-sV", "-O", "--osscan-guess", "--open", "-p", $PortsCsv, "-T4", "-oX", $XmlOut, $TargetRange)
        }
    } else {
        # Descoberta rapida + portas comuns, estilo inventario.
        $args = @(
            "-Pn",
            "--open",
            "-p", $PortsCsv,
            "-T4",
            "-oX", $XmlOut,
            $TargetRange
        )
    }

    Write-Host "[*] Executando: nmap $($args -join ' ')" -ForegroundColor DarkGray
    & $NmapPath @args
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] Nmap retornou codigo $LASTEXITCODE. Vou tentar scan de descoberta simples..." -ForegroundColor Yellow
        $args2 = @("-sn", "-T4", "-oX", $XmlOut, $TargetRange)
        & $NmapPath @args2
    }
}

function Invoke-FallbackScan {
    param([string]$TargetRange, [string]$PortsCsv)

    Write-Host "[*] Modo fallback PowerShell puro. Mais simples/lento que Nmap." -ForegroundColor Yellow
    if ($TargetRange -notmatch '^(\d+\.\d+\.\d+)\.0/24$') {
        throw "Fallback puro aceita apenas /24 simples, exemplo 192.168.0.0/24. Instale Nmap para ranges diferentes."
    }

    $base = $Matches[1]
    $ports = $PortsCsv.Split(',') | ForEach-Object { [int]$_.Trim() } | Where-Object { $_ -gt 0 -and $_ -le 65535 }
    $results = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

    1..254 | ForEach-Object -Parallel {
        $base = $using:base
        $ports = $using:ports
        $results = $using:results
        $ip = "$base.$_"
        $up = Test-Connection -ComputerName $ip -Count 1 -Quiet -TimeoutSeconds 1
        if ($up) {
            $open = @()
            foreach ($port in $ports) {
                try {
                    $client = [Net.Sockets.TcpClient]::new()
                    $task = $client.ConnectAsync($ip, $port)
                    if ($task.Wait(250) -and $client.Connected) { $open += "tcp/$port" }
                    $client.Dispose()
                } catch {}
            }
            $hostname = ""
            try { $hostname = ([System.Net.Dns]::GetHostEntry($ip)).HostName } catch {}
            $results.Add([pscustomobject]@{
                IP = $ip; Hostname = $hostname; MAC = ""; Fabricante = "";
                PortasAbertas = ($open -join "; "); SistemaProvavel = ""; Web = "";
                Compartilhamento = ""; RDP = ""; Status = "Online"
            })
        }
    } -ThrottleLimit 64

    return @($results) | Sort-Object { [version]$_.IP }
}

function New-HtmlReport {
    param([array]$Data, [string]$Path, [string]$TargetRange)
    $rows = foreach ($d in $Data) {
        $web = if ($d.Web) { "<a href='$($d.Web)'>$($d.Web)</a>" } else { "" }
        $share = if ($d.Compartilhamento) { $d.Compartilhamento } else { "" }
        "<tr><td>$($d.IP)</td><td>$($d.Hostname)</td><td>$($d.MAC)</td><td>$($d.Fabricante)</td><td>$($d.PortasAbertas)</td><td>$($d.SistemaProvavel)</td><td>$web</td><td>$share</td><td>$($d.RDP)</td></tr>"
    }

    $html = @"
<!doctype html>
<html lang="pt-br">
<head>
<meta charset="utf-8">
<title>LanScout Pro - Relatorio</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;background:#0f172a;color:#e5e7eb;margin:24px}
h1{color:#67e8f9}.card{background:#111827;border:1px solid #334155;border-radius:12px;padding:16px;margin-bottom:16px}
table{border-collapse:collapse;width:100%;background:#020617;border-radius:12px;overflow:hidden}
th,td{border-bottom:1px solid #1f2937;padding:10px;text-align:left;font-size:13px;vertical-align:top}
th{background:#164e63;color:#ecfeff;position:sticky;top:0}tr:hover{background:#111827}a{color:#93c5fd}
.badge{display:inline-block;background:#065f46;color:#d1fae5;border-radius:999px;padding:4px 10px}
</style>
</head>
<body>
<h1>LanScout Pro</h1>
<div class="card">
<span class="badge">Rede: $TargetRange</span>
<span class="badge">Dispositivos online: $($Data.Count)</span>
<span class="badge">Gerado: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')</span>
</div>
<table>
<thead><tr><th>IP</th><th>Hostname</th><th>MAC</th><th>Fabricante</th><th>Portas abertas</th><th>Sistema provavel</th><th>Web</th><th>Compartilhamento</th><th>RDP</th></tr></thead>
<tbody>
$($rows -join "`n")
</tbody>
</table>
</body>
</html>
"@
    Set-Content -Path $Path -Value $html -Encoding UTF8
}

Write-Banner

if ($InstallNmap) { Install-NmapWinget }

if (-not $Range) {
    $Range = Get-PrimaryNetworkCidr
    Write-Host "[*] Rede detectada automaticamente: $Range" -ForegroundColor Cyan
} else {
    Write-Host "[*] Rede informada: $Range" -ForegroundColor Cyan
}

New-Item -ItemType Directory -Force -Path $ExportDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$xmlPath  = Join-Path $ExportDir "lanscout_$stamp.xml"
$csvPath  = Join-Path $ExportDir "lanscout_$stamp.csv"
$jsonPath = Join-Path $ExportDir "lanscout_$stamp.json"
$htmlPath = Join-Path $ExportDir "lanscout_$stamp.html"

$nmap = if ($FallbackOnly) { $null } else { Find-Nmap }

if (-not $nmap) {
    Write-Host "[!] Nmap nao encontrado." -ForegroundColor Yellow
    Write-Host "    Para instalar e escanear automaticamente: .\LanScout-Pro.ps1 -InstallNmap" -ForegroundColor Yellow
    $data = Invoke-FallbackScan -TargetRange $Range -PortsCsv $Ports
} else {
    Write-Host "[+] Nmap encontrado: $nmap" -ForegroundColor Green
    Invoke-NmapScan -NmapPath $nmap -TargetRange $Range -DeepScan ([bool]$Deep) -PortsCsv $Ports -XmlOut $xmlPath
    $data = Parse-NmapXml -XmlPath $xmlPath
}

if (-not $data -or $data.Count -eq 0) {
    Write-Host "[!] Nenhum dispositivo encontrado. Tente executar como Administrador ou use -Deep/-Range." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "[+] Dispositivos encontrados: $($data.Count)" -ForegroundColor Green
    $data | Format-Table IP, Hostname, MAC, Fabricante, PortasAbertas, Web, Compartilhamento, RDP -AutoSize
}

$data | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
$data | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8
if (-not $NoHtml) { New-HtmlReport -Data $data -Path $htmlPath -TargetRange $Range }

Write-Host ""
Write-Host "[+] CSV : $csvPath" -ForegroundColor Green
Write-Host "[+] JSON: $jsonPath" -ForegroundColor Green
if (-not $NoHtml) { Write-Host "[+] HTML: $htmlPath" -ForegroundColor Green }
Write-Host ""
Write-Host "Dicas:" -ForegroundColor Cyan
Write-Host "  Scan rapido:  .\LanScout-Pro.ps1" -ForegroundColor Gray
Write-Host "  Instalar+scan: .\LanScout-Pro.ps1 -InstallNmap" -ForegroundColor Gray
Write-Host "  Profundo:     .\LanScout-Pro.ps1 -Deep" -ForegroundColor Gray
Write-Host "  Rede manual:  .\LanScout-Pro.ps1 -Range 192.168.0.0/24" -ForegroundColor Gray

if ($OpenResults -and (Test-Path $htmlPath)) {
    Start-Process $htmlPath
}
