$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$CacheDir = Join-Path $PSScriptRoot 'cache'
$SusfsRepo = Join-Path $CacheDir 'susfs.git'
$SusfsCommit = '2df41de789026a6422521606402576507c687435'
function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}
$DefaultDockerDisk = Join-Path $env:LOCALAPPDATA 'Docker\wsl\disk\docker_data.vhdx'
if (Test-Path $DefaultDockerDisk) {
    $DriveName = [System.IO.Path]::GetPathRoot($DefaultDockerDisk).TrimEnd(':', '\')
    $FreeBytes = (Get-PSDrive -Name $DriveName).Free
    if ($FreeBytes -lt 20GB) {
        throw "Docker's default data disk is on ${DriveName}: with less than 20 GB free. Free space before building."
    }
} else {
    Write-Warning 'Docker data disk location was not detected; check at least 20 GB is available on the drive hosting Docker data.'
}
Invoke-Checked docker @('info', '--format', '{{.ServerVersion}}')
New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
if (-not (Test-Path (Join-Path $SusfsRepo 'HEAD'))) {
    Invoke-Checked git @('init', '--bare', $SusfsRepo)
}
$PreviousErrorActionPreference = $ErrorActionPreference
try {
    # A fresh cache does not contain the commit yet. Windows PowerShell 5.1
    # treats redirected native stderr as an error when Stop is in effect.
    $ErrorActionPreference = 'Continue'
    & git -C $SusfsRepo cat-file -e "$SusfsCommit^{commit}" 2>$null
    $HasSusfsCommit = ($LASTEXITCODE -eq 0)
} finally {
    $ErrorActionPreference = $PreviousErrorActionPreference
}
if (-not $HasSusfsCommit) {
    Invoke-Checked git @('-C', $SusfsRepo, 'fetch', '--depth=1', 'https://gitlab.com/simonpunk/susfs4ksu.git', $SusfsCommit)
}
Invoke-Checked git @('-C', $SusfsRepo, 'update-ref', 'refs/heads/pinned', $SusfsCommit)
Invoke-Checked docker @('build', '-t', 'avd-integrity-upstream-build', (Join-Path $ProjectRoot 'kernel-build'))
Invoke-Checked docker @('build', '-f', (Join-Path $PSScriptRoot 'Dockerfile'), '-t', 'avd-integrity-x86-build', $ProjectRoot)
$ProjectMount = "${ProjectRoot}:/work"
$SusfsMount = "${SusfsRepo}:/input/susfs.git:ro"
Invoke-Checked docker @('run', '--rm', '-v', $ProjectMount, '-v', 'avd-integrity-x86-sources:/work/kernel-build/sources', '-v', $SusfsMount, '-w', '/work', 'avd-integrity-x86-build', 'bash', '/work/x86/scripts/build-in-container.sh')
