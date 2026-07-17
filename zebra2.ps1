<#
.SYNOPSIS
    Gerenciador USB para impressoras Zebra, preparado para execução remota:
    irm https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/zebra1.ps1 | iex

.DESCRIPTION
    - Executa em um escopo isolado para não contaminar a sessão do PowerShell.
    - Não depende do caminho físico do arquivo nem de arquivo auxiliar.
    - Não cria nem altera a variável automática que guarda o ID do processo.
    - Detecta dispositivos Zebra por VID, USBPRINT, nome PnP, hardware IDs e filas.
    - Diferencia GC420t, GC420d, ZD220 e outros modelos quando o Windows informa o modelo.
    - Mostra porta virtual USB00x e, quando disponível, a rota física USB.
    - Registra conexões e desconexões em %LOCALAPPDATA%\ZebraUsbManager.
#>

# Invoke-Expression executa no escopo atual. O operador & cria um escopo filho,
# evitando conflito com variáveis/funções que já existam no terminal do usuário.
& {
    [CmdletBinding()]
    param()

    Set-StrictMode -Version 2.0
    $ErrorActionPreference = 'Stop'

    $managerVersion = '2.0.0-iex'
    $executionOrigin = 'remoto via Invoke-RestMethod | Invoke-Expression'
    $refreshSeconds = 2
    $dataDirectory = Join-Path $env:LOCALAPPDATA 'ZebraUsbManager'
    $aliasesFile = Join-Path $dataDirectory 'portas-usb.json'
    $eventsFile = Join-Path $dataDirectory 'eventos-zebra.csv'
    $showDetails = $false

    function Get-ZebraText {
        param([AllowNull()][object]$Value)

        if ($null -eq $Value) { return '' }
        if ($Value -is [System.Array]) {
            return (($Value | ForEach-Object { [string]$_ }) -join ' | ')
        }
        return [string]$Value
    }

    function Get-ZebraObjectValue {
        param(
            [AllowNull()][object]$InputObject,
            [Parameter(Mandatory)][string]$PropertyName
        )

        if ($null -eq $InputObject) { return $null }
        $property = $InputObject.PSObject.Properties[$PropertyName]
        if ($null -eq $property) { return $null }
        return $property.Value
    }

    function Get-ZebraPnpPropertyMap {
        param(
            [Parameter(Mandatory)][string]$InstanceId,
            [Parameter(Mandatory)][bool]$PnpCmdletsAvailable
        )

        $propertyMap = @{}
        if (-not $PnpCmdletsAvailable) { return $propertyMap }

        try {
            $deviceProperties = @(Get-PnpDeviceProperty -InstanceId $InstanceId -ErrorAction Stop)
            foreach ($deviceProperty in $deviceProperties) {
                $keyName = [string](Get-ZebraObjectValue -InputObject $deviceProperty -PropertyName 'KeyName')
                if (-not [string]::IsNullOrWhiteSpace($keyName)) {
                    $propertyMap[$keyName] = Get-ZebraObjectValue -InputObject $deviceProperty -PropertyName 'Data'
                }
            }
        }
        catch {
            # O dispositivo pode desaparecer entre a enumeração e a leitura.
        }

        return $propertyMap
    }

    function Get-ZebraMapValue {
        param(
            [AllowNull()][hashtable]$Map,
            [Parameter(Mandatory)][string[]]$Keys
        )

        if ($null -eq $Map) { return $null }
        foreach ($keyName in $Keys) {
            if ($Map.ContainsKey($keyName)) {
                $candidateValue = $Map[$keyName]
                if ($null -ne $candidateValue -and
                    -not [string]::IsNullOrWhiteSpace((Get-ZebraText $candidateValue))) {
                    return $candidateValue
                }
            }
        }
        return $null
    }

    function Get-ZebraPresentDevices {
        param([Parameter(Mandatory)][bool]$PnpCmdletsAvailable)

        if ($PnpCmdletsAvailable) {
            return @(
                Get-PnpDevice -PresentOnly -ErrorAction Stop |
                    ForEach-Object {
                        [pscustomobject][ordered]@{
                            InstanceId  = [string](Get-ZebraObjectValue $_ 'InstanceId')
                            FriendlyName = [string](Get-ZebraObjectValue $_ 'FriendlyName')
                            Class       = [string](Get-ZebraObjectValue $_ 'Class')
                            Status      = [string](Get-ZebraObjectValue $_ 'Status')
                            Native      = $_
                        }
                    }
            )
        }

        return @(
            Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
                Where-Object {
                    $errorCode = Get-ZebraObjectValue $_ 'ConfigManagerErrorCode'
                    $null -eq $errorCode -or [int]$errorCode -eq 0
                } |
                ForEach-Object {
                    [pscustomobject][ordered]@{
                        InstanceId  = [string](Get-ZebraObjectValue $_ 'PNPDeviceID')
                        FriendlyName = [string](Get-ZebraObjectValue $_ 'Name')
                        Class       = [string](Get-ZebraObjectValue $_ 'PNPClass')
                        Status      = [string](Get-ZebraObjectValue $_ 'Status')
                        Native      = $_
                    }
                }
        )
    }

    function Get-ZebraNode {
        param(
            [Parameter(Mandatory)]$Device,
            [Parameter(Mandatory)][bool]$PnpCmdletsAvailable
        )

        return [pscustomobject][ordered]@{
            Device = $Device
            Props  = Get-ZebraPnpPropertyMap -InstanceId $Device.InstanceId -PnpCmdletsAvailable $PnpCmdletsAvailable
        }
    }

    function Get-ZebraUsbAncestor {
        param(
            [Parameter(Mandatory)]$StartNode,
            [Parameter(Mandatory)][hashtable]$DeviceIndex,
            [Parameter(Mandatory)][bool]$PnpCmdletsAvailable
        )

        $currentNode = $StartNode
        $visitedIds = @{}

        for ($ancestorLevel = 0; $ancestorLevel -lt 12; $ancestorLevel++) {
            if ($null -eq $currentNode -or $null -eq $currentNode.Device) { break }

            $currentInstanceId = [string]$currentNode.Device.InstanceId
            if ($currentInstanceId -match '(?i)^USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}') {
                return $currentNode
            }

            $normalizedCurrentId = $currentInstanceId.ToUpperInvariant()
            if ($visitedIds.ContainsKey($normalizedCurrentId)) { break }
            $visitedIds[$normalizedCurrentId] = $true

            $parentInstanceId = [string](Get-ZebraMapValue -Map $currentNode.Props -Keys @('DEVPKEY_Device_Parent'))
            if ([string]::IsNullOrWhiteSpace($parentInstanceId)) { break }

            $normalizedParentId = $parentInstanceId.ToUpperInvariant()
            if (-not $DeviceIndex.ContainsKey($normalizedParentId)) { break }

            $currentNode = Get-ZebraNode -Device $DeviceIndex[$normalizedParentId] -PnpCmdletsAvailable $PnpCmdletsAvailable
        }

        return $null
    }

    function Resolve-ZebraModel {
        param(
            [AllowEmptyString()][string]$PnpEvidence,
            [AllowEmptyString()][string]$QueueEvidence,
            [AllowEmptyString()][string]$FriendlyEvidence
        )

        $modelPatterns = [ordered]@{
            'GC420t' = '(?i)(?<![A-Z0-9])GC[\s_-]*420[\s_-]*T(?![A-Z0-9])'
            'GC420d' = '(?i)(?<![A-Z0-9])GC[\s_-]*420[\s_-]*D(?![A-Z0-9])'
            'ZD220t' = '(?i)(?<![A-Z0-9])ZD[\s_-]*220[\s_-]*T(?![A-Z0-9])'
            'ZD220d' = '(?i)(?<![A-Z0-9])ZD[\s_-]*220[\s_-]*D(?![A-Z0-9])'
            'ZD220'  = '(?i)(?<![A-Z0-9])ZD[\s_-]*220(?![A-Z0-9])'
            'ZD230t' = '(?i)(?<![A-Z0-9])ZD[\s_-]*230[\s_-]*T(?![A-Z0-9])'
            'ZD230d' = '(?i)(?<![A-Z0-9])ZD[\s_-]*230[\s_-]*D(?![A-Z0-9])'
            'ZD230'  = '(?i)(?<![A-Z0-9])ZD[\s_-]*230(?![A-Z0-9])'
            'GK420t' = '(?i)(?<![A-Z0-9])GK[\s_-]*420[\s_-]*T(?![A-Z0-9])'
            'GK420d' = '(?i)(?<![A-Z0-9])GK[\s_-]*420[\s_-]*D(?![A-Z0-9])'
            'GX420t' = '(?i)(?<![A-Z0-9])GX[\s_-]*420[\s_-]*T(?![A-Z0-9])'
            'GX420d' = '(?i)(?<![A-Z0-9])GX[\s_-]*420[\s_-]*D(?![A-Z0-9])'
            'ZD411'  = '(?i)(?<![A-Z0-9])ZD[\s_-]*411(?![A-Z0-9])'
            'ZD421'  = '(?i)(?<![A-Z0-9])ZD[\s_-]*421(?![A-Z0-9])'
            'ZD621'  = '(?i)(?<![A-Z0-9])ZD[\s_-]*621(?![A-Z0-9])'
            'ZT220'  = '(?i)(?<![A-Z0-9])ZT[\s_-]*220(?![A-Z0-9])'
            'ZT230'  = '(?i)(?<![A-Z0-9])ZT[\s_-]*230(?![A-Z0-9])'
            'ZT410'  = '(?i)(?<![A-Z0-9])ZT[\s_-]*410(?![A-Z0-9])'
            'ZT411'  = '(?i)(?<![A-Z0-9])ZT[\s_-]*411(?![A-Z0-9])'
            'ZT420'  = '(?i)(?<![A-Z0-9])ZT[\s_-]*420(?![A-Z0-9])'
            'ZT421'  = '(?i)(?<![A-Z0-9])ZT[\s_-]*421(?![A-Z0-9])'
        }

        $evidenceSources = @(
            [pscustomobject]@{ Text = $PnpEvidence;      Source = 'PnP/USBPRINT'; Confidence = 'Alta'  },
            [pscustomobject]@{ Text = $QueueEvidence;    Source = 'fila/driver';  Confidence = 'Média' },
            [pscustomobject]@{ Text = $FriendlyEvidence; Source = 'nome amigável'; Confidence = 'Média' }
        )

        foreach ($evidenceSource in $evidenceSources) {
            foreach ($modelName in $modelPatterns.Keys) {
                if ([string]$evidenceSource.Text -match $modelPatterns[$modelName]) {
                    return [pscustomobject]@{
                        Model      = $modelName
                        Source     = $evidenceSource.Source
                        Confidence = $evidenceSource.Confidence
                    }
                }
            }
        }

        $allEvidence = "$PnpEvidence | $QueueEvidence | $FriendlyEvidence"
        if ($allEvidence -match '(?i)Zebra|VID_0A5F|USBPRINT\\ZEBRA') {
            return [pscustomobject]@{
                Model      = 'Zebra (modelo não informado pelo Windows)'
                Source     = 'fabricante/VID'
                Confidence = 'Baixa'
            }
        }

        return [pscustomobject]@{
            Model      = 'Dispositivo compatível'
            Source     = 'evidência parcial'
            Confidence = 'Baixa'
        }
    }

    function Get-ZebraUsbRoute {
        param([AllowEmptyString()][string]$LocationPath)

        if ([string]::IsNullOrWhiteSpace($LocationPath)) { return '' }

        $routeParts = New-Object System.Collections.Generic.List[string]
        $matches = [regex]::Matches($LocationPath, '(?i)(USBROOT|USB)\((\d+)\)')
        foreach ($routeMatch in $matches) {
            if ($routeMatch.Groups[1].Value -ieq 'USBROOT') {
                [void]$routeParts.Add(('Controlador USB {0}' -f $routeMatch.Groups[2].Value))
            }
            else {
                [void]$routeParts.Add(('porta {0}' -f $routeMatch.Groups[2].Value))
            }
        }

        if ($routeParts.Count -gt 0) { return ($routeParts -join ' -> ') }
        return $LocationPath
    }

    function Get-ZebraPhysicalPort {
        param(
            [AllowEmptyString()][string]$LocationInfo,
            [AllowEmptyString()][string]$LocationPath
        )

        if ($LocationInfo -match '(?i)Port_#0*(?<PortNumber>\d+)\.Hub_#0*(?<HubNumber>\d+)') {
            return ('Porta {0} do hub {1}' -f [int]$Matches.PortNumber, [int]$Matches.HubNumber)
        }

        $usbRoute = Get-ZebraUsbRoute -LocationPath $LocationPath
        if (-not [string]::IsNullOrWhiteSpace($usbRoute)) { return $usbRoute }
        return 'Não informada pelo Windows'
    }

    function Get-ZebraQueueStatus {
        param([Parameter(Mandatory)]$Queue)

        $workOffline = Get-ZebraObjectValue $Queue 'WorkOffline'
        if ($workOffline -eq $true) { return 'Offline' }

        $queueStatusCode = Get-ZebraObjectValue $Queue 'PrinterStatus'
        $statusMap = @{
            1 = 'Outro'
            2 = 'Desconhecido'
            3 = 'Pronta/Ociosa'
            4 = 'Imprimindo'
            5 = 'Aquecendo'
            6 = 'Parada'
            7 = 'Offline'
        }
        if ($null -ne $queueStatusCode -and $statusMap.ContainsKey([int]$queueStatusCode)) {
            return $statusMap[[int]$queueStatusCode]
        }

        $textStatus = [string](Get-ZebraObjectValue $Queue 'Status')
        if (-not [string]::IsNullOrWhiteSpace($textStatus)) { return $textStatus }
        return 'Desconhecido'
    }

    function Read-ZebraPortAliases {
        param([Parameter(Mandatory)][string]$Path)

        $aliasTable = @{}
        if (-not (Test-Path -LiteralPath $Path)) { return $aliasTable }

        try {
            $jsonObject = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($null -ne $jsonObject) {
                foreach ($jsonProperty in $jsonObject.PSObject.Properties) {
                    $aliasTable[[string]$jsonProperty.Name] = [string]$jsonProperty.Value
                }
            }
        }
        catch {
            Write-Warning ('Não foi possível ler os apelidos: {0}' -f $_.Exception.Message)
        }

        return $aliasTable
    }

    function Save-ZebraPortAliases {
        param(
            [Parameter(Mandatory)][hashtable]$Aliases,
            [Parameter(Mandatory)][string]$Path
        )

        $orderedAliases = [ordered]@{}
        foreach ($aliasKey in ($Aliases.Keys | Sort-Object)) {
            $orderedAliases[$aliasKey] = $Aliases[$aliasKey]
        }
        $orderedAliases | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding UTF8
    }

    function Get-ZebraInventory {
        param(
            [Parameter(Mandatory)][hashtable]$Aliases,
            [Parameter(Mandatory)][bool]$PnpCmdletsAvailable
        )

        $presentDevices = @(Get-ZebraPresentDevices -PnpCmdletsAvailable $PnpCmdletsAvailable)
        $deviceIndex = @{}
        foreach ($presentDevice in $presentDevices) {
            if (-not [string]::IsNullOrWhiteSpace($presentDevice.InstanceId)) {
                $deviceIndex[$presentDevice.InstanceId.ToUpperInvariant()] = $presentDevice
            }
        }

        $usbDeviceCount = @(
            $presentDevices | Where-Object { $_.InstanceId -match '(?i)^(USB|USBPRINT)\\' }
        ).Count

        $candidateNodes = @()
        foreach ($presentDevice in $presentDevices) {
            $instanceId = [string]$presentDevice.InstanceId
            $friendlyName = [string]$presentDevice.FriendlyName

            $isPossibleCandidate =
                $instanceId -match '(?i)^USBPRINT\\' -or
                $instanceId -match '(?i)^USB\\VID_0A5F' -or
                $friendlyName -match '(?i)Zebra|GC[\s_-]*420|ZD[\s_-]*22[0-9]|GK[\s_-]*420|GX[\s_-]*420|ZT[\s_-]*[0-9]{3}'

            if (-not $isPossibleCandidate) { continue }

            $candidateNode = Get-ZebraNode -Device $presentDevice -PnpCmdletsAvailable $PnpCmdletsAvailable
            $hardwareIds = Get-ZebraText (Get-ZebraMapValue -Map $candidateNode.Props -Keys @('DEVPKEY_Device_HardwareIds'))
            $compatibleIds = Get-ZebraText (Get-ZebraMapValue -Map $candidateNode.Props -Keys @('DEVPKEY_Device_CompatibleIds'))
            $busDescription = Get-ZebraText (Get-ZebraMapValue -Map $candidateNode.Props -Keys @('DEVPKEY_Device_BusReportedDeviceDesc'))
            $deviceDescription = Get-ZebraText (Get-ZebraMapValue -Map $candidateNode.Props -Keys @('DEVPKEY_Device_DeviceDesc'))
            $candidateEvidence = "$instanceId | $friendlyName | $hardwareIds | $compatibleIds | $busDescription | $deviceDescription"

            if ($instanceId -match '(?i)^USB\\VID_0A5F' -or
                $candidateEvidence -match '(?i)Zebra|GC[\s_-]*420|ZD[\s_-]*22[0-9]|GK[\s_-]*420|GX[\s_-]*420|ZT[\s_-]*[0-9]{3}') {
                $candidateNodes += $candidateNode
            }
        }

        $printerQueues = @()
        try {
            $printerQueues = @(Get-CimInstance -ClassName Win32_Printer -ErrorAction Stop)
        }
        catch {
            # A detecção PnP continua mesmo com o spooler indisponível.
        }

        $nodeGroups = @{}
        foreach ($candidateNode in $candidateNodes) {
            $physicalAnchorNode = $null
            $candidateInstanceId = [string]$candidateNode.Device.InstanceId

            if ($candidateInstanceId -match '(?i)^USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}') {
                $physicalAnchorNode = $candidateNode
            }
            elseif ($candidateInstanceId -match '(?i)^USBPRINT\\') {
                $physicalAnchorNode = Get-ZebraUsbAncestor -StartNode $candidateNode -DeviceIndex $deviceIndex -PnpCmdletsAvailable $PnpCmdletsAvailable
            }

            if ($null -ne $physicalAnchorNode) {
                $groupKey = 'PHYSICAL:' + $physicalAnchorNode.Device.InstanceId.ToUpperInvariant()
            }
            else {
                $containerIdentifier = Get-ZebraText (Get-ZebraMapValue -Map $candidateNode.Props -Keys @('DEVPKEY_Device_ContainerId'))
                $parentIdentifier = Get-ZebraText (Get-ZebraMapValue -Map $candidateNode.Props -Keys @('DEVPKEY_Device_Parent'))

                if (-not [string]::IsNullOrWhiteSpace($containerIdentifier)) {
                    $groupKey = 'CONTAINER:' + $containerIdentifier.ToUpperInvariant()
                }
                elseif (-not [string]::IsNullOrWhiteSpace($parentIdentifier)) {
                    $groupKey = 'PARENT:' + $parentIdentifier.ToUpperInvariant()
                }
                else {
                    $groupKey = 'INSTANCE:' + $candidateInstanceId.ToUpperInvariant()
                }
            }

            if (-not $nodeGroups.ContainsKey($groupKey)) {
                $nodeGroups[$groupKey] = New-Object System.Collections.ArrayList
            }
            [void]$nodeGroups[$groupKey].Add($candidateNode)
        }

        $inventoryDevices = @()
        $seenPhysicalDevices = @{}

        foreach ($groupKey in $nodeGroups.Keys) {
            $groupNodes = @($nodeGroups[$groupKey])
            $printNode = $groupNodes |
                Where-Object { $_.Device.InstanceId -match '(?i)^USBPRINT\\' } |
                Select-Object -First 1

            $usbNode = $groupNodes |
                Where-Object { $_.Device.InstanceId -match '(?i)^USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}' } |
                Sort-Object { if ($_.Device.InstanceId -match '(?i)^USB\\VID_0A5F') { 0 } else { 1 } } |
                Select-Object -First 1

            if ($null -eq $usbNode -and $null -ne $printNode) {
                $usbNode = Get-ZebraUsbAncestor -StartNode $printNode -DeviceIndex $deviceIndex -PnpCmdletsAvailable $PnpCmdletsAvailable
            }

            $identityNode = if ($null -ne $printNode) { $printNode } else { $usbNode }
            if ($null -eq $identityNode) { continue }

            $physicalInstanceId = if ($null -ne $usbNode) {
                [string]$usbNode.Device.InstanceId
            }
            else {
                [string]$identityNode.Device.InstanceId
            }

            $deduplicationKey = $physicalInstanceId.ToUpperInvariant()
            if ($seenPhysicalDevices.ContainsKey($deduplicationKey)) { continue }
            $seenPhysicalDevices[$deduplicationKey] = $true

            $matchingQueues = @()
            if ($null -ne $printNode) {
                $usbPrintIdentifier = $printNode.Device.InstanceId.ToUpperInvariant()
                $matchingQueues = @(
                    $printerQueues | Where-Object {
                        $queuePnpIdentifier = [string](Get-ZebraObjectValue $_ 'PNPDeviceID')
                        -not [string]::IsNullOrWhiteSpace($queuePnpIdentifier) -and
                        $queuePnpIdentifier.ToUpperInvariant() -eq $usbPrintIdentifier
                    }
                )
            }

            if ($matchingQueues.Count -eq 0) {
                $possibleZebraQueues = @(
                    $printerQueues | Where-Object {
                        $queueName = [string](Get-ZebraObjectValue $_ 'Name')
                        $driverName = [string](Get-ZebraObjectValue $_ 'DriverName')
                        $portName = [string](Get-ZebraObjectValue $_ 'PortName')
                        $portName -match '(?i)^USB\d{3,}$' -and
                        "$queueName $driverName" -match '(?i)Zebra|GC[\s_-]*420|ZD[\s_-]*22[0-9]|GK[\s_-]*420|GX[\s_-]*420|ZT[\s_-]*[0-9]{3}'
                    }
                )
                if ($possibleZebraQueues.Count -eq 1) { $matchingQueues = $possibleZebraQueues }
            }

            $queueEvidence = ($matchingQueues | ForEach-Object {
                '{0} {1} {2} {3}' -f
                    (Get-ZebraObjectValue $_ 'Name'),
                    (Get-ZebraObjectValue $_ 'DriverName'),
                    (Get-ZebraObjectValue $_ 'PortName'),
                    (Get-ZebraObjectValue $_ 'PNPDeviceID')
            }) -join ' | '

            $pnpEvidencePieces = @()
            foreach ($evidenceNode in @($groupNodes + @($usbNode, $printNode))) {
                if ($null -eq $evidenceNode) { continue }
                $pnpEvidencePieces += [string]$evidenceNode.Device.InstanceId
                $pnpEvidencePieces += [string]$evidenceNode.Device.FriendlyName
                $pnpEvidencePieces += Get-ZebraText (Get-ZebraMapValue -Map $evidenceNode.Props -Keys @('DEVPKEY_Device_HardwareIds'))
                $pnpEvidencePieces += Get-ZebraText (Get-ZebraMapValue -Map $evidenceNode.Props -Keys @('DEVPKEY_Device_CompatibleIds'))
                $pnpEvidencePieces += Get-ZebraText (Get-ZebraMapValue -Map $evidenceNode.Props -Keys @('DEVPKEY_Device_BusReportedDeviceDesc'))
                $pnpEvidencePieces += Get-ZebraText (Get-ZebraMapValue -Map $evidenceNode.Props -Keys @('DEVPKEY_Device_DeviceDesc'))
            }
            $pnpEvidence = $pnpEvidencePieces -join ' | '
            $friendlyEvidence = ($groupNodes | ForEach-Object { [string]$_.Device.FriendlyName }) -join ' | '
            $modelInformation = Resolve-ZebraModel -PnpEvidence $pnpEvidence -QueueEvidence $queueEvidence -FriendlyEvidence $friendlyEvidence

            $locationNode = if ($null -ne $usbNode) { $usbNode } else { $identityNode }
            $locationInformation = Get-ZebraText (Get-ZebraMapValue -Map $locationNode.Props -Keys @('DEVPKEY_Device_LocationInfo'))
            $locationPathsValue = Get-ZebraMapValue -Map $locationNode.Props -Keys @('DEVPKEY_Device_LocationPaths')
            $locationPaths = @($locationPathsValue | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            $locationPath = if ($locationPaths.Count -gt 0) { [string]$locationPaths[0] } else { '' }

            $vendorIdentifier = ''
            $usbProductIdentifier = ''
            $identifierEvidence = "$physicalInstanceId | $pnpEvidence"
            if ($identifierEvidence -match '(?i)VID_([0-9A-F]{4})') {
                $vendorIdentifier = $Matches[1].ToUpperInvariant()
            }
            if ($identifierEvidence -match '(?i)PID_([0-9A-F]{4})') {
                $usbProductIdentifier = $Matches[1].ToUpperInvariant()
            }

            $serialOrInstance = ''
            if ($physicalInstanceId -match '^[^\\]+\\[^\\]+\\(.+)$') {
                $serialOrInstance = $Matches[1]
            }

            $aliasLookupKey = if (-not [string]::IsNullOrWhiteSpace($locationPath)) {
                $locationPath
            }
            else {
                $physicalInstanceId
            }
            $portAlias = if ($Aliases.ContainsKey($aliasLookupKey)) { [string]$Aliases[$aliasLookupKey] } else { '' }

            $queueNames = @($matchingQueues | ForEach-Object { [string](Get-ZebraObjectValue $_ 'Name') })
            $virtualPorts = @($matchingQueues | ForEach-Object { [string](Get-ZebraObjectValue $_ 'PortName') } | Sort-Object -Unique)
            $driverNames = @($matchingQueues | ForEach-Object { [string](Get-ZebraObjectValue $_ 'DriverName') } | Sort-Object -Unique)
            $queueStatuses = @($matchingQueues | ForEach-Object { Get-ZebraQueueStatus $_ } | Sort-Object -Unique)

            $inventoryDevices += [pscustomobject][ordered]@{
                Key                    = $deduplicationKey
                Model                  = $modelInformation.Model
                ModelConfidence        = $modelInformation.Confidence
                ModelSource            = $modelInformation.Source
                PnpStatus              = [string]$identityNode.Device.Status
                QueueStatus            = if ($queueStatuses.Count) { $queueStatuses -join ', ' } else { 'Sem fila instalada' }
                QueueName              = if ($queueNames.Count) { $queueNames -join ', ' } else { '' }
                DriverName             = if ($driverNames.Count) { $driverNames -join ', ' } else { '' }
                VirtualPort            = if ($virtualPorts.Count) { $virtualPorts -join ', ' } else { '' }
                PhysicalPort           = Get-ZebraPhysicalPort -LocationInfo $locationInformation -LocationPath $locationPath
                PortAlias              = $portAlias
                UsbRoute               = Get-ZebraUsbRoute -LocationPath $locationPath
                LocationInfo           = $locationInformation
                LocationPath           = $locationPath
                AliasLookupKey         = $aliasLookupKey
                VendorId               = $vendorIdentifier
                UsbProductId           = $usbProductIdentifier
                SerialOrInstance       = $serialOrInstance
                UsbInstanceId          = $physicalInstanceId
                UsbPrintInstanceId     = if ($null -ne $printNode) { [string]$printNode.Device.InstanceId } else { '' }
                ContainerId            = Get-ZebraText (Get-ZebraMapValue -Map $identityNode.Props -Keys @('DEVPKEY_Device_ContainerId'))
                BusReportedDescription = Get-ZebraText (Get-ZebraMapValue -Map $identityNode.Props -Keys @('DEVPKEY_Device_BusReportedDeviceDesc'))
                HardwareIds            = Get-ZebraText (Get-ZebraMapValue -Map $identityNode.Props -Keys @('DEVPKEY_Device_HardwareIds'))
            }
        }

        return [pscustomobject][ordered]@{
            ScannedAt       = Get-Date
            UsbDeviceCount  = $usbDeviceCount
            Devices         = @($inventoryDevices | Sort-Object Model, PhysicalPort)
        }
    }

    function Write-ZebraConnectionEvent {
        param(
            [Parameter(Mandatory)][ValidateSet('CONECTADA', 'DESCONECTADA')][string]$EventType,
            [Parameter(Mandatory)]$Device,
            [Parameter(Mandatory)][string]$Path
        )

        $eventRecord = [pscustomobject][ordered]@{
            DataHora       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Evento         = $EventType
            Modelo         = $Device.Model
            Confianca      = $Device.ModelConfidence
            PortaVirtual   = $Device.VirtualPort
            PortaFisica    = $Device.PhysicalPort
            ApelidoPorta   = $Device.PortAlias
            VID            = $Device.VendorId
            ProductId      = $Device.UsbProductId
            UsbInstanceId  = $Device.UsbInstanceId
            LocationPath   = $Device.LocationPath
        }

        if (Test-Path -LiteralPath $Path) {
            $eventRecord | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 -Append
        }
        else {
            $eventRecord | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
        }
    }

    function Export-ZebraInventory {
        param(
            [Parameter(Mandatory)]$Inventory,
            [Parameter(Mandatory)][string]$Directory
        )

        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $jsonPath = Join-Path $Directory "zebra-inventario-$timestamp.json"
        $csvPath = Join-Path $Directory "zebra-inventario-$timestamp.csv"
        $Inventory.Devices | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
        $Inventory.Devices | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

        return [pscustomobject]@{ JsonPath = $jsonPath; CsvPath = $csvPath }
    }

    function Write-ZebraField {
        param(
            [Parameter(Mandatory)][string]$Label,
            [AllowEmptyString()][string]$Value,
            [ConsoleColor]$Color = [ConsoleColor]::Gray
        )

        if ([string]::IsNullOrWhiteSpace($Value)) { $Value = '-' }
        Write-Host ('{0,-20}: ' -f $Label) -NoNewline -ForegroundColor DarkGray
        Write-Host $Value -ForegroundColor $Color
    }

    function Show-ZebraDashboard {
        param(
            [Parameter(Mandatory)]$Inventory,
            [Parameter(Mandatory)][string]$SpinnerCharacter,
            [Parameter(Mandatory)][string]$Version,
            [Parameter(Mandatory)][string]$Origin,
            [Parameter(Mandatory)][string]$Directory,
            [Parameter(Mandatory)][bool]$Detailed
        )

        Clear-Host
        Write-Host '==================================================================' -ForegroundColor Cyan
        Write-Host '        GERENCIADOR USB - IMPRESSORAS ZEBRA' -ForegroundColor Cyan
        Write-Host '==================================================================' -ForegroundColor Cyan
        Write-Host ('Monitorando {0} | {1:dd/MM/yyyy HH:mm:ss}' -f $SpinnerCharacter, $Inventory.ScannedAt) -ForegroundColor White
        Write-Host ('USB/USBPRINT presentes: {0} | Zebras: {1}' -f $Inventory.UsbDeviceCount, $Inventory.Devices.Count) -ForegroundColor DarkGray
        Write-Host ('Versão: {0} | Execução: {1}' -f $Version, $Origin) -ForegroundColor DarkGray
        Write-Host ('Dados: {0}' -f $Directory) -ForegroundColor DarkGray
        Write-Host ''

        if ($Inventory.Devices.Count -eq 0) {
            Write-Host '[ NENHUMA ZEBRA USB DETECTADA ]' -ForegroundColor Yellow
            Write-Host ''
            Write-Host '1. Ligue a impressora e aguarde o Windows reconhecer o USB.'
            Write-Host '2. Troque o cabo USB A-B e teste outra porta física.'
            Write-Host '3. Verifique se surge USBPRINT ou VID_0A5F no Gerenciador de Dispositivos.'
        }
        else {
            $displayNumber = 0
            foreach ($device in $Inventory.Devices) {
                $displayNumber++
                Write-Host ('--------------------------- ZEBRA #{0} ---------------------------' -f $displayNumber) -ForegroundColor DarkCyan

                $modelColor = if ($device.ModelConfidence -eq 'Baixa') { [ConsoleColor]::Yellow } else { [ConsoleColor]::Green }
                Write-ZebraField -Label 'Modelo' -Value $device.Model -Color $modelColor
                Write-ZebraField -Label 'Identificação' -Value ($device.ModelConfidence + ' via ' + $device.ModelSource)
                Write-ZebraField -Label 'Status PnP' -Value $device.PnpStatus
                Write-ZebraField -Label 'Fila Windows' -Value $device.QueueName
                Write-ZebraField -Label 'Status da fila' -Value $device.QueueStatus
                Write-ZebraField -Label 'Driver' -Value $device.DriverName
                Write-ZebraField -Label 'Porta virtual' -Value $device.VirtualPort -Color Cyan
                Write-ZebraField -Label 'Porta física' -Value $device.PhysicalPort -Color Cyan
                Write-ZebraField -Label 'Apelido da porta' -Value $device.PortAlias -Color Magenta
                Write-ZebraField -Label 'Rota USB' -Value $device.UsbRoute
                Write-ZebraField -Label 'VID / Product ID' -Value (($device.VendorId + ' / ' + $device.UsbProductId).Trim([char[]]' /'))
                Write-ZebraField -Label 'Serial/instância' -Value $device.SerialOrInstance

                if ($Detailed) {
                    Write-ZebraField -Label 'USB InstanceId' -Value $device.UsbInstanceId
                    Write-ZebraField -Label 'USBPRINT InstanceId' -Value $device.UsbPrintInstanceId
                    Write-ZebraField -Label 'LocationInfo' -Value $device.LocationInfo
                    Write-ZebraField -Label 'LocationPath' -Value $device.LocationPath
                    Write-ZebraField -Label 'ContainerId' -Value $device.ContainerId
                    Write-ZebraField -Label 'Descrição do barramento' -Value $device.BusReportedDescription
                    Write-ZebraField -Label 'Hardware IDs' -Value $device.HardwareIds
                }
                Write-Host ''
            }
        }

        Write-Host '[A] Apelidar porta  [D] Detalhes  [E] Exportar  [R] Atualizar  [Q] Sair' -ForegroundColor DarkGray
    }

    function Set-ZebraPortAliasInteractive {
        param(
            [Parameter(Mandatory)]$Inventory,
            [Parameter(Mandatory)][hashtable]$Aliases,
            [Parameter(Mandatory)][string]$Path
        )

        if ($Inventory.Devices.Count -eq 0) { return }

        Clear-Host
        Write-Host 'APELIDAR PORTA USB FÍSICA' -ForegroundColor Cyan
        Write-Host ''
        for ($deviceIndex = 0; $deviceIndex -lt $Inventory.Devices.Count; $deviceIndex++) {
            $device = $Inventory.Devices[$deviceIndex]
            Write-Host ('[{0}] {1} | {2} | atual: {3}' -f ($deviceIndex + 1), $device.Model, $device.PhysicalPort, $device.PortAlias)
        }

        Write-Host ''
        $selectionText = Read-Host 'Número da Zebra (ENTER cancela)'
        if ([string]::IsNullOrWhiteSpace($selectionText)) { return }

        $selectionNumber = 0
        if (-not [int]::TryParse($selectionText, [ref]$selectionNumber)) { return }
        if ($selectionNumber -lt 1 -or $selectionNumber -gt $Inventory.Devices.Count) { return }

        $selectedDevice = $Inventory.Devices[$selectionNumber - 1]
        $newAlias = Read-Host 'Apelido (ex.: USB traseira superior; vazio remove)'

        if ([string]::IsNullOrWhiteSpace($newAlias)) {
            if ($Aliases.ContainsKey($selectedDevice.AliasLookupKey)) {
                [void]$Aliases.Remove($selectedDevice.AliasLookupKey)
            }
        }
        else {
            $Aliases[$selectedDevice.AliasLookupKey] = $newAlias.Trim()
        }

        Save-ZebraPortAliases -Aliases $Aliases -Path $Path
    }

    function Get-ZebraPressedKey {
        try {
            if ([Console]::KeyAvailable) {
                return [Console]::ReadKey($true).Key
            }
        }
        catch {
            # Alguns hosts não oferecem KeyAvailable.
        }
        return $null
    }

    function Show-ZebraFatalError {
        param(
            [Parameter(Mandatory)]$ErrorRecord,
            [Parameter(Mandatory)][string]$Version,
            [Parameter(Mandatory)][string]$Origin
        )

        Clear-Host
        Write-Host 'FALHA NO GERENCIADOR ZEBRA' -ForegroundColor Red
        Write-Host '----------------------------------------' -ForegroundColor DarkRed
        Write-Host ('Mensagem : {0}' -f $ErrorRecord.Exception.Message) -ForegroundColor Red
        Write-Host ('Tipo     : {0}' -f $ErrorRecord.Exception.GetType().FullName) -ForegroundColor Yellow
        Write-Host ('Erro ID  : {0}' -f $ErrorRecord.FullyQualifiedErrorId) -ForegroundColor Yellow
        Write-Host ('Versão   : {0}' -f $Version) -ForegroundColor Yellow
        Write-Host ('Execução : {0}' -f $Origin) -ForegroundColor Yellow
        Write-Host ('Linha    : {0}' -f $ErrorRecord.InvocationInfo.PositionMessage) -ForegroundColor DarkYellow
        Write-Host ('Pilha    : {0}' -f $ErrorRecord.ScriptStackTrace) -ForegroundColor DarkYellow
    }

    try {
        $isWindowsPlatform = $env:OS -eq 'Windows_NT'
        if (-not $isWindowsPlatform) {
            throw 'Este gerenciador precisa ser executado no Windows 10 ou Windows 11.'
        }

        if ($PSVersionTable.PSVersion -lt [version]'5.1') {
            throw ('PowerShell 5.1 ou superior é necessário. Versão atual: {0}' -f $PSVersionTable.PSVersion)
        }

        if (-not (Test-Path -LiteralPath $dataDirectory)) {
            New-Item -Path $dataDirectory -ItemType Directory -Force | Out-Null
        }

        $pnpCmdletsAvailable = $false
        try {
            Import-Module PnpDevice -ErrorAction Stop
            $pnpCmdletsAvailable =
                $null -ne (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) -and
                $null -ne (Get-Command Get-PnpDeviceProperty -ErrorAction SilentlyContinue)
        }
        catch {
            $pnpCmdletsAvailable = $false
        }

        $portAliases = Read-ZebraPortAliases -Path $aliasesFile
        $previousDevices = @{}
        $spinnerCharacters = @('|', '/', '-', '\')
        $spinnerPosition = 0
        $stopRequested = $false

        while (-not $stopRequested) {
            try {
                $inventory = Get-ZebraInventory -Aliases $portAliases -PnpCmdletsAvailable $pnpCmdletsAvailable
            }
            catch {
                Show-ZebraFatalError -ErrorRecord $_ -Version $managerVersion -Origin $executionOrigin
                Write-Host ''
                Write-Host 'Nova tentativa em alguns segundos. Pressione CTRL+C para encerrar.' -ForegroundColor DarkGray
                Start-Sleep -Seconds $refreshSeconds
                continue
            }

            $currentDevices = @{}
            foreach ($device in $inventory.Devices) {
                $currentDevices[$device.Key] = $device
                if (-not $previousDevices.ContainsKey($device.Key)) {
                    Write-ZebraConnectionEvent -EventType 'CONECTADA' -Device $device -Path $eventsFile
                    try { [Console]::Beep(1000, 250) } catch {}
                }
            }

            foreach ($previousKey in $previousDevices.Keys) {
                if (-not $currentDevices.ContainsKey($previousKey)) {
                    Write-ZebraConnectionEvent -EventType 'DESCONECTADA' -Device $previousDevices[$previousKey] -Path $eventsFile
                }
            }
            $previousDevices = $currentDevices

            Show-ZebraDashboard `
                -Inventory $inventory `
                -SpinnerCharacter $spinnerCharacters[$spinnerPosition % $spinnerCharacters.Count] `
                -Version $managerVersion `
                -Origin $executionOrigin `
                -Directory $dataDirectory `
                -Detailed $showDetails

            $spinnerPosition++
            $refreshDeadline = (Get-Date).AddSeconds($refreshSeconds)

            do {
                $pressedKey = Get-ZebraPressedKey
                if ($null -ne $pressedKey) {
                    switch ($pressedKey.ToString()) {
                        'A' {
                            Set-ZebraPortAliasInteractive -Inventory $inventory -Aliases $portAliases -Path $aliasesFile
                            $refreshDeadline = Get-Date
                        }
                        'D' {
                            $showDetails = -not $showDetails
                            $refreshDeadline = Get-Date
                        }
                        'E' {
                            $exportedPaths = Export-ZebraInventory -Inventory $inventory -Directory $dataDirectory
                            Write-Host ''
                            Write-Host ('JSON: {0}' -f $exportedPaths.JsonPath) -ForegroundColor Green
                            Write-Host ('CSV : {0}' -f $exportedPaths.CsvPath) -ForegroundColor Green
                            Start-Sleep -Milliseconds 1300
                            $refreshDeadline = Get-Date
                        }
                        'R' { $refreshDeadline = Get-Date }
                        'Q' {
                            $stopRequested = $true
                            $refreshDeadline = Get-Date
                        }
                    }
                }

                if (-not $stopRequested -and (Get-Date) -lt $refreshDeadline) {
                    Start-Sleep -Milliseconds 100
                }
            }
            while (-not $stopRequested -and (Get-Date) -lt $refreshDeadline)
        }
    }
    catch {
        Show-ZebraFatalError -ErrorRecord $_ -Version $managerVersion -Origin $executionOrigin
    }

    Write-Host ''
    Write-Host 'Gerenciador Zebra encerrado.' -ForegroundColor DarkGray
}
