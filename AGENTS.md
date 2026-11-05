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
├── rosemary/AppRun                         # extracted stock Rosemary AppImage
├── rosemary-patched/rosemary               # patched build kept by --rosemary
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

1. `parse_args`: flags and env overrides.
2. `preflight`: OS/arch/dependency checks; creates a temp dir **inside the
   install dir** (avoids noexec `/tmp`).
3. `resolve_rosemary`: custom path → installed AppImage → system `rosemary` →
   download a pinned AppImage release and extract it with
   `--appimage-extract`. Extraction needs no FUSE.
4. `ensure_prefix`: `rosemary prefix create` unless the prefix exists.
5. `remove_old_install` / `install_roblox`: fresh Roblox into
   `<prefix>/root/Applications`, plus a pristine `RobloxVanilla.app` copy before
   any patching.
6. `install_dylib` + `patch_roblox`: patch `libmimalloc.3.dylib`.
7. `install_ui`, `install_modules`: UI app and guest `~/Opiumware`.
8. `write_launchers`: wrapper scripts, `~/.local/bin` links, `.desktop` files.
9. `launch_apps`: only when a display is present and `--no-launch` was not used.

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
- The installer treats any `--rosemary PATH` as patched and remembers it at
  `<install>/rosemary-patched/rosemary`. That path is either a symlink to the
  passed binary or a Nix result pointing at a build directory; if the passed
  path is already inside it, nothing is replaced (it is read-only in the store).
  Later runs pick it up automatically. `resolve_rosemary` normalises the
  remembered path to the executable (`bin/rosemary` inside a build directory),
  and the launchers always exec that file, never a directory. Without it,
  installation starts vanilla Roblox.

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
~/.local/share/opinuxware/bin/opinuxware-roblox           # executor; should reach Luau + Roblox servers
~/.local/share/opinuxware/bin/opinuxware                  # UI; should show the window and frontend
```

Vanilla shows the Roblox window. The executor reaches Luau execution and
Roblox's HTTP/WebSocket servers; a fault that names a missing import is a
Rosemary gap, not an installer failure. Record it in the README status.

For the UI, two cheap checks catch most regressions. First, `rosemary --analyze`
on its Mach-O must print `0 unbound`. Second, run it with
`ROSEMARY_TRACE_WEBKIT=1` and confirm the log has no unhandled promise
rejections: the frontend fires a Tauri command at boot, so a broken IPC scope
or a missing API shows up as a `CONSOLE JS ERROR` line within seconds.

## Version pins

At the top of `install.sh`:

- `ROSEMARY_VERSION`: pinned Rosemary release (`0.5.0`). Bump when a newer
  release fixes the symbols Opiumware needs.
- `ROBLOX_VERSION`: pinned macOS Intel client. Bump when the CDN drops the old
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

Vanilla Roblox (the `opinuxware-roblox-vanilla` launcher, pristine
`RobloxVanilla.app`) works on stock Rosemary 0.5.0.

The executor (`opinuxware-roblox`, `Roblox.app` + `libOpiumware.dylib`) works
when Rosemary is built with `patches/rosemary-executor-apis.patch`:

- `libOpiumware.dylib` goes from 15 unresolved imports to **0**.
- Verified: a 60-second run reaches Luau execution and Roblox's HTTP/WebSocket
  servers with zero "import nothing satisfied" faults. Before the patch it
  crashed within ~2 seconds.

The Opiumware UI (`opinuxware`) also works on the same patched build: the real
window comes up, the async Tauri frontend runs, and the run needs no special
environment. Every import of `Opiumware`'s Mach-O resolves, `___objc_personality_v0`
included.

The patch adds:

1. `crates/security/src/securetransport.rs`: SecureTransport `SSL*` over
   Rustls, with real chain + hostname verification, host callback pumping, and
   `errSSLWouldBlock`. Never disables verification.
2. `crates/security/src/trust.rs`: `SecPolicyCreateSSL`,
   `SecTrustEvaluateWithError`, `SecTrustSetOCSPResponse`,
   `SecTrustSetNetworkFetchAllowed`, `SecTrustSetAnchorCertificates` (refuses to
   replace anchors), plus chain getters.
3. `crates/rosemary/src/objc/dispatch.rs`: `objc_getClassList` /
   `objc_copyClassList` loader entries (supersedes
   `patches/rosemary-objc-classlist.patch`).
4. CoreVideo Metal texture cache, `CATransaction`, Accessibility
   (`AXIsProcessTrusted*`), `CFErrorCreate`, `CFUserNotificationDisplayAlert`,
   `CGEventCreateScrollWheelEvent`/`SetLocation`/`SetDoubleValueField`,
   `NSApplicationDidHide/UnhideNotification`, `NSImageName*`, `CGWindow*` keys,
   `kCVMetalTextureUsage`, `___NSDictionary0__struct`.
5. WebKit/Tauri support: `NSTextInputClient` protocol, `NSTextInputContext
   initWithClient:`, `WKWebViewConfiguration setURLSchemeHandler:forURLScheme:`
   plus `urlSchemeHandlerForURLScheme:`, `WKURLSchemeTask`, `loadHTMLString:baseURL:`,
   `-HTTPBodyStream`, `NSAppleScript`/`NSUserNotification*` classes, and the
   SystemConfiguration dynamic store.
6. The Opiumware UI's own needs: `dictionary_enumerate` returning the mutation
   guard on empty answers, `-[NSHTTPURLResponse initWithURL:statusCode:HTTPVersion:headerFields:]`
   plus `corefoundation::boxed::place_contents`, `isMovableByWindowBackground`,
   `publish_personality` writing every `___objc_personality_v0` slot so
   C++-less images resolve the last import and can unwind into a `@catch`, and
   `WKWebView -URL` reporting the `tauri://` scheme for pages served from a
   bundle's `_up_` directory so Tauri's IPC scope accepts the window.

