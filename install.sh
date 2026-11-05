#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Opinuxware contributors
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version. See LICENSE.
#
# Opinuxware installer for Linux
#
# Opiumware is a macOS Roblox executor. On Linux we run the very same macOS
# payload (Roblox.app, libOpiumware.dylib and the Opiumware UI app) through
# Rosemary, the macOS compatibility layer from https://github.com/microlift/rosemary
#
# Educational project. Use the executor only in games you own or are authorized
# to test. See README.md.
#
# Differences from the macOS installer:
#   * No /Applications, codesign, xattr or `open` - apps live in a Rosemary
#     prefix instead.
#   * The macOS "Injector" (insert_dylib) needs _copyfile, which Rosemary does
#     not implement yet, so the LC_LOAD_DYLIB is added by patch_macho() below.
#

set -euo pipefail

INSTALLER_VERSION="1.1.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

CHECK="${GREEN}✔${NC}"
CROSS="${RED}✖${NC}"
INFO="${CYAN}➜${NC}"
WARN="${YELLOW}⚠${NC}"

# ---------------------------------------------------------------------------
# Defaults (override with environment variables or flags)
# ---------------------------------------------------------------------------

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
LOCAL_BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

INSTALL_DIR="${OPINUXWARE_DIR:-$DATA_HOME/opinuxware}"
case "$INSTALL_DIR" in
    /*) ;;
    *) INSTALL_DIR="$PWD/$INSTALL_DIR" ;;
esac
PREFIX_DIR="$INSTALL_DIR/prefix"
APPS_DIR="$PREFIX_DIR/root/Applications"
BIN_DIR="$INSTALL_DIR/bin"

ROSEMARY_VERSION="${ROSEMARY_VERSION:-0.5.0}"
ROBLOX_VERSION="${ROBLOX_VERSION:-version-b09c93298b5d4cd1}"

ROBLOX_URL="${ROBLOX_URL:-https://setup.rbxcdn.com/mac/${ROBLOX_VERSION}-RobloxPlayer.zip}"
DYLIB_URL="${DYLIB_URL:-https://anc4cpypjs.ufs.sh/f/fuloy9zwEAJtGqv6y0IEtxoWaNu8JqLlOAHCfSQnDVgZYhc5}"
RESOURCES_URL="${RESOURCES_URL:-https://zgmwtedvc0.ufs.sh/f/K9MFNpOPhlY1yHbKzpra3Z8vpw0q7b6Wk5TdEzVAcCOr1eDl}"
UI_URL="${UI_URL:-https://anc4cpypjs.ufs.sh/f/fuloy9zwEAJtvE7eVgbncYl7dhxBGyMKF3U4o50piQgtJDnX}"

ROSEMARY_APPIMAGE_URL="${ROSEMARY_APPIMAGE_URL:-https://github.com/microlift/rosemary/releases/download/v${ROSEMARY_VERSION}/Rosemary-${ROSEMARY_VERSION}-x86_64.AppImage}"

# SHA-256 of every download. Use `${VAR-default}` (not `:-`) so an explicit
# empty value disables verification when a URL is overridden locally.
ROBLOX_SHA256="${ROBLOX_SHA256-b0de86196128bd1b778cbadcf1f235887b4917b413d415afc2eb548881d95292}"
DYLIB_SHA256="${DYLIB_SHA256-6b61c53bc1a1668716fa9a5a39d91a55a0828b0c2f253f4f9e070ac36bc621fa}"
RESOURCES_SHA256="${RESOURCES_SHA256-dd5546c647173c2131038723811149605a28762267bb808b2d755debda3078d7}"
UI_SHA256="${UI_SHA256-27f62bf2953b3548aa324d3275050069353cb753ad8f6c841b15c96ea6f21b4c}"
ROSEMARY_APPIMAGE_SHA256="${ROSEMARY_APPIMAGE_SHA256-04fbdae4d1052e2a65fa9442ded5117542da48a6022c36dd5c65e459c3adf108}"

# Guest path where Roblox ends up inside the prefix. This is baked into the
# Mach-O load command, so it must match APPS_DIR's guest spelling.
GUEST_APPS_DIR="/Applications"

LAUNCH=1
USE_BASE=1
MAKE_SHORTCUTS=1
KEEP_TEMP=0
UPDATE_ROSEMARY=0
UNINSTALL=0
ASSUME_YES=0
CUSTOM_ROSEMARY="${OPINUXWARE_ROSEMARY:-}"
ROSEMARY=""
ROSEMARY_PATCHED=0
TEMP=""

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

section() {
    echo
    echo -e "${BOLD}${CYAN}==> $1${NC}"
}

die() {
    echo -e "${RED}${CROSS} $*${NC}" >&2
    exit 1
}

warn() {
    echo -e "${WARN} $*${NC}"
}

run_step() {
    local msg="$1"
    shift

    echo -ne "${CYAN}[...]${NC} $msg\r"

    if "$@"; then
        printf "\r\033[K${GREEN}${CHECK} %s${NC}\n" "$msg"
    else
        printf "\r\033[K${RED}${CROSS} %s${NC}\n" "$msg"
        exit 1
    fi
}

banner() {
    clear 2>/dev/null || true
    echo -e "${BOLD}"
    cat <<'EOF'
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%*=--::=*@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#+-:..........:+@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%@@@@@@@@@@@#+-:..............-+@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%@@@@@%#=-:...:-=+*#%%%#*-.:=*@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@##*=-:.::=*#@@@@@@@@@@@@+-#@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#+-..:-+%@@@@@@@@@@@@@@@@#*@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%+=:.:=*%@@@@@@@@@@@@@@@@@@@+@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*+-.:=*%@@@@@=%@@@@@@@@@@@@@@#@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*+:.-##@@@@@@@@@@#=@@@@@@@@@@@%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%*=::+#%@@@@@@@@@@@@@@*:#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%**==*#@@@@@@@@@@@@@@@@@@@*-:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%#=-*%@@@@@@@@@@@@@@@@@@@@@@%+-+=@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@%#+=*%@@@@@@@@@@@@@@@@@@@@@@@@@++===**#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@%#*=+#@@@@@@@@@@@@@@@@@@@@@@@@@@@=::---=++###%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@##+-*%@@@@@@@@@@@@@@@@@@@%%%##*+=-=------=++===+***+*##%%%%%@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@**-+%%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%%%#*+=-=+++******%%%@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@-+-+%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%#+=+**#*%@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@-=:+%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%***#*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@#.:=*%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%#*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@-:-+%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@*=----@@@@@%##@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@%%%%%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF
    echo -e "${NC}"
    echo -e "${BLUE}=[ Opinuxware (Linux) Installer ]=${NC}"
    echo -e "${CYAN}Opiumware for Linux, powered by Rosemary${NC}"
    echo -e "${CYAN}Original Opiumware by @norbyv1${NC}"
    echo
}

usage() {
    cat <<EOF
Opinuxware installer - Opiumware for Linux, powered by Rosemary

Usage: $0 [OPTIONS]

Options:
  --no-launch          Install only; do not start Roblox/Opiumware afterwards
  --no-base            Do not download the MiniDarwin base into the prefix
  --no-shortcuts       Do not create ~/.local/bin links, desktop entries or ~/Opiumware
  --update-rosemary    Re-download the bundled Rosemary build
  --rosemary PATH      Use an existing Rosemary executable instead of downloading
  --keep-temp          Keep temporary downloads under the install directory
  --uninstall          Remove Opinuxware, its prefix and its shortcuts
  -y, --yes            Do not ask for confirmation (with --uninstall)
  -h, --help           Show this help
  -V, --version        Show the installer version

Environment:
  OPINUXWARE_DIR       Install directory (default: \$XDG_DATA_HOME/opinuxware)
  OPINUXWARE_ROSEMARY  Path to a Rosemary executable (same as --rosemary)
  ROSEMARY_VERSION     Rosemary release to download (default: ${ROSEMARY_VERSION})
  ROBLOX_VERSION       Roblox macOS client version (default: ${ROBLOX_VERSION})
  ROBLOX_URL, DYLIB_URL, RESOURCES_URL, UI_URL
                       Override download URLs
  ROSEMARY_APPIMAGE_URL
                       Override the Rosemary AppImage URL
  ROBLOX_SHA256, DYLIB_SHA256, RESOURCES_SHA256, UI_SHA256,
  ROSEMARY_APPIMAGE_SHA256
                       Override the pinned checksums; an empty value skips that check

Files:
  Install dir          ${INSTALL_DIR}
  Roblox               ${APPS_DIR}/Roblox.app   (guest: /Applications/Roblox.app)
  Roblox (vanilla)     ${APPS_DIR}/RobloxVanilla.app (guest: /Applications/RobloxVanilla.app)
  Opiumware UI         ${APPS_DIR}/Opiumware.app (guest: /Applications/Opiumware.app)
  Opiumware data       <prefix>/root/Users/\$USER/Opiumware (also ~/Opiumware)
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-launch) LAUNCH=0 ;;
            --no-base) USE_BASE=0 ;;
            --no-shortcuts) MAKE_SHORTCUTS=0 ;;
            --update-rosemary) UPDATE_ROSEMARY=1 ;;
            --keep-temp) KEEP_TEMP=1 ;;
            --uninstall) UNINSTALL=1 ;;
            -y|--yes) ASSUME_YES=1 ;;
            --rosemary)
                [ $# -ge 2 ] || die "--rosemary needs a path"
                CUSTOM_ROSEMARY="$2"
                shift
                ;;
            --rosemary=*) CUSTOM_ROSEMARY="${1#*=}" ;;
            -h|--help) usage; exit 0 ;;
            -V|--version) echo "opinuxware-installer $INSTALLER_VERSION"; exit 0 ;;
            *) die "Unknown option: $1 (try --help)" ;;
        esac
        shift
    done
}

# ---------------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------------

guest_home() {
    echo "$PREFIX_DIR/root/Users/$(id -un)"
}

opiumware_home() {
    echo "$(guest_home)/Opiumware"
}

verify_sha256() { # file expected label
    local file="$1" expected="$2" label="$3" actual
    [ -n "$expected" ] || return 0
    actual=$(sha256sum "$file" | cut -d' ' -f1) || return 1
    if [ "$actual" != "$expected" ]; then
        echo "checksum mismatch for $label" >&2
        echo "  expected: $expected" >&2
        echo "  actual:   $actual" >&2
        return 1
    fi
}

fetch() { # url out [sha256] [label]
    local url="$1" out="$2" expected="${3-}" label="${4:-$2}"
    if [ -t 2 ]; then
        curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -# -o "$out" "$url" || return 1
    else
        curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$out" "$url" || return 1
    fi
    verify_sha256 "$out" "$expected" "$label"
}

extract_zip() {
    local zip="$1" dest="$2"
    mkdir -p "$dest"
    if command -v unzip >/dev/null 2>&1; then
        unzip -oq "$zip" -d "$dest"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -m zipfile -e "$zip" "$dest"
    else
        echo "Neither unzip nor python3 is available" >&2
        return 127
    fi
}

cleanup() {
    if [ -n "$TEMP" ] && [ -d "$TEMP" ]; then
        if [ "$KEEP_TEMP" = 1 ]; then
            echo -e "${INFO} Temporary files kept in ${TEMP}"
        else
            rm -rf "$TEMP"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Mach-O LC_LOAD_DYLIB injection
#
# This replaces the macOS "Injector" (a build of insert_dylib). That tool
# imports _copyfile, which Rosemary does not implement (it aborts with
# SIGSEGV on a null import slot), so we add the load command ourselves.
#
# Only 64-bit little-endian Mach-O is handled, which is all Roblox ships.
# The new command is written into the existing header padding, so no offsets
# inside the file need to be rewritten.
# ---------------------------------------------------------------------------

read_u32() { od -An -tu4 -j "$2" -N4 "$1" | tr -d ' \n'; }
read_u64() { od -An -tu8 -j "$2" -N8 "$1" | tr -d ' \n'; }

put_u32() { # file offset value
    local f="$1" o="$2" v="$3"
    printf "\\x$(printf '%02x' $((v & 255)))\\x$(printf '%02x' $(((v >> 8) & 255)))\\x$(printf '%02x' $(((v >> 16) & 255)))\\x$(printf '%02x' $(((v >> 24) & 255)))" \
        | dd of="$f" bs=1 seek="$o" conv=notrunc status=none
}

align8() { echo $(( ($1 + 7) & ~7 )); }

patch_macho() {
    local file="$1" dylib_path="$2"
    local magic ncmds sizeofcmds off cmd size nsects s j fo fs min first
    local path_len cmdsize slack

    [ -f "$file" ] || { echo "missing $file" >&2; return 1; }

    if grep -aqF "$dylib_path" "$file" 2>/dev/null; then
        echo "already loads $dylib_path"
        return 0
    fi

    magic=$(read_u32 "$file" 0)
    if [ "$magic" != "4277009103" ]; then # 0xfeedfacf, MH_MAGIC_64
        echo "not a 64-bit Mach-O (magic=$magic)" >&2
        return 1
    fi

    ncmds=$(read_u32 "$file" 16)
    sizeofcmds=$(read_u32 "$file" 20)
    [ -n "$ncmds" ] && [ -n "$sizeofcmds" ] || return 1

    # Find the first section payload; everything between the end of the load
    # commands and that offset is header padding we may reuse.
    off=32
    min=0
    for ((i = 0; i < ncmds; i++)); do
        cmd=$(read_u32 "$file" "$off")
        size=$(read_u32 "$file" $((off + 4)))
        [ -n "$cmd" ] && [ -n "$size" ] && [ "$size" -ge 8 ] || return 1

        if [ "$cmd" -eq 25 ]; then # LC_SEGMENT_64
            nsects=$(read_u32 "$file" $((off + 64)))
            s=$((off + 72))
            for ((j = 0; j < nsects; j++)); do
                fo=$(read_u32 "$file" $((s + j * 80 + 48)))
                fs=$(read_u64 "$file" $((s + j * 80 + 40)))
                if [ "$fo" -gt 0 ] && [ "$fs" -gt 0 ]; then
                    if [ "$min" -eq 0 ] || [ "$fo" -lt "$min" ]; then
                        min=$fo
                    fi
                fi
            done
        fi

        off=$((off + size))
    done

    first=$((32 + sizeofcmds))
    if [ "$min" -le "$first" ]; then
        echo "no room for a new load command (commands end at $first, data at $min)" >&2
        return 1
    fi

    path_len=${#dylib_path}
    cmdsize=$(align8 $((24 + path_len + 1)))
    slack=$((min - first))
    if [ "$cmdsize" -gt "$slack" ]; then
        echo "not enough header padding: need $cmdsize bytes, have $slack" >&2
        return 1
    fi

    # struct dylib_command: cmd, cmdsize, name offset, timestamp, versions.
    put_u32 "$file" 16 $((ncmds + 1)) || return 1
    put_u32 "$file" 20 $((sizeofcmds + cmdsize)) || return 1
    put_u32 "$file" "$first" 12 || return 1            # LC_LOAD_DYLIB
    put_u32 "$file" $((first + 4)) "$cmdsize" || return 1
    put_u32 "$file" $((first + 8)) 24 || return 1
    put_u32 "$file" $((first + 12)) 0 || return 1
    put_u32 "$file" $((first + 16)) 0 || return 1
    put_u32 "$file" $((first + 20)) 0 || return 1

    printf '%s' "$dylib_path" | dd of="$file" bs=1 seek=$((first + 24)) conv=notrunc status=none || return 1
    dd if=/dev/zero bs=1 count=$((cmdsize - 24 - path_len)) \
        of="$file" seek=$((first + 24 + path_len)) conv=notrunc status=none || return 1

    echo "added LC_LOAD_DYLIB for $dylib_path"
}

# ---------------------------------------------------------------------------
# Preflight and Rosemary bootstrap
# ---------------------------------------------------------------------------

preflight() {
    [ "$(uname -s)" = "Linux" ] || die "This installer targets Linux only."

    command -v curl >/dev/null 2>&1 || die "curl is required."
    if [ -n "$ROBLOX_SHA256$DYLIB_SHA256$RESOURCES_SHA256$UI_SHA256$ROSEMARY_APPIMAGE_SHA256" ]; then
        command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required to verify downloads."
    fi
    if ! command -v unzip >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
        die "Either unzip or python3 is required to extract the downloads."
    fi
    command -v dd >/dev/null 2>&1 || die "dd is required."
    command -v od >/dev/null 2>&1 || die "od is required."
    command -v mktemp >/dev/null 2>&1 || die "mktemp is required."

    mkdir -p "$INSTALL_DIR"
    : > "$INSTALL_DIR/.opinuxware"
    TEMP="$(mktemp -d "$INSTALL_DIR/.tmp.XXXXXX")"
    trap cleanup EXIT

    case "$(uname -m)" in
        x86_64|amd64) ;;
        *)
            if [ -z "$CUSTOM_ROSEMARY" ] && ! command -v rosemary >/dev/null 2>&1; then
                die "Prebuilt Rosemary releases are x86-64 only, and this host is $(uname -m).
  Install Rosemary for your architecture first (Nix: 'nix run github:microlift/rosemary'),
  then re-run with: $0 --rosemary /path/to/rosemary"
            fi
            ;;
    esac
}

rosemary_is_current() {
    [ -x "$INSTALL_DIR/rosemary/AppRun" ] || return 1
    [ "$UPDATE_ROSEMARY" = 0 ] || return 1
    [ "$(cat "$INSTALL_DIR/rosemary/.version" 2>/dev/null || true)" = "$ROSEMARY_VERSION" ]
}

download_rosemary() {
    local appimage="$TEMP/Rosemary.AppImage"

    fetch "$ROSEMARY_APPIMAGE_URL" "$appimage" "$ROSEMARY_APPIMAGE_SHA256" "Rosemary AppImage" || return 1
    chmod +x "$appimage" || return 1

    rm -rf "$TEMP/rosemary" || return 1
    mkdir -p "$TEMP/rosemary" || return 1
    ( cd "$TEMP/rosemary" && "$appimage" --appimage-extract >/dev/null ) || return 1

    [ -x "$TEMP/rosemary/squashfs-root/AppRun" ] || {
        echo "Rosemary AppImage did not extract as expected" >&2
        return 1
    }

    rm -rf "$INSTALL_DIR/rosemary" || return 1
    mv "$TEMP/rosemary/squashfs-root" "$INSTALL_DIR/rosemary" || return 1
    echo "$ROSEMARY_VERSION" > "$INSTALL_DIR/rosemary/.version"

    "$INSTALL_DIR/rosemary/AppRun" --version >/dev/null 2>&1 || {
        echo "The extracted Rosemary build does not run on this system" >&2
        return 1
    }
}

resolve_rosemary() {
    local installed="$INSTALL_DIR/rosemary-patched/rosemary"

    if [ -d "$INSTALL_DIR/rosemary-patched" ] && [ ! -e "$installed" ]; then
        warn "Ignoring $installed: the patched Rosemary it pointed at is gone."
    fi

    if [ -n "$CUSTOM_ROSEMARY" ]; then
        [ -x "$CUSTOM_ROSEMARY" ] || die "Rosemary is not executable: $CUSTOM_ROSEMARY"
        ROSEMARY="$(cd "$(dirname "$CUSTOM_ROSEMARY")" && pwd)/$(basename "$CUSTOM_ROSEMARY")"
        # Keep the patched build at a stable path, so later re-runs and the
        # launchers use it instead of the bundled stock release. A path inside
        # the store directory is already where it belongs.
        case "$ROSEMARY" in
            "$installed"|"$installed"/*) ;;
            *)
                mkdir -p "$INSTALL_DIR/rosemary-patched" || return 1
                ln -sfn "$ROSEMARY" "$installed" || return 1
                ROSEMARY="$installed"
                ;;
        esac
        ROSEMARY_PATCHED=1
        echo -e "${INFO} Using patched Rosemary at ${BOLD}$ROSEMARY${NC}"
        return
    fi

    if [ -x "$installed" ] && [ "$UPDATE_ROSEMARY" = 0 ]; then
        ROSEMARY="$installed"
        ROSEMARY_PATCHED=1
        echo -e "${INFO} Using previously installed patched Rosemary${NC}"
        return
    fi

    if rosemary_is_current; then
        ROSEMARY="$INSTALL_DIR/rosemary/AppRun"
        echo -e "${INFO} Using bundled Rosemary ${ROSEMARY_VERSION}"
        return
    fi

    if command -v rosemary >/dev/null 2>&1 && [ "$UPDATE_ROSEMARY" = 0 ]; then
        ROSEMARY="$(command -v rosemary)"
        echo -e "${INFO} Using system Rosemary at ${BOLD}$ROSEMARY${NC}"
        return
    fi

    section "Installing Rosemary"
    echo -e "${INFO} Rosemary ${BOLD}${ROSEMARY_VERSION}${NC} (~127 MB, one time)"
    run_step "Downloading Rosemary ${ROSEMARY_VERSION}" download_rosemary
    ROSEMARY="$INSTALL_DIR/rosemary/AppRun"
}

prefix_arch_flags() {
    if [ "$(uname -m)" = "x86_64" ] || [ "$(uname -m)" = "amd64" ]; then
        return 0
    fi
    # The Roblox client is x86-64, so ask for an x86-64 Darwin base.
    printf '%s\n' "--arch" "x86_64"
}

create_prefix() {
    local -a flags=()
    local flag
    while IFS= read -r flag; do
        [ -n "$flag" ] && flags+=("$flag")
    done < <(prefix_arch_flags)

    if [ "$USE_BASE" = 1 ]; then
        if [ "${#flags[@]}" -gt 0 ]; then
            ROSEMARY_PREFIX_SETUP=download "$ROSEMARY" prefix create "$PREFIX_DIR" "${flags[@]}" || return 1
        else
            ROSEMARY_PREFIX_SETUP=download "$ROSEMARY" prefix create "$PREFIX_DIR" || return 1
        fi
    else
        if [ "${#flags[@]}" -gt 0 ]; then
            "$ROSEMARY" prefix create "$PREFIX_DIR" "${flags[@]}" --no-base || return 1
        else
            "$ROSEMARY" prefix create "$PREFIX_DIR" --no-base || return 1
        fi
    fi
}

ensure_prefix() {
    if [ -d "$PREFIX_DIR/root/Applications" ]; then
        return 0
    fi
    run_step "Creating Rosemary prefix" create_prefix
}

# ---------------------------------------------------------------------------
# Installation steps
# ---------------------------------------------------------------------------

kill_running() {
    local pid
    if command -v fuser >/dev/null 2>&1; then
        fuser -k 9002/tcp >/dev/null 2>&1 || true
    fi

    # Kill only processes that run inside this prefix. Matching on the guest
    # path with `pkill -f` is unsafe: an unrelated shell (or this installer's
    # own command line) can contain the same string.
    for pid in /proc/[0-9]*; do
        pid="${pid#/proc/}"
        [ "$pid" = "$$" ] && continue
        [ "$pid" = "${PPID:-0}" ] && continue
        [ -O "/proc/$pid" ] || continue
        [ -r "/proc/$pid/environ" ] || continue
        if ( tr '\0' '\n' < "/proc/$pid/environ" ) 2>/dev/null \
            | grep -qxF "ROSEMARY_PREFIX=$PREFIX_DIR"; then
            kill -9 "$pid" >/dev/null 2>&1 || true
        fi
    done
    return 0
}

remove_old_install() {
    rm -rf "$APPS_DIR/Roblox.app" || return 1
    rm -rf "$APPS_DIR/RobloxVanilla.app" || return 1
    rm -rf "$APPS_DIR/Opiumware.app" || return 1
    rm -rf "$(opiumware_home)/modules/decompiler" || return 1
    rm -rf "$(opiumware_home)/modules/LuauLSP" || return 1
    rm -f "$(opiumware_home)/modules/update.json" || return 1
}

install_roblox() {
    fetch "$ROBLOX_URL" "$TEMP/RobloxPlayer.zip" "$ROBLOX_SHA256" "Roblox" || return 1
    extract_zip "$TEMP/RobloxPlayer.zip" "$TEMP" || return 1

    [ -d "$TEMP/RobloxPlayer.app" ] || {
        echo "RobloxPlayer.app is missing from the downloaded archive" >&2
        return 1
    }

    rm -rf "$APPS_DIR/Roblox.app" || return 1
    mv "$TEMP/RobloxPlayer.app" "$APPS_DIR/Roblox.app" || return 1

    # The macOS installer removes these so Roblox cannot reinstall/update
    # itself over the patched build.
    rm -rf "$APPS_DIR/Roblox.app/Contents/MacOS/RobloxPlayerInstaller.app" || return 1
    rm -rf "$APPS_DIR/Roblox.app/Contents/MacOS/RobloxMenuBar.app" || return 1

    # Keep a pristine bundle for the vanilla launcher. Only Roblox.app is
    # patched and gets libOpiumware.dylib, so vanilla Roblox stays untouched.
    rm -rf "$APPS_DIR/RobloxVanilla.app" || return 1
    cp -a "$APPS_DIR/Roblox.app" "$APPS_DIR/RobloxVanilla.app" || return 1

    chmod +x "$APPS_DIR/Roblox.app/Contents/MacOS/RobloxPlayer" 2>/dev/null || true
    chmod +x "$APPS_DIR/Roblox.app/Contents/MacOS/RobloxCrashHandler" 2>/dev/null || true
    chmod +x "$APPS_DIR/Roblox.app/Contents/MacOS/libmimalloc.3.dylib" 2>/dev/null || true
    chmod +x "$APPS_DIR/RobloxVanilla.app/Contents/MacOS/RobloxPlayer" 2>/dev/null || true
    chmod +x "$APPS_DIR/RobloxVanilla.app/Contents/MacOS/RobloxCrashHandler" 2>/dev/null || true

    [ -f "$APPS_DIR/Roblox.app/Contents/MacOS/libmimalloc.3.dylib" ] || {
        echo "libmimalloc.3.dylib not found; this Roblox build is not supported" >&2
        return 1
    }
}

install_dylib() {
    fetch "$DYLIB_URL" "$TEMP/lib.zip" "$DYLIB_SHA256" "libOpiumware" || return 1
    extract_zip "$TEMP/lib.zip" "$TEMP/lib" || return 1

    [ -f "$TEMP/lib/libOpiumware.dylib" ] || {
        echo "libOpiumware.dylib is missing from the downloaded archive" >&2
        return 1
    }

    mkdir -p "$APPS_DIR/Roblox.app/Contents/Resources" || return 1
    mv -f "$TEMP/lib/libOpiumware.dylib" "$APPS_DIR/Roblox.app/Contents/Resources/libOpiumware.dylib" || return 1
}

patch_roblox() {
    patch_macho \
        "$APPS_DIR/Roblox.app/Contents/MacOS/libmimalloc.3.dylib" \
        "$GUEST_APPS_DIR/Roblox.app/Contents/Resources/libOpiumware.dylib"
}

install_ui() {
    fetch "$UI_URL" "$TEMP/ui.zip" "$UI_SHA256" "Opiumware UI" || return 1
    extract_zip "$TEMP/ui.zip" "$TEMP/ui" || return 1

    [ -d "$TEMP/ui/Opiumware.app" ] || {
        echo "Opiumware.app is missing from the downloaded archive" >&2
        return 1
    }

    rm -rf "$APPS_DIR/Opiumware.app" || return 1
    mv "$TEMP/ui/Opiumware.app" "$APPS_DIR/Opiumware.app" || return 1
    chmod +x "$APPS_DIR/Opiumware.app/Contents/MacOS/Opiumware" 2>/dev/null || true
}

install_modules() {
    local home_dir
    home_dir="$(opiumware_home)"

    fetch "$RESOURCES_URL" "$TEMP/modules.zip" "$RESOURCES_SHA256" "Opiumware resources" || return 1
    extract_zip "$TEMP/modules.zip" "$TEMP/res" || return 1

    [ -f "$TEMP/res/Resources/Decompiler" ] || {
        echo "Resources/Decompiler is missing from the downloaded archive" >&2
        return 1
    }
    [ -f "$TEMP/res/Resources/LuauLSP" ] || {
        echo "Resources/LuauLSP is missing from the downloaded archive" >&2
        return 1
    }

    mkdir -p "$home_dir"/workspace \
             "$home_dir"/autoexec \
             "$home_dir"/themes \
             "$home_dir"/modules/decompiler \
             "$home_dir"/modules/LuauLSP || return 1

    mv -f "$TEMP/res/Resources/Decompiler" "$home_dir/modules/decompiler/Decompiler" || return 1
    mv -f "$TEMP/res/Resources/LuauLSP" "$home_dir/modules/LuauLSP/LuauLSP" || return 1
    chmod +x "$home_dir/modules/decompiler/Decompiler" 2>/dev/null || true
    chmod +x "$home_dir/modules/LuauLSP/LuauLSP" 2>/dev/null || true
}

write_launcher_pair() {
    local name="$1" bundle="$2"
    cat > "$BIN_DIR/$name" <<EOF
#!/usr/bin/env bash
# Generated by the Opinuxware installer.
set -euo pipefail
export ROSEMARY_PREFIX="$PREFIX_DIR"
export ROSEMARY_PREFIX_HOME=prefix
exec "$ROSEMARY" "$GUEST_APPS_DIR/$bundle" "\$@"
EOF
    chmod +x "$BIN_DIR/$name"
}

write_launchers() {
    mkdir -p "$BIN_DIR" || return 1
    write_launcher_pair opinuxware Opiumware.app || return 1
    write_launcher_pair opinuxware-roblox Roblox.app || return 1
    write_launcher_pair opinuxware-roblox-vanilla RobloxVanilla.app || return 1

    if [ "$MAKE_SHORTCUTS" = 1 ]; then
        mkdir -p "$LOCAL_BIN" "$DESKTOP_DIR" || return 1
        ln -sf "$BIN_DIR/opinuxware" "$LOCAL_BIN/opinuxware" || return 1
        ln -sf "$BIN_DIR/opinuxware-roblox" "$LOCAL_BIN/opinuxware-roblox" || return 1
        ln -sf "$BIN_DIR/opinuxware-roblox-vanilla" "$LOCAL_BIN/opinuxware-roblox-vanilla" || return 1

        # Convenience link, so scripts can be edited at the familiar macOS path.
        if [ ! -e "$HOME/Opiumware" ] && [ ! -L "$HOME/Opiumware" ]; then
            ln -s "$(opiumware_home)" "$HOME/Opiumware" || true
        elif [ -L "$HOME/Opiumware" ] && \
             [ "$(readlink -f "$HOME/Opiumware" 2>/dev/null || true)" = "$(opiumware_home)" ]; then
            : # already points at this install
        else
            warn "$HOME/Opiumware already exists and was left alone."
            warn "Scripts for this install are in $(opiumware_home)"
        fi

        cat > "$DESKTOP_DIR/opinuxware.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Opinuxware
Comment=Roblox executor for Linux (Opiumware on Rosemary)
Exec="$BIN_DIR/opinuxware"
Icon=applications-games
Terminal=false
Categories=Game;Utility;
StartupWMClass=Opiumware
EOF

        cat > "$DESKTOP_DIR/opinuxware-roblox.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Roblox (Opinuxware)
Comment=Roblox through Rosemary with the Opiumware library loaded
Exec="$BIN_DIR/opinuxware-roblox"
Icon=applications-games
Terminal=false
Categories=Game;
StartupWMClass=RobloxPlayer
EOF

        cat > "$DESKTOP_DIR/opinuxware-roblox-vanilla.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Roblox (Vanilla)
Comment=Unmodified Roblox through Rosemary, without the Opiumware library
Exec="$BIN_DIR/opinuxware-roblox-vanilla"
Icon=applications-games
Terminal=false
Categories=Game;
StartupWMClass=RobloxPlayer
EOF

        chmod +x "$DESKTOP_DIR/opinuxware.desktop" \
                 "$DESKTOP_DIR/opinuxware-roblox.desktop" \
                 "$DESKTOP_DIR/opinuxware-roblox-vanilla.desktop" || true
        if command -v update-desktop-database >/dev/null 2>&1; then
            update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
        fi
    fi
}

launch_apps() {
    [ "$LAUNCH" = 1 ] || return 0
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        warn "No graphical session detected; skipping automatic launch."
        return 0
    fi

    # The executor needs API shims that stock Rosemary lacks; a build passed
    # with --rosemary is assumed to have them. Otherwise vanilla is the only
    # bundle that runs.
    if [ "$ROSEMARY_PATCHED" = 1 ]; then
        echo -e "${INFO} Starting Roblox with the Opiumware library..."
        nohup "$BIN_DIR/opinuxware-roblox" >"$INSTALL_DIR/launch.log" 2>&1 &
        disown || true
        return 0
    fi

    warn "Stock Rosemary lacks the executor's Security APIs; starting vanilla Roblox."
    echo -e "${INFO} Build a patched Rosemary (see README) and reinstall with:"
    echo -e "         ${BOLD}./install.sh --rosemary /path/to/rosemary${NC}"
    nohup "$BIN_DIR/opinuxware-roblox-vanilla" >"$INSTALL_DIR/launch.log" 2>&1 &
    disown || true
    return 0
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

uninstall() {
    case "$INSTALL_DIR" in
        /|"$HOME"|"$HOME/"|"") die "Refusing to remove $INSTALL_DIR" ;;
    esac
    if [ -e "$INSTALL_DIR" ] && [ ! -e "$INSTALL_DIR/.opinuxware" ]; then
        die "Refusing to remove $INSTALL_DIR: it was not created by this installer."
    fi

    section "Uninstalling Opinuxware"
    echo -e "${INFO} This removes ${BOLD}${INSTALL_DIR}${NC} (including the Rosemary prefix)."

    if [ "$ASSUME_YES" != 1 ]; then
        local answer=""
        read -r -p "Continue? [y/N] " answer || true
        case "$answer" in
            y|Y|yes|YES) ;;
            *) echo "Cancelled."; exit 0 ;;
        esac
    fi

    kill_running

    rm -f "$DESKTOP_DIR/opinuxware.desktop" \
          "$DESKTOP_DIR/opinuxware-roblox.desktop" \
          "$DESKTOP_DIR/opinuxware-roblox-vanilla.desktop"

    local link target
    for link in opinuxware opinuxware-roblox opinuxware-roblox-vanilla; do
        if [ -L "$LOCAL_BIN/$link" ] && \
           [ "$(readlink -f "$LOCAL_BIN/$link" 2>/dev/null || true)" = "$BIN_DIR/$link" ]; then
            rm -f "$LOCAL_BIN/$link"
        fi
    done

    if [ -L "$HOME/Opiumware" ]; then
        target="$(readlink -f "$HOME/Opiumware" 2>/dev/null || true)"
        case "$target" in
            "$INSTALL_DIR"/*) rm -f "$HOME/Opiumware" ;;
        esac
    fi

    rm -rf "$INSTALL_DIR"
    echo -e "${GREEN}${CHECK} Opinuxware removed${NC}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    parse_args "$@"
    banner

    if [ "$UNINSTALL" = 1 ]; then
        uninstall
        exit 0
    fi

    preflight

    resolve_rosemary
    ensure_prefix

    section "Removing old installs"
    run_step "Killing running processes" kill_running
    run_step "Removing previous Roblox and Opiumware" remove_old_install

    section "Fetching client version"
    echo -e "${INFO} Roblox: ${BOLD}$ROBLOX_VERSION${NC}"
    echo -e "${INFO} Rosemary: ${BOLD}$("$ROSEMARY" --version 2>/dev/null | head -n1 || echo unknown)${NC}"

    section "Downloading Roblox"
    echo -e "${INFO} macOS Intel build, ~150 MB"
    run_step "Downloading and unpacking Roblox" install_roblox

    section "Installing Opiumware"
    run_step "Installing libOpiumware.dylib" install_dylib
    run_step "Patching Roblox to load the library" patch_roblox
    run_step "Installing Opiumware UI" install_ui
    run_step "Installing decompiler and LuauLSP" install_modules
    run_step "Creating launchers and shortcuts" write_launchers

    echo
    echo -e "${GREEN}${BOLD}Installation complete.${NC}"
    echo
    echo -e "  ${INFO} Installed in:   ${BOLD}${INSTALL_DIR}${NC}"
    echo -e "  ${INFO} Launch UI:      ${BOLD}${BIN_DIR}/opinuxware${NC}"
    echo -e "  ${INFO} Launch Roblox:  ${BOLD}${BIN_DIR}/opinuxware-roblox${NC}"
    echo -e "  ${INFO} Vanilla Roblox: ${BOLD}${BIN_DIR}/opinuxware-roblox-vanilla${NC}"
    if [ "$MAKE_SHORTCUTS" = 1 ]; then
        echo -e "  ${INFO} Scripts:        ${BOLD}$(opiumware_home)/autoexec${NC} (also ~/Opiumware)"
    else
        echo -e "  ${INFO} Scripts:        ${BOLD}$(opiumware_home)/autoexec${NC}"
    fi
    echo -e "  ${INFO} Logs:           ${BOLD}${INSTALL_DIR}/launch.log${NC}"
    if [ "$MAKE_SHORTCUTS" = 1 ]; then
        case ":$PATH:" in
            *":$LOCAL_BIN:"*) ;;
            *) warn "$LOCAL_BIN is not in PATH; use the full paths above or add it." ;;
        esac
    fi
    echo
    echo -e "${WARN} Opiumware is a macOS build running through Rosemary; some features"
    echo -e "  may break as Rosemary's macOS coverage changes. See README.md."
    echo

    launch_apps
}

main "$@"
