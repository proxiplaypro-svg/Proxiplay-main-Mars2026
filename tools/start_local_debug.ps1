[CmdletBinding()]
param(
  [switch]$NoEmulators
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$ports = @(9099, 8080, 5001, 9199, 4000, 4400)

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  throw 'adb is required. Install Android platform-tools and add it to PATH.'
}

$devices = @(adb devices | Select-String 'device$' | ForEach-Object {
  ($_ -split "`t")[0]
})
if ($devices.Count -ne 1) {
  throw "Connect exactly one authorized Android phone by USB. Detected: $($devices.Count)."
}

foreach ($port in @(9099, 8080, 5001, 9199)) {
  adb reverse "tcp:$port" "tcp:$port" | Out-Host
}

if (-not $NoEmulators) {
  foreach ($port in $ports) {
    if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
      throw "Port $port is already listening. Stop the existing emulator process first."
    }
  }
}

Write-Host 'ADB reverse configured: device 127.0.0.1 -> workstation emulators.' -ForegroundColor Green
Write-Host 'Run Flutter with: flutter run --dart-define=USE_FIREBASE_EMULATORS=true' -ForegroundColor Yellow
Write-Host 'Do not use this flag for a release build.' -ForegroundColor Yellow

if (-not $NoEmulators) {
  Push-Location $projectRoot
  try {
    firebase emulators:start --project proxi-play-odzp2e --only auth,firestore,functions,storage
  } finally {
    Pop-Location
  }
}
