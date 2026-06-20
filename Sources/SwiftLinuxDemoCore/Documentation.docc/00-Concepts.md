# Concepts

A top-down tour of the stack — from the Swift code you write down to the
CPU — and how the Swift ecosystem adapts at each layer.

![The system stack, from your Swift code at the top down through the Swift libraries, runtime, system libraries, system calls, kernel, CPU architecture, and hardware.](concepts-stack.svg)

Every layer above provides services to the one below it, and a request
travels *down* the stack while the result comes back *up*. This chapter
walks each layer in that order. For every layer it answers three
questions: **what it is**, **what varies** across platforms, and **how
Swift adapts** to that variation. Read top to bottom and the recurring
"works on macOS, breaks on Linux" surprises stop being surprising.

The how-to chapters — <doc:01-Conditional-Compilation>, <doc:02-Build>,
<doc:06-Cross-Compile> — apply these ideas in practice.

## Layer 1 — Your Swift code

**What it is.** The source you write: the top of the stack.

**What varies.** The same source often has to differ by platform. Some
libraries exist only on one platform — `AppKit` on macOS, `Glibc` on
Linux — and some APIs have a platform-specific counterpart (`CryptoKit`
on Apple platforms, swift-crypto on Linux).

**How Swift adapts — conditional compilation.** Swift selects code at
compile time based on the *target*, so one codebase compiles everywhere:

```swift
#if os(macOS)
import AppKit
#elseif os(Linux)
import Glibc
#endif
```

`#if os(...)` switches on the operating system, `#if canImport(...)`
switches on whether a module is available, and at the package level
`.when(platforms:)` decides whether a dependency is even linked. These
guards are the subject of <doc:01-Conditional-Compilation>.

## Layer 2 — The Swift standard library and Foundation

**What it is.** Two Swift libraries your code sits on. The **standard
library** is always present and fully portable — `Array`, `String`,
`Optional`, `Dictionary`, `print()`. **Foundation** is optional and
higher-level — `Date`, `URL`, `FileManager`, `JSONEncoder`, `Process`.

**What varies.** The standard library behaves identically everywhere.
Foundation does not have a single implementation: on Apple platforms it
is the system framework; on Linux it is swift-corelibs-foundation. On
Linux some networking types even live in a separate `FoundationNetworking`
module.

**How Swift adapts.** Foundation is one public API with platform-specific
implementations underneath. You write `FileManager.default`; Foundation
decides how to carry that out on each platform. Your code targets the API
and stays the same.

## Layer 3 — The Swift runtime

**What it is.** The always-present machinery beneath the libraries:
automatic reference counting, generics and type metadata, protocol
dispatch, and error handling. It exists even if you never import
Foundation.

**What varies.** The runtime is the same *concept* on every platform, but
it is a set of libraries (`libswiftCore` and friends) that must be
present for a program to run. What differs is **how it is delivered**:
linked statically into your binary, installed system-wide, or bundled as
`.so` files alongside the executable. <doc:06-Cross-Compile> shows each
of those deployment choices on a Raspberry Pi.

## Layer 4 — System libraries (the C library)

**What it is.** The platform's C library — the lowest user-space layer
Swift builds on. `glibc` on most Linux, `libSystem` on macOS, with `musl`
as a smaller alternative libc.

**What varies.** `glibc` vs `musl` vs `libSystem` are different
implementations of a similar POSIX surface. A binary linked against one
libc generally won't run against another — which is exactly why choosing
a libc matters when you ship to a different machine.

**How Swift adapts.** The `Glibc`, `Darwin`, and `Musl` modules expose
the C library to Swift, and the runtime and Foundation link against
whichever one the target uses. **Linking** happens at this layer:
combining your code, the Swift libraries, and the system libraries into
an executable. Libraries can be linked *statically* (baked into the
binary) or *dynamically* (loaded at launch from `.so`/`.dylib` files).

## Layer 5 — System calls

**What it is.** The boundary between user space and kernel space. When
your code asks for something the OS owns — say reading a file — it
crosses this boundary. `String(contentsOfFile:)` ultimately becomes
`open()`, `read()`, `close()` requests to the kernel.

