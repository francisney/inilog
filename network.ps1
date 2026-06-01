<#
.SYNOPSIS
  LanScout Pro - Scanner de rede local para Windows 10/11 usando Nmap.

.DESCRIPTION
  - Detecta automaticamente a rede local ativa.
  - Instala Nmap via winget se solicitado.
  - Faz descoberta de dispositivos online.
  - Opcionalmente faz scan de portas comuns/servicos.
  - Exporta CSV, JSON e HTML para a Area de Trabalho.

.USO
  powershell -ExecutionPolicy Bypass -File .\LanScout-Pro-Win10-11.ps1 -InstallNmap -OpenResults
  .\LanScout-Pro-Win10-11.ps1
  .\LanScout-Pro-Win10-11.ps1 -Range 192.168.0.0/24 -Deep -OpenResults
#>

[CmdletBinding()]
param(
    [string]$Range,
    [string]$Ports = "21,22,23,25,53,80,110,135,139,143,443,445,554,587,631,993,995,1433,3306,3389,5000,5432,5900,5985,8000,8080,8443,9100",
    [switch]$Deep,
    [switch]$InstallNmap,
    [switch]$OpenResults,
    [switch]$NoInstallPrompt
)

$ErrorActionPreference = "Stop"

function Write-Title {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " LanScout Pro - Scanner de Rede Local para Windows 10/11" -ForegroundColor Cyan
    Write-Host " Descoberta de PCs/dispositivos + portas + relatorios" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-NmapPath {
    $cmd = Get-Command nmap.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        "$env:ProgramFiles\Nmap\nmap.exe",
        "${env:ProgramFiles(x86)}\Nmap\nmap.exe"
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

function Install-NmapWinget {
    Write-Host "[*] Verificando winget..." -ForegroundColor Yellow
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "winget nao encontrado. Instale o 'App Installer' pela Microsoft Store ou instale o Nmap manualmente em https://nmap.org/download.html"
    }

    Write-Host "[*] Instalando Nmap via winget..." -ForegroundColor Yellow
    Write-Host "    Comando: winget install -e --id Insecure.Nmap" -ForegroundColor DarkGray
    & winget install -e --id Insecure.Nmap --accept-package-agreements --accept-source-agreements

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Get-ActiveIPv4Config {
    $configs = Get-NetIPConfiguration | Where-Object {
        $_.IPv4Address -and
        $_.NetAdapter.Status -eq "Up" -and
        $_.IPv4Address.IPAddress -notlike "169.254.*"
    }

    $preferred = $configs | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1
    if (-not $preferred) { $preferred = $configs | Select-Object -First 1 }
    if (-not $preferred) { throw "Nao encontrei uma interface IPv4 ativa." }

    return [PSCustomObject]@{
        IP = $preferred.IPv4Address.IPAddress
        PrefixLength = [int]$preferred.IPv4Address.PrefixLength
        InterfaceAlias = $preferred.InterfaceAlias
        Gateway = if ($preferred.IPv4DefaultGateway) { $preferred.IPv4DefaultGateway.NextHop } else { "" }
    }
}

function Get-DefaultRange {
    $cfg = Get-ActiveIPv4Config
    $ip = [string]$cfg.IP
    $prefix = [int]$cfg.PrefixLength

    # Evita calculo binario complexo. Para Nmap, IP/prefixo e valido e seguro.
    $range = "$ip/$prefix"

    Write-Host "[*] Interface: $($cfg.InterfaceAlias)" -ForegroundColor DarkGray
    Write-Host "[*] IP local : $($cfg.IP)" -ForegroundColor DarkGray
    Write-Host "[*] Gateway  : $($cfg.Gateway)" -ForegroundColor DarkGray
    Write-Host "[*] Rede     : $range" -ForegroundColor DarkGray
    Write-Host ""

    return $range
}

function Get-OutputFolder {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $folder = Join-Path $desktop "LanScout_Results"
    if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }
    return $folder
}

function Invoke-NmapXml {
    param(
        [Parameter(Mandatory=$true)][string]$NmapPath,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [Parameter(Mandatory=$true)][string]$XmlPath
    )

    if (Test-Path $XmlPath) { Remove-Item $XmlPath -Force }
    $fullArgs = @($Arguments + @("-oX", $XmlPath))

    Write-Host "[*] Executando: nmap $($fullArgs -join ' ')" -ForegroundColor Yellow
    & $NmapPath @fullArgs

    if (-not (Test-Path $XmlPath)) {
        throw "O Nmap nao gerou o XML esperado: $XmlPath"
    }

    [xml](Get-Content $XmlPath -Raw)
}

function Parse-NmapHosts {
    param([xml]$Xml)

    $items = New-Object System.Collections.Generic.List[object]

    foreach ($host in $Xml.nmaprun.host) {
        if (-not $host.status -or $host.status.state -ne "up") { continue }

        $ipv4Node = @($host.address | Where-Object { $_.addrtype -eq "ipv4" }) | Select-Object -First 1
        if (-not $ipv4Node) { continue }

        $macNode = @($host.address | Where-Object { $_.addrtype -eq "mac" }) | Select-Object -First 1
        $hostnameNode = $null
        if ($host.hostnames -and $host.hostnames.hostname) {
            $hostnameNode = @($host.hostnames.hostname) | Select-Object -First 1
        }

        $openPorts = @()
        if ($host.ports -and $host.ports.port) {
            foreach ($p in @($host.ports.port)) {
                if ($p.state.state -eq "open") {
                    $svc = ""
                    if ($p.service) {
                        $svcParts = @()
                        if ($p.service.name) { $svcParts += $p.service.name }
                        if ($p.service.product) { $svcParts += $p.service.product }
                        if ($p.service.version) { $svcParts += $p.service.version }
                        $svc = ($svcParts -join " ").Trim()
                    }
                    if ($svc) { $openPorts += "$($p.portid)/$($p.protocol) $svc" }
                    else { $openPorts += "$($p.portid)/$($p.protocol)" }
                }
            }
        }

        $osGuess = ""
        if ($host.os -and $host.os.osmatch) {
            $os = @($host.os.osmatch) | Sort-Object { [int]$_.accuracy } -Descending | Select-Object -First 1
            if ($os) { $osGuess = "$($os.name) ($($os.accuracy)%)" }
        }

        $items.Add([PSCustomObject]@{
            IP = [string]$ipv4Node.addr
            Hostname = if ($hostnameNode) { [string]$hostnameNode.name } else { "" }
            MAC = if ($macNode) { [string]$macNode.addr } else { "" }
            Fabricante = if ($macNode -and $macNode.vendor) { [string]$macNode.vendor } else { "" }
            PortasAbertas = ($openPorts -join ", ")
            SistemaProvavel = $osGuess
            Status = "Online"
        }) | Out-Null
    }

    return $items | Sort-Object {[version]$_.IP}
}

function Write-Reports {
    param(
        [Parameter(Mandatory=$true)]$Data,
        [Parameter(Mandatory=$true)][string]$Folder
    )

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $csv = Join-Path $Folder "lanscout_$stamp.csv"
    $json = Join-Path $Folder "lanscout_$stamp.json"
    $html = Join-Path $Folder "lanscout_$stamp.html"

    $Data | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csv
    $Data | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -Path $json

    $style = @"
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:24px;background:#f6f7fb;color:#222}
h1{color:#0f4c81}.meta{color:#555;margin-bottom:16px}
table{border-collapse:collapse;width:100%;background:white;box-shadow:0 1px 4px #ccc}
th,td{border:1px solid #ddd;padding:8px;text-align:left;font-size:13px;vertical-align:top}
th{background:#0f4c81;color:white;position:sticky;top:0}
tr:nth-child(even){background:#f2f6fb}.online{font-weight:bold;color:#087a2a}
</style>
"@
    $pre = "<h1>LanScout Pro</h1><div class='meta'>Gerado em $(Get-Date) | Total online: $(@($Data).Count)</div>"
    $body = $Data | ConvertTo-Html -Head $style -PreContent $pre -Title "LanScout Pro" | Out-String
    $body = $body -replace '<td>Online</td>', '<td class="online">Online</td>'
    Set-Content -Encoding UTF8 -Path $html -Value $body

    return [PSCustomObject]@{ CSV=$csv; JSON=$json; HTML=$html }
}

function Invoke-PowerShellFallback {
    param([string]$RangeText)

    Write-Host "[!] Nmap nao encontrado. Usando modo PowerShell basico." -ForegroundColor Yellow
    Write-Host "[!] Para resultado estilo Advanced IP Scanner, instale/use Nmap." -ForegroundColor Yellow

    # Fallback apenas para /24 simples. Ex.: 192.168.0.10/24 => 192.168.0.1-254
    if ($RangeText -notmatch '^(\d{1,3}\.\d{1,3}\.\d{1,3})\.\d{1,3}/24$' -and $RangeText -notmatch '^(\d{1,3}\.\d{1,3}\.\d{1,3})\.0/24$') {
        throw "Modo PowerShell basico suporta apenas /24. Instale o Nmap ou informe algo como 192.168.0.0/24."
    }
    $base = $Matches[1]

    $jobs = foreach ($i in 1..254) {
        $target = "$base.$i"
        Start-Job -ScriptBlock {
            param($ip)
            $online = Test-Connection -ComputerName $ip -Count 1 -Quiet -TimeoutSeconds 1 -ErrorAction SilentlyContinue
            if ($online) {
                $name = ""
                try { $name = ([System.Net.Dns]::GetHostEntry($ip)).HostName } catch {}
                [PSCustomObject]@{ IP=$ip; Hostname=$name; MAC=""; Fabricante=""; PortasAbertas=""; SistemaProvavel=""; Status="Online" }
            }
        } -ArgumentList $target
    }

    $results = $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job -Force
    return $results | Sort-Object {[version]$_.IP}
}

Write-Title

if (-not (Test-IsAdmin)) {
    Write-Host "[!] Dica: execute como Administrador para melhor descoberta de MAC/OS." -ForegroundColor Yellow
    Write-Host ""
}

if (-not $Range) { $Range = Get-DefaultRange }

$outputFolder = Get-OutputFolder
$nmap = Get-NmapPath

if ($InstallNmap -or (-not $nmap -and -not $NoInstallPrompt)) {
    if (-not $nmap) {
        Install-NmapWinget
        $nmap = Get-NmapPath
    }
}

$data = @()

if ($nmap) {
    Write-Host "[*] Nmap encontrado: $nmap" -ForegroundColor Green
    Write-Host "[*] Alvo: $Range" -ForegroundColor Green
    Write-Host ""

    $xmlPath = Join-Path $outputFolder "nmap_scan.xml"

    if ($Deep) {
        # -O precisa de admin em muitos casos. Se falhar, tenta sem -O.
        try {
            $args = @("-sV", "-O", "--osscan-guess", "-T4", "--open", "-p", $Ports, $Range)
            $xml = Invoke-NmapXml -NmapPath $nmap -Arguments $args -XmlPath $xmlPath
        } catch {
            Write-Host "[!] Scan com deteccao de SO falhou. Tentando sem -O..." -ForegroundColor Yellow
            $args = @("-sV", "-T4", "--open", "-p", $Ports, $Range)
            $xml = Invoke-NmapXml -NmapPath $nmap -Arguments $args -XmlPath $xmlPath
        }
    } else {
        # Descoberta rapida + portas comuns para ficar util no terminal.
        $args = @("-T4", "--open", "-p", $Ports, $Range)
        $xml = Invoke-NmapXml -NmapPath $nmap -Arguments $args -XmlPath $xmlPath
    }

    $data = @(Parse-NmapHosts -Xml $xml)
} else {
    $data = @(Invoke-PowerShellFallback -RangeText $Range)
}

Write-Host ""
Write-Host "==================== DISPOSITIVOS ENCONTRADOS ====================" -ForegroundColor Cyan
if ($data.Count -eq 0) {
    Write-Host "Nenhum dispositivo encontrado. Tente executar como Administrador ou use -Range manual." -ForegroundColor Yellow
} else {
    $data | Format-Table IP, Hostname, MAC, Fabricante, PortasAbertas, SistemaProvavel -AutoSize
}

$reports = Write-Reports -Data $data -Folder $outputFolder

Write-Host ""
Write-Host "==================== RELATORIOS ====================" -ForegroundColor Cyan
Write-Host "CSV : $($reports.CSV)" -ForegroundColor Green
Write-Host "JSON: $($reports.JSON)" -ForegroundColor Green
Write-Host "HTML: $($reports.HTML)" -ForegroundColor Green

if ($OpenResults -and (Test-Path $reports.HTML)) {
    Start-Process $reports.HTML
}

Write-Host ""
Write-Host "[+] Finalizado." -ForegroundColor Green
