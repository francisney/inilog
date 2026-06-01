<#
LanScout AutoDownload - Windows 10/11
Scanner de rede local estilo terminal: baixa/instala Nmap automaticamente, faz scan e gera relatorios.
Use somente em redes onde voce tem permissao.
#>

param(
    [string]$Range = "",
    [string]$Ports = "21,22,23,53,80,135,139,443,445,3389,8080,8443,9100",
    [switch]$Deep,
    [switch]$OpenResults,
    [switch]$NoInstall,
    [switch]$KeepInstaller
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"

function Write-Title {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " LanScout AutoDownload - Scanner de Rede Windows 10/11" -ForegroundColor Cyan
    Write-Host " Baixa/instala Nmap automaticamente + scan + relatorios" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-NmapCommand {
    $cmd = Get-Command nmap.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $paths = @(
        "$env:ProgramFiles\Nmap\nmap.exe",
        "${env:ProgramFiles(x86)}\Nmap\nmap.exe",
        "$env:LOCALAPPDATA\Programs\Nmap\nmap.exe"
    )
    foreach ($p in $paths) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

function Get-PrimaryIPv4 {
    $cfgs = Get-CimInstance Win32_NetworkAdapterConfiguration |
        Where-Object { $_.IPEnabled -eq $true -and $_.DefaultIPGateway -and $_.IPAddress }

    foreach ($cfg in $cfgs) {
        $ip = @($cfg.IPAddress | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })[0]
        if ($ip -and $ip -notmatch '^(169\.254|127\.)') { return $ip }
    }

    throw "Nao encontrei uma placa de rede ativa com IPv4 e gateway."
}

function Get-DefaultRange24 {
    $ip = Get-PrimaryIPv4
    $p = $ip.Split('.')
    return "$($p[0]).$($p[1]).$($p[2]).0/24"
}

function Get-NmapInstallerUrl {
    Write-Host "[*] Procurando instalador atual do Nmap no site oficial..." -ForegroundColor Yellow
    $pageUrl = "https://nmap.org/download.html"
    $page = Invoke-WebRequest -Uri $pageUrl -UseBasicParsing

    $m = [regex]::Match($page.Content, 'https://nmap\.org/dist/nmap-[0-9\.]+-setup\.exe')
    if ($m.Success) { return $m.Value }

    $m = [regex]::Match($page.Content, 'href="(/dist/nmap-[0-9\.]+-setup\.exe)"')
    if ($m.Success) { return "https://nmap.org" + $m.Groups[1].Value }

    throw "Nao consegui encontrar automaticamente o instalador do Nmap na pagina oficial."
}

function Download-FileWithPercent {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$Destination
    )

    if (Test-Path $Destination) { Remove-Item $Destination -Force }

    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.UserAgent = "LanScout-AutoDownload"
    $response = $request.GetResponse()
    $total = $response.ContentLength
    $stream = $response.GetResponseStream()
    $file = [System.IO.File]::Create($Destination)

    try {
        $buffer = New-Object byte[] 1048576
        [int64]$downloaded = 0
        $lastPct = -1

        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $file.Write($buffer, 0, $read)
            $downloaded += $read

            if ($total -gt 0) {
                $pct = [int](($downloaded / $total) * 100)
                if ($pct -ne $lastPct) {
                    $mbDone = [math]::Round($downloaded / 1MB, 2)
                    $mbTotal = [math]::Round($total / 1MB, 2)
                    Write-Progress -Activity "Baixando Nmap" -Status "$pct% - $mbDone MB de $mbTotal MB" -PercentComplete $pct
                    Write-Host ("`rBaixando Nmap: {0}%  ({1} MB / {2} MB)" -f $pct, $mbDone, $mbTotal) -NoNewline
                    $lastPct = $pct
                }
            } else {
                $mbDone = [math]::Round($downloaded / 1MB, 2)
                Write-Progress -Activity "Baixando Nmap" -Status "$mbDone MB baixados"
                Write-Host ("`rBaixando Nmap: {0} MB" -f $mbDone) -NoNewline
            }
        }
    }
    finally {
        $file.Close()
        $stream.Close()
        $response.Close()
        Write-Progress -Activity "Baixando Nmap" -Completed
        Write-Host ""
    }

    if (-not (Test-Path $Destination)) { throw "Download falhou: arquivo nao encontrado." }
    $size = [math]::Round((Get-Item $Destination).Length / 1MB, 2)
    if ($size -lt 1) { throw "Download parece invalido: arquivo muito pequeno ($size MB)." }
    Write-Host "[+] Download concluido: $size MB" -ForegroundColor Green
}