## Opiumware UI

The UI is a Tauri 1.8 app (Rust + WKWebView). With the patch it starts: a real
window, the custom-protocol task machinery that serves `tauri://`, and the
Tauri frontend. Verified with a plain run: 70+ seconds, no faults, no
unrecognized selectors (with and without `ROSEMARY_LOG_UNRECOGNIZED`).

How it was made to start: the earlier "dies at Opiumware+0x324896, a tail
call inside wry's msg_send wrapper with rsi = 0" was a misdiagnosis. That
address is `movq (%rdx), %rsi` in `cocoa_foundation`'s `NSFastIterator::next`,
a **null dereference of `state.mutations`**, not an unwinder/`@catch` problem:

1. `dictionary_enumerate` (and only it; the array/set/enumerator versions
   already did) returned `0` for an empty or exhausted dictionary *without*
   filling `state`. cocoa_foundation reads `state.mutations` after *every*
   refill, empty answer included, so an empty `__NSCFDictionary` crashed the
   guest. Fix: `dictionary_enumerate` hands out the `NEVER_MUTATED` guard (and
   the caller's buffer as `items`) before the `batch == 0` early return.
2. wry's custom-protocol machinery (`InnerWebView::new::start_task`) builds its
   answer with `-[NSHTTPURLResponse initWithURL:statusCode:HTTPVersion:headerFields:]`,
   which was unimplemented and aborted by name. Fix: implement it (plus a
   dictionary-of-strings reader), filling the `Body<Response>` of a freshly
   allocated object via the new `corefoundation::boxed::place_contents`.
3. `-[TaoWindow isMovableByWindowBackground]` (an NSWindow property getter) was
   missing; tao asks it during window setup. Returns the default (`NO`).
4. The real `@try`/`@catch` gap: an image that links **no C++ runtime** (the UI
   does not link libc++, Roblox does) imports `___objc_personality_v0` as data,
   and `publish_personality` recorded the routine's address but never wrote the
   slot, so the last import stayed unbound and any unwind through an
   exceptions table would have jumped to zero. `publish_personality` now writes
   every `___objc_personality_v0` slot, like `publish_root_record` does for
   `_OBJC_EHTYPE_id`.
5. The Tauri IPC scope: Tauri's `Window::on_message` classifies the command
   origin as local only when `webview.url()` shares the scheme, host and port
   of the app's configured URL (`tauri://localhost`). This runtime serves the
   frontend from `file://<bundle>/Contents/Resources/_up_/<host>/<path>`
   (`servable_base`, because WebKitGTK has no handler for custom schemes), so
   `-URL` reported a `file:` URL and **every** command was rejected with
   "Scope not defined for window `main` and URL …". Fix: `-URL` inverts the
   mapping for pages under a bundle's `_up_` directory and reports
   `tauri://<host>/<path>`, bundle detected from the URL itself (this process
   is Rosemary, in the nix store, so `bare_guest_executable` is not usable
   here). WebKitGTK still resolves the relative assets against the real
   `file:` base, so both the document origin and the load path are right.

Findings that still matter:

- The custom-scheme task path **is** what runs: the trace above was reached
  through wry's own `start_task` closure, so the earlier note that "wry does
  not register a URL scheme handler on macOS" is wrong for this wry version.
  Do not remove or stub the scheme-task machinery (`serve_custom_scheme`,
  `SCHEME_TASKS`) without re-checking that the frontend still loads.
- `objc_exception::try` (`RustObjCExceptionTryCatch`) wraps a closure in
  `@try`/`@catch`; for it to catch, the unwinder needs a live personality and a
  matching `_OBJC_EHTYPE_id`. The executor's own C++ runtime supplies the
  personality via `bind`; C++-less images now get it via `publish_personality`.
- `_OBJC_EHTYPE_id` must carry the **real** `libc++abi` type_info vtable word;
  a standalone copy never matches what the guest compares against. That was
  tried and reverted as insufficient; kept that way.
- Debug scaffolding used while chasing it (a trace in `objc/src/msg.rs`, unwind
  tracing, an early return in `cxxlib.rs`) has been removed. Do not land it.

Do not "fix" executor gaps by stubbing certificate verification or the TLS
stack. Keep the patch rebasable against Rosemary `main`, and drop it if upstream
lands the same APIs. Re-check imports with
`rosemary --analyze <host path to libOpiumware.dylib>` (executor) and
`.../Opiumware.app/Contents/MacOS/Opiumware` (UI); both print `0 unbound`.

