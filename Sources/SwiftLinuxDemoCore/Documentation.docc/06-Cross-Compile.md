# Cross-Compile

Build the `swift-linux-demo` executable on a Mac and run it on a
Raspberry Pi (aarch64 Linux) that has **no Swift installed**.

Everything is compiled on the Mac; the Pi only receives a binary plus
the Swift runtime libraries. This is the cross-compilation idea from
<doc:00-Concepts> applied end to end, and a companion to the native
Linux build in <doc:02-Build>.

Target hardware here is a **Raspberry Pi 4** (Cortex-A72, `aarch64`)
running **64-bit Raspberry Pi OS / Debian 12 "bookworm"**. Confirm with
`uname -m` on the Pi — it must print `aarch64`.

## Why this approach (and not the simpler ones)

There are three ways to get a self-contained Swift binary onto the Pi.
Only the last — **Bundled-runtime** — works reliably today:

| Name | Approach | Result on a Pi 4 |
|---|---|---|
| **Fully static** | musl Static Linux SDK (`aarch64-swift-linux-musl`) | Builds, but the binary dies with `Illegal instruction` (SIGILL). The musl SDK emits instructions older aarch64 cores lack — see [swiftlang/swift#88351](https://github.com/swiftlang/swift/issues/88351). |
| **Static stdlib** | glibc SDK + `--static-swift-stdlib` | Link fails: static `libcurl.a` needs `nghttp2`, which isn't in the generated sysroot. |
| **Bundled-runtime** | glibc SDK, dynamic, ship the Swift runtime `.so`s | **Works.** The Pi already has glibc/curl/nghttp2; it just lacks the Swift runtime, so we bundle that. |

This chapter uses the **Bundled-runtime** approach.

### What the working approach actually is

It is **not** a static build — it is the opposite end of the spectrum
from the musl option. The three rows above really vary on two separate
axes: the **C library** (musl vs glibc) and the **linking** (how much is
baked into the executable vs. loaded from `.so` files at run time).

- The **musl** option is *fully static*: the Swift runtime, Foundation,
  and the C library are all linked into one file with no external
  dependencies.
- The approach we use is an ordinary *dynamically linked* executable —
  nothing is baked in; everything is loaded from shared libraries at run
  time.

It works because of a split in where those shared libraries come from:

- glibc, libcurl, and nghttp2 already ship with Raspberry Pi OS, so the
  Pi resolves those itself.
- The Swift runtime (`libswiftCore.so`, `libFoundation.so`, …) is **not**
  on the Pi, so we copy that one set of `.so`s over and point
  `LD_LIBRARY_PATH` at them.

#### What lands on the Pi, and where

Nothing is installed globally and nothing needs `sudo`. We do not touch
`apt`, `/usr`, or any system directory, and we do not install a Swift
toolchain. The whole footprint is two items in the user's home directory:

- `~/swift-linux-demo` — the executable (a single file)
- `~/swift-libs/` — a folder holding the Swift runtime `.so`s

`LD_LIBRARY_PATH=~/swift-libs` just tells the dynamic loader where to find
those Swift libraries at launch; it is a per-command (or per-shell)
setting, not a system change. The deployment is therefore fully
self-contained in the home directory — to remove it you delete those two
paths and nothing else (see the Cleanup section). The only things it uses
from the system are libraries Raspberry Pi OS already ships (glibc,
libcurl, nghttp2), which we neither install nor modify.

This is the "bundle the runtime next to the app" deployment (Option 2 in
<doc:00-Concepts>). The genuinely static middle ground is the second row
— glibc with `--static-swift-stdlib`, which bakes *only* the Swift
runtime into the binary and leaves glibc/curl dynamic, so nothing needs
shipping to the Pi. It is the nicest fit for this repo's CI, but it
currently fails to link because static `libcurl` pulls in an `nghttp2`
the generated sysroot doesn't provide.

#### The alternative: a global Swift runtime on the Pi

Bundled-runtime ships the runtime *per app*. The other model is a
**global (system-wide) runtime**: install Swift on the Pi once, and every
dynamically-linked Swift binary you copy over then runs with no bundling
— no `~/swift-libs`, no `LD_LIBRARY_PATH`. This is the *framework-dependent*
model (the runtime is a shared system component); bundled-runtime is the
*self-contained* one.

The dynamic binary this guide builds works under either model — with a
global runtime present you simply skip the bundling (step 5) and the
`LD_LIBRARY_PATH`.

Canonical ways to install Swift system-wide on a Pi:

- **swiftly** — Swift's official toolchain manager. Follow the Linux
  instructions at <https://www.swift.org/install/linux/> (swiftly is
  distributed as a tarball there), then `swiftly install <version>`. This
  installs the full swift.org toolchain (compiler + runtime).
