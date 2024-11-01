# Função para instalar e importar o módulo Speedtest
function Install-SpeedtestModule {
    if (-not (Get-Module -Name Speedtest)) {
        Write-Host "Instalando o módulo Speedtest..." -ForegroundColor Cyan
        
        # Tenta instalar o módulo Speedtest
        try {
            Install-Module -Name Speedtest -Force -Scope CurrentUser -AllowClobber
            Write-Host "Módulo Speedtest instalado com sucesso." -ForegroundColor Green
        } catch {
            Write-Host "Erro ao instalar o módulo Speedtest: $_" -ForegroundColor Red
            return $false
        }
    } else {
        Write-Host "O módulo Speedtest já está instalado." -ForegroundColor Yellow
    }
    
    # Importa o módulo Speedtest
    try {
        Import-Module Speedtest -ErrorAction Stop
        Write-Host "Módulo Speedtest importado com sucesso." -ForegroundColor Green
    } catch {
        Write-Host "Erro ao importar o módulo Speedtest: $_" -ForegroundColor Red
        return $false
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

    # Realiza o teste de velocidade usando o Speedtest
    try {
        $speedtestResult = Speedtest
        $downloadSpeed = [math]::Round($speedtestResult.Download / 1MB, 2)
        $uploadSpeed = [math]::Round($speedtestResult.Upload / 1MB, 2)
        $pingTime = $speedtestResult.Ping

        Write-Host "Velocidade de Download: $downloadSpeed MB/s" -ForegroundColor Green
        Write-Host "Velocidade de Upload: $uploadSpeed MB/s" -ForegroundColor Green
        Write-Host "Tempo de Ping: $pingTime ms" -ForegroundColor Green
    } catch {
        Write-Host "Erro ao realizar o teste de velocidade: $_" -ForegroundColor Red
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
            if (Install-SpeedtestModule) {
                Test-Network
            } else {
                Write-Host "Não foi possível instalar o módulo Speedtest." -ForegroundColor Red
            }
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
