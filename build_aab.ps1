# Builds the app bundle for Google Play. Google re-signs it with the Play app signing key.
# Run from the iqraa_app folder:  .\build_aab.ps1 -Name 1.0.11 -Number 12
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][int]$Number
)
Set-Location $PSScriptRoot

# Base64 SHA-256 of the upload key, and of the Play app signing key once Play Console shows it.
# Both are allowed, so a copy signed by either key is accepted.
$UploadKeyHash = "VdDdeg9g8ZhJp173/Q48oxLe9OHocGvwdI6CTmHjlDU="
$PlayKeyHash = ""
$Hashes = (@($UploadKeyHash, $PlayKeyHash) | Where-Object { $_ }) -join ","

flutter clean
flutter pub get
flutter build appbundle --release --obfuscate --split-debug-info=build\symbols `
    --build-name=$Name --build-number=$Number `
    --dart-define=IQRAA_SIGNING_HASHES=$Hashes `
    --dart-define=IQRAA_SECURITY_MAIL=info@iqraa.co.tz
if ($LASTEXITCODE -ne 0) { throw "The app bundle build failed." }

Copy-Item build\app\outputs\bundle\release\app-release.aab "$HOME\Desktop\iqraa-$Name.aab" -Force
Write-Host "Done: $HOME\Desktop\iqraa-$Name.aab (version $Name, build $Number). Upload it in Play Console."
if (-not $PlayKeyHash) { Write-Host "The Play app signing key hash is not set yet, so the Play copy will be blocked until it is added." }