- **apt, community release** — `sudo apt install swiftlang` from the
  Swift-Arm community repo (`swiftlang` for Debian bookworm aarch64).

| | Bundled-runtime (this guide) | Global runtime |
|---|---|---|
| Install on the Pi | none | full toolchain, once (~GB) |
| Per-app footprint | binary + `~/swift-libs` | binary only |
| `LD_LIBRARY_PATH` | required | not needed |
| `sudo` / system changes | none | usually yes |
| Best for | shipping one self-contained app | a Pi you develop on or run many Swift apps |

With a global toolchain you can also skip cross-compiling entirely and
build on the Pi (`swift build`) — slower, but no SDK setup.

Two rules that bite if ignored:

- **The toolchain and the SDK must be the same swift.org version** (this
  guide uses `6.3.2`). **Xcode's Swift will not drive the SDK** — its
  modules are stamped by a different compiler build and the SDK's
  `Foundation` is rejected. You need the *swift.org* toolchain.
- **This repo's `Package.swift` gates targets with host-based `#if os()`.**
  When SwiftPM evaluates the manifest on macOS it picks `AppKitGreeter`
  and omits `GlibcGreeter`. You must force the Linux branch before
  cross-compiling (see step 3) and revert it after. This is the same
  manifest-guard story told in <doc:01-Conditional-Compilation>, seen
  from the cross-compilation side.

Substitute your own version for `6.3.2` throughout if your toolchain
differs.

## On the Mac

