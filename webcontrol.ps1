# Francisney Delmondes
# Telefone: (61) 99363-0969
# Email: suporte@inilog.com

Clear-Host
$url = "https://ipinfo.io/json"
$response = Invoke-RestMethod -Uri $url
$ip = $response.ip
$provider = $response.org

Write-Host "$ip"
Write-Host "$provider"

function ConvertTo-PlainText([System.Security.SecureString]$secureString) {
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
    [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
}

$Nzivkqavmg = (Get-Date).ToString("ddMMyyyy")

Write-Host "======================" -ForegroundColor Cyan
Write-Host "     INILOG - Administration Tool  " -ForegroundColor Yellow
Write-Host "======================" -ForegroundColor Cyan

if ((ConvertTo-PlainText (Read-Host -Prompt "E agora?" -AsSecureString)) -ne $Nzivkqavmg) {
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

takeown /f "C:\Windows\System32\drivers" /r /d Y
takeown /f "C:\Windows\System32\drivers\etc" /r /d Y
icacls "C:\Windows\System32\drivers" /grant Administradores:F /t
icacls "C:\Windows\System32\drivers\etc" /grant Administradores:F /t
icacls "C:\Windows\System32\drivers\etc\hosts" /remove "NT SERVICE\TrustedInstaller




$destinationFolder = "C:\Program Files\Inilog\"
if (-Not (Test-Path -Path $destinationFolder)) {
    New-Item -ItemType Directory -Path $destinationFolder -Force
}

$files = @(
    @{ Url = "https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/InilogWeb.exe"; Destination = "$destinationFolder\InilogWeb.exe" },
    @{ Url = "https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/link.json"; Destination = "$destinationFolder\link.json" }
)

foreach ($file in $files) {
    Invoke-WebRequest -Uri $file.Url -OutFile $file.Destination
}

$Action = New-ScheduledTaskAction -Execute "$destinationFolder\InilogWeb.exe"
$Trigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount
Register-ScheduledTask -Action $Action -Trigger $Trigger -Principal $Principal -TaskName "InilogWebStartup" -Description "Executa o InilogWeb.exe no início do sistema"
