# Opinuxware

**Opiumware for Linux**, powered by [Rosemary](https://github.com/microlift/rosemary).

Opinuxware installs the macOS Roblox client and the Opiumware payload into an
isolated Rosemary prefix. It is an unofficial community port, not affiliated
with Opiumware, Roblox or the Rosemary project, and is provided for
**educational purposes**.

Using executors can violate Roblox's Terms of Service and may get your account
banned. Use the executor only in games you own or are explicitly authorized to
test.

## Educational purpose

This project studies how far a macOS compatibility layer can run a real game
client, and where client-side versus server-side security actually belongs.

The intended use of the executor is your own games or experiences, the way
Roblox's own tooling expects. It is not intended for cheating in other people's
games, bypassing anti-cheat, or breaking Roblox's Terms of Service.

## Status

| Component | Status |
| --- | --- |
| Installer | Works |
| **Vanilla Roblox** (`opinuxware-roblox-vanilla`) | **Works** |
| **Opiumware executor** (`opinuxware-roblox`) | **Works with the Rosemary patch** |
| Opiumware UI (`opinuxware`) | **Works with the Rosemary patch** |

Booted Roblox with the executor loaded (`libOpiumware.dylib`) for 60+ seconds,
serving Luau and reaching Roblox's servers, with **zero unbound-import crashes**.
That needs a patched Rosemary: the stock 0.5.0 release has none of the Security
APIs the executor calls. See [Rosemary source patches](#2-rosemary-source-patches--needed-for-the-executor).

The Opiumware UI also starts with the patched Rosemary: a real window comes up
and the Tauri frontend loads. That needs the custom-protocol task machinery
wry uses to serve the frontend, plus the empty-dictionary fast-enumeration fix;
see [Rosemary source patches](#2-rosemary-source-patches--needed-for-the-executor).

Vanilla play uses a pristine `RobloxVanilla.app`. The executor uses a separately
patched `Roblox.app` that loads `libOpiumware.dylib`.

The automatic launch at the end of installation starts the executor when you pass
`--rosemary` with a patched build, and vanilla Roblox otherwise.

## Requirements

- Linux on x86-64
- `curl` and `sha256sum`
- `unzip` or `python3`
- OpenGL/Vulkan driver and an X11 or Wayland session
- ~3 GB disk space (Roblox twice, Rosemary and the prefix)

Rosemary bundles SDL3, glibc and its other runtime libraries; they do not need
to be installed system-wide. ARM hosts need a native Rosemary build (see
`--rosemary`).

## Install

```sh
chmod +x install.sh
./install.sh
```

The installer downloads and verifies all payloads, creates the prefix, installs
Roblox twice (patched and pristine), installs the Opiumware UI and modules, and
creates launchers. It starts **vanilla Roblox** at the end unless `--no-launch`
is given.

All downloads have pinned SHA-256 checksums. To use a different payload, override
its URL **and** checksum, e.g. `ROBLOX_URL=... ROBLOX_SHA256=... ./install.sh`.
Set a checksum to an empty value to skip that check.

## Usage

```sh
opinuxware                    # Opiumware UI (needs a patched Rosemary)
opinuxware-roblox             # Roblox + Opiumware (needs a patched Rosemary)
opinuxware-roblox-vanilla     # unmodified Roblox (works on stock Rosemary)
```

If `~/.local/bin` is not in `PATH`, use the full paths under
`~/.local/share/opinuxware/bin/` or the desktop entries.

Scripts (autoexec, workspaces, themes) live in the guest home:
`~/.local/share/opinuxware/prefix/root/Users/$USER/Opiumware`, also linked at
`~/Opiumware`.

## Paths

| What | Host path | Guest path |
| --- | --- | --- |
| Install | `~/.local/share/opinuxware` | – |
| Patched Rosemary | `.../opinuxware/rosemary-patched/rosemary` | – |
| Bundled Rosemary | `.../opinuxware/rosemary` | – |
| Roblox (patched) | `.../prefix/root/Applications/Roblox.app` | `/Applications/Roblox.app` |
| Roblox (vanilla) | `.../prefix/root/Applications/RobloxVanilla.app` | `/Applications/RobloxVanilla.app` |
| Opiumware UI | `.../prefix/root/Applications/Opiumware.app` | `/Applications/Opiumware.app` |
| Opiumware data | `.../prefix/root/Users/$USER/Opiumware` | `~/Opiumware` |

## Options

```
--no-launch          Install only; do not start Roblox afterwards
--no-base            Do not download the MiniDarwin base into the prefix
--no-shortcuts       Do not create ~/.local/bin links, desktop entries or ~/Opiumware
--update-rosemary    Re-download the bundled Rosemary build
--rosemary PATH      Use an existing Rosemary executable instead of downloading
--keep-temp          Keep temporary downloads under the install directory
--uninstall          Remove Opinuxware, its prefix and its shortcuts
-y, --yes            Do not ask for confirmation (with --uninstall)
-h, --help           Show help
```

`OPINUXWARE_DIR` changes the install directory. `ROSEMARY_VERSION`,
`ROBLOX_VERSION` and the payload URLs/checksums can be overridden as shown
above; `--help` lists every variable. Changing a version changes the download,
so clear or update the matching checksum too.

## Patches — current state

Two unrelated things are called a “patch”:

### 1. Roblox injection — built into `install.sh`, required for the executor

The macOS installer runs an `Injector` (`insert_dylib`) that adds an
`LC_LOAD_DYLIB` to `libmimalloc.3.dylib`. That binary imports `_copyfile`, which
Rosemary does not implement, so the installer adds the load command itself
(`patch_macho`). It points at
`/Applications/Roblox.app/Contents/Resources/libOpiumware.dylib`.

- **Required** for `opinuxware-roblox`.
- **Not used** by `opinuxware-roblox-vanilla`; that app is a pristine copy.
- Applied automatically on install; nothing for you to do.

### 2. Rosemary source patches — needed for the executor
These are **not applied by the installer**. They are for the Rosemary runtime,
which has to be built and passed with `--rosemary`.

| Patch | What it fixes | Needed? |
| --- | --- | --- |
| `patches/rosemary-executor-apis.patch` | Every macOS API the executor imports: SecureTransport (`SSL*`), `SecPolicyCreateSSL`/`SecTrustEvaluateWithError`, CoreVideo Metal textures, `CATransaction`, Accessibility, `CFErrorCreate`, `NSImageName*`, and more; plus what the Opiumware UI needs (an empty-dictionary fast-enumeration fix, `NSHTTPURLResponse initWithURL:...`, `isMovableByWindowBackground`, and publishing `___objc_personality_v0` into the slot for images that link no C++ runtime) | **Yes**, for `opinuxware-roblox` and `opinuxware` |
| `patches/rosemary-objc-classlist.patch` | `objc_getClassList` / `objc_copyClassList` never registered in the loader table | Contained in the patch above; use alone only if you want that fix on its own |

Both apply to Rosemary `main` (verified on 2026-11-05) and keep Rosemary's own
tests green.

```sh
git clone https://github.com/microlift/rosemary
git -C rosemary apply "$PWD/patches/rosemary-executor-apis.patch"
nix build path:rosemary -o ~/.local/share/opinuxware/rosemary-patched/rosemary
./install.sh --rosemary ~/.local/share/opinuxware/rosemary-patched/rosemary/bin/rosemary
```

Build it at that exact path: `-o` also writes the Nix result symlink there, and it
keeps the build alive in the store. `--rosemary` accepts a binary inside that
directory (or the build directory itself) and the installer reuses it on later
runs. Once it is in place, plain
`./install.sh` picks it up automatically and logs
`Using previously installed patched Rosemary`. Whether the remembered path is
the binary or a build directory, the launchers always exec
`.../rosemary-patched/rosemary/bin/rosemary`.

Without Nix, use `cargo build --release --bin rosemary` inside the Rosemary
checkout and pass `rosemary/target/release/rosemary`.

Note that this is **our** patch work, not an upstream release. Re-check it when
Rosemary `main` moves; if upstream lands the same APIs, drop the patch.

The Opiumware UI starts on the patched Rosemary. It runs the real custom-protocol
machinery: wry registers a `WKURLSchemeHandler` for `tauri://`, this runtime's
web view hands the task to it, and the handler's `NSHTTPURLResponse` initializer
and every accessor are implemented. The behaviour was traced from two hard
faults that looked like unwinder problems but were not:

- cocoa_foundation's `NSFastIterator::next` dereferences `state.mutations`
  after every refill, and `dictionary_enumerate` returned `0` for an empty
  dictionary without filling `state` — so the guest crashed on a null pointer,
  not on a missing `@catch`. `dictionary_enumerate` (and only it) now hands out
  the mutation guard even for a zero-item answer.
- `initWithURL:statusCode:HTTPVersion:headerFields:` was unimplemented (a named
  abort, which no `@try`/`@catch` can turn into a catch here).

The real `__try`/`__catch` gap was `___objc_personality_v0`'s slot: an image
that links no C++ runtime (the UI does not link libc++) imports the name as
data, and `publish_personality` recorded the routine but never wrote the slot.
The UI's import list is now fully resolved (0 unbound).

One further fix made the UI fully usable: Tauri's IPC scope check classifies a
command's origin as local by comparing the webview's URL with the app's
configured `tauri://localhost`, but this runtime serves the frontend from
`file://<bundle>/Contents/Resources/_up_/` (WebKitGTK refuses custom schemes),
so every command was rejected with "Scope not defined". `-URL` now reports the
scheme URL (`tauri://localhost/...`) for pages under a bundle's `_up_` asset
directory, so the editor, console and file operations work. The executor still
runs 60 s with zero import faults.

Stubbing certificate verification was not done: the SecureTransport shim
verifies chains and hostnames with Rustls, and refuses unverified connections.

## Why Rosemary, not Darling

Darling's own docs say [GUI applications do not
work](https://docs.darlinghq.org/known-nonfunctional-software.html) (“very few
exceptions”, “any complex GUI application in general will not work”), and its
known-working list is CLI tools and a calculator. It ships Debian-only packages
and no Nix flake. Rosemary already runs vanilla Roblox and targets AppKit,
CoreAudio and Metal on Linux, so it is the runtime here.

## Why free and open source

Client-side anti-cheat is fundamentally bypassable: the client runs on the
player's machine and can be modified. Real protection has to be server-side.
This project is free software so its compatibility work can be inspected,
forked and improved, and so that point stays visible: hiding client code is not
a security boundary. Forks must remain open source under the same license.

## Update / Uninstall

Re-run `./install.sh` to reinstall from the pinned payloads. Use
`--update-rosemary` for a fresh Rosemary download, or `--rosemary PATH` for one
you built.

```sh
./install.sh --uninstall          # asks for confirmation
./install.sh --uninstall --yes    # no prompt
```

Uninstall removes the install directory (including its prefix) and the
shortcuts it created. It leaves any other Rosemary prefix alone.

## Troubleshooting

- **Launch fails**: the automatic launch writes `~/.local/share/opinuxware/launch.log`.
  Run a launcher from a terminal to see the same output live.
- **`an import nothing satisfied` / `SIGSEGV at 0x0`**: a symbol Rosemary does
  not provide. That is a Rosemary gap, not an installer failure.
- **`No such file or directory` for an app**: the prefix is missing or
  `OPINUXWARE_DIR` changed. Launchers pass guest paths (`/Applications/...`).
- **Prefix base download fails**: retry, or install with `--no-base`.
- **Wayland window issues**: `ROSEMARY_DECORATIONS=server opinuxware-roblox-vanilla`.

## License

Opinuxware is licensed under the **GNU General Public License, version 3 or
later** (`GPL-3.0-or-later`). See [LICENSE](LICENSE).

You can fork it, modify it, and redistribute it, provided distributed derivative
works are also GPL-3.0-or-later and their complete source is made available.
Proprietary forks are not allowed. “Free” here means free software, not
necessarily zero price; the GPL does not forbid charging for distribution.

The Rosemary patch in [`patches/`](patches) is a derivative of Rosemary and is
distributed under Rosemary's GPL-3.0 terms.

This license covers the code and documentation in this repository. Roblox and
Opiumware payloads are downloaded at install time and remain under their own
terms; they are not redistributed here.

## Credits

- **Opiumware** — original macOS executor by [@norbyv1](https://gitlab.com/norbyv1)
- **[Rosemary](https://github.com/microlift/rosemary)** — macOS compatibility
  layer and x86-64 emulator by the Microlift project (GPL-3.0)
- **[MiniDarwin](https://github.com/V3L0C1T13S/minidarwin)** — Darwin base used by
  Rosemary prefixes

No Opiumware binaries are redistributed; they are downloaded from the URLs
pinned in `install.sh`.
