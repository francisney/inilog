#requires -Version 5.1

# ============================================================
# INILOG - CENTRAL TECNICA
# Francisney Delmondes
# Hub de diagnostico, suporte, rede, hardware e recuperacao
# ============================================================

& {
    $ErrorActionPreference = 'Continue'

    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {}

    $Hub = [PSCustomObject]@{
        Name       = 'INILOG TECH CENTER'
        Directory  = 'C:\ti\TechCenter'
        Reports    = 'C:\ti\Relatorios'
        RawRepo    = 'https://raw.githubusercontent.com/francisney/inilog/refs/heads/main'
        OldTitle   = $null
        CorBorda   = 'DarkCyan'
        CorTitulo  = 'Yellow'
        CorSecao   = 'Cyan'
        CorNumero  = 'Green'
        CorInfo    = 'Cyan'
        CorOk      = 'Green'
        CorAviso   = 'Yellow'
        CorErro    = 'Red'
    }

    try {
        $Hub.OldTitle = $Host.UI.RawUI.WindowTitle
        $Host.UI.RawUI.WindowTitle = 'INILOG - Central Tecnica'
    } catch {}

    # ------------------------------------------------------------
    # VISUAL
    # ------------------------------------------------------------

    function Get-HubWidth {
        $width = 88
        try {
            $current = $Host.UI.RawUI.WindowSize.Width - 1
            if ($current -ge 64 -and $current -le 120) { $width = $current }
        } catch {}
        return $width
    }

    function Write-HubLine {
        param([char]$Character='=', [ConsoleColor]$Color='DarkCyan')
        Write-Host ($Character.ToString() * (Get-HubWidth)) -ForegroundColor $Color
    }

    function Write-HubCentered {
        param([Parameter(Mandatory)][string]$Text, [ConsoleColor]$Color='White')
        $w = Get-HubWidth
        $pad = [Math]::Max(0, [Math]::Floor(($w - $Text.Length) / 2))
        Write-Host ((' ' * $pad) + $Text) -ForegroundColor $Color
    }

    function Write-HubStatus {
        param(
            [Parameter(Mandatory)][string]$Message,
            [ValidateSet('Info','Success','Warning','Error')][string]$Type='Info'
        )
        switch ($Type) {
            'Success' { Write-Host '[OK] ' -NoNewline -ForegroundColor $Hub.CorOk;    Write-Host $Message -ForegroundColor White }
            'Warning' { Write-Host '[!]  ' -NoNewline -ForegroundColor $Hub.CorAviso; Write-Host $Message -ForegroundColor White }
            'Error'   { Write-Host '[ERRO] ' -NoNewline -ForegroundColor $Hub.CorErro; Write-Host $Message -ForegroundColor White }
            default   { Write-Host '[i]  ' -NoNewline -ForegroundColor $Hub.CorInfo; Write-Host $Message -ForegroundColor White }
        }
    }

    function Write-HubMenuItem {
        param([string]$Number,[string]$Label,[string]$Tag='')
        Write-Host '  [' -NoNewline -ForegroundColor DarkGray
        Write-Host $Number.PadLeft(2,'0') -NoNewline -ForegroundColor $Hub.CorNumero
        Write-Host '] ' -NoNewline -ForegroundColor DarkGray
        Write-Host $Label -NoNewline -ForegroundColor White
        if ($Tag) {
            Write-Host ('  [' + $Tag + ']') -ForegroundColor DarkGray
        } else {
            Write-Host ''
        }
    }

    function Write-HubToolItem {
        param([Parameter(Mandatory)]$Tool)
        $tagColor = switch ($Tool.Type) {
            'CMD'    { 'Cyan' }
            'APP'    { 'Magenta' }
            'WEB'    { 'DarkYellow' }
            'MOD'    { 'Green' }
            default  { 'DarkGray' }
        }

        Write-Host '  [' -NoNewline -ForegroundColor DarkGray
        Write-Host ([string]$Tool.Index).PadLeft(2,'0') -NoNewline -ForegroundColor $Hub.CorNumero
        Write-Host '] ' -NoNewline -ForegroundColor DarkGray
        Write-Host ($Tool.Name.PadRight(24)) -NoNewline -ForegroundColor White
        Write-Host ('[' + $Tool.Type + ']') -NoNewline -ForegroundColor $tagColor
        if ($Tool.Danger) { Write-Host ' [!]' -NoNewline -ForegroundColor Red }
        Write-Host ('  ' + $Tool.Description) -ForegroundColor DarkGray
    }

    # ------------------------------------------------------------
    # SISTEMA
    # ------------------------------------------------------------

    function Test-HubAdmin {
        try {
            $id = [Security.Principal.WindowsIdentity]::GetCurrent()
            $p = New-Object Security.Principal.WindowsPrincipal($id)
            return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        } catch { return $false }
    }

    function Initialize-HubDirectory {
        foreach ($dir in @($Hub.Directory,$Hub.Reports)) {
            try {
                if (-not (Test-Path -LiteralPath $dir)) {
                    New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
                }
            } catch {
                Write-HubStatus "Nao foi possivel criar $dir. $($_.Exception.Message)" 'Error'
                return $false
            }
        }
        return $true
    }

    function Get-HubComputerInfo {
        $caption = 'Windows'
        $build = 'Desconhecido'
        $ram = '?'
        $cpu = '?'
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            if ($os.Caption) { $caption = ([string]$os.Caption -replace '^Microsoft\s+','').Trim() }
            if ($os.BuildNumber) { $build = [string]$os.BuildNumber }
            if ($os.TotalVisibleMemorySize) { $ram = ('{0:N1} GB' -f ($os.TotalVisibleMemorySize / 1MB)) }
        } catch {
            try {
                $os = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop
                if ($os.Caption) { $caption = ([string]$os.Caption -replace '^Microsoft\s+','').Trim() }
                if ($os.BuildNumber) { $build = [string]$os.BuildNumber }
                if ($os.TotalVisibleMemorySize) { $ram = ('{0:N1} GB' -f ($os.TotalVisibleMemorySize / 1MB)) }
            } catch {}
        }
        try {
            $proc = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
            if ($proc.Name) { $cpu = ([string]$proc.Name).Trim() }
        } catch {}

        [PSCustomObject]@{
            Computer = $env:COMPUTERNAME
            Windows  = $caption
            Build    = $build
            Arch     = $(if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' })
            Admin    = $(if (Test-HubAdmin) { 'SIM' } else { 'NAO' })
            Ram      = $ram
            Cpu      = $cpu
        }
    }

    function Read-HubValue {
        param([Parameter(Mandatory)][string]$Prompt,[string]$Default='')
        if ([string]::IsNullOrWhiteSpace($Default)) { return (Read-Host $Prompt).Trim() }
        $v = (Read-Host "$Prompt [$Default]").Trim()
        if ([string]::IsNullOrWhiteSpace($v)) { return $Default }
        return $v
    }

    function Confirm-HubAction {
        param([Parameter(Mandatory)][string]$Message,[string]$Word='CONFIRMAR')
        Write-Host ''
        Write-HubStatus $Message 'Warning'
        $answer = (Read-Host "Digite $Word para continuar").Trim()
        return ($answer -eq $Word)
    }

    function Open-HubUrl {
        param([Parameter(Mandatory)][string]$Uri,[Parameter(Mandatory)][string]$Description)
        try {
            Start-Process $Uri -ErrorAction Stop
            Write-HubStatus "$Description aberto no navegador." 'Success'
        } catch {
            Write-HubStatus "Nao foi possivel abrir $Description. $($_.Exception.Message)" 'Error'
        }
    }

    function Invoke-HubRemoteScript {
        param([Parameter(Mandatory)][string]$File,[Parameter(Mandatory)][string]$Description)
        $uri = '{0}/{1}?nocache={2}' -f $Hub.RawRepo,$File,[DateTime]::UtcNow.Ticks
        try {
            Write-HubStatus "Carregando $Description..." 'Info'
            $code = Invoke-RestMethod -Uri $uri -Headers @{ 'Cache-Control'='no-cache'; 'Pragma'='no-cache' } -TimeoutSec 60 -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace([string]$code)) { throw 'Script remoto vazio.' }
            Invoke-Expression ([string]$code)
        } catch {
            Write-HubStatus "Falha ao executar $Description. $($_.Exception.Message)" 'Error'
        }
    }

    # ------------------------------------------------------------
    # DOWNLOADS SEM CACHE
    # ------------------------------------------------------------

    function New-HubRunDirectory {
        param([Parameter(Mandatory)][string]$ToolName)
        $safe = ($ToolName -replace '[^a-zA-Z0-9_.-]','_')
        $base = Join-Path $Hub.Directory $safe
        if (-not (Test-Path -LiteralPath $base)) { New-Item -ItemType Directory -Path $base -Force | Out-Null }
        $run = Join-Path $base (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
        New-Item -ItemType Directory -Path $run -Force | Out-Null
        return $run
    }

    function Get-HubFileFresh {
        param(
            [Parameter(Mandatory)][string]$Uri,
            [Parameter(Mandatory)][string]$Destination,
            [Parameter(Mandatory)][string]$Description
        )
        try {
            $nocache = if ($Uri -match '\?') { '&' } else { '?' }
            $finalUri = $Uri + $nocache + 'nocache=' + [DateTime]::UtcNow.Ticks
            Write-HubStatus "Baixando $Description..." 'Info'
            Invoke-WebRequest -Uri $finalUri -OutFile $Destination -UseBasicParsing `
                -Headers @{ 'Cache-Control'='no-cache'; 'Pragma'='no-cache'; 'User-Agent'='INILOG-TechCenter' } `
                -TimeoutSec 180 -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $Destination)) { throw 'Arquivo nao recebido.' }
            Write-HubStatus "$Description baixado." 'Success'
            return $Destination
        } catch {
            Write-HubStatus "Falha no download de $Description. $($_.Exception.Message)" 'Error'
            return $null
        }
    }

    function Start-HubZipApp {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$Uri,
            [Parameter(Mandatory)][string]$ExeName
        )
        try {
            $dir = New-HubRunDirectory -ToolName $Name
            $zip = Join-Path $dir 'tool.zip'
            if (-not (Get-HubFileFresh -Uri $Uri -Destination $zip -Description $Name)) { return }
            Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force -ErrorAction Stop
            $exe = Get-ChildItem -LiteralPath $dir -Filter $ExeName -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $exe) { throw "Executavel $ExeName nao encontrado no ZIP." }
            Start-Process -FilePath $exe.FullName -ErrorAction Stop
            Write-HubStatus "$Name iniciado." 'Success'
        } catch {
            Write-HubStatus "Falha ao iniciar $Name. $($_.Exception.Message)" 'Error'
        }
    }

    function Get-HubGitHubLatestAsset {
        param([Parameter(Mandatory)][string]$Repo,[Parameter(Mandatory)][string]$Pattern)
        try {
            $api = "https://api.github.com/repos/$Repo/releases/latest?nocache=$([DateTime]::UtcNow.Ticks)"
            $release = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent'='INILOG-TechCenter'; 'Cache-Control'='no-cache' } -TimeoutSec 60 -ErrorAction Stop
            $asset = $release.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1
            if (-not $asset) { throw "Nenhum asset compativel encontrado em $Repo." }
            return [string]$asset.browser_download_url
        } catch {
            Write-HubStatus "Nao foi possivel localizar a versao mais recente de $Repo. $($_.Exception.Message)" 'Error'
            return $null
        }
    }

    function Start-HubGitHubExe {
        param([string]$Name,[string]$Repo,[string]$Pattern)
        $url = Get-HubGitHubLatestAsset -Repo $Repo -Pattern $Pattern
        if (-not $url) { Open-HubUrl -Uri "https://github.com/$Repo/releases" -Description "$Name - releases"; return }
        $dir = New-HubRunDirectory -ToolName $Name
        $fileName = [IO.Path]::GetFileName(([Uri]$url).AbsolutePath)
        $dest = Join-Path $dir $fileName
        if (Get-HubFileFresh -Uri $url -Destination $dest -Description $Name) {
            try { Start-Process -FilePath $dest -ErrorAction Stop; Write-HubStatus "$Name iniciado." 'Success' }
            catch { Write-HubStatus "Falha ao iniciar $Name. $($_.Exception.Message)" 'Error' }
        }
    }

    function Start-HubGitHubZip {
        param([string]$Name,[string]$Repo,[string]$Pattern,[string]$ExeName)
        $url = Get-HubGitHubLatestAsset -Repo $Repo -Pattern $Pattern
        if (-not $url) { Open-HubUrl -Uri "https://github.com/$Repo/releases" -Description "$Name - releases"; return }
        Start-HubZipApp -Name $Name -Uri $url -ExeName $ExeName
    }

    # ------------------------------------------------------------
    # COMANDOS / DIAGNOSTICO RAPIDO
    # ------------------------------------------------------------

    function Invoke-HubCommand {
        param([Parameter(Mandatory)][string]$Title,[Parameter(Mandatory)][scriptblock]$Script)
        Write-Host ''
        Write-HubLine '-' DarkGray
        Write-HubCentered $Title Cyan
        Write-HubLine '-' DarkGray
        Write-Host ''
        try { & $Script }
        catch { Write-HubStatus $_.Exception.Message 'Error' }
    }

    function Invoke-QuickSummary {
        Invoke-HubCommand 'RESUMO DO COMPUTADOR' {
            $info = Get-HubComputerInfo
            Write-Host ('PC:         {0}' -f $info.Computer)
            Write-Host ('Windows:    {0} - Build {1}' -f $info.Windows,$info.Build)
            Write-Host ('Arquitetura:{0}' -f (' ' + $info.Arch))
            Write-Host ('CPU:        {0}' -f $info.Cpu)
            Write-Host ('RAM:        {0}' -f $info.Ram)
            Write-Host ('Admin:      {0}' -f $info.Admin)
            Write-Host ''
            Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue |
                Select-Object DeviceID,VolumeName,@{N='TotalGB';E={[Math]::Round($_.Size/1GB,1)}},@{N='LivreGB';E={[Math]::Round($_.FreeSpace/1GB,1)}} |
                Format-Table -AutoSize
        }
    }

    function Invoke-QuickNetwork {
        Invoke-HubCommand 'DIAGNOSTICO DE REDE' {
            Write-Host '>>> ipconfig /all' -ForegroundColor Cyan
            ipconfig /all
            Write-Host "`n>>> route print" -ForegroundColor Cyan
            route print
            Write-Host "`n>>> arp -a" -ForegroundColor Cyan
            arp -a
            Write-Host "`n>>> ping 1.1.1.1 -n 4" -ForegroundColor Cyan
            ping 1.1.1.1 -n 4
            Write-Host "`n>>> nslookup google.com" -ForegroundColor Cyan
            nslookup google.com
        }
    }

    function Invoke-QuickWifi {
        Invoke-HubCommand 'DIAGNOSTICO WI-FI' {
            Write-Host '>>> netsh wlan show interfaces' -ForegroundColor Cyan
            netsh wlan show interfaces
            Write-Host "`n>>> netsh wlan show drivers" -ForegroundColor Cyan
            netsh wlan show drivers
            Write-Host "`n>>> netsh wlan show networks mode=bssid" -ForegroundColor Cyan
            netsh wlan show networks mode=bssid
        }
    }

    function Invoke-QuickDisk {
        Invoke-HubCommand 'DISCO E VOLUMES' {
            Write-Host '>>> chkdsk C: /scan' -ForegroundColor Cyan
            chkdsk C: /scan
            Write-Host ''
            if (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue) {
                Get-PhysicalDisk | Select-Object FriendlyName,MediaType,HealthStatus,OperationalStatus,Size | Format-Table -AutoSize
            }
            Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue |
                Select-Object DeviceID,VolumeName,FileSystem,@{N='TotalGB';E={[Math]::Round($_.Size/1GB,1)}},@{N='LivreGB';E={[Math]::Round($_.FreeSpace/1GB,1)}} |
                Format-Table -AutoSize
        }
    }

    function Invoke-QuickEvents {
        Invoke-HubCommand 'ERROS E EVENTOS RECENTES' {
            Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddDays(-3)} -ErrorAction SilentlyContinue |
                Select-Object -First 40 TimeCreated,Id,ProviderName,Message |
                Format-Table -Wrap -AutoSize
        }
    }

    function Invoke-QuickWindowsHealth {
        Invoke-HubCommand 'VERIFICACAO DO WINDOWS - SEM REPARO' {
            Write-Host '>>> DISM /Online /Cleanup-Image /ScanHealth' -ForegroundColor Cyan
            & dism.exe /Online /Cleanup-Image /ScanHealth
            Write-Host "`n>>> sfc /verifyonly" -ForegroundColor Cyan
            & sfc.exe /verifyonly
        }
    }

    function Invoke-QuickWindowsRepair {
        if (-not (Test-HubAdmin)) { Write-HubStatus 'Execute o PowerShell como Administrador para reparar o Windows.' 'Error'; return }
        if (-not (Confirm-HubAction 'DISM RestoreHealth e SFC /scannow farao reparos no Windows.' 'REPARAR')) { return }
        Invoke-HubCommand 'REPARO DO WINDOWS' {
            Write-Host '>>> DISM /Online /Cleanup-Image /RestoreHealth' -ForegroundColor Cyan
            & dism.exe /Online /Cleanup-Image /RestoreHealth
            Write-Host "`n>>> sfc /scannow" -ForegroundColor Cyan
            & sfc.exe /scannow
        }
    }

    function Invoke-QuickPrinter {
        Invoke-HubCommand 'IMPRESSORAS E SPOOLER' {
            Write-Host '>>> Status do Spooler' -ForegroundColor Cyan
            Get-Service Spooler | Format-Table Status,Name,DisplayName -AutoSize
            if (Get-Command Get-Printer -ErrorAction SilentlyContinue) {
                Write-Host "`n>>> Impressoras instaladas" -ForegroundColor Cyan
                Get-Printer | Select-Object Name,DriverName,PortName,PrinterStatus | Format-Table -AutoSize
            }
        }
        if (Confirm-HubAction 'Deseja reiniciar o servico Spooler agora?' 'REINICIAR') {
            try { Restart-Service Spooler -Force -ErrorAction Stop; Write-HubStatus 'Spooler reiniciado.' 'Success' }
            catch { Write-HubStatus $_.Exception.Message 'Error' }
        }
    }

    function Invoke-QuickDefender {
        if (-not (Confirm-HubAction 'Sera iniciada uma verificacao rapida do Microsoft Defender.' 'VERIFICAR')) { return }
        Invoke-HubCommand 'MICROSOFT DEFENDER - QUICK SCAN' {
            $mp = Get-Command Start-MpScan -ErrorAction SilentlyContinue
            if ($mp) {
                Write-Host '>>> Start-MpScan -ScanType QuickScan' -ForegroundColor Cyan
                Start-MpScan -ScanType QuickScan
                Write-HubStatus 'Verificacao rapida iniciada.' 'Success'
            } else {
                Write-HubStatus 'Cmdlet do Microsoft Defender nao encontrado.' 'Warning'
            }
        }
    }

    function Invoke-QuickReport {
        if (-not (Initialize-HubDirectory)) { return }
        $file = Join-Path $Hub.Reports ("diagnostico_{0}_{1}.txt" -f $env:COMPUTERNAME,(Get-Date -Format 'yyyyMMdd_HHmmss'))
        try {
            $lines = New-Object System.Collections.Generic.List[string]
            $lines.Add('INILOG - RELATORIO DE DIAGNOSTICO')
            $lines.Add(('Data: {0}' -f (Get-Date)))
            $lines.Add(('Computador: {0}' -f $env:COMPUTERNAME))
            $lines.Add('')
            $lines.Add('=== SYSTEMINFO ===')
            $lines.AddRange([string[]](& systeminfo.exe 2>&1))
            $lines.Add('')
            $lines.Add('=== IPCONFIG /ALL ===')
            $lines.AddRange([string[]](& ipconfig.exe /all 2>&1))
            $lines.Add('')
            $lines.Add('=== DISCOS ===')
            $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue | Out-String
            $lines.Add($disks)
            $lines.Add('=== EVENTOS CRITICOS/ERROS - 24H ===')
            $events = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddHours(-24)} -ErrorAction SilentlyContinue |
                Select-Object -First 50 TimeCreated,Id,ProviderName,Message | Format-List | Out-String
            $lines.Add($events)
            $lines | Set-Content -LiteralPath $file -Encoding UTF8
            Write-HubStatus "Relatorio criado: $file" 'Success'
            Start-Process notepad.exe -ArgumentList "`"$file`""
        } catch {
            Write-HubStatus "Falha ao criar relatorio. $($_.Exception.Message)" 'Error'
        }
    }

    # ------------------------------------------------------------
    # CATALOGO
    # ------------------------------------------------------------

    function New-HubTool {
        param(
            [string]$Category,[int]$Index,[string]$Name,[string]$Description,
            [ValidateSet('CMD','APP','WEB','MOD')][string]$Type,[string]$Action,
            [string]$P1='',[string]$P2='',[string]$P3='',[bool]$Danger=$false
        )
        [PSCustomObject]@{
            Category=$Category; Index=$Index; Name=$Name; Description=$Description;
            Type=$Type; Action=$Action; P1=$P1; P2=$P2; P3=$P3; Danger=$Danger
        }
    }

    $Categories = @(
        [PSCustomObject]@{ Code='QUICK'; Number='1'; Title='Diagnostico rapido INILOG' },
        [PSCustomObject]@{ Code='MS';    Number='2'; Title='Microsoft e Sysinternals' },
        [PSCustomObject]@{ Code='HW';    Number='3'; Title='Hardware, disco e desempenho' },
        [PSCustomObject]@{ Code='NET';   Number='4'; Title='Rede e Internet' },
        [PSCustomObject]@{ Code='DRV';   Number='5'; Title='Drivers, programas e manutencao' },
        [PSCustomObject]@{ Code='NIR';   Number='6'; Title='NirSoft - joias para tecnico' },
        [PSCustomObject]@{ Code='SEC';   Number='7'; Title='Seguranca e limpeza' },
        [PSCustomObject]@{ Code='BOOT';  Number='8'; Title='Boot, recuperacao e bancada' }
    )

    $Tools = @(
        # QUICK
        (New-HubTool 'QUICK' 1 'Resumo do PC'          'Windows, CPU, RAM e discos' 'CMD' 'QuickSummary'),
        (New-HubTool 'QUICK' 2 'Diagnostico de rede'   'ipconfig, rota, ARP, ping e DNS' 'CMD' 'QuickNetwork'),
        (New-HubTool 'QUICK' 3 'Diagnostico Wi-Fi'     'interface, driver e redes/BSSID' 'CMD' 'QuickWifi'),
        (New-HubTool 'QUICK' 4 'Disco e volumes'       'CHKDSK /scan, discos fisicos e espaco livre' 'CMD' 'QuickDisk'),
        (New-HubTool 'QUICK' 5 'Erros recentes'        'Eventos criticos/erros dos ultimos 3 dias' 'CMD' 'QuickEvents'),
        (New-HubTool 'QUICK' 6 'Saude do Windows'      'DISM ScanHealth + SFC verifyonly, sem reparar' 'CMD' 'QuickWindowsHealth'),
        (New-HubTool 'QUICK' 7 'Reparar Windows'       'DISM RestoreHealth + SFC /scannow' 'CMD' 'QuickWindowsRepair' '' '' '' $true),
        (New-HubTool 'QUICK' 8 'Impressoras / Spooler' 'Lista impressoras e pode reiniciar Spooler' 'CMD' 'QuickPrinter'),
        (New-HubTool 'QUICK' 9 'Defender Quick Scan'   'Inicia verificacao rapida do Microsoft Defender' 'CMD' 'QuickDefender'),
        (New-HubTool 'QUICK' 10 'Gerar relatorio TXT'  'Systeminfo, rede, discos e eventos em C:\ti\Relatorios' 'CMD' 'QuickReport'),

        # MICROSOFT
        (New-HubTool 'MS' 1 'Microsoft Sysinternals' 'Central avancada com dezenas de utilitarios Microsoft' 'MOD' 'RemoteScript' 'sysinternals.ps1'),
        (New-HubTool 'MS' 2 'PowerToys'              'File Locksmith, PowerRename, Hosts, utilitarios Microsoft' 'WEB' 'Web' 'https://learn.microsoft.com/windows/powertoys/'),
        (New-HubTool 'MS' 3 'WinDbg'                 'Analise profissional de dumps e telas azuis' 'WEB' 'Web' 'https://learn.microsoft.com/windows-hardware/drivers/debugger/'),
        (New-HubTool 'MS' 4 'Microsoft Safety Scanner' 'Scanner antimalware sob demanda da Microsoft' 'WEB' 'Web' 'https://learn.microsoft.com/microsoft-365/security/intelligence/safety-scanner-download'),

        # HARDWARE
        (New-HubTool 'HW' 1 'HWiNFO'          'Sensores, temperatura, clocks e inventario completo' 'WEB' 'Web' 'https://www.hwinfo.com/download/'),
        (New-HubTool 'HW' 2 'CPU-Z'           'CPU, placa-mae, RAM e SPD' 'WEB' 'Web' 'https://www.cpuid.com/softwares/cpu-z.html'),
        (New-HubTool 'HW' 3 'GPU-Z'           'GPU, VRAM, sensores e BIOS da placa de video' 'WEB' 'Web' 'https://www.techpowerup.com/gpuz/'),
        (New-HubTool 'HW' 4 'CrystalDiskInfo' 'SMART e saude de HDD/SSD/NVMe' 'WEB' 'Web' 'https://crystalmark.info/en/software/crystaldiskinfo/'),
        (New-HubTool 'HW' 5 'CrystalDiskMark' 'Benchmark de leitura e escrita de discos' 'WEB' 'Web' 'https://crystalmark.info/en/software/crystaldiskmark/'),
        (New-HubTool 'HW' 6 'WizTree'         'Descobre rapidamente o que ocupa espaco no disco' 'WEB' 'Web' 'https://diskanalyzer.com/download'),
        (New-HubTool 'HW' 7 'Everything'      'Busca instantanea de arquivos e pastas' 'WEB' 'Web' 'https://www.voidtools.com/downloads/'),
        (New-HubTool 'HW' 8 'OCCT'            'Stress test de CPU, GPU, RAM e fonte' 'WEB' 'Web' 'https://www.ocbase.com/download'),
        (New-HubTool 'HW' 9 'LatencyMon'      'Analisa DPC/ISR e problemas de audio/latencia' 'WEB' 'Web' 'https://www.resplendence.com/latencymon'),

        # REDE
        (New-HubTool 'NET' 1 'Wireshark'              'Captura e analise profunda de pacotes' 'WEB' 'Web' 'https://www.wireshark.org/download.html'),
        (New-HubTool 'NET' 2 'Nmap / Zenmap'          'Descoberta de hosts, portas e servicos' 'WEB' 'Web' 'https://nmap.org/download.html'),
        (New-HubTool 'NET' 3 'Advanced IP Scanner'    'Scanner visual rapido de rede local' 'WEB' 'Web' 'https://www.advanced-ip-scanner.com/'),
        (New-HubTool 'NET' 4 'Angry IP Scanner'       'Scanner leve de IPs e portas' 'WEB' 'Web' 'https://angryip.org/download/'),
        (New-HubTool 'NET' 5 'CurrPorts'              'Portas TCP/UDP e processo responsavel' 'APP' 'ZipApp' 'https://www.nirsoft.net/utils/cports-x64.zip' 'cports.exe'),
        (New-HubTool 'NET' 6 'Wireless Network Watcher' 'Mostra dispositivos conectados na rede' 'APP' 'ZipApp' 'https://www.nirsoft.net/utils/wnetwatcher-x64.zip' 'WNetWatcher.exe'),
        (New-HubTool 'NET' 7 'WinMTR'                 'Ping + traceroute continuo para perda/latencia' 'WEB' 'Web' 'https://github.com/White-Tiger/WinMTR/releases'),
        (New-HubTool 'NET' 8 'Speedtest INILOG'       'Executa seu teste de velocidade atual' 'MOD' 'RemoteScript' 'speedtest.ps1'),

        # DRIVERS / MANUTENCAO
        (New-HubTool 'DRV' 1 'Driver Store Explorer'  'Gerencia DriverStore e identifica drivers antigos' 'APP' 'GitHubZip' 'lostindark/DriverStoreExplorer' '(?i)DriverStoreExplorer.*\.zip$' 'Rapr.exe'),
        (New-HubTool 'DRV' 2 'DDU'                    'Remove completamente drivers de video/audio' 'WEB' 'Web' 'https://www.wagnardsoft.com/display-driver-uninstaller-ddu-'),
        (New-HubTool 'DRV' 3 'Snappy Driver Installer Origin' 'Drivers offline e instalacao tecnica' 'WEB' 'Web' 'https://www.glenn.delahoy.com/snappy-driver-installer-origin/'),
        (New-HubTool 'DRV' 4 'Revo Uninstaller'       'Desinstalacao e limpeza de residuos' 'WEB' 'Web' 'https://www.revouninstaller.com/revo-uninstaller-free-download/'),
        (New-HubTool 'DRV' 5 'Bulk Crap Uninstaller'  'Remove muitos programas e sobras rapidamente' 'WEB' 'Web' 'https://github.com/Klocman/Bulk-Crap-Uninstaller/releases'),
        (New-HubTool 'DRV' 6 'Windows Repair Toolbox' 'Central de reparo e utilitarios para tecnico' 'WEB' 'Web' 'https://windows-repair-toolbox.com/'),
        (New-HubTool 'DRV' 7 'Patch My PC Home Updater' 'Atualiza varios aplicativos instalados' 'WEB' 'Web' 'https://patchmypc.com/product/home-updater'),

        # NIRSOFT
        (New-HubTool 'NIR' 1 'BlueScreenView'  'Le minidumps de tela azul rapidamente' 'APP' 'ZipApp' 'https://www.nirsoft.net/utils/bluescreenview-x64.zip' 'BlueScreenView.exe'),
        (New-HubTool 'NIR' 2 'USBDeview'       'Historico e gerenciamento de dispositivos USB' 'APP' 'ZipApp' 'https://www.nirsoft.net/utils/usbdeview-x64.zip' 'USBDeview.exe'),
        (New-HubTool 'NIR' 3 'AppCrashView'    'Lista crashes registrados pelo Windows Error Reporting' 'APP' 'ZipApp' 'https://www.nirsoft.net/utils/appcrashview.zip' 'AppCrashView.exe'),
        (New-HubTool 'NIR' 4 'ShellExView'     'Diagnostica extensoes de shell/menu de contexto' 'APP' 'ZipApp' 'https://www.nirsoft.net/utils/shexview-x64.zip' 'shexview.exe'),
        (New-HubTool 'NIR' 5 'DevManView'      'Gerenciador de dispositivos alternativo e tecnico' 'APP' 'ZipApp' 'https://www.nirsoft.net/utils/devmanview-x64.zip' 'DevManView.exe'),
        (New-HubTool 'NIR' 6 'DriverView'      'Mostra todos os drivers carregados no Windows' 'APP' 'ZipApp' 'https://www.nirsoft.net/utils/driverview-x64.zip' 'DriverView.exe'),
        (New-HubTool 'NIR' 7 'RegScanner'      'Pesquisa avancada e muito rapida no Registro' 'APP' 'ZipApp' 'https://www.nirsoft.net/utils/regscanner-x64.zip' 'RegScanner.exe'),
        (New-HubTool 'NIR' 8 'SearchMyFiles'   'Busca avancada de arquivos sem indexacao' 'WEB' 'Web' 'https://www.nirsoft.net/utils/search_my_files.html'),
        (New-HubTool 'NIR' 9 'WhatIsHang'      'Ajuda a diagnosticar programas travados' 'WEB' 'Web' 'https://www.nirsoft.net/utils/what_is_hang.html'),

        # SEGURANCA
        (New-HubTool 'SEC' 1 'Malwarebytes AdwCleaner' 'Adware, PUPs, barras e alteracoes indesejadas' 'WEB' 'Web' 'https://www.malwarebytes.com/adwcleaner'),
        (New-HubTool 'SEC' 2 'Emsisoft Emergency Kit'  'Scanner portatil de malware para atendimento' 'WEB' 'Web' 'https://www.emsisoft.com/en/home/emergency-kit/'),
        (New-HubTool 'SEC' 3 'VirusTotal'              'Analisa arquivos e URLs com multiplos motores' 'WEB' 'Web' 'https://www.virustotal.com/gui/home/upload'),
        (New-HubTool 'SEC' 4 'Microsoft Defender Scan' 'Executa Quick Scan pelo PowerShell' 'CMD' 'QuickDefender'),
        (New-HubTool 'SEC' 5 'Safety Scanner Microsoft' 'Scanner Microsoft sob demanda' 'WEB' 'Web' 'https://learn.microsoft.com/microsoft-365/security/intelligence/safety-scanner-download'),

        # BOOT / RECUPERACAO
        (New-HubTool 'BOOT' 1 'Rufus'          'Cria pendrive bootavel rapidamente' 'APP' 'GitHubExe' 'pbatard/rufus' '^rufus-[0-9.]+p?\.exe$'),
        (New-HubTool 'BOOT' 2 'Ventoy'         'Pendrive multiboot para varias ISOs' 'APP' 'GitHubZip' 'ventoy/Ventoy' '(?i)ventoy-.*-windows\.zip$' 'Ventoy2Disk.exe'),
        (New-HubTool 'BOOT' 3 'MemTest86'      'Teste de memoria RAM independente do Windows' 'WEB' 'Web' 'https://www.memtest86.com/download.htm'),
        (New-HubTool 'BOOT' 4 'TestDisk / PhotoRec' 'Recuperacao de particoes e arquivos' 'WEB' 'Web' 'https://www.cgsecurity.org/wiki/TestDisk_Download'),
        (New-HubTool 'BOOT' 5 'Rescuezilla'    'Imagem, clone e restauracao de discos com GUI' 'WEB' 'Web' 'https://rescuezilla.com/download'),
        (New-HubTool 'BOOT' 6 'Clonezilla'     'Clone e imagem de discos para bancada' 'WEB' 'Web' 'https://clonezilla.org/downloads.php'),
        (New-HubTool 'BOOT' 7 'GParted Live'   'Particionamento offline por boot' 'WEB' 'Web' 'https://gparted.org/download.php')
    )

    # ------------------------------------------------------------
    # EXECUCAO DE FERRAMENTAS
    # ------------------------------------------------------------

    function Invoke-HubTool {
        param([Parameter(Mandatory)]$Tool)

        if ($Tool.Danger) {
            if (-not (Confirm-HubAction "A acao '$($Tool.Name)' pode alterar o Windows. Continue apenas se souber o que esta fazendo." 'CONTINUAR')) { return }
        }

        switch ($Tool.Action) {
            'QuickSummary'       { Invoke-QuickSummary }
            'QuickNetwork'       { Invoke-QuickNetwork }
            'QuickWifi'          { Invoke-QuickWifi }
            'QuickDisk'          { Invoke-QuickDisk }
            'QuickEvents'        { Invoke-QuickEvents }
            'QuickWindowsHealth' { Invoke-QuickWindowsHealth }
            'QuickWindowsRepair' { Invoke-QuickWindowsRepair }
            'QuickPrinter'       { Invoke-QuickPrinter }
            'QuickDefender'      { Invoke-QuickDefender }
            'QuickReport'        { Invoke-QuickReport }
            'RemoteScript'       { Invoke-HubRemoteScript -File $Tool.P1 -Description $Tool.Name }
            'Web'                { Open-HubUrl -Uri $Tool.P1 -Description $Tool.Name }
            'ZipApp'             { Start-HubZipApp -Name $Tool.Name -Uri $Tool.P1 -ExeName $Tool.P2 }
            'GitHubExe'          { Start-HubGitHubExe -Name $Tool.Name -Repo $Tool.P1 -Pattern $Tool.P2 }
            'GitHubZip'          { Start-HubGitHubZip -Name $Tool.Name -Repo $Tool.P1 -Pattern $Tool.P2 -ExeName $Tool.P3 }
            default              { Write-HubStatus "Acao desconhecida: $($Tool.Action)" 'Error' }
        }
    }

    # ------------------------------------------------------------
    # MENUS
    # ------------------------------------------------------------

    function Show-HubHeader {
        param([Parameter(Mandatory)]$Info)
        Clear-Host
        Write-HubLine '=' $Hub.CorBorda
        Write-HubCentered 'INILOG' $Hub.CorTitulo
        Write-HubCentered 'TECH CENTER - CENTRAL TECNICA' White
        Write-HubLine '=' $Hub.CorBorda
        Write-Host ''
        Write-Host '  PC:      ' -NoNewline -ForegroundColor DarkGray; Write-Host $Info.Computer -ForegroundColor White
        Write-Host '  Windows: ' -NoNewline -ForegroundColor DarkGray; Write-Host ("{0} - Build {1}" -f $Info.Windows,$Info.Build) -ForegroundColor White
        Write-Host '  CPU:     ' -NoNewline -ForegroundColor DarkGray; Write-Host $Info.Cpu -ForegroundColor White
        Write-Host '  RAM:     ' -NoNewline -ForegroundColor DarkGray; Write-Host $Info.Ram -ForegroundColor White
        Write-Host '  Admin:   ' -NoNewline -ForegroundColor DarkGray
        if ($Info.Admin -eq 'SIM') { Write-Host 'SIM' -ForegroundColor Green } else { Write-Host 'NAO' -ForegroundColor Yellow }
        Write-Host '  Pasta:   ' -NoNewline -ForegroundColor DarkGray; Write-Host $Hub.Directory -ForegroundColor White
    }

    function Show-HubMainMenu {
        param([Parameter(Mandatory)]$Info)
        Show-HubHeader -Info $Info
        Write-Host ''
        Write-Host '  CENTRAIS' -ForegroundColor $Hub.CorSecao
        foreach ($c in $Categories) { Write-HubMenuItem $c.Number $c.Title }
        Write-Host ''
        Write-HubLine '-' DarkGray
        Write-HubMenuItem 'S' 'Pesquisar ferramenta pelo nome'
        Write-HubMenuItem '90' 'Abrir pasta do Tech Center'
        Write-HubMenuItem '91' 'Gerar relatorio rapido do PC'
        Write-HubMenuItem '00' 'Voltar ao INILOG'
        Write-HubLine '=' $Hub.CorBorda
        Write-Host ''
        Write-Host '  Legenda: [CMD] comando direto | [APP] baixa/abre | [WEB] fonte oficial | [MOD] modulo INILOG' -ForegroundColor DarkGray
        Write-Host ''
    }

    function Show-HubCategoryMenu {
        param([Parameter(Mandatory)]$Category,[Parameter(Mandatory)]$Info)
        do {
            Show-HubHeader -Info $Info
            Write-Host ''
            Write-Host ('  ' + $Category.Title.ToUpperInvariant()) -ForegroundColor $Hub.CorSecao
            Write-Host ''

            $list = @($Tools | Where-Object { $_.Category -eq $Category.Code } | Sort-Object Index)
            foreach ($tool in $list) { Write-HubToolItem -Tool $tool }

            Write-Host ''
            Write-HubLine '-' DarkGray
            Write-HubMenuItem '00' 'Voltar as categorias'
            Write-HubLine '=' $Hub.CorBorda
            Write-Host ''

            $choice = (Read-Host 'Escolha uma ferramenta').Trim()
            if ($choice -match '^0+$') { return }

            $number = 0
            if ([int]::TryParse($choice,[ref]$number)) {
                $tool = $list | Where-Object { $_.Index -eq $number } | Select-Object -First 1
                if ($tool) {
                    Write-Host ''
                    Invoke-HubTool -Tool $tool
                } else {
                    Write-HubStatus "Opcao '$choice' invalida." 'Warning'
                }
            } else {
                Write-HubStatus "Opcao '$choice' invalida." 'Warning'
            }

            Write-Host ''
            [void](Read-Host 'Pressione Enter para voltar')
        } while ($true)
    }

    function Search-HubTools {
        param([Parameter(Mandatory)]$Info)
        Show-HubHeader -Info $Info
        Write-Host ''
        $q = (Read-Host 'Digite parte do nome ou descricao').Trim()
        if (-not $q) { return }

        $matches = @($Tools | Where-Object { $_.Name -like "*$q*" -or $_.Description -like "*$q*" } | Sort-Object Category,Index)
        if ($matches.Count -eq 0) {
            Write-HubStatus 'Nenhuma ferramenta encontrada.' 'Warning'
            [void](Read-Host 'Pressione Enter para voltar')
            return
        }

        Write-Host ''
        for ($i=0; $i -lt $matches.Count; $i++) {
            Write-Host ('  [{0}] {1} [{2}] - {3}' -f ($i+1).ToString().PadLeft(2,'0'),$matches[$i].Name,$matches[$i].Type,$matches[$i].Description) -ForegroundColor White
        }
        Write-Host ''
        $sel = Read-HubValue 'Escolha resultado; 0 para cancelar' '0'
        $n = 0
        if ([int]::TryParse($sel,[ref]$n) -and $n -ge 1 -and $n -le $matches.Count) {
            Write-Host ''
            Invoke-HubTool -Tool $matches[$n-1]
            Write-Host ''
            [void](Read-Host 'Pressione Enter para voltar')
        }
    }

    # ------------------------------------------------------------
    # PRINCIPAL
    # ------------------------------------------------------------

    try {
        Initialize-HubDirectory | Out-Null
        $Info = Get-HubComputerInfo

        do {
            Show-HubMainMenu -Info $Info
            $choice = (Read-Host 'Escolha uma opcao').Trim()
            if ($choice -match '^\d+$') {
                try { $choice = ([int]$choice).ToString() } catch {}
            }

            if ($choice -match '^0+$') { break }

            $category = $Categories | Where-Object { $_.Number -eq $choice } | Select-Object -First 1
            if ($category) {
                Show-HubCategoryMenu -Category $category -Info $Info
                continue
            }

            switch ($choice.ToUpperInvariant()) {
                'S'  { Search-HubTools -Info $Info }
                '90' {
                    try { Start-Process explorer.exe -ArgumentList "`"$($Hub.Directory)`"" }
                    catch { Write-HubStatus $_.Exception.Message 'Error'; Start-Sleep -Seconds 1 }
                }
                '91' {
                    Invoke-QuickReport
                    Write-Host ''
                    [void](Read-Host 'Pressione Enter para voltar')
                }
                default {
                    Write-HubStatus "Opcao '$choice' invalida." 'Warning'
                    Start-Sleep -Milliseconds 700
                }
            }
        } while ($true)

    } finally {
        try {
            if (-not [string]::IsNullOrWhiteSpace([string]$Hub.OldTitle)) {
                $Host.UI.RawUI.WindowTitle = $Hub.OldTitle
            }
        } catch {}
        Clear-Host
    }
}
