# Define o caminho do arquivo onde as informações serão salvas
$outputFile = "C:\ti\info_pc.txt"

# Cria o diretório "C:\ti" caso ele não exista
if (!(Test-Path -Path "C:\ti")) {
    New-Item -ItemType Directory -Path "C:\ti"
}

# Função para verificar o tipo de memória RAM (DDR3 ou DDR4)
function Get-RAMType {
    $memoryType = Get-WmiObject -Class Win32_PhysicalMemory | Select-Object -ExpandProperty MemoryType
    switch ($memoryType) {
        20 { return "DDR" }
        21 { return "DDR2" }
        24 { return "DDR3" }
        26 { return "DDR4" }
        default { return "Tipo desconhecido" }
    }
}

# Coleta informações de memória
$memoryInfo = Get-WmiObject -Class Win32_PhysicalMemory | ForEach-Object {
    @{
        "Capacidade (GB)" = [math]::round($_.Capacity / 1GB, 2)
        "Velocidade (MHz)" = $_.Speed
        "Tipo" = Get-RAMType
    }
}

# Coleta informações do processador
$cpuInfo = Get-WmiObject -Class Win32_Processor | Select-Object -Property Name, Manufacturer, MaxClockSpeed, NumberOfCores, NumberOfLogicalProcessors

# Coleta informações da placa-mãe
$motherboardInfo = Get-WmiObject -Class Win32_BaseBoard | Select-Object -Property Manufacturer, Product

# Coleta informações do armazenamento e verifica se é SSD ou HDD
$diskInfo = Get-WmiObject -Class Win32_DiskDrive | ForEach-Object {
    @{
        "Modelo" = $_.Model
        "Tipo" = if ($_.MediaType -eq "Fixed hard disk media") { "HDD" } elseif ($_.MediaType -eq "Removable Media") { "SSD" } else { "Desconhecido" }
        "Espaço Total (GB)" = [math]::round($_.Size / 1GB, 2)
    }
}

# Coleta espaço total do disco
$storageInfo = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    @{
        "Unidade" = $_.DeviceID
        "Espaço Total (GB)" = [math]::round($_.Size / 1GB, 2)
        "Espaço Livre (GB)" = [math]::round($_.FreeSpace / 1GB, 2)
    }
}

# Salva as informações no arquivo
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

# Grava o relatório no arquivo
$report | Out-File -FilePath $outputFile -Encoding UTF8

Write-Output "Relatório salvo em $outputFile"
