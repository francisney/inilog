#requires -version 5.1
<#
.SYNOPSIS
    Gerenciador/monitor de impressoras Zebra conectadas por USB.

.NOTES
    Versão 1.1.0 - remove qualquer uso interno do nome reservado PID e adiciona diagnóstico detalhado.

.DESCRIPTION
    - Detecta Zebra mesmo sem o driver ZDesigner, usando PnP/USBPRINT/IEEE-1284.
    - Diferencia GC420t, GC420d, ZD220 e outros modelos quando o Windows expõe o modelo.
    - Mostra a porta virtual do spooler (USB001, USB002...) e a rota física USB.
    - Correlaciona a fila de impressão pelo PNPDeviceID.
    - Registra conexão/desconexão e permite apelidar a porta física.
    - Não altera drivers, filas ou dispositivos.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\Gerenciador-ZebraUSB.ps1

.EXAMPLE
    .\Gerenciador-ZebraUSB.ps1 -UmaVez -MostrarDebug
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 60)]
    [int]$IntervaloSegundos = 2,

    [string]$DiretorioDados = (Join-Path $env:LOCALAPPDATA 'ZebraUsbManager'),

    [switch]$UmaVez,
    [switch]$SemSom,
    [switch]$MostrarDebug
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

try {
    Import-Module PnpDevice -ErrorAction Stop
}
catch {
    Write-Error 'O módulo PnpDevice não está disponível. Execute no Windows 10/11 com Windows PowerShell 5.1.'
    exit 1
}

if (-not (Test-Path -LiteralPath $DiretorioDados)) {
    New-Item -Path $DiretorioDados -ItemType Directory -Force | Out-Null
}

$ArquivoApelidos = Join-Path $DiretorioDados 'portas-usb.json'
$ArquivoEventos  = Join-Path $DiretorioDados 'eventos-zebra.csv'
$VersaoScript    = '1.1.0'
$CaminhoScript   = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }

function Get-TextValue {
    param([object]$Value)

    if ($null -eq $Value) { return '' }

    if ($Value -is [System.Array]) {
        return (($Value | ForEach-Object { [string]$_ }) -join ' | ')
    }

    return [string]$Value
}

function Get-PnpPropertyMap {
    param([Parameter(Mandatory)][string]$InstanceId)

    $map = @{}
    try {
        $properties = @(Get-PnpDeviceProperty -InstanceId $InstanceId -ErrorAction Stop)
        foreach ($property in $properties) {
            if (-not [string]::IsNullOrWhiteSpace([string]$property.KeyName)) {
                $map[[string]$property.KeyName] = $property.Data
            }
        }
    }
    catch {
        # Um nó pode desaparecer entre a enumeração e a consulta.
    }

    return $map
}

function Get-MapValue {
    param(
        [hashtable]$Map,
        [Parameter(Mandatory)][string[]]$Keys
    )

    if ($null -eq $Map) { return $null }

    foreach ($key in $Keys) {
        if ($Map.ContainsKey($key)) {
            $value = $Map[$key]
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace((Get-TextValue $value))) {
                return $value
            }
        }
    }

    return $null
}

function Get-PnpNodeById {
    param([string]$InstanceId)

    if ([string]::IsNullOrWhiteSpace($InstanceId)) { return $null }

    try {
        $device = Get-PnpDevice -InstanceId $InstanceId -PresentOnly -ErrorAction Stop
        return [pscustomobject]@{
            Device = $device
            Props  = Get-PnpPropertyMap -InstanceId $device.InstanceId
        }
    }
    catch {
        return $null
    }
}

