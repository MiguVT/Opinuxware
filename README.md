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

This project exists to see how far a macOS compatibility layer can take a real
game client, and to make the point that client-side security is not a security
boundary: anti-cheat that trusts the client can always be bypassed, so real
protection has to live server-side.

The intended use of the executor is your own games or experiences, the way
Roblox's own tooling expects. It is not intended for cheating in other people's
games, bypassing anti-cheat, or breaking Roblox's Terms of Service.

## Status

| Component | Status |
| --- | --- |
| Installer | Works |
| Vanilla Roblox (`opinuxware-roblox-vanilla`) | Works on stock Rosemary |
| Opiumware executor (`opinuxware-roblox`) | Works with the Rosemary patch |
| Opiumware UI (`opinuxware`) | Works with the Rosemary patch |

The game boots through the executor for 60+ seconds, reaches Luau execution,
and talks to Roblox's servers without a single crash from an unbound import.
That needs a patched Rosemary, because the stock 0.5.0 release has none of the
Security APIs the executor calls. See [Rosemary source patches](#2-the-rosemary-source-patch-built-by-you).

Vanilla play uses a pristine `RobloxVanilla.app`. The executor uses a
separately patched `Roblox.app` that loads `libOpiumware.dylib`.

The installer starts the executor after installation when you pass `--rosemary`
with a patched build, and vanilla Roblox otherwise.

## Requirements

- Linux on x86-64
- `curl` and `sha256sum`
- `unzip` or `python3`
- OpenGL/Vulkan driver and an X11 or Wayland session
- ~3 GB disk space (Roblox twice, Rosemary and the prefix)

Rosemary bundles SDL3, glibc and its other runtime libraries, so nothing needs
to be installed system-wide. ARM hosts need a native Rosemary build, see
`--rosemary`.

## Install

```sh
chmod +x install.sh
./install.sh
```

The installer downloads and verifies every payload, creates the prefix,
installs Roblox twice (patched and pristine), installs the Opiumware UI and
modules, and creates launchers. It starts **vanilla Roblox** at the end unless
`--no-launch` is given.

All downloads have pinned SHA-256 checksums. To use a different payload,
override its URL **and** checksum, e.g. `ROBLOX_URL=... ROBLOX_SHA256=...
./install.sh`. Set a checksum to an empty value to skip that check.

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

## Patches and prerequisite for the executor

Two unrelated things are called a "patch" around here. Do not mix them up.

### 1. The Roblox injection, built into `install.sh`

The macOS installer would add the `LC_LOAD_DYLIB` that loads
`libOpiumware.dylib` into Roblox with a helper called `Injector`
(`insert_dylib`). That helper imports `_copyfile`, which Rosemary does not
implement, so `install.sh` patches the Mach-O itself (`patch_macho`) and points
the injection at `/Applications/Roblox.app/Contents/Resources/libOpiumware.dylib`.

It is applied automatically and only affects the patched `Roblox.app`.
`RobloxVanilla.app` is a pristine copy and never gets it. Nothing for you to do.

### 2. The Rosemary source patch, built by you

This one patches the runtime itself, which is why the installer cannot apply
it. If you want the executor or the UI, build a patched Rosemary and hand it to
the installer:

| Patch | What it fixes | Needed? |
| --- | --- | --- |
| `patches/rosemary-executor-apis.patch` | Every macOS API the executor and UI need: SecureTransport (`SSL*`) with real Rustls verification, `SecPolicyCreateSSL`/`SecTrustEvaluateWithError`, CoreVideo Metal textures, the Tauri custom-protocol machinery, `NSHTTPURLResponse`, fast enumeration of empty dictionaries, and the exception personality for images that link no C++ runtime | Yes, for `opinuxware-roblox` and `opinuxware` |
| `patches/rosemary-objc-classlist.patch` | `objc_getClassList` / `objc_copyClassList` never registered in the loader table | Contained in the patch above; use alone only if you want that fix on its own |

```sh
git clone https://github.com/microlift/rosemary
git -C rosemary apply "$PWD/patches/rosemary-executor-apis.patch"
nix build path:rosemary -o ~/.local/share/opinuxware/rosemary-patched/rosemary
./install.sh --rosemary ~/.local/share/opinuxware/rosemary-patched/rosemary/bin/rosemary
```

Build it at that exact path: `-o` writes a result symlink there and keeps the
build alive in the store. `--rosemary` accepts the binary inside that directory,
or the build directory itself. Once it is in place, a plain `./install.sh`
picks it up again and logs `Using previously installed patched Rosemary`.
Whether the remembered path is the binary or a build directory, the launchers
always exec `.../rosemary-patched/rosemary/bin/rosemary`.

Without Nix, `cargo build --release --bin rosemary` inside the checkout works
too; pass `rosemary/target/release/rosemary`.

Two notes. This is our patch work, not an upstream release: re-check it when
Rosemary `main` moves, and drop it if upstream lands the same APIs. And the
patch does not weaken TLS or certificate checking: the SecureTransport shim
verifies chains and hostnames with Rustls and refuses unverified connections.

The full story on the fixes, dead ends included, lives in `AGENTS.md`.

## Why Rosemary, not Darling

Darling's own docs say [GUI applications do not
work](https://docs.darlinghq.org/known-nonfunctional-software.html) ("very few
exceptions", "any complex GUI application in general will not work"), its
known-working list is CLI tools and a calculator, and it ships Debian-only
packages. Rosemary already runs vanilla Roblox and targets AppKit, CoreAudio
and Metal on Linux, so the choice is easy.

## Why free and open source

Client-side anti-cheat is fundamentally bypassable: the client runs on the
player's machine and can be modified. Real protection has to be server-side.
This project is free software so its compatibility work can be inspected,
forked and improved, and so that point stays visible. Hiding client code is not
a security boundary, and forks must remain open source under the same license.

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

- **Launch fails**: the automatic launch writes
  `~/.local/share/opinuxware/launch.log`. Run the launcher from a terminal to
  see the same output live.
- **`an import nothing satisfied` / `SIGSEGV at 0x0`**: a symbol Rosemary does
  not provide. That is a Rosemary gap, not an installer failure.
- **`No such file or directory` for an app**: the prefix is missing or
  `OPINUXWARE_DIR` changed. Launchers pass guest paths (`/Applications/...`).
- **Prefix base download fails**: retry, or install with `--no-base`.
- **Wayland window issues**: `ROSEMARY_DECORATIONS=server opinuxware-roblox-vanilla`.

## License

Opinuxware is licensed under the **GNU General Public License, version 3 or
later** (`GPL-3.0-or-later`). See [LICENSE](LICENSE).

You can fork it, modify it, and redistribute it, provided distributed
derivative works are also GPL-3.0-or-later and their complete source is made
available. Proprietary forks are not allowed. "Free" here means free software,
not necessarily zero price; the GPL does not forbid charging for distribution.

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