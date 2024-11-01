# Função para testar a conexão de rede
function Test-Network {
    # Fazendo ping em google.com
    Write-Host "Fazendo ping em google.com..." -ForegroundColor Cyan
    $pingResult = ping google.com -n 4

    # Exibe o resultado do ping
    if ($pingResult) {
        Write-Host "Ping concluído." -ForegroundColor Green
        Write-Host $pingResult
    } else {
        Write-Host "Falha no ping para google.com." -ForegroundColor Red
    }

    # Medindo a velocidade da internet
    Write-Host "Medindo a velocidade da internet..." -ForegroundColor Cyan

    # Instalação do módulo Speedtest, se necessário
    if (-not (Get-Module -Name Speedtest)) {
        Install-Module -Name Speedtest -Force -Scope CurrentUser -AllowClobber
    }

    # Importa o módulo Speedtest
    Import-Module Speedtest

    # Realiza o teste de velocidade
    $speedtestResult = Speedtest
    $downloadSpeed = [math]::Round($speedtestResult.Download / 1MB, 2)
    $uploadSpeed = [math]::Round($speedtestResult.Upload / 1MB, 2)
    $pingTime = $speedtestResult.Ping

    Write-Host "Velocidade de Download: $downloadSpeed MB/s" -ForegroundColor Green
    Write-Host "Velocidade de Upload: $uploadSpeed MB/s" -ForegroundColor Green
    Write-Host "Tempo de Ping: $pingTime ms" -ForegroundColor Green

    # Obtendo informações do IP e provedor
    $ipInfo = Invoke-RestMethod -Uri "https://ipinfo.io/json"

    Write-Host "Seu IP: $($ipInfo.ip)" -ForegroundColor Green
    Write-Host "Provedor: $($ipInfo.org)" -ForegroundColor Green
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
