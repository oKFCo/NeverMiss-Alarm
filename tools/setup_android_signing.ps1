$ErrorActionPreference = "Stop"

$keytool = "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"
if (-not (Test-Path $keytool)) {
  throw "keytool not found at $keytool"
}

$chars = (48..57) + (65..90) + (97..122)
$storePass = -join ($chars | Get-Random -Count 24 | ForEach-Object { [char]$_ })
$alias = "nevermiss_release"
$dname = "CN=NeverMiss Alarm, OU=Engineering, O=oKFCo, L=NA, S=NA, C=US"

$releaseKeystore = "android/release.keystore"
if (Test-Path $releaseKeystore) {
  Remove-Item $releaseKeystore -Force
}

& $keytool `
  -genkeypair `
  -v `
  -keystore $releaseKeystore `
  -alias $alias `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -storepass $storePass `
  -keypass $storePass `
  -dname $dname

@(
  "storeFile=../release.keystore"
  "storePassword=$storePass"
  "keyAlias=$alias"
  "keyPassword=$storePass"
) | Set-Content "android/key.properties"

$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $releaseKeystore)))
@(
  "ANDROID_KEYSTORE_BASE64=$b64"
  "ANDROID_STORE_PASSWORD=$storePass"
  "ANDROID_KEY_ALIAS=$alias"
  "ANDROID_KEY_PASSWORD=$storePass"
) | Set-Content "android/github_actions_secrets.txt"

@(
  "Keystore: android/release.keystore"
  "Alias: $alias"
  "StorePassword: $storePass"
  "KeyPassword: $storePass"
) | Set-Content "android/release_signing_credentials.txt"

Write-Output "Generated:"
Write-Output " - android/release.keystore"
Write-Output " - android/key.properties"
Write-Output " - android/github_actions_secrets.txt"
Write-Output " - android/release_signing_credentials.txt"
