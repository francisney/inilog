# Francisney Delmondes
# Telefone: (61) 99363-0969
# Email: suporte@inilog.com

$host.UI.RawUI.WindowTitle = "MUDAR DE INTERNET [INILOG - Support]"

function ConvertTo-PlainText([System.Security.SecureString]$secureString) {
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
    [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
}

Write-Host ".." -ForegroundColor Cyan
Write-Host "." -ForegroundColor Cyan

if ((ConvertTo-PlainText (Read-Host -Prompt "Digite a senha para mudar de internet:" -AsSecureString)) -ne "11223344") {
    Write-Host @"
       _____
     /      \
    |  O  O  |
    |   __   |
     \______/
"@ -ForegroundColor red
    Write-Host "" 
    Write-Host "      Ihiii!" -ForegroundColor red
    Start-Sleep -Seconds 1 
    irm https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/tetris.ps1 | iex
    return
}

function Exibir-Linha {
    Write-Host ("-" * 65) -ForegroundColor Gray
}

Clear-Host

# Definindo as informações das operadoras
$operadora1 = @{
    Nome     = "Vivo ADSL (cabo)"
    IP       = "192.168.15.112"
    Gateway  = "192.168.15.1"
    DNS1     = "8.8.8.8"
    DNS2     = "1.1.1.1"
}

$operadora2 = @{
    Nome     = "4G Vivo Box"
    IP       = "192.168.1.112"
    Gateway  = "192.168.1.1"
    DNS1     = "8.8.8.8"
    DNS2     = "1.1.1.1"
}

Write-Host "MUDAR DE INTERNET" -ForegroundColor Yellow
Exibir-Linha
Write-Host "Selecione a rede para se conectar:" -ForegroundColor Gray
Write-Host ""
Write-Host "1. Conectar na rede da [$($operadora1.Nome)]" -ForegroundColor Cyan
Write-Host "2. Conectar na rede da [$($operadora2.Nome)]" -ForegroundColor Cyan
Write-Host ""
Write-Host "3. Configurar automaticamente [DHCP]" -ForegroundColor Cyan
Write-Host ""
Write-Host "0. Sair [EXIT]" -ForegroundColor Cyan
Exibir-Linha

Write-Host "ALERTA: Certifique-se de que todos os computadores estejam na mesma rede." -ForegroundColor Red
Exibir-Linha

$opcao = Read-Host "Escolha uma opção e pressione [ENTER]"
Exibir-Linha

switch ($opcao) {
    1 {
        try {
            & netsh interface ip set address name="Ethernet" static $($operadora1.IP) 255.255.255.0 $($operadora1.Gateway)
            & netsh interface ip set dns name="Ethernet" static $($operadora1.DNS1) primary
            & netsh interface ip add dns name="Ethernet" $($operadora1.DNS2) index=2
            Write-Host "Conectado com sucesso à rede [$($operadora1.Nome)]" -ForegroundColor Green
            Write-Host "Para mais ajuda, visite: https://inilog.com/hesk" -ForegroundColor Gray
        }
        catch {
            Write-Host "Erro ao conectar à rede $($operadora1.Nome). Detalhes do erro: $_" -ForegroundColor DarkRed
        }
        Read-Host "Pressione [Enter] para sair"
    }
    2 {
        try {
            & netsh interface ip set address name="Ethernet" static $($operadora2.IP) 255.255.255.0 $($operadora2.Gateway)
            & netsh interface ip set dns name="Ethernet" static $($operadora2.DNS1) primary
            & netsh interface ip add dns name="Ethernet" $($operadora2.DNS2) index=2
            Write-Host "Conectado com sucesso à rede [$($operadora2.Nome)]" -ForegroundColor Green
            Write-Host "Para mais ajuda, visite: https://inilog.com/hesk" -ForegroundColor Gray
        }
        catch {
            Write-Host "Erro ao conectar à rede $($operadora2.Nome). Detalhes do erro: $_" -ForegroundColor DarkRed
        }
        Read-Host "Pressione [Enter] para sair"
    }
    3 {
        netsh interface ip set address name="Ethernet" dhcp
        netsh interface ip set dnsservers name="Ethernet" dhcp
        Write-Host "Comando para obter endereço IP automático executado com sucesso..." -ForegroundColor Cyan
        Write-Host ".." -ForegroundColor Cyan
        Write-Host "." -ForegroundColor Cyan
        Read-Host "Pressione [Enter] para sair"
    }
    0 {
        Write-Host "Saindo do programa..." -ForegroundColor Gray
        exit
    }
    default {
        Write-Host "Opção inválida. Por favor, tente novamente." -ForegroundColor DarkRed
        Read-Host "Pressione [Enter] para continuar"
    }
}