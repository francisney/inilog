#requires -Version 5.1

# ============================================================
# INILOG - Central Microsoft Sysinternals
# Francisney Delmondes
# https://live.sysinternals.com/tools/
# ============================================================

& {
    $ErrorActionPreference = 'Continue'

    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {}

    $Sys = [PSCustomObject]@{
        BaseUrl      = 'https://live.sysinternals.com/tools'
        Directory    = 'C:\ti\Sysinternals'
        OldTitle     = $null
        CorBorda     = 'DarkCyan'
        CorTitulo    = 'Yellow'
        CorSecao     = 'Cyan'
        CorNumero    = 'Green'
        CorInfo      = 'Cyan'
        CorOk        = 'Green'
        CorAviso     = 'Yellow'
        CorErro      = 'Red'
    }

    try {
        $Sys.OldTitle = $Host.UI.RawUI.WindowTitle
        $Host.UI.RawUI.WindowTitle = 'INILOG - Microsoft Sysinternals'
    } catch {}

    function Get-SysWidth {
        $width = 82
        try {
            $current = $Host.UI.RawUI.WindowSize.Width - 1
            if ($current -ge 60 -and $current -le 120) { $width = $current }
        } catch {}
        return $width
    }

    function Write-SysLine {
        param([char]$Character='=', [ConsoleColor]$Color='DarkCyan')
        Write-Host ($Character.ToString() * (Get-SysWidth)) -ForegroundColor $Color
    }

    function Write-SysCentered {
        param([Parameter(Mandatory)][string]$Text, [ConsoleColor]$Color='White')
        $w = Get-SysWidth
        $pad = [Math]::Max(0, [Math]::Floor(($w - $Text.Length) / 2))
        Write-Host ((' ' * $pad) + $Text) -ForegroundColor $Color
    }

    function Write-SysStatus {
        param(
            [Parameter(Mandatory)][string]$Message,
            [ValidateSet('Info','Success','Warning','Error')][string]$Type='Info'
        )
        switch ($Type) {
            'Success' { Write-Host '[OK] ' -NoNewline -ForegroundColor $Sys.CorOk;    Write-Host $Message -ForegroundColor White }
            'Warning' { Write-Host '[!]  ' -NoNewline -ForegroundColor $Sys.CorAviso; Write-Host $Message -ForegroundColor White }
            'Error'   { Write-Host '[ERRO] ' -NoNewline -ForegroundColor $Sys.CorErro; Write-Host $Message -ForegroundColor White }
            default   { Write-Host '[i]  ' -NoNewline -ForegroundColor $Sys.CorInfo; Write-Host $Message -ForegroundColor White }
        }
    }

    function Test-SysAdmin {
        try {
            $id = [Security.Principal.WindowsIdentity]::GetCurrent()
            $p = New-Object Security.Principal.WindowsPrincipal($id)
            return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        } catch { return $false }
    }

    function Initialize-SysDirectory {
        try {
            if (-not (Test-Path -LiteralPath $Sys.Directory)) {
                New-Item -ItemType Directory -Path $Sys.Directory -Force -ErrorAction Stop | Out-Null
            }
            return $true
        } catch {
            try {
                $Sys.Directory = Join-Path $env:TEMP 'INILOG\Sysinternals'
                if (-not (Test-Path -LiteralPath $Sys.Directory)) {
                    New-Item -ItemType Directory -Path $Sys.Directory -Force -ErrorAction Stop | Out-Null
                }
                Write-SysStatus "Usando diretório alternativo: $($Sys.Directory)" 'Warning'
                return $true
            } catch {
                Write-SysStatus "Não foi possível criar a pasta das ferramentas. $($_.Exception.Message)" 'Error'
                return $false
            }
        }
    }

    function Test-SysMicrosoftSignature {
        param([Parameter(Mandatory)][string]$Path)
        try {
            $sig = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
            if ($sig.Status -ne 'Valid') { return $false }
            if ($null -eq $sig.SignerCertificate) { return $false }
            return ([string]$sig.SignerCertificate.Subject -match 'Microsoft')
        } catch { return $false }
    }

    function Get-SysToolFileName {
        param([Parameter(Mandatory)]$Tool)
        if ([Environment]::Is64BitOperatingSystem -and -not [string]::IsNullOrWhiteSpace([string]$Tool.File64)) {
            return [string]$Tool.File64
        }
        return [string]$Tool.File32
    }

    function Get-SysToolFresh {
        param([Parameter(Mandatory)]$Tool)

        if (-not (Initialize-SysDirectory)) { return $null }

        $fileName = Get-SysToolFileName -Tool $Tool
        if ([string]::IsNullOrWhiteSpace($fileName)) {
            Write-SysStatus "Executável não definido para $($Tool.Name)." 'Error'
            return $null
        }

        $destination = Join-Path $Sys.Directory $fileName
        $temporary = "$destination.download.exe"
        $nocache = [DateTime]::UtcNow.Ticks
        $uri = '{0}/{1}?nocache={2}' -f $Sys.BaseUrl, $fileName, $nocache

        try {
            if (Test-Path -LiteralPath $temporary) {
                Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
            }

            Write-SysStatus "Baixando $($Tool.Name) diretamente da Microsoft..." 'Info'

            Invoke-WebRequest -Uri $uri `
                -OutFile $temporary `
                -UseBasicParsing `
                -Headers @{ 'Cache-Control'='no-cache'; 'Pragma'='no-cache' } `
                -TimeoutSec 120 `
                -ErrorAction Stop

            if (-not (Test-Path -LiteralPath $temporary)) {
                throw 'O arquivo não foi recebido.'
            }

            Write-SysStatus 'Verificando assinatura digital Microsoft...' 'Info'
            if (-not (Test-SysMicrosoftSignature -Path $temporary)) {
                throw 'A assinatura digital Microsoft não pôde ser validada.'
            }

            try {
                Move-Item -LiteralPath $temporary -Destination $destination -Force -ErrorAction Stop
            } catch {
                # Se a versão anterior estiver em uso, salva a nova com nome único.
                $base = [IO.Path]::GetFileNameWithoutExtension($fileName)
                $ext  = [IO.Path]::GetExtension($fileName)
                $destination = Join-Path $Sys.Directory ("{0}_{1}{2}" -f $base, [DateTime]::Now.ToString('yyyyMMdd_HHmmss'), $ext)
                Move-Item -LiteralPath $temporary -Destination $destination -Force -ErrorAction Stop
            }

            Write-SysStatus "$($Tool.Name) validado: $destination" 'Success'
            return $destination
        } catch {
            if (Test-Path -LiteralPath $temporary) {
                Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
            }
            Write-SysStatus "Falha ao obter $($Tool.Name). $($_.Exception.Message)" 'Error'
            return $null
        }
    }

    function Read-SysValue {
        param(
            [Parameter(Mandatory)][string]$Prompt,
            [string]$Default=''
        )
        if ([string]::IsNullOrWhiteSpace($Default)) {
            return (Read-Host $Prompt).Trim()
        }
        $v = (Read-Host "$Prompt [$Default]").Trim()
        if ([string]::IsNullOrWhiteSpace($v)) { return $Default }
        return $v
    }

    function Confirm-SysDanger {
        param([Parameter(Mandatory)][string]$Message, [string]$Word='CONFIRMAR')
        Write-Host ''
        Write-SysStatus $Message 'Warning'
        $answer = (Read-Host "Digite $Word para continuar").Trim()
        return ($answer -eq $Word)
    }

    function Invoke-SysConsoleCommand {
        param(
            [Parameter(Mandatory)][string]$Path,
            [string[]]$Arguments=@()
        )

        Write-Host ''
        Write-SysLine '-' DarkGray
        Write-Host '  COMANDO: ' -NoNewline -ForegroundColor DarkGray
        Write-Host (([IO.Path]::GetFileName($Path)) + ' ' + ($Arguments -join ' ')) -ForegroundColor Cyan
        Write-SysLine '-' DarkGray
        Write-Host ''

        try {
            & $Path @Arguments
        } catch {
            Write-SysStatus "Erro ao executar comando. $($_.Exception.Message)" 'Error'
        }
    }

    function Start-SysGuiTool {
        param([Parameter(Mandatory)]$Tool, [Parameter(Mandatory)][string]$Path)
        try {
            Start-Process -FilePath $Path -ErrorAction Stop
            Write-SysStatus "$($Tool.Name) iniciado." 'Success'
        } catch {
            Write-SysStatus "Não foi possível iniciar $($Tool.Name). $($_.Exception.Message)" 'Error'
        }
    }

    function Invoke-SysAction {
        param([Parameter(Mandatory)]$Tool, [Parameter(Mandatory)][string]$Path)

        $args = @()

        switch ([string]$Tool.Action) {
            'NoArgs' {
                Invoke-SysConsoleCommand -Path $Path
            }

            'CoreInfo' {
                # Sem parâmetros: Coreinfo exibe CPU, caches, NUMA, sockets e recursos.
                Invoke-SysConsoleCommand -Path $Path
            }

            'Autorunsc' {
                # Todos os pontos de inicialização, ocultando Microsoft, com hash e assinatura.
                $args = @('-a','*','-m','-s','-h')
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'Tcpvcon' {
                # Mostra todos endpoints sem resolver DNS para retornar rápido.
                $args = @('-a','-n')
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'PsPing' {
                $target = Read-SysValue 'IP ou host' '8.8.8.8'
                $args = @('-n','10',$target)
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'Whois' {
                $target = Read-SysValue 'Domínio ou IP'
                if ($target) { Invoke-SysConsoleCommand -Path $Path -Arguments @($target) }
            }

            'ProcDump' {
                $process = Read-SysValue 'Processo ou PID' 'explorer.exe'
                $dumpDir = 'C:\ti\Dumps'
                try { New-Item -ItemType Directory -Path $dumpDir -Force | Out-Null } catch {}
                $safeName = ($process -replace '[^a-zA-Z0-9_.-]','_')
                $dumpFile = Join-Path $dumpDir ("{0}_{1}.dmp" -f $safeName, (Get-Date -Format 'yyyyMMdd_HHmmss'))
                $args = @('-accepteula','-ma',$process,$dumpFile)
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
                Write-SysStatus "Dump solicitado em: $dumpFile" 'Info'
            }

            'Handle' {
                $target = Read-SysValue 'Nome do arquivo/pasta/objeto a localizar'
                if ($target) {
                    $args = @('-accepteula',$target)
                    Invoke-SysConsoleCommand -Path $Path -Arguments $args
                }
            }

            'ListDlls' {
                $process = Read-SysValue 'Processo ou PID' 'explorer'
                $args = @('-v',$process)
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'LogonSessions' {
                $args = @('-p')
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'Du' {
                $dir = Read-SysValue 'Pasta para analisar' 'C:\'
                $args = @('-l','1',$dir)
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'NtfsInfo' {
                $drive = Read-SysValue 'Letra da unidade NTFS' 'C'
                $drive = $drive.TrimEnd(':')
                Invoke-SysConsoleCommand -Path $Path -Arguments @($drive)
            }

            'FindLinks' {
                $file = Read-SysValue 'Arquivo para localizar hard links'
                if ($file) { Invoke-SysConsoleCommand -Path $Path -Arguments @($file.Trim('"')) }
            }

            'Streams' {
                $default = Join-Path $env:USERPROFILE 'Downloads'
                $target = Read-SysValue 'Arquivo ou pasta para verificar ADS' $default
                Invoke-SysConsoleCommand -Path $Path -Arguments @($target.Trim('"'))
            }

            'Junction' {
                $target = Read-SysValue 'Arquivo/pasta ou junction para consultar' 'C:\'
                Invoke-SysConsoleCommand -Path $Path -Arguments @($target.Trim('"'))
            }

            'Contig' {
                $target = Read-SysValue 'Arquivo/pasta para analisar fragmentação' 'C:\Windows\explorer.exe'
                $args = @('-a',$target.Trim('"'))
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'EfsDump' {
                $target = Read-SysValue 'Pasta/arquivo EFS para consultar' $env:USERPROFILE
                Invoke-SysConsoleCommand -Path $Path -Arguments @($target.Trim('"'))
            }

            'MoveFile' {
                if (-not (Confirm-SysDanger 'MoveFile agenda mover ou excluir arquivos no próximo boot.' 'AGENDAR')) { return }
                $source = Read-SysValue 'Arquivo de origem'
                if (-not $source) { return }
                $dest = Read-SysValue 'Destino. Digite DELETE para excluir no próximo boot'
                if ($dest -eq 'DELETE') { $dest = '' }
                Invoke-SysConsoleCommand -Path $Path -Arguments @($source.Trim('"'),$dest.Trim('"'))
            }

            'Ru' {
                $key = Read-SysValue 'Chave do Registro' 'HKLM\SOFTWARE'
                $args = @('-l','1',$key)
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'Hex2Dec' {
                $value = Read-SysValue 'Valor decimal ou hexadecimal (ex: 0xFF)' '0xFF'
                Invoke-SysConsoleCommand -Path $Path -Arguments @($value)
            }

            'Strings' {
                $target = Read-SysValue 'Arquivo a analisar' 'C:\Windows\System32\notepad.exe'
                $args = @('-n','6',$target.Trim('"'))
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'AccessChk' {
                Write-Host '  [1] Permissões de arquivo/pasta' -ForegroundColor White
                Write-Host '  [2] Serviços do Windows' -ForegroundColor White
                Write-Host '  [3] Processo' -ForegroundColor White
                $m = Read-SysValue 'Modo' '1'
                switch ($m) {
                    '2' { $args = @('-accepteula','-c','*') }
                    '3' {
                        $p = Read-SysValue 'Processo ou PID' 'explorer.exe'
                        $args = @('-accepteula','-p',$p)
                    }
                    default {
                        $t = Read-SysValue 'Arquivo ou pasta' 'C:\Windows'
                        $args = @('-accepteula','-v',$t.Trim('"'))
                    }
                }
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'SigCheck' {
                Write-Host '  [1] Verificar arquivo com assinatura + hash' -ForegroundColor White
                Write-Host '  [2] Procurar executáveis não assinados em System32' -ForegroundColor White
                $m = Read-SysValue 'Modo' '1'
                if ($m -eq '2') {
                    $args = @('-accepteula','-u','-e','-nobanner','C:\Windows\System32')
                } else {
                    $f = Read-SysValue 'Arquivo' 'C:\Windows\System32\notepad.exe'
                    $args = @('-accepteula','-a','-h','-i','-nobanner',$f.Trim('"'))
                }
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'Sysmon' {
                Write-Host '  [1] Mostrar configuração atual' -ForegroundColor White
                Write-Host '  [2] Instalar Sysmon com configuração padrão' -ForegroundColor White
                Write-Host '  [3] Mostrar schema de configuração' -ForegroundColor White
                Write-Host '  [4] Desinstalar Sysmon' -ForegroundColor White
                $m = Read-SysValue 'Modo' '1'
                switch ($m) {
                    '2' {
                        if (Confirm-SysDanger 'O Sysmon instalará serviço e driver persistentes no Windows.' 'INSTALAR') {
                            Invoke-SysConsoleCommand -Path $Path -Arguments @('-accepteula','-i')
                        }
                    }
                    '3' { Invoke-SysConsoleCommand -Path $Path -Arguments @('-s') }
                    '4' {
                        if (Confirm-SysDanger 'Esta ação removerá o serviço/driver Sysmon.' 'REMOVER') {
                            Invoke-SysConsoleCommand -Path $Path -Arguments @('-u','force')
                        }
                    }
                    default { Invoke-SysConsoleCommand -Path $Path -Arguments @('-c') }
                }
            }

            'RegJump' {
                $key = Read-SysValue 'Chave para abrir no Regedit' 'HKLM\Software\Microsoft\Windows\CurrentVersion\Run'
                Invoke-SysConsoleCommand -Path $Path -Arguments @($key)
            }

            'PsExec' {
                $hostName = Read-SysValue 'Computador remoto (nome ou IP)'
                if (-not $hostName) { return }
                $command = Read-SysValue 'Comando remoto' 'hostname'
                $args = @("\\$hostName",'-accepteula','cmd.exe','/c',$command)
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'PsInfo' {
                $hostName = Read-SysValue 'Computador remoto; deixe LOCAL para este PC' 'LOCAL'
                if ($hostName -eq 'LOCAL') { $args = @() } else { $args = @("\\$hostName") }
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'PsList' {
                $args = @('-t')
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'PsLoggedOn' {
                $hostName = Read-SysValue 'Computador remoto; deixe LOCAL para este PC' 'LOCAL'
                if ($hostName -eq 'LOCAL') { $args = @() } else { $args = @("\\$hostName") }
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'PsService' {
                Write-Host '  [1] Listar serviços' -ForegroundColor White
                Write-Host '  [2] Consultar um serviço' -ForegroundColor White
                Write-Host '  [3] Reiniciar um serviço' -ForegroundColor White
                $m = Read-SysValue 'Modo' '1'
                switch ($m) {
                    '2' {
                        $svc = Read-SysValue 'Nome do serviço' 'Spooler'
                        $args = @('query',$svc)
                    }
                    '3' {
                        $svc = Read-SysValue 'Nome do serviço' 'Spooler'
                        if (-not (Confirm-SysDanger "O serviço '$svc' será reiniciado." 'REINICIAR')) { return }
                        $args = @('restart',$svc)
                    }
                    default { $args = @() }
                }
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'PsFile' {
                $hostName = Read-SysValue 'Computador remoto; deixe LOCAL para este PC' 'LOCAL'
                if ($hostName -eq 'LOCAL') { $args = @() } else { $args = @("\\$hostName") }
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'PsGetSid' {
                $account = Read-SysValue 'Conta ou SID; deixe vazio para SID do computador' ''
                if ($account) { $args = @($account) } else { $args = @($env:COMPUTERNAME) }
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'PsLogList' {
                $log = Read-SysValue 'Log de eventos' 'System'
                $count = Read-SysValue 'Quantidade de eventos recentes' '50'
                $args = @('-n',$count,$log)
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'PsSuspend' {
                $proc = Read-SysValue 'Processo ou PID' 'notepad.exe'
                Write-Host '  [1] Suspender' -ForegroundColor White
                Write-Host '  [2] Retomar' -ForegroundColor White
                $m = Read-SysValue 'Ação' '1'
                if ($m -eq '2') { $args = @('-r',$proc) } else { $args = @($proc) }
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'PsKill' {
                $proc = Read-SysValue 'Processo ou PID para encerrar'
                if (-not $proc) { return }
                if (-not (Confirm-SysDanger "O processo '$proc' será encerrado." 'ENCERRAR')) { return }
                Invoke-SysConsoleCommand -Path $Path -Arguments @($proc)
            }

            'PsShutdown' {
                Write-Host '  [1] Bloquear sessão' -ForegroundColor White
                Write-Host '  [2] Reiniciar PC' -ForegroundColor White
                Write-Host '  [3] Desligar PC' -ForegroundColor White
                Write-Host '  [4] Cancelar desligamento pendente' -ForegroundColor White
                $m = Read-SysValue 'Ação' '1'
                switch ($m) {
                    '2' {
                        if (-not (Confirm-SysDanger 'O computador será reiniciado.' 'REINICIAR')) { return }
                        $args = @('-r','-t','0')
                    }
                    '3' {
                        if (-not (Confirm-SysDanger 'O computador será desligado.' 'DESLIGAR')) { return }
                        $args = @('-k','-t','0')
                    }
                    '4' { $args = @('-a') }
                    default { $args = @('-l') }
                }
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'HelpOnly' {
                Write-SysStatus 'Ferramenta aberta sem parâmetros para exibir a ajuda/uso e evitar alterações automáticas.' 'Warning'
                Invoke-SysConsoleCommand -Path $Path
            }

            'AdRestore' {
                $filter = Read-SysValue 'Filtro/nome do objeto AD a pesquisar'
                if (-not $filter) { return }
                Write-SysStatus 'A restauração não será feita automaticamente; será exibida a pesquisa/ajuda da ferramenta.' 'Warning'
                Invoke-SysConsoleCommand -Path $Path -Arguments @($filter)
            }

            'SDelete' {
                Write-Host '  [1] Apagar arquivo/pasta com sobrescrita' -ForegroundColor White
                Write-Host '  [2] Zerar espaço livre de uma unidade' -ForegroundColor White
                $m = Read-SysValue 'Modo' '1'
                if (-not (Confirm-SysDanger 'SDelete pode tornar dados irrecuperáveis.' 'APAGAR')) { return }
                if ($m -eq '2') {
                    $drive = Read-SysValue 'Unidade' 'C:'
                    $args = @('-accepteula','-z',$drive)
                } else {
                    $target = Read-SysValue 'Arquivo ou pasta a excluir'
                    if (-not $target) { return }
                    $args = @('-accepteula','-p','1',$target.Trim('"'))
                }
                Invoke-SysConsoleCommand -Path $Path -Arguments $args
            }

            'DbgViewCli' {
                Write-SysStatus 'DbgView CLI ficará capturando saída de debug até você interromper com Ctrl+C.' 'Warning'
                Invoke-SysConsoleCommand -Path $Path
            }

            default {
                Invoke-SysConsoleCommand -Path $Path
            }
        }
    }

    function New-SysTool {
        param(
            [string]$Category,
            [int]$Index,
            [string]$Name,
            [string]$Description,
            [string]$File32,
            [string]$File64,
            [ValidateSet('GUI','CMD')][string]$Mode,
            [string]$Action='NoArgs',
            [bool]$Danger=$false
        )
        [PSCustomObject]@{
            Category=$Category; Index=$Index; Name=$Name; Description=$Description
            File32=$File32; File64=$File64; Mode=$Mode; Action=$Action; Danger=$Danger
        }
    }

    $Categories = @(
        [PSCustomObject]@{ Code='PROC'; Number='1'; Title='Processos, inicialização e diagnóstico' },
        [PSCustomObject]@{ Code='NET';  Number='2'; Title='Rede e conectividade' },
        [PSCustomObject]@{ Code='DISK'; Number='3'; Title='Disco, arquivos e NTFS' },
        [PSCustomObject]@{ Code='SYS';  Number='4'; Title='Sistema, hardware e memória' },
        [PSCustomObject]@{ Code='SEC';  Number='5'; Title='Segurança, permissões e Registro' },
        [PSCustomObject]@{ Code='PS';   Number='6'; Title='Administração remota / PsTools' },
        [PSCustomObject]@{ Code='AD';   Number='7'; Title='Active Directory' },
        [PSCustomObject]@{ Code='UTIL'; Number='8'; Title='Utilitários e produtividade' },
        [PSCustomObject]@{ Code='LAB';  Number='9'; Title='Avançadas / laboratório' }
    )

    $Tools = @(
        # PROCESSOS / DIAGNÓSTICO
        (New-SysTool 'PROC' 1  'Process Explorer' 'Processos, DLLs, handles e árvore de processos' 'procexp.exe' 'procexp64.exe' 'GUI'),
        (New-SysTool 'PROC' 2  'Process Monitor'  'Registro, arquivos, processos e atividade em tempo real' 'Procmon.exe' 'Procmon64.exe' 'GUI'),
        (New-SysTool 'PROC' 3  'Autoruns'         'Tudo que inicia automaticamente no Windows' 'Autoruns.exe' 'Autoruns64.exe' 'GUI'),
        (New-SysTool 'PROC' 4  'Autorunsc'        'CMD: autoruns de terceiros + hash + assinatura' 'autorunsc.exe' 'autorunsc64.exe' 'CMD' 'Autorunsc'),
        (New-SysTool 'PROC' 5  'VMMap'            'Mapa detalhado da memória virtual de processos' 'vmmap.exe' 'vmmap64.exe' 'GUI'),
        (New-SysTool 'PROC' 6  'ProcDump'         'CMD: gera dump completo de um processo' 'procdump.exe' 'procdump64.exe' 'CMD' 'ProcDump'),
        (New-SysTool 'PROC' 7  'Handle'           'CMD: descobre quem está usando arquivo/pasta' 'handle.exe' 'handle64.exe' 'CMD' 'Handle'),
        (New-SysTool 'PROC' 8  'ListDLLs'         'CMD: DLLs carregadas por processo' 'Listdlls.exe' 'Listdlls64.exe' 'CMD' 'ListDlls'),
        (New-SysTool 'PROC' 9  'DebugView'        'Captura mensagens de debug do Windows e apps' 'Dbgview.exe' 'dbgview64.exe' 'GUI'),
        (New-SysTool 'PROC' 10 'DebugView CLI'    'CMD: captura contínua de mensagens de debug' 'dbgviewcli.exe' 'dbgviewcli64.exe' 'CMD' 'DbgViewCli'),
        (New-SysTool 'PROC' 11 'LoadOrder'        'Mostra ordem de carregamento de drivers' 'LoadOrd.exe' 'LoadOrd64.exe' 'GUI'),
        (New-SysTool 'PROC' 12 'LogonSessions'    'CMD: sessões de logon e processos por sessão' 'logonsessions.exe' 'logonsessions64.exe' 'CMD' 'LogonSessions'),

        # REDE
        (New-SysTool 'NET' 1 'TCPView'    'Conexões TCP/UDP e processo responsável' 'tcpview.exe' 'tcpview64.exe' 'GUI'),
        (New-SysTool 'NET' 2 'TCPvcon'    'CMD: lista todos endpoints TCP/UDP sem DNS' 'tcpvcon.exe' 'tcpvcon64.exe' 'CMD' 'Tcpvcon'),
        (New-SysTool 'NET' 3 'PsPing'     'CMD: latência e conectividade - 10 testes' 'psping.exe' 'psping64.exe' 'CMD' 'PsPing'),
        (New-SysTool 'NET' 4 'Whois'      'CMD: consulta domínio ou IP' 'whois.exe' 'whois64.exe' 'CMD' 'Whois'),
        (New-SysTool 'NET' 5 'RDCMan'     'Gerenciador de múltiplas conexões RDP' 'RDCMan-x86.exe' 'RDCMan.exe' 'GUI'),
        (New-SysTool 'NET' 6 'ShareEnum'  'Compartilhamentos de rede e permissões' 'ShareEnum.exe' 'ShareEnum64.exe' 'GUI'),
        (New-SysTool 'NET' 7 'PortMon'    'Monitor de portas serial/paralela (legado)' 'portmon.exe' '' 'GUI'),

        # DISCO / ARQUIVOS
        (New-SysTool 'DISK' 1  'Disk2VHD'  'Converte discos físicos em VHD/VHDX' 'disk2vhd.exe' 'disk2vhd64.exe' 'GUI'),
        (New-SysTool 'DISK' 2  'DiskMon'   'Monitora atividade de disco em tempo real' 'Diskmon.exe' 'Diskmon64.exe' 'GUI'),
        (New-SysTool 'DISK' 3  'DiskView'  'Visualização gráfica de setores do disco' 'DiskView.exe' 'DiskView64.exe' 'GUI'),
        (New-SysTool 'DISK' 4  'DU'        'CMD: uso de espaço por pasta, nível 1' 'du.exe' 'du64.exe' 'CMD' 'Du'),
        (New-SysTool 'DISK' 5  'NTFSInfo'  'CMD: MFT, clusters e metadados NTFS' 'ntfsinfo.exe' 'ntfsinfo64.exe' 'CMD' 'NtfsInfo'),
        (New-SysTool 'DISK' 6  'FindLinks' 'CMD: localiza hard links de um arquivo' 'FindLinks.exe' 'FindLinks64.exe' 'CMD' 'FindLinks'),
        (New-SysTool 'DISK' 7  'Streams'   'CMD: detecta Alternate Data Streams (ADS)' 'streams.exe' 'streams64.exe' 'CMD' 'Streams'),
        (New-SysTool 'DISK' 8  'Junction'  'CMD: consulta junctions e reparse points' 'junction.exe' 'junction64.exe' 'CMD' 'Junction'),
        (New-SysTool 'DISK' 9  'Contig'    'CMD: analisa fragmentação de arquivo' 'Contig.exe' 'Contig64.exe' 'CMD' 'Contig'),
        (New-SysTool 'DISK' 10 'DiskExt'   'CMD: mapeamento volume -> disco físico' 'diskext.exe' 'diskext64.exe' 'CMD' 'NoArgs'),
        (New-SysTool 'DISK' 11 'EFSDump'   'CMD: informações sobre arquivos EFS' 'efsdump.exe' '' 'CMD' 'EfsDump'),
        (New-SysTool 'DISK' 12 'MoveFile'  'CMD: agenda mover/excluir no próximo boot' 'movefile.exe' 'movefile64.exe' 'CMD' 'MoveFile' $true),
        (New-SysTool 'DISK' 13 'PendMoves' 'CMD: mostra operações pendentes para reboot' 'pendmoves.exe' 'pendmoves64.exe' 'CMD' 'NoArgs'),
        (New-SysTool 'DISK' 14 'Sync'      'CMD: força flush de dados para disco' 'sync.exe' 'sync64.exe' 'CMD' 'NoArgs'),
        (New-SysTool 'DISK' 15 'LDMDump'   'CMD: informações de discos dinâmicos' 'ldmdump.exe' '' 'CMD' 'NoArgs'),

        # SISTEMA / HARDWARE
        (New-SysTool 'SYS' 1  'RAMMap'       'Uso detalhado da memória física' 'RAMMap.exe' 'RAMMap64.exe' 'GUI'),
        (New-SysTool 'SYS' 2  'Coreinfo GUI' 'Topologia de CPU em interface gráfica' 'CoreinfoEx.exe' 'CoreinfoEx64.exe' 'GUI'),
        (New-SysTool 'SYS' 3  'Coreinfo CMD' 'CMD: CPU, caches, NUMA, sockets e recursos' 'Coreinfo.exe' 'Coreinfo64.exe' 'CMD' 'CoreInfo'),
        (New-SysTool 'SYS' 4  'BgInfo'       'Informações do PC na área de trabalho' 'Bginfo.exe' 'Bginfo64.exe' 'GUI'),
        (New-SysTool 'SYS' 5  'WinObj'       'Namespace do Object Manager do Windows' 'Winobj.exe' 'Winobj64.exe' 'GUI'),
        (New-SysTool 'SYS' 6  'Desktops'     'Até quatro desktops virtuais Sysinternals' 'Desktops.exe' 'Desktops64.exe' 'GUI'),
        (New-SysTool 'SYS' 7  'ClockRes'     'CMD: resolução atual do relógio do sistema' 'Clockres.exe' 'Clockres64.exe' 'CMD' 'NoArgs'),
        (New-SysTool 'SYS' 8  'CacheSet'     'Controle do working set do Cache Manager' 'Cacheset.exe' 'Cacheset64.exe' 'GUI'),
        (New-SysTool 'SYS' 9  'PipeList'     'CMD: lista named pipes do sistema' 'pipelist.exe' 'pipelist64.exe' 'CMD' 'NoArgs'),
        (New-SysTool 'SYS' 10 'Registry Usage' 'CMD: tamanho de chave e subchaves do Registro' 'ru.exe' 'ru64.exe' 'CMD' 'Ru'),
        (New-SysTool 'SYS' 11 'Hex2Dec'      'CMD: conversão decimal/hexadecimal' 'hex2dec.exe' 'hex2dec64.exe' 'CMD' 'Hex2Dec'),
        (New-SysTool 'SYS' 12 'Strings'      'CMD: extrai strings ASCII/Unicode de binários' 'strings.exe' 'strings64.exe' 'CMD' 'Strings'),

        # SEGURANÇA / REGISTRO
        (New-SysTool 'SEC' 1 'AccessEnum'      'Permissões em arquivos, pastas e Registro' 'AccessEnum.exe' '' 'GUI'),
        (New-SysTool 'SEC' 2 'AccessChk'       'CMD: auditoria de permissões e serviços' 'accesschk.exe' 'accesschk64.exe' 'CMD' 'AccessChk'),
        (New-SysTool 'SEC' 3 'Sigcheck'        'CMD: assinatura digital, hash e arquivos não assinados' 'sigcheck.exe' 'sigcheck64.exe' 'CMD' 'SigCheck'),
        (New-SysTool 'SEC' 4 'Sysmon'          'Instalar, consultar ou remover monitor de eventos avançado' 'Sysmon.exe' 'Sysmon64.exe' 'CMD' 'Sysmon'),
        (New-SysTool 'SEC' 5 'Autologon'       'Configura logon automático no Windows' 'Autologon.exe' 'Autologon64.exe' 'GUI'),
        (New-SysTool 'SEC' 6 'RegJump'         'CMD: abre Regedit direto em uma chave' 'regjump.exe' '' 'CMD' 'RegJump'),
        (New-SysTool 'SEC' 7 'RootkitRevealer' 'Detector de discrepâncias de Registro/arquivo (legado)' 'RootkitRevealer.exe' '' 'GUI'),

        # PSTOOLS / REMOTO
        (New-SysTool 'PS' 1  'PsExec'     'CMD: executa comando em computador remoto' 'PsExec.exe' 'PsExec64.exe' 'CMD' 'PsExec'),
        (New-SysTool 'PS' 2  'PsInfo'     'CMD: informações locais ou remotas do Windows' 'PsInfo.exe' 'PsInfo64.exe' 'CMD' 'PsInfo'),
        (New-SysTool 'PS' 3  'PsList'     'CMD: árvore de processos e threads' 'pslist.exe' 'pslist64.exe' 'CMD' 'PsList'),
        (New-SysTool 'PS' 4  'PsLoggedOn' 'CMD: usuários logados local/remotamente' 'PsLoggedon.exe' 'PsLoggedon64.exe' 'CMD' 'PsLoggedOn'),
        (New-SysTool 'PS' 5  'PsService'  'CMD: listar, consultar ou reiniciar serviços' 'PsService.exe' 'PsService64.exe' 'CMD' 'PsService'),
        (New-SysTool 'PS' 6  'PsFile'     'CMD: arquivos abertos remotamente' 'psfile.exe' 'psfile64.exe' 'CMD' 'PsFile'),
        (New-SysTool 'PS' 7  'PsGetSid'   'CMD: traduz conta <-> SID' 'PsGetsid.exe' 'PsGetsid64.exe' 'CMD' 'PsGetSid'),
        (New-SysTool 'PS' 8  'PsLogList'  'CMD: últimos eventos do Event Log' 'psloglist.exe' 'psloglist64.exe' 'CMD' 'PsLogList'),
        (New-SysTool 'PS' 9  'PsSuspend'  'CMD: suspender ou retomar processo' 'pssuspend.exe' 'pssuspend64.exe' 'CMD' 'PsSuspend'),
        (New-SysTool 'PS' 10 'PsKill'     'CMD: encerra processo local/remoto' 'pskill.exe' 'pskill64.exe' 'CMD' 'PsKill' $true),
        (New-SysTool 'PS' 11 'PsShutdown' 'CMD: bloquear, reiniciar ou desligar' 'psshutdown.exe' 'psshutdown64.exe' 'CMD' 'PsShutdown' $true),
        (New-SysTool 'PS' 12 'PsPasswd'   'CMD: alteração de senha - ajuda/manual por segurança' 'pspasswd.exe' 'pspasswd64.exe' 'CMD' 'HelpOnly' $true),

        # ACTIVE DIRECTORY
        (New-SysTool 'AD' 1 'AD Explorer' 'Editor/visualizador avançado de Active Directory' 'ADExplorer.exe' 'ADExplorer64.exe' 'GUI'),
        (New-SysTool 'AD' 2 'AD Insight'  'Monitor de chamadas LDAP de aplicativos' 'ADInsight.exe' 'ADInsight64.exe' 'GUI'),
        (New-SysTool 'AD' 3 'ADRestore'   'CMD: localizar/restaurar objetos AD excluídos' 'adrestore.exe' 'adrestore64.exe' 'CMD' 'AdRestore' $true),

        # UTILITÁRIOS
        (New-SysTool 'UTIL' 1 'ZoomIt'     'Zoom, desenho e anotações para suporte/apresentação' 'ZoomIt.exe' 'ZoomIt64.exe' 'GUI'),
        (New-SysTool 'UTIL' 2 'ShellRunas' 'Executar programas como outro usuário via shell' 'ShellRunas.exe' '' 'CMD' 'HelpOnly'),

        # AVANÇADAS / LAB
        (New-SysTool 'LAB' 1  'SDelete'       'Apagamento seguro e limpeza de espaço livre' 'sdelete.exe' 'sdelete64.exe' 'CMD' 'SDelete' $true),
        (New-SysTool 'LAB' 2  'RegDelNull'    'Remove chaves com caracteres NULL - ajuda/manual' 'RegDelNull.exe' 'RegDelNull64.exe' 'CMD' 'HelpOnly' $true),
        (New-SysTool 'LAB' 3  'VolumeID'      'Altera serial lógico de volume - ajuda/manual' 'Volumeid.exe' 'Volumeid64.exe' 'CMD' 'HelpOnly' $true),
        (New-SysTool 'LAB' 4  'Ctrl2Cap'      'Driver que remapeia Caps Lock para Ctrl - ajuda/manual' 'ctrl2cap.exe' '' 'CMD' 'HelpOnly' $true),
        (New-SysTool 'LAB' 5  'LiveKD'        'Debug de kernel ao vivo - ajuda/manual' 'livekd.exe' 'livekd64.exe' 'CMD' 'HelpOnly' $true),
        (New-SysTool 'LAB' 6  'NotMyFault'    'Força falhas/crashes para laboratório' 'notmyfault.exe' 'notmyfault64.exe' 'GUI' 'NoArgs' $true),
        (New-SysTool 'LAB' 7  'CPU Stress'    'Carga artificial de CPU para laboratório' 'CPUSTRES.EXE' 'CPUSTRES64.EXE' 'GUI' 'NoArgs' $true),
        (New-SysTool 'LAB' 8  'TestLimit'     'Testes de limites de memória/handles - ajuda/manual' 'Testlimit.exe' 'Testlimit64.exe' 'CMD' 'HelpOnly' $true),
        (New-SysTool 'LAB' 9  'LoadOrder CLI' 'CMD: ordem de carregamento de drivers' 'LoadOrdC.exe' 'LoadOrdC64.exe' 'CMD' 'NoArgs'),
        (New-SysTool 'LAB' 10 'Reghide'       'Exemplo técnico de chaves de Registro ocultas' 'Reghide.exe' '' 'CMD' 'HelpOnly' $true)
    )

    function Get-SysComputerInfo {
        $caption = 'Windows'
        $build = 'Desconhecido'
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            if ($os.Caption) { $caption = ([string]$os.Caption -replace '^Microsoft\s+','').Trim() }
            if ($os.BuildNumber) { $build = [string]$os.BuildNumber }
        } catch {
            try {
                $os = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop
                if ($os.Caption) { $caption = ([string]$os.Caption -replace '^Microsoft\s+','').Trim() }
                if ($os.BuildNumber) { $build = [string]$os.BuildNumber }
            } catch {}
        }
        [PSCustomObject]@{
            Computer = $env:COMPUTERNAME
            Windows = $caption
            Build = $build
            Arch = $(if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' })
            Admin = $(if (Test-SysAdmin) { 'SIM' } else { 'NÃO' })
        }
    }

    function Show-SysHeader {
        param([Parameter(Mandatory)]$Info)
        Clear-Host
        Write-SysLine '=' $Sys.CorBorda
        Write-SysCentered 'INILOG' $Sys.CorTitulo
        Write-SysCentered 'MICROSOFT SYSINTERNALS - CENTRAL AVANÇADA' White
        Write-SysLine '=' $Sys.CorBorda
        Write-Host ''
        Write-Host '  PC:      ' -NoNewline -ForegroundColor DarkGray; Write-Host $Info.Computer -ForegroundColor White
        Write-Host '  Windows: ' -NoNewline -ForegroundColor DarkGray; Write-Host ("{0} - Build {1}" -f $Info.Windows,$Info.Build) -ForegroundColor White
        Write-Host '  Arq:     ' -NoNewline -ForegroundColor DarkGray; Write-Host $Info.Arch -ForegroundColor White
        Write-Host '  Admin:   ' -NoNewline -ForegroundColor DarkGray
        if ($Info.Admin -eq 'SIM') { Write-Host 'SIM' -ForegroundColor Green } else { Write-Host 'NÃO' -ForegroundColor Yellow }
        Write-Host '  Pasta:   ' -NoNewline -ForegroundColor DarkGray; Write-Host $Sys.Directory -ForegroundColor White
        Write-Host '  Origem:  ' -NoNewline -ForegroundColor DarkGray; Write-Host 'Microsoft Sysinternals Live - download sempre novo' -ForegroundColor Cyan
    }

    function Write-SysCategoryItem {
        param([string]$Number,[string]$Title)
        Write-Host '  [' -NoNewline -ForegroundColor DarkGray
        Write-Host $Number.PadLeft(2,'0') -NoNewline -ForegroundColor $Sys.CorNumero
        Write-Host '] ' -NoNewline -ForegroundColor DarkGray
        Write-Host $Title -ForegroundColor White
    }

    function Write-SysToolItem {
        param([Parameter(Mandatory)]$Tool)
        $modeColor = if ($Tool.Mode -eq 'GUI') { 'Magenta' } else { 'Cyan' }
        Write-Host '  [' -NoNewline -ForegroundColor DarkGray
        Write-Host ([string]$Tool.Index).PadLeft(2,'0') -NoNewline -ForegroundColor $Sys.CorNumero
        Write-Host '] ' -NoNewline -ForegroundColor DarkGray
        Write-Host ($Tool.Name.PadRight(22)) -NoNewline -ForegroundColor White
        Write-Host ('[' + $Tool.Mode + ']') -NoNewline -ForegroundColor $modeColor
        if ($Tool.Danger) { Write-Host ' [!]' -NoNewline -ForegroundColor Red }
        Write-Host ('  ' + $Tool.Description) -ForegroundColor DarkGray
    }

    function Show-SysMainMenu {
        param([Parameter(Mandatory)]$Info)
        Show-SysHeader -Info $Info
        Write-Host ''
        Write-Host '  CATEGORIAS' -ForegroundColor $Sys.CorSecao
        foreach ($c in $Categories) { Write-SysCategoryItem $c.Number $c.Title }
        Write-Host ''
        Write-SysLine '-' DarkGray
        Write-SysCategoryItem 'S' 'Pesquisar ferramenta pelo nome'
        Write-SysCategoryItem '90' 'Abrir pasta das ferramentas'
        Write-SysCategoryItem '91' 'Abrir catálogo oficial Microsoft'
        Write-SysCategoryItem '00' 'Voltar ao INILOG'
        Write-SysLine '=' $Sys.CorBorda
        Write-Host ''
    }

    function Invoke-SysTool {
        param([Parameter(Mandatory)]$Tool)

        if ($Tool.Danger) {
            Write-SysStatus 'Ferramenta marcada como avançada. Leia a descrição antes de continuar.' 'Warning'
            if (-not (Confirm-SysDanger "Deseja realmente abrir/executar $($Tool.Name)?" 'CONTINUAR')) { return }
        }

        $path = Get-SysToolFresh -Tool $Tool
        if (-not $path) { return }

        if ($Tool.Mode -eq 'GUI') {
            Start-SysGuiTool -Tool $Tool -Path $path
        } else {
            Invoke-SysAction -Tool $Tool -Path $path
        }
    }

    function Show-SysCategoryMenu {
        param([Parameter(Mandatory)]$Category,[Parameter(Mandatory)]$Info)

        do {
            Show-SysHeader -Info $Info
            Write-Host ''
            Write-Host ('  ' + $Category.Title.ToUpperInvariant()) -ForegroundColor $Sys.CorSecao
            Write-Host '  GUI = abre programa | CMD = já executa um comando útil/pede somente o necessário' -ForegroundColor DarkGray
            Write-Host ''

            $list = @($Tools | Where-Object { $_.Category -eq $Category.Code } | Sort-Object Index)
            foreach ($tool in $list) { Write-SysToolItem -Tool $tool }

            Write-Host ''
            Write-SysLine '-' DarkGray
            Write-SysCategoryItem '00' 'Voltar às categorias'
            Write-SysLine '=' $Sys.CorBorda
            Write-Host ''

            $choice = (Read-Host 'Escolha uma ferramenta').Trim()
            if ($choice -match '^0+$') { return }

            $number = 0
            if ([int]::TryParse($choice,[ref]$number)) {
                $tool = $list | Where-Object { $_.Index -eq $number } | Select-Object -First 1
                if ($tool) {
                    Write-Host ''
                    Invoke-SysTool -Tool $tool
                } else {
                    Write-SysStatus "Opção '$choice' inválida." 'Warning'
                }
            } else {
                Write-SysStatus "Opção '$choice' inválida." 'Warning'
            }

            Write-Host ''
            [void](Read-Host 'Pressione Enter para voltar')
        } while ($true)
    }

    function Search-SysTools {
        param([Parameter(Mandatory)]$Info)
        Show-SysHeader -Info $Info
        Write-Host ''
        $q = (Read-Host 'Digite parte do nome ou descrição').Trim()
        if (-not $q) { return }

        $matches = @($Tools | Where-Object { $_.Name -like "*$q*" -or $_.Description -like "*$q*" } | Sort-Object Category,Index)
        if ($matches.Count -eq 0) {
            Write-SysStatus 'Nenhuma ferramenta encontrada.' 'Warning'
            [void](Read-Host 'Pressione Enter para voltar')
            return
        }

        Write-Host ''
        for ($i=0; $i -lt $matches.Count; $i++) {
            Write-Host ('  [{0}] {1} [{2}] - {3}' -f ($i+1).ToString().PadLeft(2,'0'),$matches[$i].Name,$matches[$i].Mode,$matches[$i].Description) -ForegroundColor White
        }
        Write-Host ''
        $sel = Read-SysValue 'Escolha resultado; 0 para cancelar' '0'
        $n = 0
        if ([int]::TryParse($sel,[ref]$n) -and $n -ge 1 -and $n -le $matches.Count) {
            Write-Host ''
            Invoke-SysTool -Tool $matches[$n-1]
            Write-Host ''
            [void](Read-Host 'Pressione Enter para voltar')
        }
    }

    try {
        Initialize-SysDirectory | Out-Null
        $Info = Get-SysComputerInfo

        do {
            Show-SysMainMenu -Info $Info
            $choice = (Read-Host 'Escolha uma opção').Trim()
            if ($choice -match '^\d+$') {
                try { $choice = ([int]$choice).ToString() } catch {}
            }

            if ($choice -match '^0+$') { break }

            $category = $Categories | Where-Object { $_.Number -eq $choice } | Select-Object -First 1
            if ($category) {
                Show-SysCategoryMenu -Category $category -Info $Info
                continue
            }

            switch ($choice.ToUpperInvariant()) {
                'S'  { Search-SysTools -Info $Info }
                '90' {
                    try {
                        Start-Process explorer.exe -ArgumentList "`"$($Sys.Directory)`""
                    } catch { Write-SysStatus $_.Exception.Message 'Error'; Start-Sleep -Seconds 1 }
                }
                '91' {
                    try {
                        Start-Process 'https://live.sysinternals.com/tools/'
                    } catch { Write-SysStatus $_.Exception.Message 'Error'; Start-Sleep -Seconds 1 }
                }
                default {
                    Write-SysStatus "Opção '$choice' inválida." 'Warning'
                    Start-Sleep -Milliseconds 800
                }
            }
        } while ($true)

    } finally {
        try {
            if (-not [string]::IsNullOrWhiteSpace([string]$Sys.OldTitle)) {
                $Host.UI.RawUI.WindowTitle = $Sys.OldTitle
            }
        } catch {}
        Clear-Host
    }
}
