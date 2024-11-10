# Francisney Delmondes
# Telefone: (61) 99363-0969
# Email: suporte@inilog.com

Clear-Host
Write-Host "======================" -ForegroundColor Cyan
Write-Host "     INILOG - Administration Tool  " -ForegroundColor Yellow
Write-Host "======================" -ForegroundColor Cyan

function Show-Menu {
    Write-Host -ForegroundColor White "Choose an option:"
    
    Write-Host -ForegroundColor Cyan "[1] Power Options"
    Write-Host -ForegroundColor Cyan "[2] Computer Name"
    Write-Host -ForegroundColor Cyan "[3] Advanced Sharing"
    Write-Host -ForegroundColor Cyan "[4] Device Manager"
    Write-Host -ForegroundColor Cyan "[5] User Accounts"
    Write-Host -ForegroundColor Cyan "[6] System"
    Write-Host -ForegroundColor Cyan "[7] Task Manager"
    Write-Host -ForegroundColor Cyan "[8] Registry Editor"
    Write-Host -ForegroundColor Cyan "[9] Network NCPA.CPL"
    Write-Host -ForegroundColor Cyan "[10] Control Panel"
    Write-Host -ForegroundColor Cyan "[11] Printers"
    Write-Host -ForegroundColor Cyan "[12] Password Never Expires"
    Write-Host -ForegroundColor Cyan "[0] Exit"
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
        11 { Start-Process "control.exe" -ArgumentList "printers" }
        12 { Get-LocalUser -Name ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name.Split("\")[-1]) | Set-LocalUser -PasswordNeverExpires $true }
        
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
    
    # Limpar a tela e voltar ao início após a escolha
    Clear-Host
    Write-Host "======================" -ForegroundColor Cyan
    Write-Host "     INILOG - Administration Tool  " -ForegroundColor Yellow
    Write-Host "======================" -ForegroundColor Cyan
    Write-Host "Returning to the main menu..." -ForegroundColor Green

    # Esperar o usuário pressionar Enter para continuar
    Read-Host "Press Enter to continue..."
}
