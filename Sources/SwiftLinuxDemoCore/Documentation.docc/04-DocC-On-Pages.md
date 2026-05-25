# Document

## Why publish documentation as a real website

If you've shipped a Swift library before but always sent users to a
README on GitHub, this is the upgrade path: rendered documentation
with full symbol pages, code examples, and full-text search — hosted
on a free URL and rebuilt automatically on every push to `main`.

[DocC][docc] is Apple's documentation compiler; [GitHub Pages][pages]
is GitHub's static-site host. The two fit together cleanly with a
small workflow file plus three flags on the build command and one
extra permission scope on the deploy step.

[docc]: https://www.swift.org/documentation/docc/
[pages]: https://docs.github.com/en/pages/getting-started-with-github-pages/about-github-pages

## What DocC produces

DocC is Apple's documentation compiler. Pointed at a Swift target, it
extracts the public API surface, renders any Markdown articles
authored alongside the source (the `Documentation.docc` folder), and
produces a single browsable archive — either a `.doccarchive` bundle
for use inside Xcode, or a tree of static HTML when given the right
flags.

The static-HTML mode is what we want. Every page is a regular file on
disk, and any plain HTTP server can serve them; no Apple-specific
"DocC server" is required.

## The build step

`.github/workflows/docs.yml` runs on every push to `main`. The build
step is one command:

```bash
swift package \
  --allow-writing-to-directory ./_site \
  generate-documentation \
  --target SwiftLinuxDemoCore \
  --transform-for-static-hosting \
  --hosting-base-path SwiftLinuxDemo \
  --output-path ./_site
```

The three DocC-specific flags each do one job:

- `--target SwiftLinuxDemoCore` — which target's docs to build. The
  CLI target (`SwiftLinuxDemo`) is intentionally thin and has no DocC
  catalog of its own; all the prose lives in the library, where the
  public API surface also lives.
- `--transform-for-static-hosting` — rewrites the generated HTML to
  use relative paths and an `index.html` at each route, so any static
  host (not just Apple's tooling) can serve it.
- `--hosting-base-path SwiftLinuxDemo` — the repository name. GitHub
  Pages serves project sites at `https://<owner>.github.io/<repo>/`,
  so every internal link needs `/SwiftLinuxDemo/` as a path prefix.

The `swift package generate-documentation` invocation comes from
[swift-docc-plugin][docc-plugin], a SwiftPM plugin you add to
`Package.swift` as a dependency. Once it's there, the command becomes
available as a package plugin without further setup.

[docc-plugin]: https://github.com/swiftlang/swift-docc-plugin

## The deploy step

GitHub's official Pages actions handle the upload and deploy:

```yaml
- uses: actions/upload-pages-artifact@v3
  with:
    path: _site
- uses: actions/deploy-pages@v4
```

Two actions, in order: package the `_site` folder as a Pages
artifact, then deploy it. The deploy job needs:

```yaml
permissions:
  pages: write
  id-token: write
```

`pages: write` is the obvious one. `id-token: write` is there for the
same reason it was in <doc:03-Attestation>: GitHub uses an OIDC token
to verify that the deploy is coming from a workflow run authorized
to publish to this repo's Pages site. The token doesn't get used for
artifact signing here, only for *who-can-deploy* authorization.

And the repository itself needs Pages enabled with the *GitHub
Actions* build source. Either through the UI
(`Settings → Pages → Source: GitHub Actions`) or via the API in one
shot:

```bash
gh api -X POST /repos/gestrich/SwiftLinuxDemo/pages -f build_type=workflow
```

## Why a separate target for documentation?

DocC builds documentation for *one* target at a time. Splitting the
package into a thin executable (`SwiftLinuxDemo`) and a library
(`SwiftLinuxDemoCore`) means the documented surface lives in the
library, and the CLI stays as a small `ArgumentParser` shim that
calls into it. That split makes the executable easier to test, easier
to reuse from other code, and easier to document — DocC will only
have to walk one module.

## See Also

- <doc:05-Discoveries>
- [DocC documentation reference][docc] on swift.org.
- [GitHub Pages and Actions integration][pages-actions].

[pages-actions]: https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site#publishing-with-a-custom-github-actions-workflow
