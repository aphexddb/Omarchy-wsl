#requires -Version 5.1
<#
.SYNOPSIS
  Verify a built Omarchy WSL image behaves like Omarchy.

.DESCRIPTION
  Runs a throwaway container from the image and asserts that the Omarchy CLI,
  theming, shell environment, and headline CLI tools are present and working.

.PARAMETER Tag
  Image to test. Default: omarchy:latest
#>
[CmdletBinding()]
param(
  [string]$Tag = "omarchy:latest"
)

$ErrorActionPreference = "Stop"

# Verification script run inside the container. Kept as a single-quoted here-
# string (so bash quoting is preserved) and normalised to LF before use.
$bashRaw = @'
set +e
FAILED=0
export PATH="$HOME/.local/share/omarchy/bin:$PATH"

chk() {
  if eval "$2" >/dev/null 2>&1; then
    echo "PASS: $1"
  else
    echo "FAIL: $1"
    FAILED=1
  fi
}

chk "omarchy command present"      'command -v omarchy'
chk "omarchy dispatches"           'omarchy --help'
chk "omarchy version readable"     'cat "$HOME/.local/share/omarchy/version"'
chk "omarchy repo at OMARCHY_PATH" 'test -d "$HOME/.local/share/omarchy/bin"'
chk "bash env loads omarchy"       'bash -c "source ~/.local/share/omarchy/default/bash/rc; command -v omarchy"'
chk "config copied to ~/.config"   'test -d ~/.config/hypr && test -d ~/.config/omarchy'
chk "theme.name is tokyo-night"    '[ "$(cat ~/.config/omarchy/current/theme.name)" = "tokyo-night" ]'
chk "themed config generated"      'test -f ~/.config/omarchy/current/theme/alacritty.toml'
chk "theme list works"             'omarchy theme list | grep -qi tokyo'
chk "wsl.conf present"             'test -f /etc/wsl.conf'
chk "default user is omarchy"      'grep -q "default=omarchy" /etc/wsl.conf'
chk "passwordless sudo"            'sudo -n true'

for t in bat eza fd rg fzf jq nvim starship zoxide gum btop lazygit fastfetch tmux; do
  chk "tool: $t" "command -v $t"
done

# Desktop stack — verified only when this is a full-desktop build.
if pacman -Q hyprland >/dev/null 2>&1; then
  echo "--- desktop build detected ---"
  for p in hyprland waybar mako hyprlock hypridle uwsm swaybg xdg-desktop-portal-hyprland; do
    chk "desktop: $p" "pacman -Q $p"
  done
else
  echo "SKIP: desktop stack (CLI-only / DESKTOP=0 build)"
fi

echo "----------------------------------------"
if [ "$FAILED" = 0 ]; then
  echo "ALL_CHECKS_PASSED"
else
  echo "SOME_CHECKS_FAILED"
fi
exit $FAILED
'@

$bash = $bashRaw -replace "`r`n", "`n"

Write-Host "Testing image '$Tag'..." -ForegroundColor Cyan
$output = & wslc.exe run --rm $Tag bash -c $bash 2>&1
$exit = $LASTEXITCODE
$output | ForEach-Object { Write-Host $_ }

if ($exit -eq 0 -and ($output -match "ALL_CHECKS_PASSED")) {
  Write-Host "`nVERIFICATION PASSED" -ForegroundColor Green
  exit 0
} else {
  Write-Host "`nVERIFICATION FAILED (exit $exit)" -ForegroundColor Red
  exit 1
}
