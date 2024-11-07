$host.UI.RawUI.WindowTitle = "MUDAR DE INTERNET [INILOG - Support]"

Clear-Host

$host.UI.RawUI.WindowSize = New-Object Management.Automation.Host.Size(65, 15)

Write-Host "MUDAR DE INTERNET"
Write-Host "__________________________________________________"
Write-Host "---- 1. Conectar na rede da [Vivo ADSL (cabo)]"
Write-Host "---- 2. Conectar na rede da [4G Vivo Box]"
Write-Host "----"
Write-Host "---- 3. REDEFINIR REDE [CONECTA AUTOMATICO] [DHCP]"
Write-Host "----"
Write-Host "---- 0. SAIR [EXIT]"
[System.Windows.Forms.MessageBox]::Show("ALERTA! Deixe todos computadores na mesma rede.", "Atenção", [System.Windows.Forms.MessageBoxButtons]::OK)

Write-Host "__________________________________________________"
$opcao = Read-Host "Escolha e tecle [ENTER]:"
Write-Host "---------------------------------------------------"

switch ($opcao) {
    1 {
        Set-NetIPInterface -InterfaceAlias "Ethernet" -Dhcp Disabled
        New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.15.112" -PrefixLength 24 -DefaultGateway "192.168.15.1"
        Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "8.8.8.8"
        [System.Windows.Forms.MessageBox]::Show("Comando executado! Conectado [Vivo ADSL (cabo)] https://inilog.com/hesk", "Sucesso", [System.Windows.Forms.MessageBoxButtons]::OK)
        exit
    }
    2 {
        Set-NetIPInterface -InterfaceAlias "Ethernet" -Dhcp Disabled
        New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.1.112" -PrefixLength 24 -DefaultGateway "192.168.1.1"
        Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "8.8.8.8"
        [System.Windows.Forms.MessageBox]::Show("Comando executado! Conectado [4G Vivo Box] https://inilog.com/hesk", "Sucesso", [System.Windows.Forms.MessageBoxButtons]::OK)
        exit
    }
    3 {
        Set-NetIPInterface -InterfaceAlias "Ethernet" -Dhcp Enabled
        Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ResetServerAddresses
        [System.Windows.Forms.MessageBox]::Show("Comando executado! Configurado para conectar via [DHCP] https://inilog.com/hesk", "Sucesso", [System.Windows.Forms.MessageBoxButtons]::OK)
        exit
    }
    0 {
        exit
    }
    default {
        Write-Host "Opção inválida. Tente novamente."
    }
}
