# Test

## Why the release pipeline runs tests first

`release.yml`'s first job is `test`. The `build-linux` job declares
`needs: test`, so if a test fails on the tagged commit, no binary is
ever compiled, no attestation is ever issued, and no GitHub Release
is created. The tag stays in the repo, but the failed workflow run is
plainly visible in the Actions tab.

This ordering matters. It would be tempting to run the build in
parallel with the tests — they're independent steps — but doing so
opens a window where a half-broken commit produces a signed, attested,
published binary. Putting the test job at the front closes that
window at the cost of a few extra minutes per release.

## What the test job does

```yaml
test:
  name: Test
  runs-on: ubuntu-24.04
  timeout-minutes: 30
  steps:
    - name: Checkout
      uses: actions/checkout@v4

    - name: Install system dependencies
      run: sudo apt-get install -y libcurl4-openssl-dev libxml2-dev

    - name: Test
      run: swift test
```

Two setup steps, then one line that does the actual work. The
`ubuntu-24.04` runner image ships Swift preinstalled, and pinning
the image version is also how the workflow holds the Swift toolchain
version stable (see <doc:02-Build>). The apt step covers
the C dependencies Foundation needs on Linux.

Running on Linux exclusively is a deliberate scope choice for this
repo, but it has a real side effect: every test in the suite has to
either work on Linux or be guarded by a `#if os(...)` source-level
condition. The `swift-testing` framework makes the latter
straightforward — see `Tests/SwiftLinuxDemoCoreTests/PlatformReportTests.swift`
for an example.

## Why the CI workflow runs the same tests on every push

`ci.yml` runs essentially the same job — `swift build`, `swift test`,
plus a `swift build -c release --static-swift-stdlib` smoke test — on
every push and pull request, not just on tags. Two jobs, separate
workflows, same toolchain pin.

The split is intentional:

- `release.yml` is *gated* by tests. A red test breaks a release.
- `ci.yml` is *predictive*. A red test on `main` warns you before you
  tag, so a tag is never the first time you find out the suite is
  broken.

Without the predictive layer, the failure mode is: tag a release,
release.yml fails on the test job, you have to delete the tag, fix,
re-tag. With CI in place, you would have already seen the same test
fail on the push that introduced the bug — which is much cheaper to
respond to.

## What gets tested in this repo

The test suite uses [swift-testing][swift-testing] (`import Testing`)
rather than XCTest. Eight tests across three suites cover the
library's public surface:

- `Greeter` — pure string greeting, plus whitespace handling.
- `Hasher` — SHA-256 against known vectors. Confirms that swift-crypto
  on Linux and CryptoKit on macOS produce identical output.
- `PlatformInfo` — verifies that `current()` produces a non-empty OS
  and architecture string, and that the rendered report includes each
  field.
- `PlatformReport` — confirms the source-level `#if os(...)` guard
  routes to the right platform-exclusive helper (`AppKitGreeter` on
  macOS, `GlibcGreeter` on Linux).

[swift-testing]: https://swiftpackageindex.com/swiftlang/swift-testing/main/documentation/testing
