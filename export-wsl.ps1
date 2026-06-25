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

if (-not (Get-Command wslc.exe -ErrorAction SilentlyContinue)) {
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

# Clean up any leftover container with this name from a previous run.
& wslc.exe rm $ContainerName 2>$null | Out-Null

Write-Host "Exporting image '$Image' -> '$OutFile'" -ForegroundColor Cyan
try {
  Write-Host "Creating export container '$ContainerName'..." -ForegroundColor DarkGray
  & wslc.exe create --name $ContainerName $Image
  if ($LASTEXITCODE -ne 0) { throw "wslc create failed (exit $LASTEXITCODE)" }

  Write-Host "Exporting root filesystem..." -ForegroundColor DarkGray
  & wslc.exe export -o $OutFile $ContainerName
  if ($LASTEXITCODE -ne 0) { throw "wslc export failed (exit $LASTEXITCODE)" }
}
finally {
  & wslc.exe rm $ContainerName 2>$null | Out-Null
}

$size = [math]::Round((Get-Item $OutFile).Length / 1GB, 2)
Write-Host "`nWrote $OutFile ($size GB)" -ForegroundColor Green
Write-Host "Install it with: wsl --install --from-file `"$OutFile`"" -ForegroundColor Green