**What varies.** Linux and macOS (Darwin) expose different system-call
sets and numbers, so the same high-level call lands on different syscalls
underneath.

**How Swift adapts.** You almost never write syscalls directly — the C
library and Foundation translate for you. The same Swift line works on
both systems because the layers beneath it route to the right syscall for
the target.

## Layer 6 — The kernel

**What it is.** The core of the operating system: process scheduling,
memory management, filesystems, networking, and device drivers.
Applications never touch hardware directly; they ask the kernel through
system calls.

**What varies.** Linux uses the Linux kernel; macOS uses XNU. And a
**Linux distribution** (Ubuntu, Debian, Fedora) is the kernel *plus*
system libraries, a package manager, and configuration bundled together —
the kernel is just one component. Raspberry Pi OS, used in
<doc:06-Cross-Compile>, is a Debian distribution.

**How Swift adapts.** Swift doesn't target a kernel directly; it targets
an operating system and a libc. So moving between distributions of the
same kernel (Debian ↔ Ubuntu) is usually minor — packaging and versions —
while moving between kernels (Linux ↔ XNU) is the large jump.

## Layer 7 — CPU architecture

**What it is.** The instruction set the processor actually runs:
machine instructions, registers, calling conventions, and binary format.

**What varies.** `x86_64` (Intel/AMD), `ARM64`/`AArch64` (Apple Silicon,
AWS Graviton, Raspberry Pi), and `RISC-V`. "x86" comes from Intel's
8086/286/386/486 family; "x86-64" is AMD's 64-bit extension that both
Intel and AMD now use; "ARM64" is the 64-bit ARM architecture. The
difference reaches all the way down to the instruction used to enter the
kernel — `syscall` on Linux `x86_64`, `svc #0` on Linux `ARM64` — even
though both reach the same kernel.

**How Swift adapts — cross-compilation.** The compiler can emit
instructions for a CPU *other* than the one it runs on. You tell it the
**target triple** — for example `aarch64-unknown-linux-gnu` (CPU = `aarch64`,
vendor = `unknown`, OS = `linux`, environment = `gnu`). That is how you
build on a Mac for a Raspberry Pi, the subject of <doc:06-Cross-Compile>.

> **Cross-compilation vs emulation.** Cross-compilation *builds* for
> another CPU; the result runs natively there with no translation.
> Emulation *runs* another CPU's code through a translator, which is
> slower. Docker is neither — it is containerization, sharing the host
> kernel, so the architecture must normally match (though Docker can add
> QEMU emulation to run a foreign architecture).

## Layer 8 — Hardware

**What it is.** The physical CPU, memory, and devices. Everything in the
layers above eventually executes here.

**What varies.** This is the concrete machine the CPU architecture above
describes — a Mac, a Linux server, a Raspberry Pi. Swift reaches it only
through all the layers above; you never address it directly.

## Putting it together

Portability really moves along three independent axes, and they are not
equal in size:

- **CPU architecture** (`x86_64` ↔ `ARM64`) — swaps instructions;
  cross-compilation handles it.
- **Operating system** (Linux ↔ macOS) — the biggest jump: different C
  library, system calls, kernel, and Foundation implementation.
- **Distribution** (Ubuntu ↔ Debian) — usually the smallest: packaging,
  versions, and configuration.

Pure Swift — the standard library, your algorithms — travels freely. The
friction is always at the lower layers: files, networking, processes, and
security. The whole reason it works is that the compiler, runtime,
Foundation, and linker each carry platform-specific pieces selected for
your target, while the code you write stays mostly the same.

### Aside: the compiled binary

Stepping off the layer stack for a moment — the executable those layers
produce has internal sections: code, constants, data, a symbol table, and
debug information. Debug info maps a machine address back to a source file,
line, and variable names, so a debugger can show `main.swift:42` instead
of `0x10423F810`. A release build often *strips* the debug sections for a
smaller, faster-loading binary that is harder to reverse engineer — the
executable stays one file, only the debug data is removed.