function Get-UsbAncestorNode {
    param([Parameter(Mandatory)]$StartNode)

    $current = $StartNode
    $visited = @{}

    for ($level = 0; $level -lt 10; $level++) {
        if ($null -eq $current -or $null -eq $current.Device) { break }

        $currentId = [string]$current.Device.InstanceId
        if ($currentId -match '^USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}') {
            return $current
        }

        if ($visited.ContainsKey($currentId)) { break }
        $visited[$currentId] = $true

        $parentId = Get-MapValue -Map $current.Props -Keys @('DEVPKEY_Device_Parent')
        if ([string]::IsNullOrWhiteSpace([string]$parentId)) { break }

        $current = Get-PnpNodeById -InstanceId ([string]$parentId)
    }

    return $null
}

function Resolve-ZebraModel {
    param(
        [string]$PnpText,
        [string]$QueueText,
        [string]$FriendlyText
    )

    $patterns = [ordered]@{
        'GC420t' = '(?i)(?<![A-Z0-9])GC[\s_-]*420[\s_-]*T(?![A-Z0-9])'
        'GC420d' = '(?i)(?<![A-Z0-9])GC[\s_-]*420[\s_-]*D(?![A-Z0-9])'
        'GC420'  = '(?i)(?<![A-Z0-9])GC[\s_-]*420(?![A-Z0-9])'
        'ZD220'  = '(?i)(?<![A-Z0-9])ZD[\s_-]*220(?:[\s_-]*(?:D|T))?(?![A-Z0-9])'
        'ZD230'  = '(?i)(?<![A-Z0-9])ZD[\s_-]*230(?:[\s_-]*(?:D|T))?(?![A-Z0-9])'
        'GK420t' = '(?i)(?<![A-Z0-9])GK[\s_-]*420[\s_-]*T(?![A-Z0-9])'
        'GK420d' = '(?i)(?<![A-Z0-9])GK[\s_-]*420[\s_-]*D(?![A-Z0-9])'
        'GX420t' = '(?i)(?<![A-Z0-9])GX[\s_-]*420[\s_-]*T(?![A-Z0-9])'
        'GX420d' = '(?i)(?<![A-Z0-9])GX[\s_-]*420[\s_-]*D(?![A-Z0-9])'
        'ZD421'  = '(?i)(?<![A-Z0-9])ZD[\s_-]*421(?:[\s_-]*(?:D|T))?(?![A-Z0-9])'
    }

    $sources = @(
        [pscustomobject]@{ Name = 'PnP/IEEE-1284'; Text = $PnpText;      Confidence = 'Alta'  },
        [pscustomobject]@{ Name = 'Fila/driver';   Text = $QueueText;    Confidence = 'Média' },
        [pscustomobject]@{ Name = 'Nome amigável'; Text = $FriendlyText; Confidence = 'Média' }
    )

    foreach ($source in $sources) {
        if ([string]::IsNullOrWhiteSpace($source.Text)) { continue }

        foreach ($entry in $patterns.GetEnumerator()) {
            if ($source.Text -match $entry.Value) {
                return [pscustomobject]@{
                    Model      = [string]$entry.Key
                    Confidence = [string]$source.Confidence
                    Source     = [string]$source.Name
                }
            }
        }

        $genericMatch = [regex]::Match(
            $source.Text,
            '(?i)(?<![A-Z0-9])(?:GC|GK|GX|ZD|ZT|ZQ|ZE|ZM)[\s_-]*[0-9]{3}[A-Z]?(?![A-Z0-9])'
        )

        if ($genericMatch.Success) {
            $genericModel = ($genericMatch.Value -replace '[\s_-]', '').ToUpperInvariant()
            return [pscustomobject]@{
                Model      = $genericModel
                Confidence = [string]$source.Confidence
                Source     = [string]$source.Name
            }
        }
    }

    return [pscustomobject]@{
        Model      = 'Zebra (modelo não informado)'
        Confidence = 'Baixa'
        Source     = 'Fabricante/VID'
    }
}

