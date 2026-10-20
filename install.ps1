# Tandem Worker installer for Windows. No admin rights: everything goes in %LOCALAPPDATA%\TandemWorker, plus one
# Startup entry so the worker starts again at every log-in. Run it again to update (your sign-in is kept).
#   irm https://raw.githubusercontent.com/NotGurneal/tandem-worker/main/install.ps1 | iex
#   uninstall:  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/NotGurneal/tandem-worker/main/install.ps1))) -Uninstall
param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'      # Invoke-WebRequest is many times faster without the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo    = 'NotGurneal/tandem-worker'
$Dir     = Join-Path $env:LOCALAPPDATA 'TandemWorker'
$AppDir  = Join-Path $Dir 'app'
$NodeDir = Join-Path $Dir 'node'
$Startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'TandemWorker.vbs'

function Stop-Worker {
  $lock = Join-Path $Dir 'worker.lock'
  if (Test-Path $lock) { $id = [int](Get-Content $lock -Raw); Stop-Process -Id $id -Force -ErrorAction SilentlyContinue; Start-Sleep 1 }
}

if ($Uninstall) {
  Stop-Worker
  Remove-Item $Startup -Force -ErrorAction SilentlyContinue
  Remove-Item $Dir -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host 'Tandem Worker removed from this computer.'
  return
}

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$tmp = Join-Path $Dir 'tmp\install'
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# 1. Node.js (portable zip, current LTS, checked against nodejs.org's published SHA-256)
$node = Join-Path $NodeDir 'node.exe'
if (-not (Test-Path $node)) {
  $rel = (Invoke-RestMethod 'https://nodejs.org/dist/index.json') | Where-Object { $_.lts -and $_.files -contains 'win-x64-zip' } | Select-Object -First 1
  $name = "node-$($rel.version)-win-x64"
  Write-Host "Downloading Node.js $($rel.version)..."
  $zip = Join-Path $tmp "$name.zip"
  Invoke-WebRequest "https://nodejs.org/dist/$($rel.version)/$name.zip" -OutFile $zip
  $sums = (Invoke-WebRequest "https://nodejs.org/dist/$($rel.version)/SHASUMS256.txt" -UseBasicParsing).Content
  $want = ($sums -split "`n" | Where-Object { $_ -match "  $name\.zip$" }) -replace '\s.*$', ''
  if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $want.ToUpper()) { throw 'Node.js download failed its checksum.' }
  Expand-Archive $zip -DestinationPath $tmp -Force
  Remove-Item $NodeDir -Recurse -Force -ErrorAction SilentlyContinue
  Move-Item (Join-Path $tmp $name) $NodeDir
}

# 2. The worker itself (latest release; it updates itself from here on, see worker.js checkUpdate)
$tag = (Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest").tag_name
Write-Host "Downloading Tandem Worker $tag..."
$wzip = Join-Path $tmp 'tandem-worker.zip'
Invoke-WebRequest "https://github.com/$Repo/releases/latest/download/tandem-worker.zip" -OutFile $wzip
Stop-Worker
Remove-Item $AppDir -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive $wzip -DestinationPath $AppDir -Force
Set-Content -Path (Join-Path $Dir 'version.txt') -Value $tag -Encoding ASCII
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

# 3. Sign in (once; only a session token is kept, in this folder)
$worker = Join-Path $AppDir 'worker.js'
$cfg = Join-Path $Dir 'worker.json'
$signedIn = (Test-Path $cfg) -and ((Get-Content $cfg -Raw) -match '"token"')
if (-not $signedIn) {
  & $node $worker login
  if ($LASTEXITCODE -ne 0) { throw 'Sign-in failed: run the installer again to retry.' }
}

# 4. Start at every log-in (hidden), and now
$vbs = "CreateObject(""WScript.Shell"").Run """"""$node"""" """"$worker"""" run"", 0, False"
Set-Content -Path $Startup -Value $vbs -Encoding ASCII
Start-Process -FilePath $node -ArgumentList "`"$worker`"", 'run' -WindowStyle Hidden
Start-Sleep 3
& $node $worker status
Write-Host ''
Write-Host 'Tandem Worker is running. It starts again whenever you log in to this computer.'
Write-Host 'Lock the screen (Win+L) instead of signing out to keep jobs running.'
