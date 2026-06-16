#!/bin/bash
# /etc/oobe.sh — Omarchy WSL out-of-box experience (first interactive launch).
#
# Referenced by /etc/wsl-distribution.conf ([oobe] command). Runs once, as root,
# the first time the user opens a shell. Must exit 0 for WSL to open the shell.
#
# Omarchy ships a baked-in `omarchy` user at uid 1000 (== oobe.defaultUid), so
# unlike a stock distro we don't need to interactively create an account — we
# just confirm it exists and welcome the user. If for some reason uid 1000 is
# missing (e.g. a stripped rootfs), fall back to creating one interactively.

set -ue

DEFAULT_UID='1000'
DEFAULT_GROUPS='wheel'

if getent passwd "$DEFAULT_UID" >/dev/null; then
  user="$(getent passwd "$DEFAULT_UID" | cut -d: -f1)"
  echo
  echo "  Welcome to Omarchy on WSL!"
  echo "  Signed in as '$user'. Run 'omarchy' to explore the command suite."
  echo
  exit 0
fi

echo 'Please create a default UNIX user account. The username does not need to match your Windows username.'
echo 'For more information visit: https://aka.ms/wslusers'

while true; do
  read -p 'Enter new UNIX username: ' username

  if /usr/sbin/useradd --uid "$DEFAULT_UID" --create-home --shell /bin/bash --user-group "$username"; then
    /usr/sbin/usermod -aG "$DEFAULT_GROUPS" "$username" || true
    passwd -d "$username" || true
    break
  else
    /usr/sbin/userdel -r "$username" 2>/dev/null || true
  fi
done

exit 0
