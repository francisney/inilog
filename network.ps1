<#
LanScout SpeedStyle - Windows 10/11
Baixa o instalador oficial do Nmap com barra de progresso, executa a instalação e faz scan da rede local.
Use somente em redes onde você tem permissão.
#>

param(
    [string]$Range = "",
    [string]$Ports = "21,22,23,53,80,135,139,443,445,3389,8080,8443,9100",
    [switch]$Deep,
    [switch]$DownloadNmap,
    [switch]$OpenResults,
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Title {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " LanScout SpeedStyle - Scanner de Rede Local Windows 10/11" -ForegroundColor Cyan
    Write-Host " Baixa Nmap com porcentagem + scan + relatorios" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Test-Admin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-NmapCommand {
    $cmd = Get-Command nmap.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $paths = @(
        "$env:ProgramFiles\Nmap\nmap.exe",
        "${env:ProgramFiles(x86)}\Nmap\nmap.exe"
    )
    foreach ($p in $paths) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

function Get-PrimaryIPv4 {
    $cfg = Get-CimInstance Win32_NetworkAdapterConfiguration |
        Where-Object { $_.IPEnabled -eq $true -and $_.DefaultIPGateway -and $_.IPAddress } |
        Select-Object -First 1

    if (-not $cfg) { throw "Nao encontrei uma placa de rede ativa com gateway." }

    $ip = @($cfg.IPAddress | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })[0]
    if (-not $ip) { throw "Nao encontrei IPv4 valido." }
    return $ip
}

function Get-DefaultRange24 {
    $ip = Get-PrimaryIPv4
    $parts = $ip.Split('.')
    return "$($parts[0]).$($parts[1]).$($parts[2]).0/24"
}

function Get-NmapInstallerUrl {
    Write-Host "[*] Procurando instalador atual do Nmap no site oficial..." -ForegroundColor Yellow
    $downloadPage = Invoke-WebRequest -Uri "https://nmap.org/download.html" -UseBasicParsing
    $matches = [regex]::Matches($downloadPage.Content, 'https://nmap\.org/dist/nmap-[0-9\.]+-setup\.exe')
    if ($matches.Count -eq 0) {
        $matches = [regex]::Matches($downloadPage.Content, 'href="(/dist/nmap-[0-9\.]+-setup\.exe)"')
        if ($matches.Count -gt 0) {
            return "https://nmap.org" + $matches[0].Groups[1].Value
        }
        throw "Nao consegui encontrar o link do instalador do Nmap na pagina oficial."
    }
    return $matches[0].Value
}

function Download-FileWithProgress {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$Destination
    )

    if (Test-Path $Destination) { Remove-Item $Destination -Force }

    $client = New-Object System.Net.WebClient
    $global:downloadComplete = $false
    $global:downloadError = $null

    Register-ObjectEvent -InputObject $client -EventName DownloadProgressChanged -Action {
        $pct = $EventArgs.ProgressPercentage
        $received = [math]::Round($EventArgs.BytesReceived / 1MB, 2)
        $total = if ($EventArgs.TotalBytesToReceive -gt 0) { [math]::Round($EventArgs.TotalBytesToReceive / 1MB, 2) } else { 0 }
        if ($total -gt 0) {
            Write-Progress -Activity "Baixando Nmap" -Status "$received MB de $total MB" -PercentComplete $pct
        } else {
            Write-Progress -Activity "Baixando Nmap" -Status "$received MB baixados" -PercentComplete 0
        }
    } | Out-Null

    Register-ObjectEvent -InputObject $client -EventName DownloadFileCompleted -Action {
        if ($EventArgs.Error) { $global:downloadError = $EventArgs.Error }
        $global:downloadComplete = $true
    } | Out-Null

    Write-Host "[*] Baixando:" -ForegroundColor Yellow
    Write-Host "    $Url" -ForegroundColor DarkGray
    $client.DownloadFileAsync([Uri]$Url, $Destination)

    while (-not $global:downloadComplete) {
        Start-Sleep -Milliseconds 200
    }
    Write-Progress -Activity "Baixando Nmap" -Completed
    $client.Dispose()

    if ($global:downloadError) { throw $global:downloadError }
    if (-not (Test-Path $Destination)) { throw "Download falhou: arquivo nao encontrado." }

    $size = [math]::Round((Get-Item $Destination).Length / 1MB, 2)
    Write-Host "[+] Download concluido: $size MB" -ForegroundColor Green
}

function Install-NmapSpeedStyle {
    $nmap = Get-NmapCommand
    if ($nmap) {
        Write-Host "[+] Nmap ja esta instalado: $nmap" -ForegroundColor Green
        return
    }

    $url = Get-NmapInstallerUrl
    $installer = Join-Path $env:TEMP ([IO.Path]::GetFileName($url))
    Download-FileWithProgress -Url $url -Destination $installer

    Write-Host "[*] Abrindo instalador do Nmap..." -ForegroundColor Yellow
    Write-Host "    Avance no instalador. Quando terminar, o scan continua." -ForegroundColor DarkGray
    Write-Host "    Dica: mantenha Npcap marcado para melhor descoberta de rede." -ForegroundColor DarkGray

    $p = Start-Process -FilePath $installer -Wait -PassThru
    Write-Host "[*] Instalador finalizado com codigo: $($p.ExitCode)" -ForegroundColor Yellow

    $nmap = Get-NmapCommand
    if (-not $nmap) {
        Write-Host "[!] Nmap ainda nao apareceu no PATH. Vou tentar caminhos padrao..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        $nmap = Get-NmapCommand
    }

    if (-not $nmap) {
        throw "Nmap nao foi encontrado depois da instalacao. Feche e abra o PowerShell, ou instale manualmente pelo instalador baixado: $installer"
    }

    Write-Host "[+] Nmap instalado: $nmap" -ForegroundColor Green
}

function Invoke-NmapScan {
    param(
        [Parameter(Mandatory=$true)][string]$NmapPath,
        [Parameter(Mandatory=$true)][string]$TargetRange,
        [Parameter(Mandatory=$true)][string]$Ports,
        [switch]$Deep
    )

    $desktop = [Environment]::GetFolderPath('Desktop')
    $outDir = Join-Path $desktop "LanScout_Results"
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $xmlPath = Join-Path $outDir "lanscout_$stamp.xml"
    $txtPath = Join-Path $outDir "lanscout_$stamp.txt"
    $csvPath = Join-Path $outDir "lanscout_$stamp.csv"
    $htmlPath = Join-Path $outDir "lanscout_$stamp.html"

    if ($Deep) {
        $args = @("-A", "-T4", "--open", "-p", $Ports, "-oX", $xmlPath, "-oN", $txtPath, $TargetRange)
    } else {
        $args = @("-sV", "-T4", "--open", "-p", $Ports, "-oX", $xmlPath, "-oN", $txtPath, $TargetRange)
    }

    Write-Host "[*] Executando scan:" -ForegroundColor Yellow
    Write-Host "    $NmapPath $($args -join ' ')" -ForegroundColor DarkGray
    Write-Host ""

    $proc = Start-Process -FilePath $NmapPath -ArgumentList $args -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ne 0) { Write-Host "[!] Nmap retornou codigo $($proc.ExitCode). Vou tentar ler o que foi gerado." -ForegroundColor Yellow }

    if (-not (Test-Path $xmlPath)) { throw "Arquivo XML do Nmap nao foi gerado." }

    [xml]$xml = Get-Content $xmlPath
    $rows = @()

    foreach ($hostNode in $xml.nmaprun.host) {
        $status = $hostNode.status.state
        if ($status -ne "up") { continue }

        $ipv4 = ($hostNode.address | Where-Object { $_.addrtype -eq "ipv4" } | Select-Object -First 1).addr
        $macNode = $hostNode.address | Where-Object { $_.addrtype -eq "mac" } | Select-Object -First 1
        $mac = $macNode.addr
        $vendor = $macNode.vendor
        $hostname = ($hostNode.hostnames.hostname | Select-Object -First 1).name

        $openPorts = @()
        foreach ($portNode in $hostNode.ports.port) {
            if ($portNode.state.state -eq "open") {
                $svc = $portNode.service.name
                $product = $portNode.service.product
                $version = $portNode.service.version
                $label = "$($portNode.portid)/$($portNode.protocol)"
                if ($svc) { $label += " $svc" }
                if ($product) { $label += " $product" }
                if ($version) { $label += " $version" }
                $openPorts += $label
            }
        }

        $osGuess = ""
        if ($hostNode.os.osmatch) { $osGuess = ($hostNode.os.osmatch | Select-Object -First 1).name }

        $rows += [PSCustomObject]@{
            IP = $ipv4
            Hostname = if ($hostname) { $hostname } else { "" }
            MAC = if ($mac) { $mac } else { "" }
            Fabricante = if ($vendor) { $vendor } else { "" }
            PortasAbertas = ($openPorts -join "; ")
            SistemaProvavel = $osGuess
        }
    }

    $rows | Sort-Object IP | Format-Table -AutoSize
    $rows | Sort-Object IP | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

    $html = $rows | Sort-Object IP | ConvertTo-Html -Title "LanScout Results" -PreContent "<h1>LanScout SpeedStyle</h1><p>Rede: $TargetRange<br>Data: $(Get-Date)</p>" | Out-String
    $html | Set-Content -Path $htmlPath -Encoding UTF8

    Write-Host ""
    Write-Host "[+] Encontrados: $($rows.Count) dispositivos ativos" -ForegroundColor Green
    Write-Host "[+] CSV : $csvPath" -ForegroundColor Green
    Write-Host "[+] HTML: $htmlPath" -ForegroundColor Green
    Write-Host "[+] TXT : $txtPath" -ForegroundColor Green

    if ($OpenResults) {
        Start-Process $htmlPath
    }
}

Write-Title

if (-not (Test-Admin)) {
    Write-Host "[!] Recomendo executar como Administrador para melhor deteccao de MAC/fabricante." -ForegroundColor Yellow
}

if (-not $Range) {
    $Range = Get-DefaultRange24
    Write-Host "[*] Rede detectada automaticamente: $Range" -ForegroundColor Yellow
}

if ($DownloadNmap -and -not $SkipInstall) {
    Install-NmapSpeedStyle
}

$nmapPath = Get-NmapCommand
if (-not $nmapPath) {
    Write-Host "[!] Nmap nao encontrado." -ForegroundColor Yellow
    Write-Host "    Rode com -DownloadNmap para baixar com porcentagem e instalar." -ForegroundColor Yellow
    Write-Host "    Exemplo: .\LanScout-SpeedStyle-Win10-11.ps1 -DownloadNmap -OpenResults" -ForegroundColor Yellow
    exit 1
}

Invoke-NmapScan -NmapPath $nmapPath -TargetRange $Range -Ports $Ports -Deep:$Deep

Write-Host "[+] Concluido." -ForegroundColor Green
