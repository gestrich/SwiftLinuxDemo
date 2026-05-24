# ``SwiftLinuxDemoCore``

A working example of how a small Swift command-line tool can be built,
signed, and published in a way that anyone can independently verify —
from raw source code through to a binary downloaded on someone else's
machine.

## What this project is

When you download a binary from the internet, you usually have no way
to confirm where it actually came from. The source code might be open
and well-audited, but the binary on the release page is opaque: it
could have been built from a different commit, modified after the fact,
or replaced entirely with something malicious. Most of the time, all
you have to go on is *"the URL looks official."*

This project shows what a stronger model looks like in practice. The
Swift CLI it ships is deliberately small — a handful of subcommands
wrapping a couple of library targets. The interesting part is the
*release pipeline* around it. Every release is built on a Linux runner
from a specific commit of this repository, packaged with the Swift
runtime statically linked, and accompanied by a cryptographic proof —
signed during the build itself — that the resulting binary came from
that exact source.

A user who downloads the binary can verify all of those claims with a
single command, without needing to trust the maintainer's account
security, the CDN that served the file, or any other link in the
chain.

## How the chapters fit together

The walkthrough has two threads running side by side: the *mechanics*
(the YAML files, the build flags, the gh CLI commands) and the *trust
model* underneath them — what supply-chain problem each piece actually
solves, and, just as importantly, what it doesn't.

One sentence to keep in mind throughout:

> Attestation proves *how* a binary was produced; provenance is the
> broader history that gives that proof meaning.

## Topics

### Walkthrough

- <doc:01-The-Pipeline>
- <doc:02-Building-On-Linux>
- <doc:03-Attestation>
- <doc:04-DocC-On-Pages>
- <doc:05-Discoveries>

### Library types

- ``Greeter``
- ``Hasher``
- ``PlatformInfo``
- ``Fetcher``
