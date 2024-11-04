# Francisney Delmondes
# Telefone: (61) 99363-0969
# Email: suporte@inilog.com

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
Clear-Host

# Verifica se o PowerShell está sendo executado como administrador
If (-Not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Este script precisa ser executado como administrador."
    exit
}

Write-Host "Iniciando limpeza completa do sistema e navegadores..."

# Limpeza do Edge
$EdgePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
Remove-Item -Path "$EdgePath\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$EdgePath\History" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$EdgePath\Cookies" -Force -ErrorAction SilentlyContinue

# Limpeza do Chrome
$ChromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
Remove-Item -Path "$ChromePath\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$ChromePath\History" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$ChromePath\Cookies" -Force -ErrorAction SilentlyContinue

# Limpeza do Firefox
$FirefoxPath = "$env:APPDATA\Mozilla\Firefox\Profiles"
$FirefoxProfiles = Get-ChildItem -Path $FirefoxPath -Directory
foreach ($Profile in $FirefoxProfiles) {
    Remove-Item -Path "$Profile\cache2\entries\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$Profile\cookies.sqlite" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$Profile\places.sqlite" -Force -ErrorAction SilentlyContinue
}

Write-Host "Resetando Winsock e limpando cache DNS..."
netsh winsock reset | Out-Null
ipconfig /flushdns | Out-Null

Write-Host "Resetando a pilha TCP/IP..."
netsh int ip reset | Out-Null

Write-Host "Desativando serviços de rastreamento do Windows..."
Stop-Service -Name DiagTrack -Force -ErrorAction SilentlyContinue
Stop-Service -Name dmwappushservice -Force -ErrorAction SilentlyContinue
sc.exe delete DiagTrack | Out-Null
sc.exe delete dmwappushservice | Out-Null

Write-Host "Executando tarefas de manutenção ociosa do sistema..."
& "$env:windir\system32\rundll32.exe" advapi32.dll,ProcessIdleTasks

Write-Host "Limpeza concluída com sucesso!"
