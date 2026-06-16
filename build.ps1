#requires -Version 5.1
<#
.SYNOPSIS
  Reproducibly build the Omarchy WSL container image with wslc.

.DESCRIPTION
  Wraps `wslc build`. Run from the repo root (the directory containing the
  Dockerfile and the cloned `omarchy/` checkout).

  By default it builds the FULL Omarchy desktop. Desktop options can be turned
  off individually with the switches below (each maps to a Dockerfile build arg
  and a packages/groups/<group>.packages list).

.PARAMETER Tag
  Image tag to produce. Default: omarchy:latest

.PARAMETER NoDesktop
  Build a curated CLI-only image (DESKTOP=0): no Hyprland desktop.

.PARAMETER NoApps
  Skip large GUI apps (browser, office, media editors, chat, …). APPS=0

.PARAMETER NoLogin
  Skip the login manager + boot splash (sddm, plymouth). LOGIN=0

.PARAMETER NoPrinting
  Skip the CUPS printing stack. PRINTING=0

.PARAMETER NoInput
  Skip fcitx5 input methods. INPUT=0

.PARAMETER NoCache
  Build without the layer cache.

.EXAMPLE
  ./build.ps1                       # full desktop

.EXAMPLE
  ./build.ps1 -NoApps -NoLogin      # desktop without heavy apps or sddm/plymouth

.EXAMPLE
  ./build.ps1 -NoDesktop -Tag omarchy:cli   # CLI-only image
#>
[CmdletBinding()]
param(
  [string]$Tag = "omarchy:latest",
  [switch]$NoDesktop,
  [switch]$NoApps,
  [switch]$NoLogin,
  [switch]$NoPrinting,
  [switch]$NoInput,
  [switch]$NoCache
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

if (-not (Test-Path (Join-Path $root "omarchy\install.sh"))) {
  throw "Cannot find the Omarchy checkout at '$root\omarchy'. Set it up first: ./setup-omarchy.ps1"
}

# Map switches to 0/1 build args (default 1 = enabled).
$toggles = [ordered]@{
  DESKTOP  = if ($NoDesktop)  { 0 } else { 1 }
  APPS     = if ($NoApps)     { 0 } else { 1 }
  LOGIN    = if ($NoLogin)    { 0 } else { 1 }
  PRINTING = if ($NoPrinting) { 0 } else { 1 }
  INPUT    = if ($NoInput)    { 0 } else { 1 }
}

$wslcArgs = @("build", "-t", $Tag)
foreach ($k in $toggles.Keys) { $wslcArgs += "--build-arg", "$k=$($toggles[$k])" }
if ($NoCache) { $wslcArgs += "--no-cache" }
$wslcArgs += "-f", (Join-Path $root "Dockerfile"), $root

$summary = ($toggles.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join " "
Write-Host "Building '$Tag' ($summary)..." -ForegroundColor Cyan
Write-Host "wslc $($wslcArgs -join ' ')" -ForegroundColor DarkGray

& wslc.exe @wslcArgs
if ($LASTEXITCODE -ne 0) { throw "wslc build failed with exit code $LASTEXITCODE" }

Write-Host "`nBuilt '$Tag'. Verify it with: ./test.ps1 -Tag $Tag" -ForegroundColor Green