function Install-NmapAutomatically {
    $nmap = Get-NmapCommand
    if ($nmap) {
        Write-Host "[+] Nmap ja encontrado: $nmap" -ForegroundColor Green
        return $nmap
    }

    if ($NoInstall) { throw "Nmap nao encontrado e -NoInstall foi usado." }

    $url = Get-NmapInstallerUrl
    $installer = Join-Path $env:TEMP ([System.IO.Path]::GetFileName($url))

    Write-Host "[*] Baixando instalador oficial do Nmap..." -ForegroundColor Yellow
    Write-Host "    $url" -ForegroundColor DarkGray
    Download-FileWithPercent -Url $url -Destination $installer

    Write-Host "[*] Instalando Nmap..." -ForegroundColor Yellow
    Write-Host "    Se aparecer janela do instalador/Npcap, clique em Next/Install." -ForegroundColor DarkGray

    $args = @("/S")
    $p = Start-Process -FilePath $installer -ArgumentList $args -Wait -PassThru
    Write-Host "[*] Instalador terminou com codigo: $($p.ExitCode)" -ForegroundColor Yellow

    Start-Sleep -Seconds 3
    $nmap = Get-NmapCommand

    if (-not $nmap) {
        Write-Host "[!] Modo silencioso nao confirmou a instalacao. Abrindo instalador visual..." -ForegroundColor Yellow
        $p = Start-Process -FilePath $installer -Wait -PassThru
        Start-Sleep -Seconds 3
        $nmap = Get-NmapCommand
    }

    if (-not $nmap) {
        throw "Nmap nao foi encontrado depois da instalacao. Tente fechar/abrir o PowerShell ou execute o instalador manualmente: $installer"
    }

    if (-not $KeepInstaller) {
        try { Remove-Item $installer -Force -ErrorAction SilentlyContinue } catch {}
    }

    Write-Host "[+] Nmap pronto: $nmap" -ForegroundColor Green
    return $nmap
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

    Write-Host ""
    Write-Host "[*] Executando scan:" -ForegroundColor Yellow
    Write-Host "    $NmapPath $($args -join ' ')" -ForegroundColor DarkGray
    Write-Host ""

    $proc = Start-Process -FilePath $NmapPath -ArgumentList $args -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ne 0) { Write-Host "[!] Nmap retornou codigo $($proc.ExitCode). Tentando ler resultados..." -ForegroundColor Yellow }
    if (-not (Test-Path $xmlPath)) { throw "Arquivo XML do Nmap nao foi gerado." }

    [xml]$xml = Get-Content $xmlPath
    $rows = @()

    foreach ($hostNode in $xml.nmaprun.host) {
        if ($hostNode.status.state -ne "up") { continue }

        $ipv4 = ($hostNode.address | Where-Object { $_.addrtype -eq "ipv4" } | Select-Object -First 1).addr
        $macNode = $hostNode.address | Where-Object { $_.addrtype -eq "mac" } | Select-Object -First 1
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
            MAC = if ($macNode.addr) { $macNode.addr } else { "" }
            Fabricante = if ($macNode.vendor) { $macNode.vendor } else { "" }
            PortasAbertas = ($openPorts -join "; ")
            SistemaProvavel = $osGuess
        }
    }

    $rows = $rows | Sort-Object IP
    if ($rows.Count -gt 0) {
        $rows | Format-Table -AutoSize
    } else {
        Write-Host "[!] Nenhum dispositivo com as portas escolhidas apareceu no resultado." -ForegroundColor Yellow
        Write-Host "    Dica: para descobrir apenas hosts online, use: nmap -sn $TargetRange" -ForegroundColor DarkGray
    }

    $rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    $html = $rows | ConvertTo-Html -Title "LanScout Results" -PreContent "<h1>LanScout AutoDownload</h1><p>Rede: $TargetRange<br>Data: $(Get-Date)</p>" | Out-String
    $html | Set-Content -Path $htmlPath -Encoding UTF8

    Write-Host ""
    Write-Host "[+] Encontrados: $($rows.Count) dispositivos com portas abertas no filtro" -ForegroundColor Green
    Write-Host "[+] CSV : $csvPath" -ForegroundColor Green
    Write-Host "[+] HTML: $htmlPath" -ForegroundColor Green
    Write-Host "[+] TXT : $txtPath" -ForegroundColor Green

    if ($OpenResults) { Start-Process $htmlPath }
}

try {
    Write-Title

    if (-not (Test-Admin)) {
        Write-Host "[!] Recomendo executar como Administrador para instalar Nmap/Npcap e detectar MAC/fabricante." -ForegroundColor Yellow
    }

    if (-not $Range) {
        $Range = Get-DefaultRange24
        Write-Host "[*] Rede detectada automaticamente: $Range" -ForegroundColor Yellow
    }

    $nmapPath = Install-NmapAutomatically
    Invoke-NmapScan -NmapPath $nmapPath -TargetRange $Range -Ports $Ports -Deep:$Deep

    Write-Host "[+] Concluido." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "[ERRO] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Tente executar como Administrador. Se o problema for instalacao, instale o Nmap manualmente e rode de novo." -ForegroundColor Yellow
    exit 1
}