function Get-PrinterStatusText {
    param($Queue)

    if ($null -eq $Queue) { return 'Sem fila instalada' }
    if ($Queue.WorkOffline) { return 'Offline no Windows' }

    switch ([int]$Queue.PrinterStatus) {
        1 { return 'Outro' }
        2 { return 'Desconhecido' }
        3 { return 'Ociosa/Pronta' }
        4 { return 'Imprimindo' }
        5 { return 'Aquecendo' }
        6 { return 'Parada' }
        7 { return 'Offline' }
        default { return ('Status {0}' -f $Queue.PrinterStatus) }
    }
}

function Get-UsbRoute {
    param([string]$LocationPath)

    if ([string]::IsNullOrWhiteSpace($LocationPath)) { return '' }

    $parts = [regex]::Matches($LocationPath, '(?i)USB(?:ROOT)?\([^\)]+\)') |
        ForEach-Object { $_.Value }

    return ($parts -join ' -> ')
}

function Get-PhysicalPortText {
    param(
        [string]$LocationInfo,
        [string]$LocationPath
    )

    if ($LocationInfo -match '(?i)Port_#(?<port>[0-9]+)\.Hub_#(?<hub>[0-9]+)') {
        $port = [int]$Matches.port
        $hub  = [int]$Matches.hub
        return ('Porta {0} do hub {1} ({2})' -f $port, $hub, $LocationInfo)
    }

    $route = Get-UsbRoute -LocationPath $LocationPath
    if (-not [string]::IsNullOrWhiteSpace($route)) { return $route }

    return 'Localização física não exposta pelo Windows'
}

function Read-PortAliases {
    $aliases = @{}

    if (-not (Test-Path -LiteralPath $ArquivoApelidos)) { return $aliases }

    try {
        $json = Get-Content -LiteralPath $ArquivoApelidos -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($null -ne $json) {
            foreach ($property in $json.PSObject.Properties) {
                $aliases[[string]$property.Name] = [string]$property.Value
            }
        }
    }
    catch {
        Write-Warning ('Não foi possível ler {0}: {1}' -f $ArquivoApelidos, $_.Exception.Message)
    }

    return $aliases
}

function Save-PortAliases {
    param([hashtable]$Aliases)

    $ordered = [ordered]@{}
    foreach ($key in ($Aliases.Keys | Sort-Object)) {
        $ordered[$key] = $Aliases[$key]
    }

    $ordered | ConvertTo-Json | Set-Content -LiteralPath $ArquivoApelidos -Encoding UTF8
}

