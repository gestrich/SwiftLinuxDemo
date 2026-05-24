# SwiftLinuxDemo — Build Plan

This file drives a `/loop` that picks up the next unchecked task each iteration
and runs to completion. Mark items `[x]` as they finish, and append learnings
under the relevant task body.

The goal of the project: a minimal Swift CLI that ships a verifiable
statically-linked Linux binary via GitHub Actions (with SLSA build provenance
attestation), plus a DocC tutorial published as a GitHub Pages site. It is the
"runnable example" companion to
`AIDevTools/docs/guides/linux-builds-and-attestations.html`.

The project lives at `https://github.com/gestrich/SwiftLinuxDemo`.

---

## Foundation

- [x] **Scaffold Swift package layout (library + executable + tests)**
  Rewrite `Package.swift` for `swift-tools-version: 6.2` with:
    - Dependencies: `swift-argument-parser`, `swift-crypto`,
      `swift-docc-plugin` (DocC), `Crypto` only linked on Linux via
      `.when(platforms: [.linux])`.
    - Executable product `swift-linux-demo` (target `SwiftLinuxDemo`).
    - Library target `SwiftLinuxDemoCore` that owns the actual logic
      (Greeter, Hasher, Fetcher, PlatformInfo) and a `Documentation.docc`
      catalog. The CLI target is a thin shell over the library, which is the
      "blog-friendly" version of the AIDevTools split.
    - Tests target `SwiftLinuxDemoCoreTests` using swift-testing.
  Implement Greeter (pure), Hasher (uses `Crypto.SHA256` cross-platform),
  PlatformInfo (OS + arch + Swift compile flags), Fetcher (URLSession — the
  reason we install `libcurl4-openssl-dev` on Linux).
  CLI subcommands: `greet`, `hash`, `info`, `fetch`.

- [x] **Author DocC catalog with tutorial chapters**
  *Used Markdown articles (not `.tutorial` files) — DocC tutorials require
  `@Image` placeholders, articles render cleanly without assets and read
  well as a blog. The Discoveries chapter is a stub; the experiments
  workflow fills it in with literal compiler errors.*
  Under `Sources/SwiftLinuxDemoCore/Documentation.docc/`:
    - `SwiftLinuxDemoCore.md` — landing page.
    - `Tutorials/Table-of-Contents.tutorial` — `@Tutorials` root.
    - `Tutorials/01-The-Pipeline.tutorial` — the seven-step flow (tag →
      workflow → build → attest → release → install → verify).
    - `Tutorials/02-Building-On-Linux.tutorial` — `--static-swift-stdlib`,
      the libcurl/libxml2 question, the swift-actions/setup-swift pin.
    - `Tutorials/03-Attestation.tutorial` — `id-token: write`, OIDC, Fulcio,
      Rekor, the stolen-account threat model.
    - `Tutorials/04-DocC-On-Pages.tutorial` — how *this* repo publishes its
      own tutorial (meta).
    - `Tutorials/05-Discoveries.tutorial` — the discoveries section from
      the source guide, re-pointed at this repo's files.
  Each chapter cites the exact `Package.swift` / `release.yml` snippet from
  *this* repo so a reader can follow along.

## Release pipeline

- [x] **Author `.github/workflows/release.yml` (Linux-only)**
    - `on: push: tags: ['v*']`.
    - Workflow-level `permissions: { attestations: write, contents: write,
      id-token: write }`.
    - `test` job: ubuntu-latest, swift-actions/setup-swift@v2 pinned to 6.2,
      `apt-get install libcurl4-openssl-dev libxml2-dev`, `swift test`.
    - `build-linux` job (needs: test): same setup, then
      `swift build -c release --product swift-linux-demo --static-swift-stdlib`,
      `tar -czf swift-linux-demo-linux-x86_64.tar.gz -C .build/release
      swift-linux-demo`, then `actions/attest-build-provenance@v2` with
      `subject-path: 'swift-linux-demo-*.tar.gz'`, then `upload-artifact`.
    - `release` job (needs: build-linux): download artifact, generate
      `checksums.txt` with `sha256sum`, `gh release create` with the tarball
      and checksums.
  *No* macOS jobs — the project intentionally demonstrates Linux only.

- [x] **Author `.github/workflows/ci.yml`**
  Push + PR trigger on `main`. ubuntu-latest, setup-swift 6.2, apt deps,
  `swift build` + `swift test`. Fast feedback before tagging a release.

- [x] **Author `.github/workflows/docs.yml`**
  Push trigger on `main` (after CI). Build DocC archive with
  `swift package --allow-writing-to-directory ./_site generate-documentation
  --target SwiftLinuxDemoCore --transform-for-static-hosting
  --hosting-base-path SwiftLinuxDemo --output-path ./_site`. Upload via
  `actions/upload-pages-artifact@v3`, deploy via `actions/deploy-pages@v4`.
  Permissions: `pages: write`, `id-token: write`.

## Scripts & docs

- [x] **Write `scripts/release.sh`**
  Mirror the AIDevTools wrapper: refuse non-`v*` versions, refuse dirty
  trees, refuse duplicate tags (local + origin), then `git tag` + `git push
  origin <tag>`, then echo the Actions URL.

- [x] **Write `scripts/install.sh`**
  Linux-x86_64-only platform detection, fetch latest release via the GitHub
  API, download tarball + checksums, verify SHA-256, install to
  `/usr/local/bin` (sudo fallback). Refuse macOS with a friendly note: "this
  demo only ships Linux binaries — clone and `swift build` on macOS."

- [x] **Write `README.md`**
  One-paragraph intro, install one-liner, `gh attestation verify` one-liner,
  link to the DocC tutorial Pages URL, link to the source guide in
  AIDevTools.

