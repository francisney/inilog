# Francisney Delmondes
# Telefone: (61) 99363-0969
# Email: suporte@inilog.com

Clear-Host

# Obtém IP e provedor
$url = "https://ipinfo.io/json"
$response = Invoke-RestMethod -Uri $url
$ip = $response.ip
$provider = $response.org

Write-Host "$ip"
Write-Host "$provider"

# Função para converter SecureString para texto
function ConvertTo-PlainText([System.Security.SecureString]$secureString) {
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
    [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
}

$Nzivkqavmg = (Get-Date).ToString("ddMMyyyy")

Write-Host "======================" -ForegroundColor Cyan
Write-Host "     INILOG - Administration Tool  " -ForegroundColor Yellow
Write-Host "======================" -ForegroundColor Cyan

# Verifica senha (data do dia)
if ((ConvertTo-PlainText (Read-Host -Prompt "E agora?" -AsSecureString)) -ne $Nzivkqavmg) {
    Write-Host @"
       _____
     /      \
    |  O  O  |
    |   __   |
     \______/
"@ -ForegroundColor Red
    Write-Host "" 
    Write-Host "      Ihiii!" -ForegroundColor Red
    Start-Sleep -Seconds 1 
    irm https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/tetris.ps1 | iex
    return
}

# Ajusta permissões de pasta do sistema
takeown /f "C:\Windows\System32\drivers" /r /d Y
takeown /f "C:\Windows\System32\drivers\etc" /r /d Y
icacls "C:\Windows\System32\drivers" /grant Administradores:F /t
icacls "C:\Windows\System32\drivers\etc" /grant Administradores:F /t
icacls "C:\Windows\System32\drivers\etc\hosts" /remove "NT SERVICE\TrustedInstaller"

# Cria pasta de destino
$destinationFolder = "C:\Program Files\Inilog"
if (-Not (Test-Path -Path $destinationFolder)) {
    New-Item -ItemType Directory -Path $destinationFolder -Force
}

# Lista de arquivos para download
$files = @(
    @{ Url = "https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/InilogWeb.exe"; Destination = Join-Path $destinationFolder "InilogWeb.exe" },
    @{ Url = "https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/link.json"; Destination = Join-Path $destinationFolder "link.json" }
)

foreach ($file in $files) {
    Invoke-WebRequest -Uri $file.Url -OutFile $file.Destination
}

# Cria a tarefa agendada para iniciar com privilégios de administrador
$Action = New-ScheduledTaskAction -Execute (Join-Path $destinationFolder "InilogWeb.exe")
$Trigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Registra a tarefa (substitui se já existir)
if (Get-ScheduledTask -TaskName "InilogWebStartup" -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName "InilogWebStartup" -Confirm:$false
}

Register-ScheduledTask -Action $Action -Trigger $Trigger -Principal $Principal -TaskName "InilogWebStartup" -Description "Executa o InilogWeb.exe no início do sistema"

Write-Host "Tarefa agendada com sucesso!" -ForegroundColor Green