function Get-ZebraUsbInventory {
    param([hashtable]$Aliases)

    $allPresent = @(Get-PnpDevice -PresentOnly -ErrorAction Stop)
    $usbCount = @($allPresent | Where-Object { $_.InstanceId -match '^(USB|USBPRINT)\\' }).Count

    $basicCandidates = @(
        $allPresent | Where-Object {
            $_.InstanceId -match '^USBPRINT\\' -or
            $_.InstanceId -match '^USB\\VID_0A5F' -or
            $_.FriendlyName -match '(?i)Zebra|GC420|ZD220'
        }
    )

    $nodes = @()
    foreach ($device in $basicCandidates) {
        $props = Get-PnpPropertyMap -InstanceId $device.InstanceId
        $hardwareIds = Get-MapValue -Map $props -Keys @('DEVPKEY_Device_HardwareIds')
        $compatibleIds = Get-MapValue -Map $props -Keys @('DEVPKEY_Device_CompatibleIds')
        $busDescription = Get-MapValue -Map $props -Keys @('DEVPKEY_Device_BusReportedDeviceDesc')
        $deviceDescription = Get-MapValue -Map $props -Keys @('DEVPKEY_Device_DeviceDesc')

        $evidence = @(
            $device.InstanceId,
            $device.FriendlyName,
            (Get-TextValue $hardwareIds),
            (Get-TextValue $compatibleIds),
            (Get-TextValue $busDescription),
            (Get-TextValue $deviceDescription)
        ) -join ' | '

        if ($device.InstanceId -match '^USB\\VID_0A5F' -or
            $evidence -match '(?i)Zebra|GC[\s_-]*420|ZD[\s_-]*220') {
            $nodes += [pscustomobject]@{
                Device = $device
                Props  = $props
            }
        }
    }

    $queues = @()
    try {
        $queues = @(Get-CimInstance -ClassName Win32_Printer -ErrorAction Stop)
    }
    catch {
        # O spooler pode estar parado. A detecção PnP continua funcionando.
    }

    $groups = @{}
    foreach ($node in $nodes) {
        # O mesmo equipamento físico costuma gerar ao menos dois nós:
        # USB\VID_xxxx (dispositivo físico) e USBPRINT\... (função de impressão).
        # Agrupar pela instância física evita duplicar a Zebra e preserva a fila correta.
        $physicalAnchor = $null
        if ($node.Device.InstanceId -match '^USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}') {
            $physicalAnchor = $node
        }
        elseif ($node.Device.InstanceId -match '^USBPRINT\\') {
            $physicalAnchor = Get-UsbAncestorNode -StartNode $node
        }

        if ($null -ne $physicalAnchor -and $null -ne $physicalAnchor.Device) {
            $groupKey = 'PHYSICAL:' + ([string]$physicalAnchor.Device.InstanceId).ToUpperInvariant()
        }
        else {
            $containerId = Get-MapValue -Map $node.Props -Keys @('DEVPKEY_Device_ContainerId')
            $parentId = Get-MapValue -Map $node.Props -Keys @('DEVPKEY_Device_Parent')

            if ($null -ne $containerId -and -not [string]::IsNullOrWhiteSpace([string]$containerId)) {
                $groupKey = 'CONTAINER:' + ([string]$containerId).ToUpperInvariant()
            }
            elseif ($null -ne $parentId -and -not [string]::IsNullOrWhiteSpace([string]$parentId)) {
                $groupKey = 'PARENT:' + ([string]$parentId).ToUpperInvariant()
            }
            else {
                $groupKey = 'INSTANCE:' + ([string]$node.Device.InstanceId).ToUpperInvariant()
            }
        }

        if (-not $groups.ContainsKey($groupKey)) {
            $groups[$groupKey] = New-Object System.Collections.ArrayList
        }
        [void]$groups[$groupKey].Add($node)
    }

    $results = @()
    $seenPhysicalIds = @{}

    foreach ($groupKey in $groups.Keys) {
        $groupNodes = @($groups[$groupKey])

        $printNode = $groupNodes |
            Where-Object { $_.Device.InstanceId -match '^USBPRINT\\' } |
            Select-Object -First 1

        $usbNode = $groupNodes |
            Where-Object { $_.Device.InstanceId -match '^USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}' } |
            Sort-Object { if ($_.Device.InstanceId -match '^USB\\VID_0A5F') { 0 } else { 1 } } |
            Select-Object -First 1

        if ($null -eq $usbNode -and $null -ne $printNode) {
            $usbNode = Get-UsbAncestorNode -StartNode $printNode
        }

        $identityNode = $printNode
        if ($null -eq $identityNode) { $identityNode = $usbNode }
        if ($null -eq $identityNode) { continue }

        $physicalId = ''
        if ($null -ne $usbNode) { $physicalId = [string]$usbNode.Device.InstanceId }
        if ([string]::IsNullOrWhiteSpace($physicalId)) { $physicalId = [string]$identityNode.Device.InstanceId }

        $dedupeKey = $physicalId.ToUpperInvariant()
        if ($seenPhysicalIds.ContainsKey($dedupeKey)) { continue }
        $seenPhysicalIds[$dedupeKey] = $true

        $matchingQueues = @()
        if ($null -ne $printNode) {
            $pnpId = ([string]$printNode.Device.InstanceId).ToUpperInvariant()
            $matchingQueues = @(
                $queues | Where-Object {
                    -not [string]::IsNullOrWhiteSpace([string]$_.PNPDeviceID) -and
                    ([string]$_.PNPDeviceID).ToUpperInvariant() -eq $pnpId
                }
            )
        }

        if ($matchingQueues.Count -eq 0) {
            $matchingQueues = @(
                $queues | Where-Object {
                    $_.PortName -match '^USB[0-9]{3,}$' -and
                    (([string]$_.Name + ' ' + [string]$_.DriverName) -match '(?i)Zebra|GC420|ZD220')
                }
            )

            if ($matchingQueues.Count -gt 1) {
                $matchingQueues = @()
            }
        }

        $queueText = ($matchingQueues | ForEach-Object {
            '{0} {1} {2} {3}' -f $_.Name, $_.DriverName, $_.PortName, $_.PNPDeviceID
        }) -join ' | '

        $pnpPieces = @()
        foreach ($node in @($groupNodes + @($usbNode, $printNode))) {
            if ($null -eq $node -or $null -eq $node.Device) { continue }
            $pnpPieces += [string]$node.Device.InstanceId
            $pnpPieces += Get-TextValue (Get-MapValue -Map $node.Props -Keys @('DEVPKEY_Device_HardwareIds'))
            $pnpPieces += Get-TextValue (Get-MapValue -Map $node.Props -Keys @('DEVPKEY_Device_CompatibleIds'))
            $pnpPieces += Get-TextValue (Get-MapValue -Map $node.Props -Keys @('DEVPKEY_Device_BusReportedDeviceDesc'))
            $pnpPieces += Get-TextValue (Get-MapValue -Map $node.Props -Keys @('DEVPKEY_Device_DeviceDesc'))
        }
        $pnpText = $pnpPieces -join ' | '

        $friendlyText = ($groupNodes | ForEach-Object { [string]$_.Device.FriendlyName }) -join ' | '
        $modelInfo = Resolve-ZebraModel -PnpText $pnpText -QueueText $queueText -FriendlyText $friendlyText

        $locationNode = $usbNode
        if ($null -eq $locationNode) { $locationNode = $identityNode }

        $locationInfo = Get-TextValue (Get-MapValue -Map $locationNode.Props -Keys @('DEVPKEY_Device_LocationInfo'))
        $locationPathsValue = Get-MapValue -Map $locationNode.Props -Keys @('DEVPKEY_Device_LocationPaths')
        $locationPaths = @($locationPathsValue | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        $locationPath = ''
        if ($locationPaths.Count -gt 0) { $locationPath = [string]$locationPaths[0] }

        $vid = ''
        $productId = ''
        $idEvidence = $physicalId + ' ' + $pnpText
        if ($idEvidence -match '(?i)VID_([0-9A-F]{4})') { $vid = $Matches[1].ToUpperInvariant() }
        if ($idEvidence -match '(?i)PID_([0-9A-F]{4})') { $productId = $Matches[1].ToUpperInvariant() }

        $aliasKey = $locationPath
        if ([string]::IsNullOrWhiteSpace($aliasKey)) { $aliasKey = $physicalId }

        $portAlias = ''
        if ($Aliases.ContainsKey($aliasKey)) { $portAlias = [string]$Aliases[$aliasKey] }

        $queueNames = @($matchingQueues | ForEach-Object { [string]$_.Name })
        $virtualPorts = @($matchingQueues | ForEach-Object { [string]$_.PortName } | Sort-Object -Unique)
        $driverNames = @($matchingQueues | ForEach-Object { [string]$_.DriverName } | Sort-Object -Unique)
        $queueStatuses = @($matchingQueues | ForEach-Object { Get-PrinterStatusText -Queue $_ } | Sort-Object -Unique)

        $results += [pscustomobject][ordered]@{
            Chave                 = $dedupeKey
            Modelo                = $modelInfo.Model
            ConfiancaModelo       = $modelInfo.Confidence
            FonteModelo           = $modelInfo.Source
            StatusPnP             = [string]$identityNode.Device.Status
            StatusFila            = if ($queueStatuses.Count) { $queueStatuses -join ', ' } else { 'Sem fila instalada' }
            Fila                   = if ($queueNames.Count) { $queueNames -join ', ' } else { '' }
            Driver                 = if ($driverNames.Count) { $driverNames -join ', ' } else { '' }
            PortaVirtual           = if ($virtualPorts.Count) { $virtualPorts -join ', ' } else { '' }
            PortaFisica            = Get-PhysicalPortText -LocationInfo $locationInfo -LocationPath $locationPath
            ApelidoPorta           = $portAlias
            RotaUsb                = Get-UsbRoute -LocationPath $locationPath
            LocationInfo           = $locationInfo
            LocationPath           = $locationPath
            AliasKey               = $aliasKey
            VID                    = $vid
            ProductId              = $productId
            UsbInstanceId          = $physicalId
            UsbPrintInstanceId     = if ($null -ne $printNode) { [string]$printNode.Device.InstanceId } else { '' }
            ContainerId            = Get-TextValue (Get-MapValue -Map $identityNode.Props -Keys @('DEVPKEY_Device_ContainerId'))
            BusReportedDescription = Get-TextValue (Get-MapValue -Map $identityNode.Props -Keys @('DEVPKEY_Device_BusReportedDeviceDesc'))
            HardwareIds            = Get-TextValue (Get-MapValue -Map $identityNode.Props -Keys @('DEVPKEY_Device_HardwareIds'))
        }
    }

    return [pscustomobject]@{
        ScannedAt = Get-Date
        UsbCount  = $usbCount
        Devices   = @($results | Sort-Object Modelo, PortaFisica)
    }
}

function Write-ZebraEvent {
    param(
        [Parameter(Mandatory)][ValidateSet('CONECTADA', 'DESCONECTADA')][string]$EventType,
        [Parameter(Mandatory)]$Device
    )

    $record = [pscustomobject][ordered]@{
        DataHora       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Evento         = $EventType
        Modelo         = $Device.Modelo
        Confianca      = $Device.ConfiancaModelo
        PortaVirtual   = $Device.PortaVirtual
        PortaFisica    = $Device.PortaFisica
        ApelidoPorta   = $Device.ApelidoPorta
        VID            = $Device.VID
        'PID'          = $Device.ProductId
        UsbInstanceId  = $Device.UsbInstanceId
        LocationPath   = $Device.LocationPath
    }

    if (Test-Path -LiteralPath $ArquivoEventos) {
        $record | Export-Csv -LiteralPath $ArquivoEventos -NoTypeInformation -Encoding UTF8 -Append
    }
    else {
        $record | Export-Csv -LiteralPath $ArquivoEventos -NoTypeInformation -Encoding UTF8
    }
}

function Export-ZebraSnapshot {
    param([Parameter(Mandatory)]$Snapshot)

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $jsonPath = Join-Path $DiretorioDados ("zebra-snapshot-$stamp.json")
    $csvPath  = Join-Path $DiretorioDados ("zebra-snapshot-$stamp.csv")

    $Snapshot.Devices | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $Snapshot.Devices | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

    return [pscustomobject]@{ Json = $jsonPath; Csv = $csvPath }
}

function Write-Field {
    param(
        [Parameter(Mandatory)][string]$Label,
        [AllowEmptyString()][string]$Value,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { $Value = '-' }
    Write-Host ('{0,-18}: ' -f $Label) -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -ForegroundColor $Color
}

function Show-ZebraDashboard {
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][string]$Spinner
    )

    Clear-Host
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '              GERENCIADOR USB - IMPRESSORAS ZEBRA' -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host ('Monitorando {0}  |  {1:dd/MM/yyyy HH:mm:ss}' -f $Spinner, $Snapshot.ScannedAt) -ForegroundColor White
    Write-Host ('USB/USBPRINT presentes: {0}  |  Zebras: {1}' -f $Snapshot.UsbCount, $Snapshot.Devices.Count) -ForegroundColor DarkGray
    Write-Host ('Versão: {0}  |  Script: {1}' -f $VersaoScript, $CaminhoScript) -ForegroundColor DarkGray
    Write-Host ('Dados e logs: {0}' -f $DiretorioDados) -ForegroundColor DarkGray
    Write-Host ''

    if ($Snapshot.Devices.Count -eq 0) {
        Write-Host '[ NENHUMA ZEBRA USB DETECTADA ]' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '1. Ligue a impressora.' -ForegroundColor White
        Write-Host '2. Troque o cabo USB A-B e teste outra porta.' -ForegroundColor White
        Write-Host '3. Verifique se aparece um nó USBPRINT no Gerenciador de Dispositivos.' -ForegroundColor White
        Write-Host '4. O VID oficial da Zebra normalmente aparece como VID_0A5F.' -ForegroundColor White
    }
    else {
        $number = 0
        foreach ($device in $Snapshot.Devices) {
            $number++
            Write-Host ('------------------------ ZEBRA #{0} ------------------------' -f $number) -ForegroundColor DarkCyan

            $modelColor = [ConsoleColor]::Green
            if ($device.ConfiancaModelo -eq 'Baixa') { $modelColor = [ConsoleColor]::Yellow }

            Write-Field -Label 'Modelo'          -Value $device.Modelo              -Color $modelColor
            Write-Field -Label 'Confiança'       -Value ($device.ConfiancaModelo + ' via ' + $device.FonteModelo)
            Write-Field -Label 'PnP'             -Value $device.StatusPnP             -Color $(if ($device.StatusPnP -eq 'OK') { 'Green' } else { 'Yellow' })
            Write-Field -Label 'Fila Windows'    -Value $device.Fila
            Write-Field -Label 'Status da fila'  -Value $device.StatusFila
            Write-Field -Label 'Driver'          -Value $device.Driver
            Write-Field -Label 'Porta virtual'   -Value $device.PortaVirtual          -Color Cyan
            Write-Field -Label 'Porta física'    -Value $device.PortaFisica           -Color Cyan
            Write-Field -Label 'Apelido'         -Value $device.ApelidoPorta           -Color Magenta
            Write-Field -Label 'Rota USB'        -Value $device.RotaUsb
            Write-Field -Label 'VID / PID'       -Value (($device.VID + ' / ' + $device.ProductId).Trim([char[]]' /'))

            if ($MostrarDebug) {
                Write-Field -Label 'USB InstanceId'      -Value $device.UsbInstanceId
                Write-Field -Label 'USBPRINT InstanceId' -Value $device.UsbPrintInstanceId
                Write-Field -Label 'LocationInfo'        -Value $device.LocationInfo
                Write-Field -Label 'LocationPath'        -Value $device.LocationPath
                Write-Field -Label 'ContainerId'         -Value $device.ContainerId
                Write-Field -Label 'Bus description'     -Value $device.BusReportedDescription
                Write-Field -Label 'Hardware IDs'        -Value $device.HardwareIds
            }
            Write-Host ''
        }
    }

    Write-Host '[A] Apelidar porta  [E] Exportar JSON/CSV  [R] Atualizar  [Q] Sair' -ForegroundColor DarkGray
}

