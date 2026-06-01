Clear-Host

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Scanner simples de rede local - PowerShell"
Write-Host " Mostra IPs online + hostname"
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# Detecta IPv4 principal
$config = Get-WmiObject Win32_NetworkAdapterConfiguration |
    Where-Object {
        $_.IPEnabled -eq $true -and
        $_.DefaultIPGateway -ne $null -and
        $_.IPAddress -ne $null
    } |
    Select-Object -First 1

$ip = @($config.IPAddress | Where-Object {
    $_ -match '^\d{1,3}(\.\d{1,3}){3}$' -and
    $_ -notmatch '^169\.254\.'
})[0]

if (-not $ip) {
    Write-Host "Nao consegui detectar o IP local." -ForegroundColor Red
    exit
}

$partes = $ip.Split(".")
$rede = "$($partes[0]).$($partes[1]).$($partes[2])"

Write-Host "Seu IP: $ip" -ForegroundColor Yellow
Write-Host "Escaneando: $rede.1 ate $rede.254" -ForegroundColor Yellow
Write-Host ""
Write-Host "Procurando dispositivos online..." -ForegroundColor Cyan
Write-Host ""

$resultados = New-Object System.Collections.ArrayList
$jobs = @()

1..254 | ForEach-Object {
    $alvo = "$rede.$_"

    $jobs += Start-Job -ScriptBlock {
        param($ipAlvo)

        try {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $resposta = $ping.Send($ipAlvo, 400)

            if ($resposta.Status -eq "Success") {
                try {
                    $hostname = ([System.Net.Dns]::GetHostEntry($ipAlvo)).HostName
                }
                catch {
                    $hostname = "Desconhecido"
                }

                [PSCustomObject]@{
                    IP       = $ipAlvo
                    Hostname = $hostname
                    Status   = "Online"
                }
            }

            $ping.Dispose()
        }
        catch {
        }

    } -ArgumentList $alvo
}

$resultados = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job

$resultados = @($resultados | Sort-Object {
    [int](($_.IP -split "\.")[3])
})

if ($resultados.Count -eq 0) {
    Write-Host "Nenhum dispositivo respondeu ao ping." -ForegroundColor Yellow
}
else {
    $resultados | Format-Table -AutoSize
}

Write-Host ""
Write-Host "Total online: $($resultados.Count)" -ForegroundColor Green
