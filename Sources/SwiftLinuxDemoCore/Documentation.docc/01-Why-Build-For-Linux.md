# Why Build for Linux

Swift began as an Apple-platforms language, but it runs on Linux too —
and there are real reasons to ship a Linux build of a Swift project, not
just an Apple one.

> **TODO:** write the overview paragraph that frames the two motivations
> below and sets up the rest of the documentation. No source material
> exists yet — do not invent specifics.

## Cheaper

Linux is the default of server and cloud computing, where the hosting is
cheaper and you aren't tied to Apple hardware to run or build the code.

> **TODO:** flesh out the cost argument with concrete points — Linux
> server/cloud hosting vs. macOS hosting, cheaper ARM instances (e.g. AWS
> Graviton), CI minutes, no Apple-hardware requirement. Needs real figures
> or examples; do not invent numbers.

## Embedded devices

Linux also runs on small and embedded hardware — single-board computers
like the Raspberry Pi and many IoT devices — which makes a Linux Swift
build the way to put Swift on those targets. The hands-on path for one
such target is in <doc:06-Cross-Compile>, and the architecture concepts
behind it are in <doc:00-Concepts>.

> **TODO:** expand the embedded-devices motivation: which classes of
> devices, why Swift there, and what the developer experience looks like.
> Needs source info.
