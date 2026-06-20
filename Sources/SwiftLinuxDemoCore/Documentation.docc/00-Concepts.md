# Concepts

A mental model for what actually changes when you build and run the
same Swift code on macOS and Linux — and how the layers beneath your
code (runtime, system libraries, system calls, kernel, and CPU) fit
together.

The how-to chapters that follow — <doc:01-Conditional-Compilation>,
<doc:02-Build>, <doc:04-Attest> — assume the ideas on this page. This
chapter builds the intuition behind them.

## The big picture

Running Swift code involves several layers, each providing services to
the one above it:

```
Your Swift code
      ↓
Foundation (optional)
      ↓
Swift standard library
      ↓
System libraries   (glibc on Linux, libSystem on macOS)
      ↓
System calls
      ↓
Kernel             (Linux, or XNU on macOS)
      ↓
CPU instructions   (x86_64, ARM64, …)
      ↓
Hardware
```

When you target Linux instead of macOS, only some of these layers
change. The rest of this chapter walks each one.

## Layer 1: CPU architecture

This is the lowest software-visible layer. An architecture defines the
machine instructions, registers, memory layout, function calling
conventions, and binary format that a CPU understands.

| Architecture | Common usage |
|---|---|
| `x86_64` | Intel/AMD: Windows PCs, Linux servers |
| `ARM64` (`aarch64`) | Apple Silicon, AWS Graviton, iPhones, Android, Raspberry Pi |
| `RISC-V` | Open-standard cores, embedded |

**x86** comes from Intel's processor family — the 8086, 80286, 80386,
and 80486 — which eventually became known collectively as x86.

**x86-64** is the 64-bit extension of x86, originally developed by AMD.
Today both Intel and AMD CPUs use it.

**ARM64** comes from ARM ("Advanced RISC Machines"). ARM designs the
architecture; companies like Apple, Qualcomm, and Samsung build the
actual chips. ARM itself is headquartered in Cambridge.

### Architecture and operating system are independent

CPU architecture and operating system are *separate* axes. The
architecture defines the instructions a processor runs; the operating
system defines the services programs can ask for. The same Ubuntu runs
on `x86_64` or `ARM64`, and the same `ARM64` chip can run Linux, macOS,
or Windows. Keeping these two ideas apart is the foundation of the
mental model at the end of this chapter.

## Layer 2: Cross-compilation

Normally you compile for the machine you're sitting at:

```
Mac ARM
   ↓
Mac ARM executable
```

Cross-compilation generates instructions for a *different* CPU:

```
Mac ARM
   ↓
Linux x86 executable
```

The compiler simply emits instructions for another CPU. Think of it as
sitting in America writing a book in French — you don't have to be
French to write French. <doc:06-Cross-Compile> walks through doing this
for real, building on a Mac for a Raspberry Pi.

### Target triples

To do this, the compiler needs to know the target, expressed as a
*triple*:

```
x86_64-unknown-linux-gnu
```

| Field | Value |
|---|---|
| CPU | `x86_64` |
| Vendor | `unknown` |
| OS | `linux` |
| Environment | `gnu` |

Another example: `aarch64-apple-macosx`.

## Layer 3: The Swift standard library

The standard library is *always* required. It provides `Array`,
`String`, `Optional`, `Dictionary`, `print()`, and so on. These are
**not** Foundation — you can write the following without importing
anything:

```swift
let numbers = [1, 2, 3]
print(numbers)
```

## Layer 4: Foundation

Foundation is *optional*. It provides higher-level types like `Date`,
`URL`, `FileManager`, `JSONEncoder`, and `Process`, and sits on top of
the standard library:

```
Foundation
     ↓
Swift standard library
```

### How Foundation works

There is **not** a completely separate Foundation for Linux. Instead,
one major codebase has platform-specific implementations underneath a
stable public API:

```swift
#if os(macOS)
    // use Darwin
#elseif os(Linux)
    // use Glibc
#endif
```

You write `FileManager.default`; Foundation decides how to implement
that on each platform.

## Layer 5: Operating system differences

Eventually something has to ask the OS for a resource. Reading a file
travels the full stack:

```
FileManager
   ↓
Foundation
   ↓
System libraries   (glibc / libSystem)
   ↓
System calls
   ↓
Kernel
   ↓
Disk
```

This is where platform-specific behavior lives.

### System calls

A *system call* is the boundary between user-space (your program) and
kernel-space (the operating system core). Innocuous-looking Swift:

```swift
String(contentsOfFile: "/tmp/test.txt")
```

eventually becomes something conceptually like `open()`, `read()`,
`close()`. Each of those is a request asking the kernel to perform a
privileged operation on your behalf — your program never touches the
disk directly.

### Same API, different implementation

At the top, the Swift API can look identical across platforms; the
lower layers differ:

```
Linux:  Swift → Foundation → glibc     → Linux syscalls  → Linux kernel
macOS:  Swift → Foundation → libSystem → Darwin syscalls → XNU kernel
```

`String(contentsOfFile:)` is the same call in both; what it resolves to
underneath is not.

### The system-call instruction

The difference reaches all the way down to the machine instruction used
to enter the kernel:

