#!/bin/sh
# Sims Saver installer for Linux and macOS.
#
#   curl -fsSL https://sims-saver.nix.uno/install.sh | sh
#
# Installs for the current user only (no sudo): ~/.local on Linux,
# ~/Applications on macOS, a user Flatpak on Steam Deck.
#
# Options (as environment variables or flags):
#   SIMS_SAVER_VERSION=v0.1.0 / --version v0.1.0   install a specific release
#   --system      Linux: install the .deb/.rpm system-wide via the package
#                 manager instead (needs sudo; in-app updates then go
#                 through the package manager too)
#   --flatpak     Linux: install the Flatpak bundle (default on Steam Deck)
#   --no-launch   do not start the app afterwards
#   SIMS_SAVER_BASE_URL=https://mirror/...   fetch assets from a directory elsewhere
#
# Downloads are verified against the release's checksums.txt.
set -eu

SITE="https://sims-saver.nix.uno"
VERSION="${SIMS_SAVER_VERSION:-}"
SYSTEM_INSTALL=0
FLATPAK=0
LAUNCH=1

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift ;;
    --system) SYSTEM_INSTALL=1 ;;
    --user) SYSTEM_INSTALL=0 ;; # accepted for compatibility; user-level is the default
    --flatpak) FLATPAK=1 ;;
    --no-launch) LAUNCH=0 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required"; }

need curl
OS=$(uname -s)
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH=amd64 ;;
  arm64|aarch64) ARCH=arm64 ;;
  *) die "unsupported architecture: $ARCH" ;;
esac

# Resolve the version.
if [ -z "$VERSION" ] && [ -n "${SIMS_SAVER_BASE_URL:-}" ]; then
  die "SIMS_SAVER_BASE_URL needs --version (or SIMS_SAVER_VERSION) as well"
fi
if [ -z "$VERSION" ]; then
  VERSION=$(curl -fsSL "$SITE/latest-version.txt" | tr -d '[:space:]')
  [ -n "$VERSION" ] || die "could not determine the latest release from $SITE"
fi
VER=${VERSION#v}
BASE="${SIMS_SAVER_BASE_URL:-$SITE/releases/$VERSION}"
say "Installing Sims Saver $VERSION"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

fetch() { # fetch <asset>
  say "Downloading $1"
  curl -fsSL -o "$1" "$BASE/$1" || die "download failed: $BASE/$1"
}

verify() { # verify <asset>
  [ -f checksums.txt ] || fetch checksums.txt
  want=$(grep " \*\{0,1\}$1\$" checksums.txt | cut -d' ' -f1)
  [ -n "$want" ] || die "no checksum listed for $1"
  if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum "$1" | cut -d' ' -f1)
  else got=$(shasum -a 256 "$1" | cut -d' ' -f1); fi
  [ "$got" = "$want" ] || die "checksum mismatch for $1"
  say "Verified $1"
}

install_linux_deb() {
  asset="sims-saver_${VER}_${ARCH}.deb"
  fetch "$asset"; verify "$asset"
  say "Installing package (sudo)"
  sudo apt-get install -y "./$asset"
}

install_linux_rpm() {
  case "$ARCH" in amd64) rarch=x86_64 ;; arm64) rarch=aarch64 ;; esac
  asset="sims-saver-${VER}-1.${rarch}.rpm"
  fetch "$asset"; verify "$asset"
  say "Installing package (sudo)"
  if command -v dnf >/dev/null 2>&1; then sudo dnf install -y "./$asset"
  elif command -v zypper >/dev/null 2>&1; then sudo zypper --non-interactive install "./$asset"
  else sudo rpm -Uvh "./$asset"; fi
}

