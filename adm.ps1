function Show-Menu {
    Write-Host "Choose an option:"
    Write-Host "1 - Power Options"
    Write-Host "2 - Computer Name"
    Write-Host "3 - Advanced Sharing"
    Write-Host "4 - Device Manager"
    Write-Host "5 - User Accounts"
    Write-Host "6 - System"
    Write-Host "7 - Task Manager"
    Write-Host "8 - Registry Editor"
    Write-Host "9 - Network Information"
    Write-Host "10 - Uninstall Programs"
    Write-Host "0 - Exit"
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
        default { Write-Host "Invalid option, please try again." }
    }
}

while ($true) {
    Show-Menu
    $choice = Read-Host "Enter option number"
    
    if ($choice -eq '0') {
        exit
    } else {
        Start-Tool -choice $choice
    }
}
