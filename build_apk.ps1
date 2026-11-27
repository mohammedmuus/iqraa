# Builds the APK for the website download (GitHub release), signed with the upload key.
# Run from the iqraa_app folder:  .\build_apk.ps1 -Name 1.0.11 -Number 12
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][int]$Number
)
Set-Location $PSScriptRoot

# Base64 SHA-256 of the upload key, which signs this APK.
$UploadKeyHash = "VdDdeg9g8ZhJp173/Q48oxLe9OHocGvwdI6CTmHjlDU="

flutter clean
flutter pub get
flutter build apk --release --obfuscate --split-debug-info=build\symbols `
    --build-name=$Name --build-number=$Number `
    --dart-define=IQRAA_DIRECT=true `
    --dart-define=IQRAA_SIGNING_HASHES=$UploadKeyHash `
    --dart-define=IQRAA_SECURITY_MAIL=info@iqraa.co.tz
if ($LASTEXITCODE -ne 0) { throw "The APK build failed." }

Copy-Item build\app\outputs\flutter-apk\app-release.apk "$HOME\Desktop\iqraa.apk" -Force
Write-Host "Done: $HOME\Desktop\iqraa.apk (version $Name, build $Number). Upload it to the GitHub release as iqraa.apk."
