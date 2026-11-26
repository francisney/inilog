$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
& $csc /nologo /codepage:65001 /target:winexe /optimize+ /platform:anycpu "/win32manifest:$root\client\app.manifest" "/out:$dist\upload.exe" /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.Web.Extensions.dll "$root\client\Program.cs" "$root\client\UploadClient.cs"
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar upload.exe' }
& $csc /nologo /codepage:65001 /target:exe "/out:$dist\UploadTests.exe" "/r:$dist\upload.exe" /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll "$root\tests\UploadTests.cs"
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar verificacoes' }
$server = Start-Process python -ArgumentList @("$root\tests\mock_server.py",'--ready',"$dist\mock.json") -PassThru -WindowStyle Hidden
try {
    for ($i=0; $i -lt 50; $i++) { if (Test-Path "$dist\mock.json") { break }; Start-Sleep -Milliseconds 100 }
    $endpoint = (Get-Content "$dist\mock.json" -Raw | ConvertFrom-Json).endpoint
    & "$dist\UploadTests.exe" $endpoint "$dist\window.png" "$dist\validation.json"
    if ($LASTEXITCODE -ne 0) { throw 'Falha nas verificacoes' }
    $item = Get-Item "$dist\upload.exe"
    $hash = Get-FileHash "$dist\upload.exe" -Algorithm SHA256
    @{file='upload.exe';bytes=$item.Length;sha256=$hash.Hash;platform='AnyCPU';target='Windows 10 / Windows 11';framework='NET Framework 4.x'} | ConvertTo-Json | Set-Content "$dist\build-info.json" -Encoding UTF8
} finally { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
