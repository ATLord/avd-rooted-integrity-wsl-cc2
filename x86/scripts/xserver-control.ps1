param(
    [Parameter(Mandatory=$true)][ValidateSet('Start','Stop')][string]$Action,
    [Parameter(Mandatory=$true)][string]$Executable,
    [string]$Authority,
    [int]$DisplayNumber = 3,
    [int]$ProcessId = 0
)
$ErrorActionPreference = 'Stop'
if ($Action -eq 'Stop') {
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($process -and $process.Path -eq $Executable) { Stop-Process -Id $ProcessId }
    exit 0
}
if (-not (Test-Path -LiteralPath $Executable) -or -not (Test-Path -LiteralPath $Authority)) { throw 'X server or authorization file missing.' }
if (Get-NetTCPConnection -LocalPort (6000 + $DisplayNumber) -State Listen -ErrorAction SilentlyContinue) { throw 'X display port is already in use.' }
$arguments = @(':' + $DisplayNumber, '-multiwindow', '-clipboard', '-listen', 'tcp', '-auth', ('"' + $Authority + '"'))
$process = Start-Process -FilePath $Executable -ArgumentList $arguments -WorkingDirectory (Split-Path $Executable -Parent) -WindowStyle Hidden -PassThru
Start-Sleep -Milliseconds 700
if ($process.HasExited) { throw "X server exited with code $($process.ExitCode)." }
Write-Output $process.Id
