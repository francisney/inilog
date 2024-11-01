$speedtestDir = "C:\ti"
$speedtestExe = "$speedtestDir\speedtest.exe"
$speedtestUrl = "https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/speedtest.exe"

function Download-Speedtest {
    if (-not (Test-Path $speedtestDir)) {
        New-Item -ItemType Directory -Path $speedtestDir -Force
    }

    if (-not (Test-Path $speedtestExe)) {
        try {
            Invoke-WebRequest -Uri $speedtestUrl -OutFile $speedtestExe -ErrorAction Stop
        } catch {
            Write-Host "Erro ao baixar speedtest.exe: $_" -ForegroundColor Red
            return $false
        }
    }

    return $true
}

function Test-Network {
    $pingResult = Test-Connection -ComputerName google.com -Count 4 -ErrorAction Stop
    $pingResult | ForEach-Object { Write-Host "$($_.Address): $($_.ResponseTime) ms" -ForegroundColor Green }

    if (Download-Speedtest) {
        try {
            $speedtestResult = & $speedtestExe --simple
            Write-Host $speedtestResult -ForegroundColor Green
        } catch {
            Write-Host "Erro ao realizar o teste de velocidade: $_" -ForegroundColor Red
        }
    }

    try {
        $ipInfo = Invoke-RestMethod -Uri "https://ipinfo.io/json"
        Write-Host "Seu IP: $($ipInfo.ip)" -ForegroundColor Green
        Write-Host "Provedor: $($ipInfo.org)" -ForegroundColor Green
    } catch {
        Write-Host "Erro ao obter informações do IP: $_" -ForegroundColor Red
    }
}

Test-Network
