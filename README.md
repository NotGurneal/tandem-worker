# Tandem Worker

Runs Tandem jobs in the background on a Windows PC. No admin rights needed.

Install or update (PowerShell):

    irm https://raw.githubusercontent.com/NotGurneal/tandem-worker/main/install.ps1 | iex

It asks for your Tandem login once, then starts on every log-in. Lock the screen (Win+L) instead of signing out to keep jobs running.

Status:   & "$env:LOCALAPPDATA\TandemWorker\node\node.exe" "$env:LOCALAPPDATA\TandemWorker\app\worker.js" status

Uninstall:

    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/NotGurneal/tandem-worker/main/install.ps1))) -Uninstall
