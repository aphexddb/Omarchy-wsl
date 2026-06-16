# syntax=docker/dockerfile:1
#
# Omarchy WSL — Step 1: reproducible "omarchy" container image.
#
# Build with wslc (Docker-compatible):
#   wslc build -t omarchy:latest .
# or use the wrapper:
#   ./build.ps1
#
# The image is Arch-based (like Omarchy itself), wires up the official
# [omarchy] pacman repo, installs the Omarchy CLI + configs + theming, and is
# preconfigured for WSL (systemd on, default user `omarchy`). It does NOT run
# upstream install.sh, whose preflight guards require bare-metal Arch with
# Limine/Btrfs/SDDM/Plymouth — none of which exist in a container. See README.md.

FROM archlinux:latest

# --- Desktop feature toggles (build args, default = full desktop) ------------
# Set any to 0 to slim the image. DESKTOP is the master switch; the rest only
# apply when DESKTOP=1. See packages/groups/ and README.md.
#   DESKTOP=0   -> curated CLI-only image (no Hyprland desktop)
#   APPS=0      -> skip large GUI apps (browser, office, media, chat, …)
#   LOGIN=0     -> skip sddm + plymouth (login manager / boot splash)
#   PRINTING=0  -> skip CUPS printing stack
#   INPUT=0     -> skip fcitx5 input methods
ARG DESKTOP=1
ARG APPS=1
ARG LOGIN=1
ARG PRINTING=1
ARG INPUT=1
ARG USERNAME=omarchy

# --- 1. Base prerequisites + pacman keyring (root) --------------------------
RUN pacman-key --init && \
    pacman-key --populate archlinux && \
    pacman -Sy --noconfirm --needed archlinux-keyring && \
    pacman -S --noconfirm --needed base-devel git sudo && \
    pacman -Scc --noconfirm

# --- 2. Default `omarchy` user with passwordless sudo -----------------------
# Mirrors Omarchy's user-level install model (it refuses to run as root).
RUN useradd -m -G wheel -s /bin/bash "$USERNAME" && \
    passwd -d "$USERNAME" && \
    echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-omarchy-wsl && \
    chmod 0440 /etc/sudoers.d/99-omarchy-wsl

# --- 3. Bring in the Omarchy checkout (incl. .git) + WSL build assets --------
COPY omarchy /home/$USERNAME/.local/share/omarchy
COPY install /home/$USERNAME/omarchy-wsl/install
COPY packages /home/$USERNAME/omarchy-wsl/packages

# --- 4. Normalise the build context for Linux -------------------------------
# The context comes from Windows: autocrlf rewrote tracked files to CRLF and the
# +x bit was dropped. Regenerating the working tree from the git blobs restores
# LF endings and executable bits exactly as upstream ships them. The WSL helper
# files (not tracked by that repo) are de-CRLF'd directly.
RUN git config --global --add safe.directory /home/$USERNAME/.local/share/omarchy && \
    git -C /home/$USERNAME/.local/share/omarchy config core.autocrlf false && \
    git -C /home/$USERNAME/.local/share/omarchy config core.fileMode true && \
    git -C /home/$USERNAME/.local/share/omarchy reset --hard HEAD && \
    find /home/$USERNAME/omarchy-wsl -type f \( -name '*.sh' -o -name '*.packages' \) \
      -exec sed -i 's/\r$//' {} + && \
    chown -R "$USERNAME:$USERNAME" /home/$USERNAME

# --- 5. Run the WSL-adapted Omarchy installer as the omarchy user -----------
USER $USERNAME
WORKDIR /home/$USERNAME
RUN DESKTOP="$DESKTOP" APPS="$APPS" LOGIN="$LOGIN" PRINTING="$PRINTING" INPUT="$INPUT" \
    bash /home/$USERNAME/omarchy-wsl/install/omarchy-wsl-install.sh

# --- 6. WSL configuration ---------------------------------------------------
USER root
COPY wsl.conf /etc/wsl.conf
RUN sed -i 's/\r$//' /etc/wsl.conf

# --- 7. WSL distribution assets (shared by BOTH distros) --------------------
# These turn the image into an installable WSL distro: a distribution config
# (name/default user/shortcut/terminal profile), the first-run OOBE script, the
# Start-menu icon (.ico converted from Omarchy's icon.png), and a Tokyo Night
# Windows Terminal profile. The same files are baked into the desktop and basic
# images so both register identically — see README.md.
COPY wsl/wsl-distribution.conf /etc/wsl-distribution.conf
COPY wsl/oobe.sh /etc/oobe.sh
COPY wsl/terminal-profile.json /usr/lib/wsl/terminal-profile.json
RUN sed -i 's/\r$//' /etc/wsl-distribution.conf /etc/oobe.sh /usr/lib/wsl/terminal-profile.json && \
    magick /home/$USERNAME/.local/share/omarchy/icon.png \
      -background none -define icon:auto-resize=256,128,64,48,32,16 \
      /usr/lib/wsl/omarchy.ico && \
    chown root:root /etc/wsl.conf /etc/wsl-distribution.conf /etc/oobe.sh \
      /usr/lib/wsl/terminal-profile.json /usr/lib/wsl/omarchy.ico && \
    chmod 0644 /etc/wsl.conf /etc/wsl-distribution.conf \
      /usr/lib/wsl/terminal-profile.json /usr/lib/wsl/omarchy.ico && \
    chmod 0755 /etc/oobe.sh

# --- 8. systemd hygiene for WSL ---------------------------------------------
# Mask units that misbehave or are redundant under WSL's networking/init. WSL
# manages /etc/resolv.conf and hosts itself, so resolved/networkd/NM only fight
# it, and the tmpfiles/tmp.mount units error against WSL's mount layout.
#
# systemd-firstboot is critical to mask: it runs on first boot with
# --prompt-locale/--prompt-root-password and blocks for console input that never
# arrives under WSL, wedging the whole boot ("initializing" forever) so dbus,
# logind and the user session never start. Masking it lets boot complete.
#
# Default to multi-user.target: WSL has no boot-time display manager, so
# graphical.target would only try (and fail/hang) to start sddm. Hyprland is
# launched on demand via WSLg instead.
RUN systemctl mask \
      systemd-firstboot.service \
      systemd-resolved.service \
      systemd-networkd.service \
      systemd-networkd.socket \
      NetworkManager.service \
      systemd-tmpfiles-setup.service \
      systemd-tmpfiles-clean.service \
      systemd-tmpfiles-clean.timer \
      systemd-tmpfiles-setup-dev.service \
      systemd-tmpfiles-setup-dev-early.service \
      tmp.mount 2>/dev/null || true && \
    systemctl set-default multi-user.target 2>/dev/null || true

# --- 8b. Locale -------------------------------------------------------------
# Generate en_US.UTF-8 (Omarchy's upstream default) and make it the system
# locale, so interactive shells don't warn "cannot change locale".
RUN sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen && \
    locale-gen && \
    echo 'LANG=en_US.UTF-8' > /etc/locale.conf

# --- 9. Final cleanup -------------------------------------------------------
# Drop the build staging dir. Also try to drop the seeded resolv.conf (WSL
# regenerates its own and shipping one is discouraged) — but it's bind-mounted
# during the build, so removal is best-effort and must not fail the build.
RUN rm -rf /home/$USERNAME/omarchy-wsl && \
    { rm -f /etc/resolv.conf 2>/dev/null || true; }

USER $USERNAME
WORKDIR /home/$USERNAME
ENV OMARCHY_PATH=/home/$USERNAME/.local/share/omarchy
CMD ["/bin/bash", "-l"]
