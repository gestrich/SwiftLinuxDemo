# Shipping DocC on GitHub Pages

The site you're reading right now is built and deployed by a workflow in the
same repo it documents. Here is how that loop closes.

## The workflow

`.github/workflows/docs.yml` runs on every push to `main`. The build step is
one command:

```bash
swift package \
  --allow-writing-to-directory ./_site \
  generate-documentation \
  --target SwiftLinuxDemoCore \
  --transform-for-static-hosting \
  --hosting-base-path SwiftLinuxDemo \
  --output-path ./_site
```

Three flags worth unpacking:

- `--target SwiftLinuxDemoCore` — which target's docs to build. The CLI
  target (`SwiftLinuxDemo`) is intentionally thin and has no DocC catalog;
  all the prose lives in the library, which is also where the public API
  surface lives.
- `--transform-for-static-hosting` — rewrites the generated HTML to use
  relative paths and an `index.html` at each route, so it runs under any
  static host (no Apple "DocC server" needed).
- `--hosting-base-path SwiftLinuxDemo` — the repo name. GitHub Pages serves
  this site at `https://<owner>.github.io/<repo>/`, so every internal link
  needs `/SwiftLinuxDemo/` as a prefix.

## The deploy step

```yaml
- uses: actions/upload-pages-artifact@v3
  with:
    path: _site
- uses: actions/deploy-pages@v4
```

Two actions, in order: package the `_site` folder as a Pages artifact, then
deploy it. The deploy step needs:

```yaml
permissions:
  pages: write
  id-token: write
```

And the repo needs Pages enabled with the "GitHub Actions" build source
(Settings → Pages → Source: GitHub Actions, or `gh api -X POST
/repos/<owner>/<repo>/pages -f build_type=workflow`).

## Why a separate target for docs?

DocC builds documentation for *one* target at a time. Splitting the package
into a thin executable (`SwiftLinuxDemo`) and a library
(`SwiftLinuxDemoCore`) puts the documented surface in the library. The CLI
stays as a small ArgumentParser shim that calls into the library — easier
to test, easier to document.

## Meta: this page

The article you're reading is `04-DocC-On-Pages.md` inside
`Sources/SwiftLinuxDemoCore/Documentation.docc/`. The build command above
turns it into HTML and the deploy step pushes it to the URL you opened.

## See Also

- <doc:05-Discoveries>
