function Show-Menu {
    Write-Host -ForegroundColor White "Choose an option:"
    
    Write-Host -ForegroundColor Cyan "[1] Power Options" -NoNewline
    Write-Host -ForegroundColor Cyan "      [2] Computer Name"
    
    Write-Host -ForegroundColor Cyan "[3] Advanced Sharing" -NoNewline
    Write-Host -ForegroundColor Cyan "      [4] Device Manager"
    
    Write-Host -ForegroundColor Cyan "[5] User Accounts" -NoNewline
    Write-Host -ForegroundColor Cyan "      [6] System"
    
    Write-Host -ForegroundColor Cyan "[7] Task Manager" -NoNewline
    Write-Host -ForegroundColor Cyan "       [8] Registry Editor"
    
    Write-Host -ForegroundColor Cyan "[9] Network Information" -NoNewline
    Write-Host -ForegroundColor Cyan "  [10] Control Panel"
    
    Write-Host -ForegroundColor Red "[0] Exit"
}

while ($true) {
    Show-Menu
    $option = Read-Host "Enter option number"
    
    if ($option -eq '0') {
        break
    } else {
        # Processa a opção selecionada
        Write-Host "You selected option $option" -ForegroundColor Green
    }
}

Show-Menu


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
