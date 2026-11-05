# AGENTS.md

Notes for maintainers (human or AI) working on Opinuxware.

## What this project is

A Linux port of the Opiumware macOS installer. The script does not reimplement
Opiumware; it downloads the original macOS payload and runs it through
[Rosemary](https://github.com/microlift/rosemary), a macOS compatibility layer
and x86-64 emulator.

There is no application code here. `install.sh` is the whole product, and
`README.md` is user documentation. Keep them in sync when behaviour changes.

This is an educational project. Its intended use is own/authorized games, and
its stated position is that anti-cheat belongs server-side. Keep that framing in
user-facing text; do not present it as a cheating tool.

The project is GPL-3.0-or-later; see `LICENSE`.

## Runtime choice: Rosemary, not Darling

Rosemary was chosen after evaluating Darling. Darling's own documentation says
GUI applications do not work ("very few exceptions", "any complex GUI
application in general will not work"), its known-working list is CLI tools and
a calculator, and it ships Debian-only packages. Rosemary already runs vanilla
Roblox, reimplements AppKit over SDL3, translates Metal to Vulkan, and publishes
x86-64 releases plus a Nix flake.

Do not add a second runtime or Darling support without a concrete reason and a
test that it runs the Roblox client. If someone proposes it, point at
`docs.darlinghq.org/known-nonfunctional-software.html` and the current
`README.md` comparison.

## Non-negotiables

- **Linux only.** Do not reintroduce macOS commands (`codesign`, `xattr`,
  `/Applications`, `open`, `killall`, `lsof`, `launchctl`, `hdiutil`).
- **The guest is macOS.** Apps run inside a Rosemary prefix. Anything passed to
  Rosemary as an app to launch must use the guest path (`/Applications/...`),
  not the host path. File arguments for host-side tools are the opposite: use
  host paths (see the injection note below).
- **Do not use the macOS Injector under Rosemary.** `Resources/Injector` is a
  build of `insert_dylib` and imports `_copyfile`; Rosemary does not implement
  it, so the process dies with `SIGSEGV at 0x0` on the null import slot. The
  installer patches the Mach-O itself in `patch_macho()`.
- **Keep the injected path in sync with the install layout.** The `LC_LOAD_DYLIB`
  string is `/Applications/Roblox.app/Contents/Resources/libOpiumware.dylib`.
  If `GUEST_APPS_DIR` or the app name changes, update both the patch call and
  the launchers.
- **Do not commit downloaded payloads or extracted apps.** Everything is fetched
  at install time from the URLs at the top of `install.sh`.
- **Warn about ToS/account risk** in user-facing docs. Do not present this as
  officially supported by Roblox, Opiumware or Rosemary.
- **License:** GPL-3.0-or-later. Do not relicense the project or add code that
  cannot be distributed under the GPL. Distributed forks must stay open source.
  The Rosemary patch follows Rosemary's GPL-3.0.
- **Educational framing:** keep the README's intended-use statement (own or
  authorized games) and the server-side anti-cheat rationale. Do not advertise
  or optimize the project for cheating in other games.

## Layout created at install time

```text
~/.local/share/opinuxware/                  # OPINUXWARE_DIR / XDG_DATA_HOME
├── bin/opinuxware                          # launcher for the UI
├── bin/opinuxware-roblox                   # launcher for Roblox + Opiumware
├── bin/opinuxware-roblox-vanilla           # launcher for unmodified Roblox
├── rosemary/AppRun                         # extracted Rosemary AppImage
└── prefix/                                 # ROSEMARY_PREFIX
    └── root/
        ├── Applications/
        │   ├── Roblox.app/                 # guest /Applications/Roblox.app (patched)
        │   ├── RobloxVanilla.app/          # guest /Applications/RobloxVanilla.app
        │   └── Opiumware.app/              # guest /Applications/Opiumware.app
        └── Users/$USER/Opiumware/          # guest ~/Opiumware
```

`RobloxVanilla.app` is a pristine copy made **before** `libOpiumware.dylib` is
installed and `libmimalloc.3.dylib` is patched. Do not patch it, and do not
point the Opiumware launcher at it. `$HOME/Opiumware` is a symlink to the guest
home copy, so users can edit autoexec files at the familiar macOS path. The
launchers export `ROSEMARY_PREFIX` and `ROSEMARY_PREFIX_HOME=prefix`.

## Installer flow

1. `parse_args` — flags and env overrides.
2. `preflight` — OS/arch/dependency checks; creates a temp dir **inside the
   install dir** (avoids noexec `/tmp`).
3. `resolve_rosemary` — custom path → installed AppImage → system `rosemary` →
   download a pinned AppImage release and extract it with
   `--appimage-extract`. Extraction needs no FUSE.
4. `ensure_prefix` — `rosemary prefix create` unless the prefix exists.
5. `remove_old_install` / `install_roblox` — fresh Roblox into
   `<prefix>/root/Applications`, plus a pristine `RobloxVanilla.app` copy before
   any patching.
6. `install_dylib` + `patch_roblox` — patch `libmimalloc.3.dylib`.
7. `install_ui`, `install_modules` — UI app and guest `~/Opiumware`.
8. `write_launchers` — wrapper scripts, `~/.local/bin` links, `.desktop` files.
9. `launch_apps` — only when a display is present and `--no-launch` was not used.

`--uninstall` runs before `preflight` on purpose: it must work even if `curl`
or the architecture requirements are not available.

## Mach-O patching details

`patch_macho FILE DYLIB_PATH` adds a single `LC_LOAD_DYLIB` command:

- Assumes 64-bit little-endian Mach-O (`0xfeedfacf`), which is what Roblox ships.
- Walks the load commands to find the smallest section file offset. Bytes
  between the end of the load commands (`32 + sizeofcmds`) and that offset are
  header padding and can be reused.
- Writes the new command into that padding, then bumps `ncmds` and `sizeofcmds`.
  No file offsets move, so no segment/section rewriting is needed.
- The pinned `libmimalloc.3.dylib` has ~3.5 KB of padding; a load command with a
  ~60-byte path needs 88 bytes.
- If a future build has no padding, the function fails with a clear message.
  Do not silently fall back to the Injector; it does not work under Rosemary.
- Idempotent: it skips when the dylib path already appears in the file.

The patch is verified by running `rosemary --analyze <host path to patched
libmimalloc>`; Rosemary should mention imports coming from
`@rpath/libOpiumware.dylib`. Note that `--analyze` resolves the command-line path
on the host, while normal `run` resolves guest paths inside the prefix.

## Rosemary source patches

`patches/rosemary-executor-apis.patch` is the one users need for the executor.
It is **not** applied by the installer; it patches Rosemary itself.

- Vanilla Roblox does not need it.
- The executor needs it: it resolves every import `libOpiumware.dylib` has.
- `patches/rosemary-objc-classlist.patch` is the standalone
  `objc_getClassList` fix, already contained in the main patch. Keep it only as
  a minimal reproducer for upstream.
- The installer treats any `--rosemary PATH` as patched, remembers it at
  `<install>/rosemary-patched/rosemary`, and launches the executor from the
  install. Without it, installation starts vanilla Roblox.

Rebase procedure: `git clone` Rosemary, `git apply` the patch, `nix build
path:.` (or Cargo), run `rosemary --analyze` on `libOpiumware.dylib`, expect
"0 imports unbound", then smoke-run `opinuxware-roblox` for 60 s and confirm no
`nothing satisfied` faults. Do not commit Rust sources here; this repo only
carries the `.patch`.

## Bash conventions and pitfalls

- `set -euo pipefail` at the top. Keep it.
- `run_step "message" function` executes a function inside an `if`, which
  **disables `errexit` for the whole function body**. Every fallible command in
  a step function must therefore use `|| return 1` (or an explicit check).
- Prefer functions over `bash -c` with nested quoting. The original macOS script
  used one large `bash -c`; do not go back to that.
- Quote paths; the install directory can contain spaces.
- The temp dir is cleaned by an `EXIT` trap. Background launchers must not
  depend on it.
- `pkill -f` on guest paths is unsafe: an unrelated shell (or this installer's
  own command line) can contain `/Applications/Roblox.app`, so the installer
  killed a test shell that way once. `kill_running` instead scans
  `/proc/*/environ` for `ROSEMARY_PREFIX=<our prefix>` and only kills those.
- Do not add a required dependency on `jq`, `python3`, `socat`, etc.
  `python3 -m zipfile` is an optional fallback when `unzip` is missing.

## Testing

Good smoke tests do not need a full re-download:

```sh
# Syntax
bash -n install.sh

# Help / version
./install.sh --help
./install.sh --version

# Full install from local archives, into a scratch dir, no GUI launch
OPINUXWARE_DIR=/tmp/opinuxware-test \
ROBLOX_URL=file:///path/to/roblox.zip ROBLOX_SHA256= \
DYLIB_URL=file:///path/to/lib.zip DYLIB_SHA256= \
RESOURCES_URL=file:///path/to/modules.zip RESOURCES_SHA256= \
UI_URL=file:///path/to/ui.zip UI_SHA256= \
./install.sh --rosemary /path/to/rosemary/AppRun --no-launch --no-shortcuts

# Verify the load command is present and loadable
rosemary --analyze /tmp/opinuxware-test/prefix/root/Applications/Roblox.app/Contents/MacOS/libmimalloc.3.dylib | grep libOpiumware

# Uninstall
OPINUXWARE_DIR=/tmp/opinuxware-test ./install.sh --uninstall --yes
```

`curl` supports `file://` URLs, which is how the test above avoids the network.
On a minimal NixOS host without `unzip`/`python3`, a temporary `unzip` shim that
calls `7z` is fine for testing the rest of the flow; do not add `7z` as a
runtime dependency.

Real runtime checks require a graphical session:

```sh
~/.local/share/opinuxware/bin/opinuxware-roblox-vanilla   # should stay open
~/.local/share/opinuxware/bin/opinuxware-roblox           # executor; currently crashes
~/.local/share/opinuxware/bin/opinuxware                  # UI; currently crashes
```

Vanilla should show the Roblox window. The executor should reach
`_SecPolicyCreateSSL`; the UI reaches its AppKit gaps. A fault that names a
missing import is a Rosemary gap, not an installer failure — record it in the
README status.

## Version pins

At the top of `install.sh`:

- `ROSEMARY_VERSION` — pinned Rosemary release (`0.5.0`). Bump when a newer
  release fixes the symbols Opiumware needs.
- `ROBLOX_VERSION` — pinned macOS Intel client. Bump when the CDN drops the old
  build or when Opiumware targets a newer one.
- The three `*.ufs.sh` URLs are the Opiumware payload (library, resources, UI).
- `ROBLOX_SHA256`, `DYLIB_SHA256`, `RESOURCES_SHA256`, `UI_SHA256` and
  `ROSEMARY_APPIMAGE_SHA256` pin the downloads. They use `${VAR-default}` so an
  explicitly empty value disables verification (useful with local `file://`
  testing or custom URLs).

When bumping any payload, recompute its hash and update the matching variable.
When bumping Rosemary, re-check the AppImage asset name
(`Rosemary-<version>-x86_64.AppImage`), the URL and the hash from the release's
`SHA256SUMS`. When bumping Roblox, re-run the injection verification:
`libmimalloc.3.dylib` must still exist and still have enough header padding.

## Current compatibility state (as of 2026-11)

Vanilla Roblox — `opinuxware-roblox-vanilla` running the pristine
`RobloxVanilla.app` — works on stock Rosemary 0.5.0.

The executor (`opinuxware-roblox`, `Roblox.app` + `libOpiumware.dylib`) works
when Rosemary is built with `patches/rosemary-executor-apis.patch`:

- `libOpiumware.dylib` goes from 15 unresolved imports to **0**.
- Verified: a 60-second run reaches Luau execution and Roblox's HTTP/WebSocket
  servers with zero "import nothing satisfied" faults. Before the patch it
  crashed within ~2 seconds.

What the patch adds, roughly:

1. `crates/security/src/securetransport.rs` — SecureTransport `SSL*` over
   Rustls, with real chain + hostname verification, host callback pumping, and
   `errSSLWouldBlock`. Never disables verification.
2. `crates/security/src/trust.rs` — `SecPolicyCreateSSL`,
   `SecTrustEvaluateWithError`, `SecTrustSetOCSPResponse`,
   `SecTrustSetNetworkFetchAllowed`, `SecTrustSetAnchorCertificates` (refuses to
   replace anchors), plus chain getters.
3. `crates/rosemary/src/objc/dispatch.rs` — `objc_getClassList` /
   `objc_copyClassList` loader entries (supersedes
   `patches/rosemary-objc-classlist.patch`).
4. CoreVideo Metal texture cache, `CATransaction`, Accessibility
   (`AXIsProcessTrusted*`), `CFErrorCreate`, `CFUserNotificationDisplayAlert`,
   `CGEventCreateScrollWheelEvent`/`SetLocation`/`SetDoubleValueField`,
   `NSApplicationDidHide/UnhideNotification`, `NSImageName*`, `CGWindow*` keys,
   `kCVMetalTextureUsage`, `___NSDictionary0__struct`.

Still not run: the Opiumware UI. Its 33 remaining imports are `NSUserNotification*`,
`NSAppleScript`, `SystemConfiguration` dynamic-store keys, `fclonefileat`,
`__objc_personality_v0`, class-pair/ivar metadata calls, and a few SSL getters.
That is the next gap, and it does not affect the executor.

Do not "fix" executor gaps by stubbing certificate verification or the TLS
stack. Keep the patch rebasable against Rosemary `main`, and drop it if upstream
lands the same APIs. Re-check imports with
`rosemary --analyze <host path to libOpiumware.dylib>`.

