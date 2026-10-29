param(
    [string]$RuntimeHome = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'avd-windows-runtime'),
    [string]$AvdName = 'Pixel_9_Pro_XL_Windows',
    [int]$Port = 5554
)

$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$sdk = Join-Path $RuntimeHome 'sdk'
$emulator = Join-Path $sdk 'emulator\emulator.exe'
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$kernel = Join-Path $project 'x86\out\bzImage-x86_64'
$avdHome = Join-Path $RuntimeHome 'avd'
foreach ($path in @($emulator, $adb, $kernel, (Join-Path $avdHome "$AvdName.ini"))) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required file not found: $path" }
}

$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:ANDROID_USER_HOME = $RuntimeHome
$env:ANDROID_AVD_HOME = $avdHome
$keyDir = Join-Path $RuntimeHome 'adb-keys'
if (Test-Path -LiteralPath (Join-Path $keyDir 'adbkey')) { $env:ADB_VENDOR_KEYS = $keyDir }
$serial = "emulator-$Port"
$devices = & $adb devices
$deviceLine = $devices | Where-Object { $_ -match "^$([regex]::Escape($serial))\s" }
if ($deviceLine -and $deviceLine -match '\sdevice\s*$') {
    $nameOutput = & $adb -s $serial emu avd name
    if ($nameOutput -and (($nameOutput | Select-Object -First 1).Trim() -eq $AvdName)) {
        Write-Host "$AvdName is already running on $serial."
        exit 0
    }
}
if ($deviceLine) {
    throw "$serial is already in use by another device."
}

& $emulator -avd $AvdName -port $Port -kernel $kernel -no-snapshot -gpu swiftshader_indirect -accel on -qemu -append kernelsu.allow_shell=1
exit $LASTEXITCODE
