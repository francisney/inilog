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
    
    Write-Host -ForegroundColor Cyan "[11] Printers" -NoNewline
    Write-Host -ForegroundColor Cyan "      [0] Exit"
}

while ($true) {
    Show-Menu
    $option = Read-Host "Enter option number"
    
    if ($option -eq '0') {
        break
    } else {
        Write-Host "You selected option $option" -ForegroundColor Green
    }
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
        11 { Start-Process "control printers" }
        0 { exit }
        default { Write-Host "Invalid option, please try again." }
    }
}

while ($true) {
    Show-Menu
    $choice = Read-Host "Enter option number"
    Start-Tool -choice $choice
}
