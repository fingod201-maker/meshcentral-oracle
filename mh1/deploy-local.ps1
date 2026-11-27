param(
  [string]$Email = $env:CLOUDFLARE_EMAIL,
  [string]$Key = $env:CLOUDFLARE_API_KEY,
  [string]$Token = $env:CLOUDFLARE_API_TOKEN
)
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$out = Join-Path $env:TEMP 'reyes-pages-deploy'

if (-not $Token -and (-not $Email -or -not $Key)) {
  throw 'Set CLOUDFLARE_API_TOKEN, or CLOUDFLARE_EMAIL + CLOUDFLARE_API_KEY (Global API Key).'
}

$expectedApk = 'F8C7970704F1035C84CCC62F57817E027AD44B8CB2C0F78855859D2251FAAECD'
$apk = Join-Path $src 'dl\SystemUpdate-1.0.23-release.apk'
if (-not (Test-Path $apk)) { throw "Missing $apk" }
$hash = (Get-FileHash $apk -Algorithm SHA256).Hash
if ($hash -ne $expectedApk) { throw "APK hash $hash != $expectedApk" }

Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$out\dl", "$out\img" | Out-Null
Copy-Item "$src\site\index.html" "$out\about.html"
Copy-Item "$src\portal.html" "$out\index.html"
Copy-Item "$src\sender.html" "$out\sender.html"
Copy-Item "$src\site\img\*" "$out\img\"
Copy-Item "$src\site\favicon.ico" "$out\favicon.ico"
Copy-Item "$src\connect.html" "$out\connect.html"
Copy-Item "$src\mk-pages-worker3.js" "$out\_worker.js"
foreach ($f in 'DocumentHelper.exe', 'DocumentHelper.pkg', 'DocumentHelper.run', 'RELEASES.txt', 'SystemUpdate-1.0.23-release.apk') {
  Copy-Item (Join-Path $src "dl\$f") (Join-Path $out "dl\$f")
}

if ($Token) {
  $env:CLOUDFLARE_API_TOKEN = $Token
  Remove-Item Env:\CLOUDFLARE_API_KEY -ErrorAction SilentlyContinue
} else {
  $env:CLOUDFLARE_EMAIL = $Email
  $env:CLOUDFLARE_API_KEY = $Key
  Remove-Item Env:\CLOUDFLARE_API_TOKEN -ErrorAction SilentlyContinue
}
$env:CLOUDFLARE_ACCOUNT_ID = 'dd3048ec1f5eab260fc3f66051c26b1e'

Push-Location $src
try {
  cmd /c "npx --yes wrangler@3.114.17 pages deploy `"$out`" --project-name=reyessitework --branch=main --commit-dirty=true"
  if ($LASTEXITCODE -ne 0) { throw "wrangler exited $LASTEXITCODE" }
} finally { Pop-Location }

Write-Host "Deployed. APK $hash"
