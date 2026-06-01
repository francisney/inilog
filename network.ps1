Clear-Host


# Detecta o IPv4 principal
$ip = Get-NetIPConfiguration |
    Where-Object {
        $_.IPv4Address -and
        $_.IPv4DefaultGateway
    } |
    Select-Object -First 1 -ExpandProperty IPv4Address |
    Select-Object -ExpandProperty IPAddress

if (-not $ip) {
    Write-Host "Nao consegui detectar o IP local." -ForegroundColor Red
    exit
}

# Pega a base da rede. Exemplo: 192.168.15
$partes = $ip.Split(".")
$rede = "$($partes[0]).$($partes[1]).$($partes[2])"

Write-Host "Seu IP: $ip" -ForegroundColor Yellow
Write-Host "Escaneando: $rede.1 ate $rede.254" -ForegroundColor Yellow
Write-Host ""

$jobs = @()

1..254 | ForEach-Object {
    $alvo = "$rede.$_"

    $jobs += Start-Job -ScriptBlock {
        param($ipAlvo)

        $online = Test-Connection -ComputerName $ipAlvo -Count 1 -Quiet -TimeoutSeconds 1

        if ($online) {
            $hostname = ""

            try {
                $dns = Resolve-DnsName -Name $ipAlvo -ErrorAction Stop
                $hostname = ($dns | Where-Object { $_.NameHost } | Select-Object -First 1).NameHost
            } catch {
                try {
                    $hostname = [System.Net.Dns]::GetHostEntry($ipAlvo).HostName
                } catch {
                    $hostname = "Desconhecido"
                }
            }

            [PSCustomObject]@{
                IP       = $ipAlvo
                Hostname = $hostname
                Status   = "Online"
            }
        }

    } -ArgumentList $alvo
}

Write-Host "Procurando dispositivos online..." -ForegroundColor Cyan
Write-Host ""

$resultados = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job

$resultados |
    Sort-Object {
        [int](($_.IP -split "\.")[3])
    } |
    Format-Table -AutoSize

Write-Host ""
Write-Host "Total online: $($resultados.Count)" -ForegroundColor Green
