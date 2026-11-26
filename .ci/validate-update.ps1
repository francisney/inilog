param(
    [Parameter(Mandatory = $true)][string]$Candidate,
    [Parameter(Mandatory = $true)][string]$Original,
    [Parameter(Mandatory = $true)][string]$CandidateRawUri,
    [string]$PreviousRawUri
)
$ErrorActionPreference = 'Stop'
$script:Checks = New-Object 'Collections.Generic.List[string]'
function Assert-InilogTest {
    param([bool]$Condition, [string]$Description)
    if (-not $Condition) { throw "VALIDATION FAILED: $Description" }
    [void]$script:Checks.Add($Description)
}

$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($Candidate, [ref]$tokens, [ref]$parseErrors)
Assert-InilogTest (@($parseErrors).Count -eq 0) ('Windows PowerShell syntax: ' + (@($parseErrors.Message) -join '; '))
Assert-InilogTest ($PSVersionTable.PSVersion.Major -eq 5) 'Validation runtime is Windows PowerShell 5.1'
foreach ($definition in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    . ([ScriptBlock]::Create($definition.Extent.Text))
}
$originalTokens = $null
$originalErrors = $null
$originalAst = [Management.Automation.Language.Parser]::ParseFile($Original, [ref]$originalTokens, [ref]$originalErrors)
$originalSwitch = $originalAst.FindAll({
    param($node)
    $node -is [Management.Automation.Language.SwitchStatementAst] -and $node.Condition.Extent.Text -eq '$choice'
}, $true) | Select-Object -First 1
Assert-InilogTest ($null -ne $originalSwitch) 'Original action table located'
$originalUris = @{}
foreach ($clause in $originalSwitch.Clauses) {
    $originalUris[[int]$clause.Item1.Value] = @($clause.Item2.FindAll({
        param($node)
        $node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.Value -match '^https?://'
    }, $true) | ForEach-Object { $_.Value })
}

$actions = @(Get-InilogActions)
$removed = @(2, 4, 11, 12, 21, 23, 26, 28, 32, 33)
Assert-InilogTest ($actions.Count -eq 24) '24 callable actions remain'
Assert-InilogTest (@($actions.Id | Sort-Object -Unique).Count -eq $actions.Count) 'Action IDs are unique'
foreach ($number in $removed) {
    Assert-InilogTest ($number -notin $actions.Id) ("Removed action is not callable: " + $number)
}
foreach ($action in $actions) {
    Assert-InilogTest (($action.Uris -join '|') -ceq ($originalUris[$action.Id] -join '|')) ("Original URLs preserved: " + $action.Id)
}
$visible = @(Get-InilogVisibleActions $actions)
Assert-InilogTest ($visible.Count -eq 22) '22 actions are visible'
Assert-InilogTest ((@($actions | Where-Object { -not $_.Visible } | Sort-Object Id).Id -join ',') -eq '9,14') 'Only 9 and 14 are hidden'
Assert-InilogTest (34 -in $visible.Id) 'Audit action 34 is visible'
Assert-InilogTest (@(Get-InilogVisibleActions $actions 'Ativação').Count -eq 0) 'Hidden action 9 is not searchable'
Assert-InilogTest (@(Get-InilogVisibleActions $actions 'Reservado').Count -eq 0) 'Reserved category is not searchable'
Assert-InilogTest (3 -in @(Get-InilogVisibleActions $actions 'impressao').Id) 'Search accepts text without accents'
Assert-InilogTest ((@($actions | Where-Object Run).Id -join ',') -eq '34') 'Only the audit download starts automatically'

function Clear-Host {}
Initialize-InilogState -DownloadDirectory 'C:\ti'
function Get-InilogConsoleWidth { return 110 }
$wide = (Show-InilogMenu 6>&1 | ForEach-Object { $_.ToString() }) -join ''
Assert-InilogTest ($wide.Contains('Auditoria INILOG')) 'Wide menu renders audit action'
Assert-InilogTest (-not $wide.Contains('Ativação')) 'Wide menu does not expose action 9'
Assert-InilogTest (-not $wide.Contains('Serviço específico')) 'Wide menu does not expose action 14'
function Get-InilogConsoleWidth { return 70 }
$narrow = (Show-InilogMenu 6>&1 | ForEach-Object { $_.ToString() }) -join ''
Assert-InilogTest ($narrow.Contains('HWiNFO64')) 'Narrow menu renders remaining tools'
Assert-InilogTest ($narrow.Contains('0 Sair')) 'Narrow menu renders navigation'