install_linux_user() {
  asset="sims-saver_${VER}_linux_${ARCH}.tar.gz"
  fetch "$asset"; verify "$asset"
  bin="$HOME/.local/bin"; apps="$HOME/.local/share/applications"; icons="$HOME/.local/share/icons"
  mkdir -p "$bin" "$apps" "$icons"
  tar -xzf "$asset" -C "$bin" ./sims-saver 2>/dev/null || tar -xzf "$asset" -C "$bin" sims-saver
  chmod 755 "$bin/sims-saver"
  # Icons in the user's hicolor theme, where GNOME and KDE look for them.
  if tar -tzf "$asset" | grep -q '^\./icons/'; then
    tar -xzf "$asset" -C "$icons" --strip-components=2 ./icons
  else
    mkdir -p "$icons/hicolor/256x256/apps"
    curl -fsSL "$SITE/icon.png" -o "$icons/hicolor/256x256/apps/sims-saver.png" 2>/dev/null || true
  fi
  touch "$icons/hicolor" 2>/dev/null || true
  cat > "$apps/sims-saver.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Sims Saver
Comment=Sync Sims saves, tray and mods to your cloud storage
Exec=$bin/sims-saver
Icon=sims-saver
Terminal=false
Categories=Utility;
StartupWMClass=sims-saver
DESKTOP
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$apps" 2>/dev/null || true
  say "Installed to $bin/sims-saver"
  case ":$PATH:" in *":$bin:"*) ;; *) say "Note: $bin is not on your PATH; the app menu entry still works." ;; esac
  if ! ldconfig -p 2>/dev/null | grep -q libwebkit2gtk-4.1; then
    say "Note: Sims Saver needs libwebkit2gtk-4.1 and GTK 3 — e.g. sudo apt install libwebkit2gtk-4.1-0 (Debian/Ubuntu) or sudo dnf install webkit2gtk4.1 (Fedora). Or rerun with --system to let the package manager pull them in."
  fi
  LAUNCH_CMD="$bin/sims-saver"
}

install_linux_flatpak() {
  need flatpak
  asset="sims-saver_${VER}_linux_${ARCH}.flatpak"
  fetch "$asset"; verify "$asset"
  say "Installing Flatpak (user)"
  flatpak install --user -y --noninteractive "./$asset"
  LAUNCH_CMD="flatpak run uno.nix.sims-saver"
}

install_macos() {
  asset="sims-saver_${VER}_macos_universal.dmg"
  fetch "$asset"; verify "$asset"
  say "Mounting image"
  mount=$(hdiutil attach -nobrowse -readonly -noautoopen "$asset" | awk -F'\t' '/\/Volumes\//{print $NF}' | head -n1)
  [ -n "$mount" ] || die "could not mount $asset"
  # User-level by default; the app can update itself there. Pass --system
  # to install for all users into /Applications.
  dest="$HOME/Applications"
  [ "$SYSTEM_INSTALL" = 1 ] && dest="/Applications"
  mkdir -p "$dest" 2>/dev/null || true
  [ -w "$dest" ] || die "$dest is not writable; rerun with sudo or without --system"
  say "Copying to $dest"
  rm -rf "$dest/Sims Saver.app"
  cp -R "$mount/Sims Saver.app" "$dest/"
  hdiutil detach "$mount" -quiet || true
  # Releases from 0.3.4 on are signed and notarized. Older ones were not;
  # only for those, clear the quarantine flag so Gatekeeper lets them open.
  if ! spctl -a -t exec "$dest/Sims Saver.app" >/dev/null 2>&1; then
    xattr -dr com.apple.quarantine "$dest/Sims Saver.app" 2>/dev/null || true
  fi
  say "Installed $dest/Sims Saver.app"
  LAUNCH_CMD="open -a \"$dest/Sims Saver.app\""
}

LAUNCH_CMD=""
case "$OS" in
  Darwin) install_macos ;;
  Linux)
    os_id=$(. /etc/os-release 2>/dev/null && echo "${ID:-}")
    if [ "$FLATPAK" = 1 ] || [ "$os_id" = steamos ]; then install_linux_flatpak
    elif [ "$SYSTEM_INSTALL" = 1 ]; then
      if command -v dpkg >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then install_linux_deb; LAUNCH_CMD="sims-saver"
      elif command -v rpm >/dev/null 2>&1; then install_linux_rpm; LAUNCH_CMD="sims-saver"
      else die "--system needs apt or rpm; run without it for a user-level install"; fi
    else install_linux_user; fi
    ;;
  *) die "unsupported OS: $OS" ;;
esac

say "Done. Sims Saver runs in the system tray; it will walk you through setup on first launch."
if [ "$LAUNCH" = 1 ] && [ -n "$LAUNCH_CMD" ] && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ] || [ "$OS" = Darwin ]; }; then
  say "Launching"
  cd "$HOME"
  eval "nohup $LAUNCH_CMD >/dev/null 2>&1 &"
fi
