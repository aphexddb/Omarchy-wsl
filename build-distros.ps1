#requires -Version 5.1
<#
.SYNOPSIS
  Build BOTH Omarchy WSL distro images in wslc: a graphical desktop one and a
  basic (CLI-only) one.

.DESCRIPTION
  Produces two images from the same Dockerfile:

    omarchy:desktop  - full Omarchy graphical desktop (Hyprland + apps)
    omarchy:basic    - curated CLI-only Omarchy (DESKTOP=0)

  Both bake in the SAME WSL distribution assets (/etc/wsl-distribution.conf,
  /etc/oobe.sh, the Start-menu icon and the Windows Terminal profile), so they
  register identically under the name "Omarchy" with the same default user.

  After this finishes you have two images in `wslc images`. Pass -Export to also
  generate installable .wsl files (Omarchy.wsl and Omarchy-Basic.wsl) via
  export-wsl.ps1.

.PARAMETER DesktopTag
  Tag for the graphical desktop image. Default: omarchy:desktop

.PARAMETER BasicTag
  Tag for the basic CLI image. Default: omarchy:basic

.PARAMETER NoCache
  Build both images without the layer cache.

.PARAMETER Only
  Build only one of the two: 'desktop' or 'basic'.

.PARAMETER Export
  After building, export each image to an installable .wsl file
  (desktop -> Omarchy.wsl, basic -> Omarchy-Basic.wsl).

.PARAMETER OutDir
  Directory for the exported .wsl files. Default: the repo root.

.EXAMPLE
  ./build-distros.ps1

.EXAMPLE
  ./build-distros.ps1 -Export

.EXAMPLE
  ./build-distros.ps1 -Only basic -Export
#>
[CmdletBinding()]
param(
  [string]$DesktopTag = "omarchy:desktop",
  [string]$BasicTag = "omarchy:basic",
  [switch]$NoCache,
  [ValidateSet("desktop", "basic", "both")]
  [string]$Only = "both",
  [switch]$Export,
  [string]$OutDir
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$build = Join-Path $root "build.ps1"
$exportScript = Join-Path $root "export-wsl.ps1"

if (-not (Test-Path $build)) { throw "Cannot find build.ps1 at '$build'." }
if ($Export -and -not (Test-Path $exportScript)) { throw "Cannot find export-wsl.ps1 at '$exportScript'." }
if (-not $OutDir) { $OutDir = $root }

if ($Only -in @("desktop", "both")) {
  Write-Host "=== Building graphical desktop image '$DesktopTag' ===" -ForegroundColor Cyan
  & $build -Tag $DesktopTag -NoCache:$NoCache
  if ($LASTEXITCODE -ne 0) { throw "Desktop build failed (exit $LASTEXITCODE)." }
  if ($Export) {
    & $exportScript -Image $DesktopTag -OutFile (Join-Path $OutDir "Omarchy.wsl")
    if ($LASTEXITCODE -ne 0) { throw "Desktop export failed (exit $LASTEXITCODE)." }
  }
}

if ($Only -in @("basic", "both")) {
  Write-Host "`n=== Building basic CLI image '$BasicTag' ===" -ForegroundColor Cyan
  & $build -Tag $BasicTag -NoDesktop -NoCache:$NoCache
  if ($LASTEXITCODE -ne 0) { throw "Basic build failed (exit $LASTEXITCODE)." }
  if ($Export) {
    & $exportScript -Image $BasicTag -OutFile (Join-Path $OutDir "Omarchy-Basic.wsl")
    if ($LASTEXITCODE -ne 0) { throw "Basic export failed (exit $LASTEXITCODE)." }
  }
}

Write-Host "`nDone. Images in wslc:" -ForegroundColor Green
& wslc.exe images
if ($Export) {
  Write-Host "`nExported .wsl files in '$OutDir':" -ForegroundColor Green
  Get-ChildItem -Path $OutDir -Filter "Omarchy*.wsl" -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host ("  {0} ({1} GB)" -f $_.Name, [math]::Round($_.Length / 1GB, 2)) -ForegroundColor Green }
  Write-Host "Install one with: wsl --install --from-file Omarchy.wsl" -ForegroundColor Green
} else {
  Write-Host "`nNext: re-run with -Export to generate .wsl files, or see README.md." -ForegroundColor Green
}
