# Build all Firebase Hosting web targets (see firebase.json) and deploy.
# Requires: Flutter SDK on PATH, firebase-tools (`npm i -g firebase-tools`), `firebase login`.
# Optional: pass dart-define values for keys (same as local run), e.g.:
#   $env:GOOGLE_MAPS_API_KEY="..."; $env:RECAPTCHA_SITE_KEY="..."; .\scripts\build_web_and_deploy_hosting.ps1
#   (Legacy: MAPS_API_KEY is accepted as an alias for GOOGLE_MAPS_API_KEY.)

$ErrorActionPreference = "Stop"
# scripts/ -> project root (folder containing pubspec.yaml)
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $root

$flutterExe = "C:\Users\royal\flutter_stable\bin\flutter.bat"
if (-not (Test-Path $flutterExe)) {
  Write-Error "Flutter not found at: $flutterExe"
}
$env:PATH = "C:\Users\royal\flutter_stable\bin;" + $env:PATH

& flutter pub get

$defines = @()
$gmaps = $env:GOOGLE_MAPS_API_KEY
if (-not $gmaps -and $env:MAPS_API_KEY) { $gmaps = $env:MAPS_API_KEY }
if (-not $gmaps) { $gmaps = "AIzaSyDTd_0szhv_DKOZX5hZyaCMMpDQn-K0Xfo" }
if ($gmaps) { $defines += "--dart-define=GOOGLE_MAPS_API_KEY=$gmaps" }
$gemini = $env:GEMINI_API_KEY
if ($gemini) { $defines += "--dart-define=GEMINI_API_KEY=$gemini" }
if ($env:RECAPTCHA_SITE_KEY) { $defines += "--dart-define=RECAPTCHA_SITE_KEY=$($env:RECAPTCHA_SITE_KEY)" }
if ($env:LIVEKIT_URL) { $defines += "--dart-define=LIVEKIT_URL=$($env:LIVEKIT_URL)" }

$common = @("build", "web", "--release") + $defines

& flutter @($common + @("-t", "lib/main.dart", "-o", "build/web-main"))
& flutter @($common + @("-t", "lib/main_admin.dart", "-o", "build/web-admin"))
& flutter @($common + @("-t", "lib/main_fleet.dart", "-o", "build/web-fleet"))

if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
  Write-Error "Firebase CLI not found. Install: npm i -g firebase-tools"
}

firebase deploy --only hosting
