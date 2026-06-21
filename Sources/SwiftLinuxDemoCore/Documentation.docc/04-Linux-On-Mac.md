# Linux on Mac

Most of this project's Linux work happens in CI, but there are times you
want to produce or run a Linux build from your Mac directly. This chapter
frames *why* and *what's hard about it*; the conceptual background is in
<doc:00-Concepts> and the full hands-on procedure is in
<doc:06-Cross-Compile>.

## Motivation

### Debugging build issues

> **TODO:** explain using a local Mac→Linux build to debug Linux-only
> build failures without the round-trip through CI. Needs source info —
> do not invent.

### Working with embedded devices (faster on Mac)

Building on the Mac and shipping the result to a small device is often
much faster than compiling on the device itself (a Raspberry Pi compiles
slowly). The end-to-end version of this — build on the Mac, run on the Pi
— is <doc:06-Cross-Compile>.

> **TODO:** expand on the embedded workflow advantages of building on the
> Mac vs. on-device.

## Challenges

### CPU architecture

The Mac and the target may use different instruction sets (Apple Silicon
is ARM64; many Linux servers are x86_64). That difference is what makes
this more than a recompile. See the CPU-architecture layer in
<doc:00-Concepts>.

### System calls

The other moving part is the operating system: a Linux binary talks to
the Linux kernel through its system-call interface, which differs from
macOS's. The system-call boundary is covered in <doc:00-Concepts>.

## Cross-compilation

Cross-compilation is building, on your Mac, a binary whose instructions
target another CPU and OS. This project's worked example — installing the
Swift SDK, building, and running on a Raspberry Pi — is the whole of
<doc:06-Cross-Compile>. The concept and how it differs from emulation are
in <doc:00-Concepts>.

## Emulation

Emulation runs another machine's code by translating its instructions at
run time, rather than building native code for it ahead of time. The
contrast with cross-compilation (and where Docker fits) is covered in
<doc:00-Concepts>.

> **TODO:** if this chapter should carry its own emulation walkthrough
> (e.g. running a Linux container via QEMU on the Mac) rather than only
> pointing at <doc:00-Concepts>, add it here.

## See Also

- <doc:00-Concepts>
- <doc:06-Cross-Compile>
