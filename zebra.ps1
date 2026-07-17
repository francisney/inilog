<#
Executar diretamente no PowerShell:
irm https://raw.githubusercontent.com/francisney/inilog/refs/heads/main/zebra1.ps1 | iex

Gerenciador Zebra USB em arquivo único:
- Atualiza automaticamente em tempo real.
- Mostra cabo USB conectado ou desconectado.
- Diferencia o estado físico da conexão do estado da fila do Windows.
- Mostra cada instalação Zebra em um quadro completo.
- Funciona inteiramente em memória com Invoke-RestMethod | Invoke-Expression.
#>

& {
    [CmdletBinding()]
    param()

    Set-StrictMode -Version 2.0
    $ErrorActionPreference = 'Stop'

    # Limpa dados e arquivos deixados pelas versões antigas.
    $legacyFolders = @(
        (Join-Path $env:LOCALAPPDATA 'ZebraUsbManager'),
        (Join-Path $env:LOCALAPPDATA 'ZebraUSBManager')
    ) | Select-Object -Unique

    foreach ($legacyFolder in $legacyFolders) {
        if (-not [string]::IsNullOrWhiteSpace($legacyFolder) -and
            (Test-Path -LiteralPath $legacyFolder)) {
            Remove-Item -LiteralPath $legacyFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:TEMP) -and
        (Test-Path -LiteralPath $env:TEMP)) {
        Get-ChildItem -LiteralPath $env:TEMP -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^(Gerenciador-ZebraUSB|zebra-gerenciador).*\.ps1$'
            } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    $refreshMilliseconds = 1000
    $showAdvancedInformation = $false
    $reportDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
    if ([string]::IsNullOrWhiteSpace($reportDirectory)) {
        $reportDirectory = $env:TEMP
    }

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
            # O dispositivo pode ser removido enquanto suas propriedades são lidas.
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
                            InstanceId   = [string](Get-ZebraObjectValue $_ 'InstanceId')
                            FriendlyName = [string](Get-ZebraObjectValue $_ 'FriendlyName')
                            Class        = [string](Get-ZebraObjectValue $_ 'Class')
                            Status       = [string](Get-ZebraObjectValue $_ 'Status')
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
                        InstanceId   = [string](Get-ZebraObjectValue $_ 'PNPDeviceID')
                        FriendlyName = [string](Get-ZebraObjectValue $_ 'Name')
                        Class        = [string](Get-ZebraObjectValue $_ 'PNPClass')
                        Status       = [string](Get-ZebraObjectValue $_ 'Status')
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

        foreach ($evidenceText in @($PnpEvidence, $QueueEvidence, $FriendlyEvidence)) {
            foreach ($modelName in $modelPatterns.Keys) {
                if ([string]$evidenceText -match $modelPatterns[$modelName]) {
                    return $modelName
                }
            }
        }

        $allEvidence = "$PnpEvidence | $QueueEvidence | $FriendlyEvidence"
        if ($allEvidence -match '(?i)Zebra|VID_0A5F|USBPRINT\\ZEBRA') {
            return 'Zebra'
        }

        return 'Impressora Zebra'
    }

    function Get-ZebraUsbRoute {
        param([AllowEmptyString()][string]$LocationPath)

        if ([string]::IsNullOrWhiteSpace($LocationPath)) { return '' }

        $routeParts = New-Object System.Collections.Generic.List[string]
        $routeMatches = [regex]::Matches($LocationPath, '(?i)(USBROOT|USB)\((\d+)\)')
        foreach ($routeMatch in $routeMatches) {
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
        return 'Não identificada pelo Windows'
    }

    function Get-ZebraQueueState {
        param([Parameter(Mandatory)]$Queue)

        $workOffline = Get-ZebraObjectValue $Queue 'WorkOffline'
        $queueStatusCode = Get-ZebraObjectValue $Queue 'PrinterStatus'

        if ($workOffline -eq $true) {
            return [pscustomobject]@{
                Text       = 'Offline no Windows'
                ShortText  = 'Offline'
                Category   = 'Offline'
                IsOffline  = $true
                IsUsable   = $false
            }
        }

        if ($null -ne $queueStatusCode) {
            switch ([int]$queueStatusCode) {
                3 {
                    return [pscustomobject]@{
                        Text = 'Disponível'; ShortText = 'Disponível'; Category = 'Ready'; IsOffline = $false; IsUsable = $true
                    }
                }
                4 {
                    return [pscustomobject]@{
                        Text = 'Imprimindo'; ShortText = 'Imprimindo'; Category = 'Printing'; IsOffline = $false; IsUsable = $true
                    }
                }
                5 {
                    return [pscustomobject]@{
                        Text = 'Preparando'; ShortText = 'Preparando'; Category = 'Busy'; IsOffline = $false; IsUsable = $true
                    }
                }
                6 {
                    return [pscustomobject]@{
                        Text = 'Pausada ou parada'; ShortText = 'Pausada'; Category = 'Paused'; IsOffline = $false; IsUsable = $false
                    }
                }
                7 {
                    return [pscustomobject]@{
                        Text = 'Offline no Windows'; ShortText = 'Offline'; Category = 'Offline'; IsOffline = $true; IsUsable = $false
                    }
                }
            }
        }

        return [pscustomobject]@{
            Text       = 'Sem resposta da impressora'
            ShortText  = 'Sem resposta'
            Category   = 'Unknown'
            IsOffline  = $false
            IsUsable   = $false
        }
    }

    function Test-ZebraPrinterQueue {
        param([Parameter(Mandatory)]$Queue)

        $queueName = [string](Get-ZebraObjectValue $Queue 'Name')
        $driverName = [string](Get-ZebraObjectValue $Queue 'DriverName')
        $portName = [string](Get-ZebraObjectValue $Queue 'PortName')
        $queuePnpIdentifier = [string](Get-ZebraObjectValue $Queue 'PNPDeviceID')
        $evidence = "$queueName | $driverName | $portName | $queuePnpIdentifier"

        return (
            $portName -match '(?i)^USB\d{3,}$' -and
            $evidence -match '(?i)Zebra|ZDesigner|GC[\s_-]*420|ZD[\s_-]*[0-9]{3}|GK[\s_-]*420|GX[\s_-]*420|ZT[\s_-]*[0-9]{3}'
        )
    }

    function Get-ZebraQueueCandidates {
        param(
            [Parameter(Mandatory)][object[]]$PrinterQueues,
            [AllowNull()]$PrintNode,
            [Parameter(Mandatory)][string]$Model,
            [Parameter(Mandatory)][int]$PhysicalDeviceCount
        )

        $result = @()
        $usbPrintIdentifier = ''
        if ($null -ne $PrintNode) {
            $usbPrintIdentifier = ([string]$PrintNode.Device.InstanceId).ToUpperInvariant()
        }

        $normalizedModel = ($Model -replace '[^A-Za-z0-9]', '').ToUpperInvariant()
        $baseModel = $normalizedModel -replace '(?i)[TD]$', ''

        foreach ($queue in $PrinterQueues) {
            if (-not (Test-ZebraPrinterQueue -Queue $queue)) { continue }

            $queueName = [string](Get-ZebraObjectValue $queue 'Name')
            $driverName = [string](Get-ZebraObjectValue $queue 'DriverName')
            $portName = [string](Get-ZebraObjectValue $queue 'PortName')
            $queuePnpIdentifier = [string](Get-ZebraObjectValue $queue 'PNPDeviceID')
            $queueEvidence = "$queueName $driverName $queuePnpIdentifier"
            $normalizedQueueEvidence = ($queueEvidence -replace '[^A-Za-z0-9]', '').ToUpperInvariant()
            $queueState = Get-ZebraQueueState -Queue $queue

            $exactMatch = (
                -not [string]::IsNullOrWhiteSpace($usbPrintIdentifier) -and
                -not [string]::IsNullOrWhiteSpace($queuePnpIdentifier) -and
                $queuePnpIdentifier.ToUpperInvariant() -eq $usbPrintIdentifier
            )

            $modelMatch = $false
            if (-not [string]::IsNullOrWhiteSpace($baseModel) -and $baseModel -ne 'ZEBRA') {
                $modelMatch = $normalizedQueueEvidence.Contains($baseModel)
            }

            if ($PhysicalDeviceCount -gt 1 -and -not $exactMatch -and -not $modelMatch) {
                continue
            }

            $score = 0
            $association = 'Possível'

            if ($exactMatch) {
                $score += 100
                $association = 'Confirmada'
            }
            elseif ($modelMatch) {
                $score += 50
                $association = 'Provável'
            }
            elseif ($PhysicalDeviceCount -eq 1) {
                $score += 20
                $association = 'Possível'
            }

            if ($queueState.IsUsable) { $score += 15 }
            if ($queueState.IsOffline) { $score -= 15 }
            if ($portName -match '(?i)^USB\d{3,}$') { $score += 5 }

            $result += [pscustomobject][ordered]@{
                Name          = $queueName
                Driver        = $driverName
                Port          = $portName
                State         = $queueState.Text
                ShortState    = $queueState.ShortText
                Category      = $queueState.Category
                IsOffline     = $queueState.IsOffline
                IsUsable      = $queueState.IsUsable
                Association   = $association
                Score         = $score
                PnpIdentifier = $queuePnpIdentifier
            }
        }

        return @(
            $result |
                Sort-Object -Property `
                    @{ Expression = 'Score'; Descending = $true },
                    @{ Expression = 'IsOffline'; Descending = $false },
                    @{ Expression = 'Name'; Descending = $false }
        )
    }

    function Test-ZebraModelCompatibility {
        param(
            [AllowEmptyString()][string]$FirstModel,
            [AllowEmptyString()][string]$SecondModel
        )

        $first = ($FirstModel -replace '[^A-Za-z0-9]', '').ToUpperInvariant()
        $second = ($SecondModel -replace '[^A-Za-z0-9]', '').ToUpperInvariant()

        if ([string]::IsNullOrWhiteSpace($first) -or
            [string]::IsNullOrWhiteSpace($second)) {
            return $true
        }

        if ($first -in @('ZEBRA', 'IMPRESSORAZEBRA') -or
            $second -in @('ZEBRA', 'IMPRESSORAZEBRA')) {
            return $true
        }

        $firstBase = $first -replace '(?i)[TD]$', ''
        $secondBase = $second -replace '(?i)[TD]$', ''
        return $firstBase -eq $secondBase
    }

    function Get-ZebraInventory {
        param([Parameter(Mandatory)][bool]$PnpCmdletsAvailable)

        $presentDevices = @(Get-ZebraPresentDevices -PnpCmdletsAvailable $PnpCmdletsAvailable)
        $deviceIndex = @{}
        foreach ($presentDevice in $presentDevices) {
            if (-not [string]::IsNullOrWhiteSpace($presentDevice.InstanceId)) {
                $deviceIndex[$presentDevice.InstanceId.ToUpperInvariant()] = $presentDevice
            }
        }

        $candidateNodes = @()
        foreach ($presentDevice in $presentDevices) {
            $instanceId = [string]$presentDevice.InstanceId
            $friendlyName = [string]$presentDevice.FriendlyName

            $isPossibleCandidate =
                $instanceId -match '(?i)^USBPRINT\\' -or
                $instanceId -match '(?i)^USB\\VID_0A5F' -or
                $friendlyName -match '(?i)Zebra|GC[\s_-]*420|ZD[\s_-]*[0-9]{3}|GK[\s_-]*420|GX[\s_-]*420|ZT[\s_-]*[0-9]{3}'

            if (-not $isPossibleCandidate) { continue }

            $candidateNode = Get-ZebraNode -Device $presentDevice -PnpCmdletsAvailable $PnpCmdletsAvailable
            $hardwareIds = Get-ZebraText (Get-ZebraMapValue -Map $candidateNode.Props -Keys @('DEVPKEY_Device_HardwareIds'))
            $compatibleIds = Get-ZebraText (Get-ZebraMapValue -Map $candidateNode.Props -Keys @('DEVPKEY_Device_CompatibleIds'))
            $busDescription = Get-ZebraText (Get-ZebraMapValue -Map $candidateNode.Props -Keys @('DEVPKEY_Device_BusReportedDeviceDesc'))
            $deviceDescription = Get-ZebraText (Get-ZebraMapValue -Map $candidateNode.Props -Keys @('DEVPKEY_Device_DeviceDesc'))
            $candidateEvidence = "$instanceId | $friendlyName | $hardwareIds | $compatibleIds | $busDescription | $deviceDescription"

            if ($instanceId -match '(?i)^USB\\VID_0A5F' -or
                $candidateEvidence -match '(?i)Zebra|GC[\s_-]*420|ZD[\s_-]*[0-9]{3}|GK[\s_-]*420|GX[\s_-]*420|ZT[\s_-]*[0-9]{3}') {
                $candidateNodes += $candidateNode
            }
        }

        $printerQueues = @()
        try {
            $printerQueues = @(Get-CimInstance -ClassName Win32_Printer -ErrorAction Stop)
        }
        catch {
            # A conexão USB ainda pode ser mostrada sem o serviço de impressão.
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

        $physicalDeviceCount = $nodeGroups.Count
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
            $queueEvidence = ($printerQueues | ForEach-Object {
                '{0} {1} {2}' -f
                    (Get-ZebraObjectValue $_ 'Name'),
                    (Get-ZebraObjectValue $_ 'DriverName'),
                    (Get-ZebraObjectValue $_ 'PortName')
            }) -join ' | '

            $model = Resolve-ZebraModel -PnpEvidence $pnpEvidence -QueueEvidence $queueEvidence -FriendlyEvidence $friendlyEvidence
            $queueCandidates = Get-ZebraQueueCandidates `
                -PrinterQueues $printerQueues `
                -PrintNode $printNode `
                -Model $model `
                -PhysicalDeviceCount $physicalDeviceCount

            $primaryQueue = if ($queueCandidates.Count -gt 0) { $queueCandidates[0] } else { $null }

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

            $stableKey = $deduplicationKey
            if (-not [string]::IsNullOrWhiteSpace($serialOrInstance)) {
                $stableKey = ('{0}|{1}|{2}' -f $vendorIdentifier, $usbProductIdentifier, $serialOrInstance).ToUpperInvariant()
            }

            $overallState = 'Conectada, mas não configurada no Windows'
            $overallCategory = 'Warning'
            if ($null -ne $primaryQueue) {
                switch ($primaryQueue.Category) {
                    'Printing' {
                        $overallState = 'Imprimindo'
                        $overallCategory = 'Good'
                    }
                    'Busy' {
                        $overallState = 'Preparando para imprimir'
                        $overallCategory = 'Good'
                    }
                    'Paused' {
                        $overallState = 'Pausada no Windows'
                        $overallCategory = 'Warning'
                    }
                    'Offline' {
                        $overallState = 'Conectada, mas aparece offline no Windows'
                        $overallCategory = 'Warning'
                    }
                    'Unknown' {
                        $overallState = 'Conectada; o Windows não informou se está pronta'
                        $overallCategory = 'Warning'
                    }
                    default {
                        $overallState = 'Pronta para uso'
                        $overallCategory = 'Good'
                    }
                }
            }

            $inventoryDevices += [pscustomobject][ordered]@{
                Key                    = $stableKey
                Model                  = $model
                IsConnected            = $true
                CableStatus            = 'CONECTADO'
                OverallState           = $overallState
                OverallCategory        = $overallCategory
                QueueName              = if ($null -ne $primaryQueue) { $primaryQueue.Name } else { '' }
                QueueState             = if ($null -ne $primaryQueue) { $primaryQueue.State } else { 'Não configurada' }
                DriverName             = if ($null -ne $primaryQueue) { $primaryQueue.Driver } else { '' }
                VirtualPort            = if ($null -ne $primaryQueue) { $primaryQueue.Port } else { '' }
                QueueAssociation       = if ($null -ne $primaryQueue) { $primaryQueue.Association } else { '' }
                QueueCandidates        = @($queueCandidates)
                PhysicalPort           = Get-ZebraPhysicalPort -LocationInfo $locationInformation -LocationPath $locationPath
                UsbRoute               = Get-ZebraUsbRoute -LocationPath $locationPath
                VendorId               = $vendorIdentifier
                UsbProductId           = $usbProductIdentifier
                SerialOrInstance       = $serialOrInstance
                UsbInstanceId          = $physicalInstanceId
                UsbPrintInstanceId     = if ($null -ne $printNode) { [string]$printNode.Device.InstanceId } else { '' }
                LocationInfo           = $locationInformation
                LocationPath           = $locationPath
                ContainerId            = Get-ZebraText (Get-ZebraMapValue -Map $identityNode.Props -Keys @('DEVPKEY_Device_ContainerId'))
                BusReportedDescription = Get-ZebraText (Get-ZebraMapValue -Map $identityNode.Props -Keys @('DEVPKEY_Device_BusReportedDeviceDesc'))
                HardwareIds            = Get-ZebraText (Get-ZebraMapValue -Map $identityNode.Props -Keys @('DEVPKEY_Device_HardwareIds'))
                LastSeen               = Get-Date
                DisconnectedAt         = $null
            }
        }

        # A lista acima representa as Zebras físicas atualmente presentes.
        # A tela final é organizada por instalação/fila do Windows para que cada
        # nome, como "promocao" ou "etiqueta", receba seu próprio quadro.
        $physicalInventoryDevices = @($inventoryDevices)
        $installedQueueEntries = @()

        foreach ($printerQueue in $printerQueues) {
            if (-not (Test-ZebraPrinterQueue -Queue $printerQueue)) { continue }

            $queueName = [string](Get-ZebraObjectValue $printerQueue 'Name')
            $driverName = [string](Get-ZebraObjectValue $printerQueue 'DriverName')
            $portName = [string](Get-ZebraObjectValue $printerQueue 'PortName')
            $queuePnpIdentifier = [string](Get-ZebraObjectValue $printerQueue 'PNPDeviceID')
            $queueState = Get-ZebraQueueState -Queue $printerQueue
            $queueModel = Resolve-ZebraModel `
                -PnpEvidence '' `
                -QueueEvidence ("$queueName | $driverName | $queuePnpIdentifier") `
                -FriendlyEvidence ''

            $installedQueueEntries += [pscustomobject][ordered]@{
                Key             = ('QUEUE:{0}|{1}' -f $queueName, $portName).ToUpperInvariant()
                Name            = $queueName
                Driver          = $driverName
                Port            = $portName
                PnpIdentifier   = $queuePnpIdentifier
                Model           = $queueModel
                State           = $queueState.Text
                StateCategory   = $queueState.Category
                IsOffline       = $queueState.IsOffline
                IsUsable        = $queueState.IsUsable
            }
        }

        $displayDevices = @()
        $physicalUsageCount = @{}

        foreach ($queueEntry in $installedQueueEntries) {
            $matchedPhysical = $null
            $connectionConfidence = 'Não detectada'

            # Associação mais segura: o PNPDeviceID da fila coincide com o nó
            # USBPRINT que está fisicamente presente neste momento.
            if (-not [string]::IsNullOrWhiteSpace($queueEntry.PnpIdentifier)) {
                $matchedPhysical = @(
                    $physicalInventoryDevices |
                        Where-Object {
                            (-not [string]::IsNullOrWhiteSpace($_.UsbPrintInstanceId) -and
                             $_.UsbPrintInstanceId -ieq $queueEntry.PnpIdentifier) -or
                            (-not [string]::IsNullOrWhiteSpace($_.UsbInstanceId) -and
                             $_.UsbInstanceId -ieq $queueEntry.PnpIdentifier)
                        }
                ) | Select-Object -First 1

                if ($null -ne $matchedPhysical) {
                    $connectionConfidence = 'Confirmada pelo Windows'
                }
            }

            # Alguns drivers Zebra deixam PNPDeviceID vazio. Quando a fila está
            # disponível, usamos uma Zebra física do mesmo modelo como associação
            # provável. Isso não transforma uma fila sem resposta em conectada.
            if ($null -eq $matchedPhysical -and $queueEntry.IsUsable) {
                $compatiblePhysical = @(
                    $physicalInventoryDevices |
                        Where-Object {
                            Test-ZebraModelCompatibility `
                                -FirstModel $queueEntry.Model `
                                -SecondModel $_.Model
                        } |
                        Sort-Object `
                            @{ Expression = {
                                if ($physicalUsageCount.ContainsKey($_.Key)) {
                                    [int]$physicalUsageCount[$_.Key]
                                }
                                else { 0 }
                            }; Descending = $false },
                            Model,
                            PhysicalPort
                )

                if ($compatiblePhysical.Count -gt 0) {
                    $matchedPhysical = $compatiblePhysical[0]
                    $connectionConfidence = 'Provável pelo modelo e estado'
                }
            }

            if ($null -ne $matchedPhysical) {
                if (-not $physicalUsageCount.ContainsKey($matchedPhysical.Key)) {
                    $physicalUsageCount[$matchedPhysical.Key] = 0
                }
                $physicalUsageCount[$matchedPhysical.Key] = [int]$physicalUsageCount[$matchedPhysical.Key] + 1

                $overallState = 'Pronta para uso'
                $overallCategory = 'Good'
                switch ($queueEntry.StateCategory) {
                    'Printing' {
                        $overallState = 'Imprimindo'
                        $overallCategory = 'Good'
                    }
                    'Busy' {
                        $overallState = 'Preparando para imprimir'
                        $overallCategory = 'Good'
                    }
                    'Paused' {
                        $overallState = 'Pausada no Windows'
                        $overallCategory = 'Warning'
                    }
                    'Offline' {
                        $overallState = 'Cabo detectado, mas a fila está offline no Windows'
                        $overallCategory = 'Warning'
                    }
                    'Unknown' {
                        $overallState = 'Cabo detectado; aguardando resposta da impressora'
                        $overallCategory = 'Warning'
                    }
                }

                $displayModel = $queueEntry.Model
                if ($displayModel -in @('Zebra', 'Impressora Zebra') -and
                    -not [string]::IsNullOrWhiteSpace($matchedPhysical.Model)) {
                    $displayModel = $matchedPhysical.Model
                }

                $displayDevices += [pscustomobject][ordered]@{
                    Key                    = $queueEntry.Key
                    EntryType              = 'Queue'
                    Model                  = $displayModel
                    IsConnected            = $true
                    CableStatus            = 'CONECTADO'
                    OverallState           = $overallState
                    OverallCategory        = $overallCategory
                    QueueName              = $queueEntry.Name
                    QueueState             = $queueEntry.State
                    QueueStateCategory     = $queueEntry.StateCategory
                    DriverName             = $queueEntry.Driver
                    VirtualPort            = $queueEntry.Port
                    QueueAssociation       = $connectionConfidence
                    QueueCandidates        = @()
                    PhysicalPort           = $matchedPhysical.PhysicalPort
                    UsbRoute               = $matchedPhysical.UsbRoute
                    VendorId               = $matchedPhysical.VendorId
                    UsbProductId           = $matchedPhysical.UsbProductId
                    SerialOrInstance       = $matchedPhysical.SerialOrInstance
                    UsbInstanceId          = $matchedPhysical.UsbInstanceId
                    UsbPrintInstanceId     = $matchedPhysical.UsbPrintInstanceId
                    LocationInfo           = $matchedPhysical.LocationInfo
                    LocationPath           = $matchedPhysical.LocationPath
                    ContainerId            = $matchedPhysical.ContainerId
                    BusReportedDescription = $matchedPhysical.BusReportedDescription
                    HardwareIds            = $matchedPhysical.HardwareIds
                    LastSeen               = Get-Date
                    DisconnectedAt         = $null
                }
                continue
            }

            $cableStatus = 'NÃO DETECTADO'
            $overallState = 'Cabo USB desconectado, impressora desligada ou porta incorreta'
            $overallCategory = 'Bad'

            if ($queueEntry.IsUsable) {
                $cableStatus = 'NÃO CONFIRMADO'
                $overallState = 'O Windows mostra disponível, mas não confirmou qual cabo USB está sendo usado'
                $overallCategory = 'Warning'
            }
            elseif ($queueEntry.IsOffline) {
                $overallState = 'Offline — cabo USB não detectado ou impressora desligada'
            }
            elseif ($queueEntry.StateCategory -eq 'Paused') {
                $overallState = 'Fila pausada; o cabo USB não foi detectado'
                $overallCategory = 'Warning'
            }

            $displayDevices += [pscustomobject][ordered]@{
                Key                    = $queueEntry.Key
                EntryType              = 'Queue'
                Model                  = $queueEntry.Model
                IsConnected            = $false
                CableStatus            = $cableStatus
                OverallState           = $overallState
                OverallCategory        = $overallCategory
                QueueName              = $queueEntry.Name
                QueueState             = $queueEntry.State
                QueueStateCategory     = $queueEntry.StateCategory
                DriverName             = $queueEntry.Driver
                VirtualPort            = $queueEntry.Port
                QueueAssociation       = 'Nenhum dispositivo USB correspondente foi encontrado'
                QueueCandidates        = @()
                PhysicalPort           = 'Não detectada'
                UsbRoute               = ''
                VendorId               = ''
                UsbProductId           = ''
                SerialOrInstance       = ''
                UsbInstanceId          = ''
                UsbPrintInstanceId     = $queueEntry.PnpIdentifier
                LocationInfo           = ''
                LocationPath           = ''
                ContainerId            = ''
                BusReportedDescription = ''
                HardwareIds            = ''
                LastSeen               = $null
                DisconnectedAt         = $null
            }
        }

        # Também mostra uma Zebra física que esteja conectada, mas ainda não tenha
        # nenhuma fila/instalação criada no Windows.
        foreach ($physicalDevice in $physicalInventoryDevices) {
            if ($physicalUsageCount.ContainsKey($physicalDevice.Key)) { continue }

            $physicalDevice | Add-Member -NotePropertyName EntryType -NotePropertyValue 'Physical' -Force
            $physicalDevice | Add-Member -NotePropertyName QueueStateCategory -NotePropertyValue 'Unknown' -Force
            $physicalDevice.QueueName = 'Ainda não configurada no Windows'
            $physicalDevice.QueueState = 'Sem instalação'
            $physicalDevice.QueueAssociation = 'Dispositivo físico sem fila'
            $displayDevices += $physicalDevice
        }

        return [pscustomobject][ordered]@{
            ScannedAt = Get-Date
            Devices   = @(
                $displayDevices |
                    Sort-Object `
                        @{ Expression = 'IsConnected'; Descending = $true },
                        QueueName,
                        Model
            )
        }
    }

    function Copy-ZebraDisconnectedDevice {
        param(
            [Parameter(Mandatory)]$Device,
            [Parameter(Mandatory)][datetime]$DisconnectedAt
        )

        return [pscustomobject][ordered]@{
            Key                    = $Device.Key
            EntryType              = $Device.EntryType
            Model                  = $Device.Model
            IsConnected            = $false
            CableStatus            = 'NÃO DETECTADO'
            OverallState           = 'Cabo USB desconectado ou impressora desligada'
            OverallCategory        = 'Bad'
            QueueName              = $Device.QueueName
            QueueState             = $Device.QueueState
            QueueStateCategory     = $Device.QueueStateCategory
            DriverName             = $Device.DriverName
            VirtualPort            = $Device.VirtualPort
            QueueAssociation       = $Device.QueueAssociation
            QueueCandidates        = @()
            PhysicalPort           = $Device.PhysicalPort
            UsbRoute               = $Device.UsbRoute
            VendorId               = $Device.VendorId
            UsbProductId           = $Device.UsbProductId
            SerialOrInstance       = $Device.SerialOrInstance
            UsbInstanceId          = $Device.UsbInstanceId
            UsbPrintInstanceId     = $Device.UsbPrintInstanceId
            LocationInfo           = $Device.LocationInfo
            LocationPath           = $Device.LocationPath
            ContainerId            = $Device.ContainerId
            BusReportedDescription = $Device.BusReportedDescription
            HardwareIds            = $Device.HardwareIds
            LastSeen               = $Device.LastSeen
            DisconnectedAt         = $DisconnectedAt
        }
    }

    function Export-ZebraReport {
        param(
            [Parameter(Mandatory)][object[]]$Devices,
            [Parameter(Mandatory)][string]$Directory
        )

        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $reportPath = Join-Path $Directory "relatorio-zebra-$timestamp.txt"

        $lines = New-Object System.Collections.Generic.List[string]
        [void]$lines.Add('RELATÓRIO DE IMPRESSORAS ZEBRA')
        [void]$lines.Add(('Gerado em: {0:dd/MM/yyyy HH:mm:ss}' -f (Get-Date)))
        [void]$lines.Add('')

        if ($Devices.Count -eq 0) {
            [void]$lines.Add('Nenhuma instalação ou impressora Zebra foi encontrada.')
        }
        else {
            $number = 0
            foreach ($device in $Devices) {
                $number++
                [void]$lines.Add(('Zebra {0}: {1}' -f $number, $device.QueueName))
                [void]$lines.Add(('  Modelo: {0}' -f $device.Model))
                [void]$lines.Add(('  Cabo USB: {0}' -f $device.CableStatus))
                [void]$lines.Add(('  Estado: {0}' -f $device.OverallState))
                [void]$lines.Add(('  Estado informado pelo Windows: {0}' -f $device.QueueState))
                [void]$lines.Add(('  Porta de impressão: {0}' -f $device.VirtualPort))
                [void]$lines.Add(('  Porta no computador: {0}' -f $device.PhysicalPort))
                [void]$lines.Add(('  Número de série: {0}' -f $device.SerialOrInstance))
                [void]$lines.Add(('  Driver: {0}' -f $device.DriverName))
                [void]$lines.Add(('  Associação: {0}' -f $device.QueueAssociation))
                [void]$lines.Add('')
            }
        }

        $lines | Set-Content -LiteralPath $reportPath -Encoding UTF8
        return $reportPath
    }

    function Write-ZebraField {
        param(
            [Parameter(Mandatory)][string]$Label,
            [AllowEmptyString()][string]$Value,
            [ConsoleColor]$Color = [ConsoleColor]::Gray
        )

        if ([string]::IsNullOrWhiteSpace($Value)) { $Value = '-' }
        Write-Host ('{0,-22}: ' -f $Label) -NoNewline -ForegroundColor DarkGray
        Write-Host $Value -ForegroundColor $Color
    }

    function Get-ZebraStateColor {
        param([Parameter(Mandatory)][string]$Category)

        switch ($Category) {
            'Good' { return [ConsoleColor]::Green }
            'Bad' { return [ConsoleColor]::Red }
            default { return [ConsoleColor]::Yellow }
        }
    }

    function Show-ZebraDashboard {
        param(
            [Parameter(Mandatory)][object[]]$Devices,
            [Parameter(Mandatory)][datetime]$ScannedAt,
            [Parameter(Mandatory)][string]$SpinnerCharacter,
            [AllowEmptyString()][string]$LastChangeMessage,
            [Parameter(Mandatory)][bool]$Detailed
        )

        $connectedDevices = @($Devices | Where-Object { $_.CableStatus -eq 'CONECTADO' })
        $unconfirmedDevices = @($Devices | Where-Object { $_.CableStatus -eq 'NÃO CONFIRMADO' })
        $notDetectedDevices = @($Devices | Where-Object { $_.CableStatus -eq 'NÃO DETECTADO' })

        Clear-Host
        Write-Host '==================================================================' -ForegroundColor Cyan
        Write-Host '              ZEBRA USB - STATUS DAS IMPRESSORAS' -ForegroundColor Cyan
        Write-Host '==================================================================' -ForegroundColor Cyan
        Write-Host ('Atualização automática {0}  {1:dd/MM/yyyy HH:mm:ss}' -f $SpinnerCharacter, $ScannedAt) -ForegroundColor White
        Write-Host ('Instalações: {0}   Conectadas: {1}   Sem cabo detectado: {2}' -f $Devices.Count, $connectedDevices.Count, $notDetectedDevices.Count) -ForegroundColor DarkGray

        if ($unconfirmedDevices.Count -gt 0) {
            Write-Host ('Conexão não confirmada pelo Windows: {0}' -f $unconfirmedDevices.Count) -ForegroundColor Yellow
        }

        if (-not [string]::IsNullOrWhiteSpace($LastChangeMessage)) {
            Write-Host ('Última alteração: {0}' -f $LastChangeMessage) -ForegroundColor Yellow
        }
        Write-Host ''

        if ($Devices.Count -eq 0) {
            Write-Host 'Nenhuma instalação ou impressora Zebra foi encontrada.' -ForegroundColor Yellow
            Write-Host 'Ligue a impressora, conecte o cabo USB ou instale o driver Zebra.' -ForegroundColor White
            Write-Host 'A tela será atualizada automaticamente.' -ForegroundColor DarkGray
            Write-Host ''
        }
        else {
            $displayNumber = 0
            foreach ($device in ($Devices | Sort-Object @{ Expression = 'IsConnected'; Descending = $true }, QueueName, Model)) {
                $displayNumber++
                $titleName = $device.QueueName
                if ([string]::IsNullOrWhiteSpace($titleName)) { $titleName = $device.Model }

                Write-Host ('---------------------- ZEBRA {0} - {1} ----------------------' -f $displayNumber, $titleName) -ForegroundColor DarkCyan
                Write-ZebraField -Label 'Nome no Windows' -Value $device.QueueName -Color White
                Write-ZebraField -Label 'Modelo' -Value $device.Model -Color Cyan

                $cableColor = [ConsoleColor]::Yellow
                if ($device.CableStatus -eq 'CONECTADO') { $cableColor = [ConsoleColor]::Green }
                elseif ($device.CableStatus -eq 'NÃO DETECTADO') { $cableColor = [ConsoleColor]::Red }

                Write-ZebraField -Label 'Cabo USB' -Value $device.CableStatus -Color $cableColor
                Write-ZebraField -Label 'Estado' -Value $device.OverallState -Color (Get-ZebraStateColor -Category $device.OverallCategory)
                Write-ZebraField -Label 'Status no Windows' -Value $device.QueueState
                Write-ZebraField -Label 'Porta de impressão' -Value $device.VirtualPort -Color Cyan
                Write-ZebraField -Label 'Porta no computador' -Value $device.PhysicalPort -Color Cyan
                Write-ZebraField -Label 'Número de série' -Value $device.SerialOrInstance

                if ($null -ne $device.DisconnectedAt -and -not $device.IsConnected) {
                    Write-ZebraField -Label 'Sem conexão desde' -Value ($device.DisconnectedAt.ToString('HH:mm:ss')) -Color Red
                }

                if ($Detailed) {
                    Write-Host ''
                    Write-Host 'Mais informações:' -ForegroundColor DarkGray
                    Write-ZebraField -Label 'Driver' -Value $device.DriverName
                    Write-ZebraField -Label 'Como foi identificado' -Value $device.QueueAssociation
                    Write-ZebraField -Label 'Rota USB' -Value $device.UsbRoute
                    Write-ZebraField -Label 'Identificador USB' -Value (($device.VendorId + ' / ' + $device.UsbProductId).Trim([char[]]' /'))
                    Write-ZebraField -Label 'USB InstanceId' -Value $device.UsbInstanceId
                    Write-ZebraField -Label 'USBPRINT InstanceId' -Value $device.UsbPrintInstanceId
                }
                Write-Host ''
            }
        }

        Write-Host '[D] Mais informações   [E] Salvar relatório   [R] Atualizar   [Q] Sair' -ForegroundColor DarkGray
    }

    function Get-ZebraPressedKey {
        try {
            if ([Console]::KeyAvailable) {
                return [Console]::ReadKey($true).Key
            }
        }
        catch {
            # Alguns terminais não oferecem leitura de tecla sem bloquear.
        }
        return $null
    }

    function Show-ZebraSimpleError {
        param([Parameter(Mandatory)]$ErrorRecord)

        Clear-Host
        Write-Host 'Não foi possível verificar as impressoras Zebra.' -ForegroundColor Red
        Write-Host ''
        Write-Host ('Motivo: {0}' -f $ErrorRecord.Exception.Message) -ForegroundColor Yellow
        Write-Host ''
        Write-Host 'Uma nova tentativa será feita automaticamente.' -ForegroundColor White
        Write-Host 'Pressione CTRL+C para encerrar.' -ForegroundColor DarkGray
    }

    try {
        if ($env:OS -ne 'Windows_NT') {
            throw 'Este gerenciador funciona somente no Windows 10 ou Windows 11.'
        }

        if ($PSVersionTable.PSVersion -lt [version]'5.1') {
            throw 'É necessário usar o Windows PowerShell 5.1 ou uma versão mais recente.'
        }

        try {
            $Host.UI.RawUI.WindowTitle = 'Zebra USB - Status da impressora'
        }
        catch {}

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

        $knownDevices = @{}
        $spinnerCharacters = @('|', '/', '-', '\')
        $spinnerPosition = 0
        $stopRequested = $false
        $lastChangeMessage = ''
        $lastChangeExpiration = [datetime]::MinValue

        while (-not $stopRequested) {
            try {
                $inventory = Get-ZebraInventory -PnpCmdletsAvailable $pnpCmdletsAvailable
            }
            catch {
                Show-ZebraSimpleError -ErrorRecord $_
                Start-Sleep -Milliseconds $refreshMilliseconds
                continue
            }

            $currentDevices = @{}
            foreach ($device in $inventory.Devices) {
                $currentDevices[$device.Key] = $device
                $wasKnown = $knownDevices.ContainsKey($device.Key)

                if ($wasKnown) {
                    $previousDevice = $knownDevices[$device.Key]

                    if ($previousDevice.IsConnected -and -not $device.IsConnected) {
                        $disconnectedTime = Get-Date
                        $device.DisconnectedAt = $disconnectedTime
                        $lastChangeMessage = ('{0} ficou sem cabo às {1:HH:mm:ss}' -f $device.QueueName, $disconnectedTime)
                        $lastChangeExpiration = (Get-Date).AddSeconds(8)
                        try {
                            [Console]::Beep(700, 180)
                            [Console]::Beep(500, 220)
                        }
                        catch {}
                    }
                    elseif (-not $previousDevice.IsConnected -and $device.IsConnected) {
                        $device.DisconnectedAt = $null
                        $lastChangeMessage = ('{0} conectada às {1:HH:mm:ss}' -f $device.QueueName, (Get-Date))
                        $lastChangeExpiration = (Get-Date).AddSeconds(8)
                        try { [Console]::Beep(1000, 220) } catch {}
                    }
                    elseif (-not $device.IsConnected -and $null -ne $previousDevice.DisconnectedAt) {
                        $device.DisconnectedAt = $previousDevice.DisconnectedAt
                    }
                }
                elseif ($device.IsConnected) {
                    $lastChangeMessage = ('{0} conectada às {1:HH:mm:ss}' -f $device.QueueName, (Get-Date))
                    $lastChangeExpiration = (Get-Date).AddSeconds(8)
                    try { [Console]::Beep(1000, 220) } catch {}
                }

                $knownDevices[$device.Key] = $device
            }

            foreach ($knownKey in @($knownDevices.Keys)) {
                if ($currentDevices.ContainsKey($knownKey)) { continue }

                $knownDevice = $knownDevices[$knownKey]
                if ($knownDevice.EntryType -eq 'Physical' -and $knownDevice.IsConnected) {
                    $disconnectedTime = Get-Date
                    $knownDevices[$knownKey] = Copy-ZebraDisconnectedDevice -Device $knownDevice -DisconnectedAt $disconnectedTime
                    $lastChangeMessage = ('{0} desconectada às {1:HH:mm:ss}' -f $knownDevice.Model, $disconnectedTime)
                    $lastChangeExpiration = (Get-Date).AddSeconds(8)
                }
                else {
                    $knownDevices.Remove($knownKey)
                }
            }

            if ((Get-Date) -gt $lastChangeExpiration) {
                $lastChangeMessage = ''
            }

            $dashboardDevices = @($knownDevices.Values)
            Show-ZebraDashboard `
                -Devices $dashboardDevices `
                -ScannedAt $inventory.ScannedAt `
                -SpinnerCharacter $spinnerCharacters[$spinnerPosition % $spinnerCharacters.Count] `
                -LastChangeMessage $lastChangeMessage `
                -Detailed $showAdvancedInformation

            $spinnerPosition++
            $refreshDeadline = (Get-Date).AddMilliseconds($refreshMilliseconds)

            do {
                $pressedKey = Get-ZebraPressedKey
                if ($null -ne $pressedKey) {
                    switch ($pressedKey.ToString()) {
                        'D' {
                            $showAdvancedInformation = -not $showAdvancedInformation
                            $refreshDeadline = Get-Date
                        }
                        'E' {
                            $reportPath = Export-ZebraReport -Devices $dashboardDevices -Directory $reportDirectory
                            Write-Host ''
                            Write-Host ('Relatório salvo em: {0}' -f $reportPath) -ForegroundColor Green
                            Start-Sleep -Milliseconds 1600
                            $refreshDeadline = Get-Date
                        }
                        'R' {
                            $refreshDeadline = Get-Date
                        }
                        'Q' {
                            $stopRequested = $true
                            $refreshDeadline = Get-Date
                        }
                    }
                }

                if (-not $stopRequested -and (Get-Date) -lt $refreshDeadline) {
                    Start-Sleep -Milliseconds 80
                }
            }
            while (-not $stopRequested -and (Get-Date) -lt $refreshDeadline)
        }
    }
    catch {
        Show-ZebraSimpleError -ErrorRecord $_
    }

    Write-Host ''
    Write-Host 'Monitoramento encerrado.' -ForegroundColor DarkGray
}