| Target | Instruction |
|---|---|
| Linux `x86_64` | `syscall` |
| Linux `ARM64` | `svc #0` |

Both invoke the *same* Linux kernel — only the instruction that crosses
the boundary changes with the architecture.

## The kernel

The kernel is the core of the operating system. It is responsible for:

- Process scheduling
- Memory management
- Filesystems
- Networking
- Device drivers

Applications don't normally talk to hardware directly; they ask the
kernel to do the work (through system calls, above). Linux uses the
Linux kernel; macOS uses XNU.

## Linux distributions

A Linux *distribution* is a complete operating system built around the
Linux kernel. A distribution bundles:

- The Linux kernel
- System libraries
- A package manager
- Shells and utilities
- Configuration

So the kernel is just *one component* of a distribution. Ubuntu, Debian,
and Fedora are all distributions sharing the same kernel lineage but
differing in packaging, versions, and defaults. (Raspberry Pi OS, used
in <doc:06-Cross-Compile>, is a Debian distribution.)

## Layer 6: Linking

Compilation produces object files. *Linking* combines your code, the
Swift libraries, Foundation, and the system libraries into a final
executable. Different targets link against different platform
libraries:

| Platform | Links against |
|---|---|
| macOS | Darwin, Apple frameworks |
| Linux | glibc, Swift runtime, Foundation |

### Dynamic libraries

Not everything lives inside your executable. An app may depend on
`libswiftCore` and `libFoundation`, which are loaded at runtime rather
than baked into the binary.

## Deploying Swift on Linux

There are two common approaches (this repo's static-stdlib build,
covered in <doc:02-Build>, is a third).

**Option 1 — install Swift system-wide.** The Swift runtime and
Foundation are installed once and shared by every app on the machine.

**Option 2 — bundle everything.** Ship the runtime libraries alongside
the executable:

```
MyApp/
    MyApp
    lib/
        libswiftCore.so
        libFoundation.so
        ...
```

The executable loads its libraries from the local folder. This is
common for self-contained deployments. <doc:06-Cross-Compile> uses
exactly this model to run on a Raspberry Pi.

## The Swift runtime

The runtime provides services like memory management, reference
counting, generics support, and protocol dispatch. It exists even when
you don't use Foundation:

```
Foundation
   ↓
Swift runtime
   ↓
OS
```

## Emulation vs cross-compilation

These are easy to confuse.

**Cross-compilation** builds for another machine, with no translation
at execution time:

```
Mac
 ↓
Linux executable
```

**Emulation** runs another machine's code virtually, translating
instructions as it goes — which is slower:

```
Linux executable
 ↓
Emulator
 ↓
Mac
```

### How emulation works

Suppose a 32-bit application executes `ADD registerA, registerB`. The
emulator reads the instruction, works out what it means, produces the
equivalent host operations, and maps the registers, memory, and system
calls. It is essentially a live translator.

## Docker

Docker is **not** emulation — it is containerization:

```
Your app
 ↓
Linux container
 ↓
Host kernel
```

The host architecture usually has to match.

### Docker + emulation

Docker can also use QEMU, combining both techniques:

```
ARM Mac
 ↓
Docker
 ↓
QEMU
 ↓
x86 Linux container
```

Now you have containerization and emulation working together.

## Debug symbols

An executable contains several sections:

```
Executable
├── Code
├── Constants
├── Data
├── Symbol table
└── Debug information
```

Debug information maps a machine address back to a source file, line
number, and variable names, so a debugger can show `main.swift:42`
instead of `0x10423F810`.

### Stripping

A release build often strips debug symbols. The benefits are a smaller
executable, faster loading, and a binary that's harder to reverse
engineer. The executable stays a single file — only the debug sections
are removed.

## Mental model summary

Swift portability comes down to six layers:

1. **CPU architecture** — ARM64 vs x86_64
2. **Operating system** — macOS vs Linux
3. **Swift runtime** — core Swift functionality
4. **Foundation** — optional higher-level APIs
5. **Linking** — connecting to platform libraries
6. **Packaging** — how runtime dependencies are deployed

### Three dimensions of change

It also helps to think of portability along three *independent* axes,
and to remember that they are not equal in size:

1. **CPU architecture** — `x86_64` ↔ `ARM64`. Swaps CPU instructions
   and a little architecture-specific kernel code.
2. **Operating system** — Linux ↔ macOS ↔ Windows. The biggest jump:
   different system libraries, system-call interface, kernel, and
   Foundation implementation.
3. **Distribution** — Ubuntu ↔ Debian ↔ Fedora. Usually the smallest:
   mostly packaging, versions, and configuration.

**Operating-system changes are generally much larger than architecture
changes.**

### What's portable, what isn't

Pure Swift — `Array`, `String`, `Optional`, algorithms — is usually
portable as-is. The places that need care are the ones that reach down
the stack: files, networking, processes, security, and other OS-specific
APIs.

The key insight is that Swift itself is largely platform-independent.
Cross-compilation works because the compiler, runtime, Foundation, and
linker each have platform-specific pieces that are selected for the
target you're building for, while your application code can often stay
exactly the same.
