#requires -Version 5.1
<#
.SYNOPSIS
  One-shot build of the basic (CLI/TUI-only) Omarchy WSL distro: Omarchy-Basic.wsl.

.DESCRIPTION
  Runs the whole pipeline end to end so you only have to invoke a single script:

    1. setup-omarchy.ps1   - fetch/update the upstream Omarchy checkout into ./omarchy
    2. build.ps1 -NoDesktop - build the curated CLI-only image (DESKTOP=0)
    3. export-wsl.ps1      - export it to an installable Omarchy-Basic.wsl

  This intentionally does NOT build the full graphical desktop image.

.PARAMETER Tag
  Tag for the basic CLI image. Default: omarchy:basic

.PARAMETER OutFile
  Destination .wsl path. Default: Omarchy-Basic.wsl in the repo root.

.PARAMETER Ref
  Branch, tag, or commit of Omarchy to check out. Default: v4.0.0 (see
  setup-omarchy.ps1 -Ref for why).

.PARAMETER Arch
  Target architecture: amd64 or arm64. Defaults to the host's architecture
  (see build.ps1 -Arch).

.PARAMETER NoCache
  Build the image without the layer cache.

.PARAMETER SkipSetup
  Skip the setup-omarchy.ps1 step (use the existing ./omarchy checkout as-is).

.EXAMPLE
  ./build-omarchy.ps1

.EXAMPLE
  ./build-omarchy.ps1 -NoCache

.EXAMPLE
  ./build-omarchy.ps1 -Ref v3.4.2 -OutFile C:\out\Omarchy-Basic.wsl
#>
[CmdletBinding()]
param(
  [string]$Tag = "omarchy:basic",
  [string]$OutFile,
  [string]$Ref,
  [ValidateSet("amd64", "arm64")]
  [string]$Arch,
  [switch]$NoCache,
  [switch]$SkipSetup
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$setupScript = Join-Path $root "setup-omarchy.ps1"
$buildScript = Join-Path $root "build.ps1"
$exportScript = Join-Path $root "export-wsl.ps1"

foreach ($s in @($setupScript, $buildScript, $exportScript)) {
  if (-not (Test-Path $s)) { throw "Cannot find required script at '$s'." }
}

if (-not $OutFile) { $OutFile = Join-Path $root "Omarchy-Basic.wsl" }
if (-not [System.IO.Path]::IsPathRooted($OutFile)) { $OutFile = Join-Path $root $OutFile }

if (-not $SkipSetup) {
  Write-Host "=== Step 1/3: Fetching/updating Omarchy checkout ===" -ForegroundColor Cyan
  if ($Ref) { & $setupScript -Ref $Ref } else { & $setupScript }
  if ($LASTEXITCODE -ne 0) { throw "setup-omarchy failed (exit $LASTEXITCODE)." }
} else {
  Write-Host "=== Step 1/3: Skipping Omarchy checkout (-SkipSetup) ===" -ForegroundColor Cyan
}

Write-Host "`n=== Step 2/3: Building basic CLI image '$Tag' ===" -ForegroundColor Cyan
if ($Arch) { & $buildScript -Tag $Tag -Arch $Arch -NoDesktop -NoCache:$NoCache }
else { & $buildScript -Tag $Tag -NoDesktop -NoCache:$NoCache }
if ($LASTEXITCODE -ne 0) { throw "Basic build failed (exit $LASTEXITCODE)." }

Write-Host "`n=== Step 3/3: Exporting '$Tag' -> '$OutFile' ===" -ForegroundColor Cyan
& $exportScript -Image $Tag -OutFile $OutFile
if ($LASTEXITCODE -ne 0) { throw "Export failed (exit $LASTEXITCODE)." }

Write-Host "`nDone. Built Omarchy-Basic.wsl:" -ForegroundColor Green
if (Test-Path $OutFile) {
  Write-Host ("  {0} ({1} GB)" -f $OutFile, [math]::Round((Get-Item $OutFile).Length / 1GB, 2)) -ForegroundColor Green
}
Write-Host "Install it with: wsl --install --from-file `"$OutFile`"" -ForegroundColor Green