## Validate locally

- [x] **Run `swift build` and `swift test` locally on macOS**
  *Pass. 8 swift-testing cases in 3 suites. CLI smoke-tested:
  `swift-linux-demo greet/hash/info` all work locally. Discovered:
  CryptoKit/SHA256Digest needs macOS 10.15+, URLSession async data needs
  macOS 12+ — added `platforms: [.macOS(.v13)]` to Package.swift to make
  these unconditionally available on macOS. No Linux equivalent gate
  needed.*

## Push & wire CI/Pages

- [x] **Commit and push initial scaffolding to `main`**
  *Pushed 6f4832d. Hit two follow-up YAML parser failures in
  experiments.yml: (1) unquoted `#if canImport(...)` in `name:` was
  treated as a YAML comment; (2) unquoted `Build (expect: …)` was treated
  as a nested mapping. Both fixed by quoting the strings.*
  Single commit, conventional message. Triggers `ci.yml` and `docs.yml`.

- [x] **Enable GitHub Pages via `gh api`**
  *Done — `build_type=workflow`. Pages will be live at
  `https://gestrich.github.io/SwiftLinuxDemo/` once `docs.yml` finishes.*
  `gh api -X POST /repos/gestrich/SwiftLinuxDemo/pages -f build_type=workflow`
  (or PUT if it already exists). Needs Pages enabled before `deploy-pages`
  will succeed.

- [x] **WAIT: `ci.yml` is green on `main`**
  *Green on commit `963cb1a` in 3m17s. Build + test + static-stdlib smoke
  test all pass on ubuntu-latest. The `--version`, `greet`, `hash`,
  `info` invocations of the statically-linked Linux binary all returned
  expected output.*

- [x] **WAIT: `docs.yml` is green on `main`**
  *Green on commit `963cb1a` in 2m55s. Pages URL is live and returning
  HTTP 200:
  `https://gestrich.github.io/SwiftLinuxDemo/documentation/swiftlinuxdemocore/`.
  No DocC warnings about missing image assets (a worry from the
  `.tutorial` → article switch) — Markdown articles render without
  complaint.*

## Experiments — empirically prove WHY each guard is needed

The source guide ("Discoveries 14.1") explains `.when(platforms:)` vs
`#if os(macOS)` in *theory*. This phase removes each guard one at a time on
the Linux runner, captures the actual compiler error, and writes those error
strings into the DocC discoveries chapter so the WHY is anchored in observed
behavior.

- [x] **Author `.github/workflows/experiments.yml`**
  `workflow_dispatch`-only workflow. Each job is one experiment:
    1. `strip-when-from-Crypto` — remove `.when(platforms: [.linux])` from
       the swift-crypto dependency. Build on Linux (should pass) AND on
       macOS (do we get a CryptoKit/Crypto name clash, or nothing? capture
       both).
    2. `strip-canImport-force-CryptoKit` — replace the `#if
       canImport(CryptoKit)` block in `Hasher.swift` with an unconditional
       `import CryptoKit`. Build on Linux — capture the
       "no such module 'CryptoKit'" diagnostic.
    3. `strip-canImport-force-Crypto-without-dep` — replace the guard with
       unconditional `import Crypto`, AND remove the `Crypto` product from
       `Package.swift`. Build on Linux + macOS — capture both
       "no such module 'Crypto'" diagnostics.
  Each job mutates files via `sed`, runs `swift build` with
  `continue-on-error: true`, redirects stderr to
  `experiments/<name>.log`, uploads as artifact. The "failure" output
  *is* the desired result.

- [x] **Trigger experiments + download captured stderr**
  *First run captured only stderr — Swift's actual compile diagnostics
  print to stdout. Re-ran with `2>&1`. Also fixed a regex that stripped
  the only entry from the dependencies array but left a trailing comma
  (`[,]`), producing "expected expression in container literal" instead
  of the "no such module" we wanted. Re-ran cleanly on run
  `26359495532`.*

- [x] **Rewrite `05-Discoveries.md` with the literal error text**
  *Done. Findings (literal quotes from the runner):*
  - *strip `.when(platforms: [.linux])`: build **succeeds** on Linux —
    `.when` is a macOS-side optimization, not a Linux correctness gate.*
  - *force `import CryptoKit` on Linux: `error: no such module 'CryptoKit'`
    at `Hasher.swift:2:8`.*
  - *force `import Crypto` with the dep removed from the target:
    `error: no such module 'Crypto'` plus the helpful warning
    `'swiftlinuxdemo': dependency 'swift-crypto' is not used by any target`.*
  Each guard gets its own step: a one-paragraph WHY, then a code fence
  showing the exact error the runner produced when the guard was removed.
  Cite the experiment job name so a curious reader can re-run it.

## Release & verify

- [ ] **Tag `v0.1.0` with `scripts/release.sh v0.1.0`**
  Only after CI is green. Pushes the tag, which fires `release.yml`.

- [ ] **WAIT: `release.yml` is green on `v0.1.0`**
  Loop checkpoint. All four jobs (test, build-linux, [attest is a step],
  release) must succeed. Verify the GitHub Release page has the tarball and
  `checksums.txt` attached.

- [ ] **End-to-end verify: `gh attestation verify` succeeds**
  Download `swift-linux-demo-linux-x86_64.tar.gz` from the v0.1.0 release
  and run `gh attestation verify <file> --repo gestrich/SwiftLinuxDemo`.
  Confirm the workflow path and commit SHA shown in the output match what
  we pushed.

- [ ] **Update README with the live Pages URL**
  Once Pages confirms the site is up, point the README at the tutorial root
  and commit the change.

---

## Learnings

(Appended as discoveries are made — each entry is anchored to the task that
produced it.)