These steps keep everything under `~/Downloads` and make **no PATH or
shell-profile changes**, so your default `swift` (Xcode's) is untouched.
We invoke the swift.org compiler by full path via a `TC` variable.

### 1. Install the matching swift.org toolchain (via swiftly)

```bash
cd ~/Downloads

# Fetch swiftly and extract just its binary (nothing lands in ~/.swiftly).
curl -fsSLO https://download.swift.org/swiftly/darwin/swiftly.pkg
pkgutil --expand-full swiftly.pkg ~/Downloads/swiftly-pkg-extract
mkdir -p ~/Downloads/swiftly/bin
cp ~/Downloads/swiftly-pkg-extract/*/Payload/bin/swiftly ~/Downloads/swiftly/bin/swiftly
chmod +x ~/Downloads/swiftly/bin/swiftly

# Point swiftly at ~/Downloads and skip profile edits.
export SWIFTLY_HOME_DIR="$HOME/Downloads/swiftly"
export SWIFTLY_BIN_DIR="$HOME/Downloads/swiftly/bin"
"$HOME/Downloads/swiftly/bin/swiftly" init --no-modify-profile --skip-install --assume-yes

# Install the toolchain (~1.4 GB download).
"$HOME/Downloads/swiftly/bin/swiftly" install 6.3.2 --assume-yes
```

> macOS requires toolchains to live in `~/Library/Developer/Toolchains/`
> as `.xctoolchain` bundles, so the toolchain itself lands there even
> though swiftly is under `~/Downloads`. It is an *additional* toolchain;
> your default `swift` does not change.

Define the path to the swift.org compiler for the remaining steps and
sanity-check it (the build tag must read `swift-6.3.2-RELEASE`, **not**
`swiftlang-...` which is Xcode's):

```bash
TC="$HOME/Library/Developer/Toolchains/swift-6.3.2-RELEASE.xctoolchain/usr/bin"
"$TC/swift" --version
```

### 2. Generate and install the glibc aarch64 SDK

```bash
cd ~/Downloads
git clone --depth 1 https://github.com/swiftlang/swift-sdk-generator.git
cd swift-sdk-generator

"$TC/swift" run swift-sdk-generator make-linux-sdk \
  --target aarch64-unknown-linux-gnu \
  --distribution-name debian --distribution-version 12 \
  --swift-version 6.3.2-RELEASE \
  --no-host-toolchain

"$TC/swift" sdk install \
  ~/Downloads/swift-sdk-generator/Bundles/6.3.2-RELEASE_debian_bookworm_aarch64.artifactbundle

"$TC/swift" sdk list   # should show 6.3.2-RELEASE_debian_bookworm_aarch64
```

### 3. Force the Linux target set (this repo only)

In `Package.swift`, the host-based guard near the top selects the macOS
targets when run from a Mac. Temporarily replace the whole
`#if os(macOS) ... #endif` block with the Linux set:

```swift
let platformExclusiveTargets: [Target] = [
    .target(name: "GlibcGreeter"),
]
let platformExclusiveCoreDeps: [Target.Dependency] = ["GlibcGreeter"]
```

You revert this in step 7. (A permanent fix would have the manifest read
a target-OS override from the environment instead of hand-editing.)

### 4. Build the executable (dynamic)

```bash
cd /path/to/SwiftLinuxDemo
"$TC/swift" build -c release --product swift-linux-demo \
  --swift-sdk 6.3.2-RELEASE_debian_bookworm_aarch64
```

Confirm the output is an aarch64 Linux binary:

```bash
file .build/aarch64-unknown-linux-gnu/release/swift-linux-demo
# ELF 64-bit LSB pie executable, ARM aarch64, ... dynamically linked,
# interpreter /lib/ld-linux-aarch64.so.1, for GNU/Linux ...
```

### 5. Bundle the Swift runtime libraries

The Pi has glibc/curl but not the Swift runtime, so package it:

```bash
SDK=~/Library/org.swift.swiftpm/swift-sdks/6.3.2-RELEASE_debian_bookworm_aarch64.artifactbundle
LIBDIR=$(find "$SDK" -type d -path '*usr/lib/swift/linux' | head -1)
( cd "$LIBDIR" && tar czf /tmp/swift-runtime.tar.gz *.so )
```

### 6. Copy the binary and runtime to the Pi

```bash
scp .build/aarch64-unknown-linux-gnu/release/swift-linux-demo \
    /tmp/swift-runtime.tar.gz \
    <user>@<pi-host>:/home/<user>/
```

### 7. Revert the temporary manifest edit

```bash
git checkout -- Package.swift
```

## On the Pi

### 1. Unpack the runtime and run

```bash
chmod +x ~/swift-linux-demo
mkdir -p ~/swift-libs
tar xzf ~/swift-runtime.tar.gz -C ~/swift-libs

LD_LIBRARY_PATH=~/swift-libs ~/swift-linux-demo info
```

### 2. (Optional) avoid typing LD_LIBRARY_PATH every time

A small wrapper, or an rpath baked at build time, removes the need for
the env var. Simplest is a launcher:

```bash
cat > ~/run-demo.sh <<'EOF'
#!/usr/bin/env bash
export LD_LIBRARY_PATH="$HOME/swift-libs"
exec "$HOME/swift-linux-demo" "$@"
EOF
chmod +x ~/run-demo.sh
~/run-demo.sh greet --name Pi
```

## Verifying

With the Pi holding **no Swift toolchain**, every subcommand should work:

```text
$ LD_LIBRARY_PATH=~/swift-libs ~/swift-linux-demo info
os:     linux
arch:   arm64
swift:  6.2+
native: glibc-hostname=raspberrypi

$ ~/swift-linux-demo greet --name Pi
Hello, Pi!

$ ~/swift-linux-demo hash hello
2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824

$ ~/swift-linux-demo fetch https://example.com
200
```

`info`'s `glibc-hostname` line proves `GlibcGreeter` (a Linux-only target
calling `gethostname`) is in the binary; `hash` exercises swift-crypto;
`fetch` exercises Foundation networking over libcurl.

## Cleanup

### On the Pi

```bash
rm -rf ~/swift-linux-demo ~/swift-libs ~/swift-runtime.tar.gz ~/run-demo.sh
```

### On the Mac

```bash
TC="$HOME/Library/Developer/Toolchains/swift-6.3.2-RELEASE.xctoolchain/usr/bin"

# Remove the installed Swift SDK(s)
"$TC/swift" sdk remove 6.3.2-RELEASE_debian_bookworm_aarch64
"$TC/swift" sdk remove swift-6.3.2-RELEASE_static-linux-0.1.0   # if you also tried musl

# Remove the swift.org toolchain (~1.4 GB) and its convenience symlink
rm -rf ~/Library/Developer/Toolchains/swift-6.3.2-RELEASE.xctoolchain
rm -f  ~/Library/Developer/Toolchains/swift-latest.xctoolchain

# Remove swiftly, the generator clone, and downloads
rm -rf ~/Downloads/swiftly ~/Downloads/swiftly-pkg-extract \
       ~/Downloads/swiftly.pkg ~/Downloads/swift-sdk-generator
rm -f  /tmp/swift-runtime.tar.gz
```

Your Xcode toolchain and default `swift` are unaffected by any of the
above.