$savedFunctions = @{}
foreach ($name in @('Save-InilogFile','Start-InilogProcess','Show-InilogLogin','Show-InilogMenu','Update-InilogNetworkInfo','Invoke-InilogAction','Wait-InilogMenu','Invoke-InilogRemoteScript')) {
    $savedFunctions[$name] = (Get-Item ('Function:' + $name)).ScriptBlock
}
function Write-InilogStatus { param($Message, $Type) }
$script:ProgressValues = New-Object 'Collections.Generic.List[int]'
function Write-Progress {
    param($Id, $Activity, $Status, $PercentComplete, [switch]$Completed)
    if (-not $Completed) { [void]$script:ProgressValues.Add([int]$PercentComplete) }
}

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
public sealed class InilogTestResponse {
    public byte[] Body;
    public string Type;
    public int Code;
    public long Length;
}
public sealed class InilogTestServer : IDisposable {
    private readonly TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
    private readonly Dictionary<string, InilogTestResponse> responses = new Dictionary<string, InilogTestResponse>();
    private Thread thread;
    private volatile bool stopped;
    public int Port { get { return ((IPEndPoint)listener.LocalEndpoint).Port; } }
    public void Add(string path, byte[] body, string type, int code, long length) {
        responses[path] = new InilogTestResponse { Body=body, Type=type, Code=code, Length=length };
    }
    public void Start() {
        listener.Start();
        thread = new Thread(Serve); thread.IsBackground = true; thread.Start();
    }
    private void Serve() {
        while (!stopped) {
            TcpClient client = null;
            try {
                client = listener.AcceptTcpClient();
                using (client) using (NetworkStream stream = client.GetStream()) {
                    stream.ReadTimeout = 5000; stream.WriteTimeout = 5000;
                    StringBuilder request = new StringBuilder();
                    while (request.Length < 65536) {
                        int value = stream.ReadByte();
                        if (value < 0) break;
                        request.Append((char)value);
                        if (request.ToString().Contains("\r\n\r\n")) break;
                    }
                    string[] parts = request.ToString().Split(' ');
                    string path = parts.Length > 1 ? parts[1].Split('?')[0] : "/";
                    InilogTestResponse response;
                    if (!responses.TryGetValue(path, out response)) {
                        byte[] missing = Encoding.UTF8.GetBytes("Not found");
                        response = new InilogTestResponse { Body=missing, Type="text/plain", Code=404, Length=missing.Length };
                    }
                    string header = "HTTP/1.0 " + response.Code + (response.Code==200 ? " OK" : " Not Found")
                        + "\r\nContent-Type: " + response.Type + "\r\nConnection: close\r\n";
                    if (response.Length >= 0) header += "Content-Length: " + response.Length + "\r\n";
                    byte[] bytes = Encoding.ASCII.GetBytes(header + "\r\n");
                    stream.Write(bytes, 0, bytes.Length);
                    stream.Write(response.Body, 0, response.Body.Length);
                    stream.Flush();
                }
            } catch (IOException) { if (client != null) client.Close(); }
              catch (SocketException) { if (stopped) return; }
              catch (ObjectDisposedException) { return; }
        }
    }
    public void Dispose() {
        stopped = true; listener.Stop();
        if (thread != null) thread.Join(2000);
    }
}
'@

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('inilog-validation-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot)
$server = New-Object InilogTestServer
try {
    $exe = [Text.Encoding]::ASCII.GetBytes('MZ' + ('demo' * 20000))
    $zip = [Text.Encoding]::ASCII.GetBytes('PK' + ('data' * 20000))
    $page = [Text.Encoding]::UTF8.GetBytes('<!doctype html><html>error</html>')
    $commentPage = [Text.Encoding]::UTF8.GetBytes("`r`n<!-- server error -->`r`n<HTML><BODY>unavailable</BODY></HTML>")
    $wrong = [Text.Encoding]::ASCII.GetBytes('not an executable')
    $exitZero = [Text.Encoding]::UTF8.GetBytes("Write-Output 'CHILD_OK'; exit 0")
    $exitSeven = [Text.Encoding]::UTF8.GetBytes('exit 7')
    $invalid = [Text.Encoding]::UTF8.GetBytes('function Broken {')
    $unicodeResult = Join-Path $testRoot 'unicode-result.txt'
    $escapedResult = $unicodeResult.Replace("'", "''")
    $unicodeScript = [Text.Encoding]::UTF8.GetBytes("[IO.File]::WriteAllText('$escapedResult', 'Olá, mundo!', [Text.Encoding]::UTF8); exit 0")
    $server.Add('/ok.exe', $exe, 'application/octet-stream', 200, $exe.Length)
    $server.Add('/ok.zip', $zip, 'application/zip', 200, $zip.Length)
    $server.Add('/unknown.zip', $zip, 'application/zip', 200, -1)
    $server.Add('/empty.exe', [byte[]]@(), 'application/octet-stream', 200, 0)
    $server.Add('/html.exe', $page, 'text/html', 200, $page.Length)
    $server.Add('/wrong.exe', $wrong, 'application/octet-stream', 200, $wrong.Length)
    $server.Add('/partial.exe', $exe[0..15], 'application/octet-stream', 200, 9999)
    $server.Add('/exit0.ps1', $exitZero, 'text/plain; charset=utf-8', 200, $exitZero.Length)
    $server.Add('/exit7.ps1', $exitSeven, 'text/plain; charset=utf-8', 200, $exitSeven.Length)
    $server.Add('/invalid.ps1', $invalid, 'text/plain; charset=utf-8', 200, $invalid.Length)
    $server.Add('/mislabelled.ps1', $exitZero, 'text/html; charset=utf-8', 200, $exitZero.Length)
    $server.Add('/html.ps1', $page, 'text/html', 200, $page.Length)
    $server.Add('/html-plain.ps1', $page, 'text/plain', 200, $page.Length)
    $server.Add('/html-comment.ps1', $commentPage, 'text/html', 200, $commentPage.Length)
    $server.Add('/invalid-html.ps1', $invalid, 'text/html', 200, $invalid.Length)
    $server.Add('/unicode.ps1', $unicodeScript, 'text/plain; charset=utf-8', 200, $unicodeScript.Length)
    $server.Start()
    $baseUrl = 'http://127.0.0.1:' + $server.Port
    $exePath = Join-Path $testRoot 'downloads com espaço\demo.exe'
    $result = Save-InilogFile -Uri ($baseUrl + '/ok.exe') -Destination $exePath -Description 'test'
    Assert-InilogTest ($result.Success -and (Get-Item $exePath).Length -eq $exe.Length) 'Download with size creates directory and correct file'
    Assert-InilogTest (@($script:ProgressValues | Where-Object { $_ -ge 0 }).Count -gt 0) 'Known-size download reports percentage'
    $script:ProgressValues.Clear()
    $result = Save-InilogFile -Uri ($baseUrl + '/unknown.zip') -Destination (Join-Path $testRoot 'unknown.zip') -Description 'test'
    Assert-InilogTest $result.Success 'Download without Content-Length completes'
    Assert-InilogTest ($script:ProgressValues.Contains(-1)) 'Unknown-size download uses indeterminate progress'
    $oldHash = (Get-FileHash $exePath).Hash
    foreach ($route in @('/empty.exe','/html.exe','/wrong.exe','/partial.exe','/missing.exe')) {
        $result = Save-InilogFile -Uri ($baseUrl + $route) -Destination $exePath -Description 'test'
        Assert-InilogTest (-not $result.Success) ('Failed/invalid response rejected: ' + $route)
        Assert-InilogTest ((Get-FileHash $exePath).Hash -eq $oldHash) ('Previous download preserved: ' + $route)
    }
    Assert-InilogTest (@(Get-ChildItem $testRoot -Filter '.inilog-*.download' -Recurse -Force).Count -eq 0) 'Partial download files are cleaned'
    Initialize-InilogState -DownloadDirectory $testRoot
    $childResult = Invoke-InilogRemoteScript -Uri ($baseUrl + '/exit0.ps1') -Description 'child' -FileName 'scripts\exit0.ps1'
    Assert-InilogTest $childResult.Success 'Child exit 0 returns to parent'
    $childResult = Invoke-InilogRemoteScript -Uri ($baseUrl + '/exit7.ps1') -Description 'child' -FileName 'scripts\exit7.ps1'
    Assert-InilogTest (-not $childResult.Success -and $childResult.Message.Contains('7')) 'Child exit 7 is reported without closing menu'
    $childResult = Invoke-InilogRemoteScript -Uri ($baseUrl + '/invalid.ps1') -Description 'child' -FileName 'scripts\invalid.ps1'
    Assert-InilogTest (-not $childResult.Success) 'Downloaded script is parsed before execution'
    $childResult = Invoke-InilogRemoteScript -Uri ($baseUrl + '/unicode.ps1') -Description 'child' -FileName "pasta com 'aspas'\unicode.ps1"
    Assert-InilogTest ($childResult.Success -and [IO.File]::ReadAllText($unicodeResult) -ceq 'Olá, mundo!') 'Child preserves UTF-8 and paths with spaces/apostrophes'

    # Regressao da opcao 9: cabecalho HTML com corpo PowerShell valido.
    # Somente este payload local inofensivo e executado.
    $childResult = Invoke-InilogRemoteScript -Uri ($baseUrl + '/mislabelled.ps1') -Description 'mislabelled test' -FileName 'scripts\mislabelled.ps1'
    Assert-InilogTest $childResult.Success 'Valid PowerShell labelled text/html downloads and runs normally'
    $cachedScript = Join-Path $testRoot 'scripts\mislabelled.ps1'
    $cachedHash = (Get-FileHash $cachedScript).Hash
    foreach ($route in @('/html.ps1','/html-plain.ps1','/html-comment.ps1','/invalid-html.ps1','/invalid.ps1')) {
        $result = Save-InilogFile -Uri ($baseUrl + $route) -Destination $cachedScript -Description 'test'
        Assert-InilogTest (-not $result.Success) ('HTML or invalid PowerShell rejected by content: ' + $route)
        Assert-InilogTest ((Get-FileHash $cachedScript).Hash -eq $cachedHash) ('Cached PowerShell preserved: ' + $route)
    }
    Assert-InilogTest (@(Get-ChildItem $testRoot -Filter '.inilog-*.download' -Recurse -Force).Count -eq 0) 'Rejected script downloads are cleaned'

    # Baixa o endereco real da opcao 9 e analisa a sintaxe, sem executa-lo.
    $reservedAction = $actions | Where-Object Id -eq 9
    $reservedPath = Join-Path $testRoot 'read-only\reservado-09.ps1'
    $reservedDownload = Save-InilogFile -Uri $reservedAction.Uris[0] -Destination $reservedPath -Description 'read-only option 9'
    Assert-InilogTest $reservedDownload.Success ('Actual option 9 URL downloads successfully: ' + $reservedDownload.Message)
    $reservedTokens = $null
    $reservedErrors = $null
    $reservedAst = [Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($reservedPath), [ref]$reservedTokens, [ref]$reservedErrors)
    Assert-InilogTest (@($reservedErrors).Count -eq 0 -and @($reservedAst.EndBlock.Statements).Count -gt 0) 'Actual option 9 response is syntactically valid PowerShell'
    Write-Output ('REMOTE_DOWNLOAD_DIAG ' + (@{id=9;downloaded=$true;script_valid=$true;executed=$false;bytes=(Get-Item $reservedPath).Length} | ConvertTo-Json -Compress))

    $script:Launches = New-Object 'Collections.Generic.List[object]'
    function Start-InilogProcess {
        param($Path, $Description, $Arguments, [switch]$AsAdministrator)
        [void]$script:Launches.Add([PSCustomObject]@{Path=$Path;Admin=[bool]$AsAdministrator;Arguments=$Arguments})
        New-InilogResult $true 'mock' $Path
    }
    function Save-InilogFile { param($Uri,$Destination,$Description) New-InilogResult $false 'mock failed' }
    [void](Invoke-InilogAction ($actions | Where-Object Id -eq 3))
    [void](Invoke-InilogAction ($actions | Where-Object Id -eq 34))
    Assert-InilogTest ($script:Launches.Count -eq 0) 'Print queue and audit do not launch a stale file after download failure'
    function Save-InilogFile { param($Uri,$Destination,$Description) New-InilogResult $true 'mock ok' $Destination }
    [void](Invoke-InilogAction ($actions | Where-Object Id -eq 3))
    [void](Invoke-InilogAction ($actions | Where-Object Id -eq 34))
    Assert-InilogTest ($script:Launches.Count -eq 2) 'Successful print queue and audit launch once each'
    Assert-InilogTest ($script:Launches[0].Path -eq 'cmd.exe' -and $script:Launches[0].Admin) 'Print queue asks Windows for elevation'
    Assert-InilogTest (-not $script:Launches[1].Admin) 'Audit preserves its normal launch mode'
    Set-Item Function:Invoke-InilogAction -Value $savedFunctions['Invoke-InilogAction']

    function Read-Host { param($Prompt,[switch]$AsSecureString) ConvertTo-SecureString -String $script:LoginText -AsPlainText -Force }
    function Show-InilogHeader {}
    function Start-Sleep { param($Milliseconds,$Seconds) }
    function Invoke-InilogRemoteScript { param($Uri,$Description,$FileName) 'unexpected pipeline output'; New-InilogResult $true 'mock' }
    $script:LoginText = 'not-the-expected-value'
    $login = Show-InilogLogin
    Assert-InilogTest ($login -is [bool] -and -not $login) 'Failed login stays false even if fallback tool emits output'
    $script:LoginText = (Get-Date).ToString('ddMMyyyy')
    $login = Show-InilogLogin
    Assert-InilogTest ($login -is [bool] -and $login) 'Existing login rule remains functional'

    function Show-InilogLogin { return $true }
    function Show-InilogMenu {}
    function Update-InilogNetworkInfo {}
    function Wait-InilogMenu {}
    $script:Choices = New-Object 'Collections.Generic.Queue[string]'
    foreach ($choice in @('09','14','02','34','0')) { $script:Choices.Enqueue($choice) }
    $script:CalledIds = New-Object 'Collections.Generic.List[int]'
    function Read-Host { param($Prompt) return $script:Choices.Dequeue() }
    function Invoke-InilogAction {
        param($Action)
        [void]$script:CalledIds.Add($Action.Id)
        New-InilogResult $true 'mock'
    }
    Start-InilogConsole -DownloadDirectory $testRoot
    Assert-InilogTest (($script:CalledIds -join ',') -eq '9,14,34') 'Menu accepts hidden IDs, rejects removed ID, and returns normally'

    $candidateBytes = [IO.File]::ReadAllBytes($Candidate)
    Assert-InilogTest (@($candidateBytes | Where-Object { $_ -gt 127 }).Count -eq 0) 'Published source is ASCII without a BOM'
    if ($PreviousRawUri) {
        $previousText = Microsoft.PowerShell.Utility\Invoke-RestMethod -Uri $PreviousRawUri -TimeoutSec 30
        $previousTokens = $null
        $previousErrors = $null
        [void][Management.Automation.Language.Parser]::ParseInput([string]$previousText, [ref]$previousTokens, [ref]$previousErrors)
        $prefixCodes = @(([string]$previousText).ToCharArray() | Select-Object -First 4 | ForEach-Object { [int]$_ })
        Write-Output ('TRANSPORT_DIAG ' + (@{previous_prefix_codes=$prefixCodes;previous_string_parse_errors=@($previousErrors).Count} | ConvertTo-Json -Compress))
    }
    foreach ($transportMode in @('File', 'Iex')) {
        $script:TransportSecureReads = 0
        $script:TransportMenuReads = 0
        function Read-Host {
            param($Prompt, [switch]$AsSecureString)
            if ($AsSecureString) {
                $script:TransportSecureReads++
                return (ConvertTo-SecureString -String ((Get-Date).ToString('ddMMyyyy')) -AsPlainText -Force)
            }
            $script:TransportMenuReads++
            if ($script:TransportMenuReads -gt 1) { throw 'Unexpected extra menu prompt.' }
            return '0'
        }
        if ($transportMode -eq 'File') {
            $transportOutput = . $Candidate 6>&1
        } else {
            # Usa os mesmos aliases e o mesmo pipeline informados pelo usuario.
            $transportOutput = irm $CandidateRawUri | iex 6>&1
        }
        Assert-InilogTest ($script:TransportSecureReads -eq 1) ($transportMode + ': actual login prompt reached')
        Assert-InilogTest ($script:TransportMenuReads -eq 1) ($transportMode + ': actual main menu reached and exited')
        Assert-InilogTest ($script:InilogState.Version -eq '2.0.2') ($transportMode + ': corrected version initialized')
        $printed = ($transportOutput | ForEach-Object { $_.ToString() }) -join ''
        Assert-InilogTest ($printed.Contains('DIAGNÓSTICO E REDE')) ($transportMode + ': accented category rendered correctly')
    }
    $summary = [PSCustomObject]@{passed=$true;checks=$script:Checks.Count;runtime=$PSVersionTable.PSVersion.ToString();visible=$visible.Count;hidden=@(9,14);removed=$removed}
    Write-Output ('VALIDACAO_OK ' + ($summary | ConvertTo-Json -Depth 4 -Compress))
    if ($env:GITHUB_STEP_SUMMARY) {
        ('## Validação INILOG' + [Environment]::NewLine + '- Resultado: aprovado' + [Environment]::NewLine + '- Verificações: ' + $script:Checks.Count + [Environment]::NewLine + '- Runtime: Windows PowerShell ' + $PSVersionTable.PSVersion) | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    }
} finally {
    $server.Dispose()
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