function Set-PortAliasInteractive {
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][hashtable]$Aliases
    )

    if ($Snapshot.Devices.Count -eq 0) { return }

    Clear-Host
    Write-Host 'APELIDAR PORTA USB FÍSICA' -ForegroundColor Cyan
    Write-Host ''

    for ($i = 0; $i -lt $Snapshot.Devices.Count; $i++) {
        $device = $Snapshot.Devices[$i]
        Write-Host ('[{0}] {1} | {2} | atual: {3}' -f ($i + 1), $device.Modelo, $device.PortaFisica, $device.ApelidoPorta)
    }

    Write-Host ''
    $choiceText = Read-Host 'Número da Zebra (ENTER cancela)'
    if ([string]::IsNullOrWhiteSpace($choiceText)) { return }

    $choice = 0
    if (-not [int]::TryParse($choiceText, [ref]$choice)) { return }
    if ($choice -lt 1 -or $choice -gt $Snapshot.Devices.Count) { return }

    $selected = $Snapshot.Devices[$choice - 1]
    $alias = Read-Host 'Apelido (ex.: USB traseira superior; vazio remove)'

    if ([string]::IsNullOrWhiteSpace($alias)) {
        if ($Aliases.ContainsKey($selected.AliasKey)) {
            [void]$Aliases.Remove($selected.AliasKey)
        }
    }
    else {
        $Aliases[$selected.AliasKey] = $alias.Trim()
    }

    Save-PortAliases -Aliases $Aliases
}

