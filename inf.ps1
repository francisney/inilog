$outputFile = "C:\ti\info_pc.txt"
if (!(Test-Path -Path "C:\ti")) {
    New-Item -ItemType Directory -Path "C:\ti"
}

function Get-RAMType {
    $memoryType = Get-CimInstance -ClassName CIM_PhysicalMemory | Select-Object -ExpandProperty MemoryType
    switch ($memoryType) {
        20 { return "DDR" }
        21 { return "DDR2" }
        24 { return "DDR3" }
        26 { return "DDR4" }
        default { return "Tipo desconhecido" }
    }
}

$memoryInfo = Get-CimInstance -ClassName CIM_PhysicalMemory | ForEach-Object {
    @{
        "Capacidade (GB)" = [math]::round($_.Capacity / 1GB, 2)
        "Velocidade (MHz)" = $_.Speed
        "Tipo" = Get-RAMType
    }
}

$cpuInfo = Get-CimInstance -ClassName CIM_Processor | Select-Object -Property Name, Manufacturer, MaxClockSpeed, NumberOfCores, NumberOfLogicalProcessors
$motherboardInfo = Get-CimInstance -ClassName CIM_BaseBoard | Select-Object -Property Manufacturer, Product

$diskInfo = Get-CimInstance -ClassName CIM_DiskDrive | ForEach-Object {
    @{
        "Modelo" = $_.Model
        "Tipo" = if ($_.MediaType -eq "Fixed hard disk media") { "HDD" } elseif ($_.MediaType -eq "Removable Media") { "SSD" } else { "Desconhecido" }
        "Espaço Total (GB)" = [math]::round($_.Size / 1GB, 2)
    }
}

$storageInfo = Get-CimInstance -ClassName CIM_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    @{
        "Unidade" = $_.DeviceID
        "Espaço Total (GB)" = [math]::round($_.Size / 1GB, 2)
        "Espaço Livre (GB)" = [math]::round($_.FreeSpace / 1GB, 2)
    }
}

$report = @(
    "Informações do Computador - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "`n== Memória (RAM) ==",
    ($memoryInfo | Out-String),
    "`n== Processador ==",
    ($cpuInfo | Out-String),
    "`n== Placa-Mãe ==",
    ($motherboardInfo | Out-String),
    "`n== Armazenamento (Disco) ==",
    ($diskInfo | Out-String),
    "`n== Espaço do Disco ==",
    ($storageInfo | Out-String)
)

$report | Out-File -FilePath $outputFile -Encoding UTF8
Write-Output "Relatório salvo em $outputFile"
