
function Show-Menu {
    Write-Host "Escolha uma opção:"
    Write-Host "1 - Opções de energia"
    Write-Host "2 - Nome do computador"
    Write-Host "3 - Compartilhamento avançado"
    Write-Host "4 - Gerenciador de dispositivos"
    Write-Host "5 - Contas de usuário"
    Write-Host "6 - Sistema"
    Write-Host "7 - Gerenciador de tarefas"
    Write-Host "8 - Editor de registro"
    Write-Host "9 - Informações de rede"
    Write-Host "10 - Desinstalar programas"
    Write-Host "0 - Sair"
}

function Start-Tool {
    param ($choice)
    switch ($choice) {
        1 { Start-Process "powercfg.cpl" }
        2 { Start-Process "SystemPropertiesComputerName" }
        3 { Start-Process "control.exe" -ArgumentList "/name Microsoft.NetworkAndSharingCenter /page Advanced" }
        4 { Start-Process "devmgmt.msc" }
        5 { Start-Process "control.exe" -ArgumentList "userpasswords2" }
        6 { Start-Process "SystemPropertiesAdvanced" }
        7 { Start-Process "taskmgr" }
        8 { Start-Process "regedit" }
        9 { Start-Process "ncpa.cpl" }
        10 { Start-Process "appwiz.cpl" }
        0 { exit }
        default { Write-Host "Opção inválida, tente novamente." }
    }
}

while ($true) {
    Show-Menu
    $choice = Read-Host "Digite o número da opção"
    Start-Tool -choice $choice
}