function Get-PressedKey {
    try {
        if ([Console]::KeyAvailable) {
            return [Console]::ReadKey($true).Key
        }
    }
    catch {
        # PowerShell ISE e alguns hosts não expõem KeyAvailable.
    }

    return $null
}

$aliases = Read-PortAliases
$previous = @{}
$spinner = @('|', '/', '-', '\')
$spinnerIndex = 0
$exitRequested = $false

while (-not $exitRequested) {
    try {
        $snapshot = Get-ZebraUsbInventory -Aliases $aliases
    }
    catch {
        Clear-Host
        Write-Host 'Falha ao consultar os dispositivos PnP:' -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ''
        Write-Host ('Versão do script : {0}' -f $VersaoScript) -ForegroundColor Yellow
        Write-Host ('Arquivo executado : {0}' -f $CaminhoScript) -ForegroundColor Yellow
        Write-Host ('Linha/comando     : {0}' -f $_.InvocationInfo.PositionMessage) -ForegroundColor DarkYellow
        Write-Host ('Pilha             : {0}' -f $_.ScriptStackTrace) -ForegroundColor DarkYellow
        Write-Host ''
        Write-Host 'Pressione CTRL+C para encerrar.' -ForegroundColor DarkGray
        Start-Sleep -Seconds $IntervaloSegundos
        continue
    }

    $current = @{}
    foreach ($device in $snapshot.Devices) {
        $current[$device.Chave] = $device

        if (-not $previous.ContainsKey($device.Chave)) {
            Write-ZebraEvent -EventType CONECTADA -Device $device
            if (-not $SemSom) {
                try { [Console]::Beep(1000, 250) } catch {}
            }
        }
    }

    foreach ($key in $previous.Keys) {
        if (-not $current.ContainsKey($key)) {
            Write-ZebraEvent -EventType DESCONECTADA -Device $previous[$key]
        }
    }

    $previous = $current
    Show-ZebraDashboard -Snapshot $snapshot -Spinner $spinner[$spinnerIndex % $spinner.Count]
    $spinnerIndex++

    if ($UmaVez) { break }

    $deadline = (Get-Date).AddSeconds($IntervaloSegundos)
    do {
        $key = Get-PressedKey
        if ($null -ne $key) {
            switch ($key.ToString()) {
                'A' {
                    Set-PortAliasInteractive -Snapshot $snapshot -Aliases $aliases
                    $deadline = Get-Date
                }
                'E' {
                    $paths = Export-ZebraSnapshot -Snapshot $snapshot
                    Write-Host ''
                    Write-Host ('Exportado: {0}' -f $paths.Json) -ForegroundColor Green
                    Write-Host ('Exportado: {0}' -f $paths.Csv) -ForegroundColor Green
                    Start-Sleep -Milliseconds 1200
                    $deadline = Get-Date
                }
                'R' { $deadline = Get-Date }
                'Q' {
                    $exitRequested = $true
                    $deadline = Get-Date
                }
            }
        }

        if (-not $exitRequested -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 100
        }
    } while (-not $exitRequested -and (Get-Date) -lt $deadline)
}

Write-Host ''
Write-Host 'Gerenciador Zebra encerrado.' -ForegroundColor DarkGray
