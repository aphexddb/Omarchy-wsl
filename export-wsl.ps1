#requires -Version 5.1
<#
.SYNOPSIS
  Export a built Omarchy wslc image to an installable .wsl file.

.DESCRIPTION
  A .wsl file is just a gzip-compressed tar of a distro's root filesystem. This
  script creates a throwaway container from the given image, exports its rootfs,
  writes it to the requested .wsl path, and cleans the container up afterwards.

  Install the result by double-clicking it, or:
    wsl --install --from-file Omarchy.wsl

.PARAMETER Image
  The wslc image to export, e.g. omarchy:desktop or omarchy:basic.

.PARAMETER OutFile
  Destination .wsl path. Default: <image-name>.wsl in the repo root.

.PARAMETER ContainerName
  Name for the temporary export container. Default: derived from the image.

.EXAMPLE
  ./export-wsl.ps1 -Image omarchy:desktop -OutFile Omarchy.wsl

.EXAMPLE
  ./export-wsl.ps1 -Image omarchy:basic -OutFile Omarchy-Basic.wsl
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Image,
  [string]$OutFile,
  [string]$ContainerName
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

$wslc = (Get-Command wslc.exe -ErrorAction SilentlyContinue).Source
if (-not $wslc) {
  $candidate = Join-Path $env:ProgramFiles "WSL\wslc.exe"
  if (Test-Path $candidate) { $wslc = $candidate }
}
if (-not $wslc) {
  throw "wslc.exe was not found on PATH. Install the WSL container CLI first."
}

if (-not $OutFile) {
  $OutFile = Join-Path $root ((($Image -replace '[:/]', '-')) + ".wsl")
}
if (-not [System.IO.Path]::IsPathRooted($OutFile)) {
  $OutFile = Join-Path $root $OutFile
}
if (-not $ContainerName) {
  $ContainerName = ($Image -replace '[:/]', '-') + "-export"
}

# wslc writes "not found" to stderr. With $ErrorActionPreference Stop, that
# becomes a terminating NativeCommandError even when redirected with 2>$null.
function Remove-WslcContainer {
  param([string]$Name)
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "SilentlyContinue"
  try { & $wslc rm --force $Name 2>&1 | Out-Null } catch { }
  finally { $ErrorActionPreference = $prev }
}

# Clean up any leftover container with this name from a previous run.
Remove-WslcContainer $ContainerName

Write-Host "Exporting image '$Image' -> '$OutFile'" -ForegroundColor Cyan
try {
  Write-Host "Creating export container '$ContainerName'..." -ForegroundColor DarkGray
  & $wslc create --name $ContainerName $Image
  if ($LASTEXITCODE -ne 0) { throw "wslc create failed (exit $LASTEXITCODE)" }

  Write-Host "Exporting root filesystem..." -ForegroundColor DarkGray
  & $wslc export -o $OutFile $ContainerName
  if ($LASTEXITCODE -ne 0) { throw "wslc export failed (exit $LASTEXITCODE)" }
}
finally {
  Remove-WslcContainer $ContainerName
}

$size = [math]::Round((Get-Item $OutFile).Length / 1GB, 2)
Write-Host "`nWrote $OutFile ($size GB)" -ForegroundColor Green
Write-Host "Install it with: wsl --install --from-file `"$OutFile`"" -ForegroundColor Green
