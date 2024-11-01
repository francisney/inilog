# Diretório onde o speedtest.exe será salvo
$speedtestDir = "C:\ti"
$speedtestExe = "$speedtestDir\speedtest.exe"
$speedtestUrl = "https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/speedtest.exe"

# Função para baixar o Speedtest CLI
function Download-Speedtest {
    if (-not (Test-Path $speedtestDir)) {
        Write-Host "Criando diretório $speedtestDir..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $speedtestDir -Force
    }

    if (-not (Test-Path $speedtestExe)) {
        Write-Host "Baixando speedtest.exe de $speedtestUrl..." -ForegroundColor Cyan
        try {
            Invoke-WebRequest -Uri $speedtestUrl -OutFile $speedtestExe -ErrorAction Stop
            Write-Host "speedtest.exe baixado com sucesso!" -ForegroundColor Green
        } catch {
            Write-Host "Erro ao baixar speedtest.exe: $_" -ForegroundColor Red
            return $false
        }
    } else {
        Write-Host "speedtest.exe já está presente em $speedtestExe." -ForegroundColor Yellow
    }

    return $true
}

# Função para testar a conexão de rede
function Test-Network {
    # Fazendo ping em google.com
    Write-Host "Fazendo ping em google.com..." -ForegroundColor Cyan
    $pingResult = Test-Connection -ComputerName google.com -Count 4 -ErrorAction Stop

    # Exibe o resultado do ping
    Write-Host "Ping concluído." -ForegroundColor Green
    $pingResult | ForEach-Object {
        Write-Host "$($_.Address): $($_.ResponseTime) ms" -ForegroundColor Green
    }

    # Medindo a velocidade da internet
    Write-Host "Medindo a velocidade da internet..." -ForegroundColor Cyan

    # Verifica se o speedtest.exe foi baixado e executa o teste
    if (Download-Speedtest) {
        try {
            $speedtestResult = & $speedtestExe --simple
            Write-Host $speedtestResult -ForegroundColor Green
        } catch {
            Write-Host "Erro ao realizar o teste de velocidade: $_" -ForegroundColor Red
        }
    }

    # Obtendo informações do IP e provedor
    try {
        $ipInfo = Invoke-RestMethod -Uri "https://ipinfo.io/json"
        Write-Host "Seu IP: $($ipInfo.ip)" -ForegroundColor Green
        Write-Host "Provedor: $($ipInfo.org)" -ForegroundColor Green
    } catch {
        Write-Host "Erro ao obter informações do IP: $_" -ForegroundColor Red
    }
}

# Função para exibir o menu
function Show-Menu {
    Clear-Host
    Write-Host "Escolha uma opção:" -ForegroundColor Yellow
    Write-Host "1: Testar Conexão de Rede" -ForegroundColor Cyan
    Write-Host "0: Sair" -ForegroundColor Red
}

# Loop do menu
do {
    Show-Menu
    $choice = Read-Host "Digite sua opção"

    switch ($choice) {
        "1" {
            Test-Network
            Read-Host "Pressione Enter para continuar..."
        }
        "0" {
            Write-Host "Saindo..." -ForegroundColor Red
        }
        default {
            Write-Host "Opção inválida, tente novamente." -ForegroundColor Red
        }
    }
} while ($choice -ne "0")
