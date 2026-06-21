# AGENTS

Working notes for agents (and humans) contributing to this repo.

## DocC documentation

The documentation catalog lives at
`Sources/SwiftLinuxDemoCore/Documentation.docc/`. Chapters are numbered
markdown files (`00-Concepts.md`, `01-…`) listed in the Topics section of
`SwiftLinuxDemoCore.md`. Pushing to `main` rebuilds and republishes the
site via `.github/workflows/docs.yml`.

### Diagrams & images

Diagrams are **hand-authored SVG** (vector) — not Mermaid, not raster
screenshots. SVG stays crisp at any zoom, renders cleanly in dark mode,
and diffs as text in git. Keep every diagram visually consistent with the
existing ones (`concepts-stack.svg`, `release-pipeline.svg`).

**Format & embedding**
- One `.svg` per diagram, in the `.docc` catalog, descriptively named
  (e.g. `concepts-stack.svg`).
- Embed with `![meaningful alt text](name.svg)`. Always write real alt
  text, and set `role="img"` + `aria-label` on the `<svg>` element.
- **Always set explicit `width` and `height` on `<svg>`** (in addition to
  `viewBox`). Without them, DocC/browsers fall back to a tiny ~300×150
  default and the diagram renders small. Use the viewBox dimensions; DocC
  scales down to the content column.
- Typical canvas width is ~760–820 units.
- After writing/editing an SVG, render it before committing:
  `qlmanage -t -s 1000 -o /tmp <file>.svg` then open `/tmp/<file>.svg.png`.

**Dark mode (always)**
- Card background `#0d1117`, border `#30363d`, corner radius `16`.
- Inner panels/zones: fill `#161b22`, border = an accent color at
  `stroke-opacity="0.6"`, radius `12`.
- Component boxes (solid bars): radius `8–9`, white text.
- Interfaces/boundaries: no fill, dashed border (`stroke-dasharray="6 4"`)
  in `#8b949e`, italic label in `#c9d1d9`.
- Connectors/arrows: `#8b949e`, stroke-width ~`2.5`, with an arrowhead
  marker.

**Color palette** (accent/node fills — choose by meaning, reuse across
diagrams):

| Use | Hex |
|---|---|
| Swift / top of stack | `#f05138` |
| warm accents, descending | `#e8590c` · `#d97706` · `#bf8700` |
| purple — libraries / boundaries | `#8957e5` · `#6639ba` |
| blue — kernel / system | `#1f6feb` (labels `#58a6ff`) |
| green — positive / "things you control" | `#3fb950` (darker `#1a7f37`) |
| gray — hardware / neutral | `#545d68` · `#8b949e` |
| muted text & labels | `#8b949e` |
| secondary text on a colored fill | `#ffffff` at `fill-opacity="0.85"` |

**Typography**
- Font: `-apple-system, Helvetica, Arial, sans-serif` for prose-style
  diagrams; `ui-monospace, SFMono-Regular, Menlo, monospace` for
  command/code-style ones (e.g. the release pipeline).
- Box title: `14.5`px, weight `600`, white.
- Annotations on a box: `12`px, white at `fill-opacity="0.85"`,
  right-aligned.
- Zone / section labels: `12.5`px, weight `700`, `letter-spacing="1"`, in
  the zone's accent color.
- Footer / caption: `12`px, italic, `#8b949e`.

**Shared visual vocabulary** (keep meaning identical across diagrams)
- Solid filled box → a **component** (a real body of code or hardware).
- Dashed outlined box or line → an **interface / boundary**.
- Green bracket or label → "ships with your app" / things you control.

On the published site DocC rehosts these under
`/images/SwiftLinuxDemoCore/<name>.svg`.
