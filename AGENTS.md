# AGENTS.md

Template repo: a Quarto website whose pages are **Literate.jl scripts** executed in CI and published to GitHub Pages.
No tests, lint, formatter, or build system — verification means running the pipeline steps below successfully.

## The pipeline (order matters)

The real sources are `docs/**/*.jl`. `.ipynb` files are generated artifacts and are **not committed**, yet
`docs/_quarto.yml` sidebar lists them (`index.ipynb`, `pythonplot-lit.ipynb`, `sub/plots-lit.ipynb`).

```sh
julia --project=@. -p 4 .github/ci.jl                          # 1. execute Literate notebooks -> .cache/docs/**
bash .github/quarto.sh                                          # 2-5. stage, install Quarto, render, verify, publish
```

Steps 2-5 are one bash script, not inline YAML: it copies `.cache/docs/*` into `docs/`, downloads and checksum-verifies
the latest standalone Quarto, renders a **throwaway copy** of `docs/` (see the `.jl` gotcha below), asserts every page,
and only then replaces `docs/_site/`. It prints `::group::` sections under `GITHUB_ACTIONS` and plain headers locally,
and it never modifies a tracked file. `.github/workflows/ci.yml` is the source of truth; `ci.jl` and `quarto.sh` are
the drivers it invokes (one Julia, one shell). Both honor `DOCDIR` (default `docs`) and `NBCACHE` (default `.cache`).

Run `ci.jl` **from the repo root**: it calls `Literate.notebook(file, dirname(file))` with paths relative to the CWD.
`quarto.sh` likewise must run from the repo root and fails fast with a named path if `docs/_quarto.yml` is missing.

## Gotchas that will bite you

- **Stale generated notebooks survive locally.** `ci.jl` writes `.ipynb` into `docs/` *and* copies to `.cache/`; both
  are gitignored (`*.ipynb`, `.cache/`), so `git status` stays clean and hides them. `clean_cache` only prunes orphans
  inside `.cache/`, never the copies in `docs/` — so renaming or deleting a `docs/*.jl` leaves its `.ipynb` behind and
  Quarto keeps rendering it as a live page (the sidebar controls navigation, not which files render). After a rename
  or delete: `rm -rf .cache && find docs -name '*.ipynb' -delete && rm -rf docs/*_files`, then rebuild. (Rendering a
  single notebook in place, e.g. `quarto render docs/foo.ipynb`, also drops assets in `docs/foo_files/`.)
- **`.gitignore` hardcodes `.cache/` while the directory comes from `ENV["NBCACHE"]`** (default `.cache` in
  `.github/ci.jl`; set in `ci.yml`). If you change `NBCACHE`, add the new name to `.gitignore` too. Likewise `*.ipynb`
  is repo-wide, so committing a genuine notebook needs `git add -f`.
- **A `.jl` sibling silently shadows its `.ipynb`.** This is the single biggest trap. If `docs/foo.jl` exists next to
  `docs/foo.ipynb`, Quarto does *not* render the notebook — it copies the raw `.ipynb` into `_site` as a static
  resource, exits **0**, and prints no warning. With all three sources present you get only `404.html` + `about.html`
  plus a ~230-byte `index.html` that is just a `<meta http-equiv="refresh">` stub (the target it names varies:
  `404.html` in one run, `about.html` in another). `ci.jl` leaves exactly this state on disk, so the `.jl` files must
  be absent from *the tree that is rendered*. `quarto.sh` copies `docs/` to a `mktemp -d` directory, deletes `*.jl`
  **in the copy**, renders it into that same directory (`$stage/_site`), verifies it there, and only then replaces
  `docs/_site/` by copying. Never pass `--output-dir` pointing outside the project: Quarto warns about exactly that
  ("did not expect the path configuration being used in this project") and then **refuses to remove stale output**
  there, so an old build can mask a broken one.

  Two alternatives were tested and are worse. **Deleting the `.jl` files in place** (what this repo used to do) is
  load-bearing but destructive: run it locally and `git checkout docs/` is your only recovery. **Renaming them to
  `.jl.bak` and restoring afterwards** renders correctly and leaks nothing into `_site`, but `kill -9` between the two
  steps leaves all three sources renamed (measured: 0 `.jl`, 3 `.jl.bak`). A killed staging run leaks only a ~1 MB
  `mktemp -d` directory — the `trap ... EXIT` cannot fire on `SIGKILL` — and never touches a tracked file.
  **A `project.render:` file list in `_quarto.yml` does not help at all** — the collision is resolved before that list
  is consulted, so you still get 3 pages and the redirect stub.

  To reproduce it against a scratch copy, keeping your sources:

  ```sh
  stage=$(mktemp -d) && cp -r docs/. "$stage"/ && rm -rf "$stage/.quarto" "$stage/_site"
  find "$stage" -type f -name '*.jl' -delete && quarto render "$stage" --to html
  ```

  A missing page is easy to miss, so `quarto.sh` asserts that every `docs/**.qmd` and `docs/**.ipynb` has a non-empty
  `_site/**.html` sibling in the **staging** output and that its `index.html` is not a refresh stub; it derives the
  expected list from the sources, so adding a page needs no edit there. Because the checks run on the staging copy
  before `docs/_site` is replaced, a failed build leaves the previous site in place rather than publishing a partial
  one. Clear `docs/.quarto/` too when re-rendering by hand after edits.
- **Cache is content-hash based.** `.cache/<path>/<name>.sha` stores the SHA256 of the `.jl`; a match skips execution.
  Re-run one notebook: `rm .cache/docs/sub/plots-lit.sha` then re-run `ci.jl`. Full rebuild: `rm -rf .cache`.
- **Only `.jl` sources are discovered.** `list_notebooks` ignores `.ipynb` files already in `docs/`. `to_literate`
  in `ci.jl` is an unused helper for one-off manual notebook conversions.
- **`.qmd` files are prose only.** `IJulia` is not in `Manifest.toml`, so Quarto cannot execute Julia cells. Put
  executable code in a `docs/**.jl`; `about.qmd` / `404.qmd` contain no code.
- **Adding a page requires three edits**: create `docs/foo.jl`, run `ci.jl`, and add `foo.ipynb` (note the extension)
  to `website.sidebar.contents` in `docs/_quarto.yml`.
- A notebook error makes `ci.jl` exit non-zero after printing `Please check error(s).`; per-notebook failures are
  collected via `pmap(...; on_error=identity)` rather than raised immediately, so scroll up for the real traceback.

## Literate conventions used here

Literate is called with `mdstrings=true`. `#===` … `===#` is a markdown cell, `#---` starts a new code cell, and
`# `-prefixed lines become markdown (use `# # Title` for a page heading). Markdown links in notebooks are checked
monthly by lychee (`linkcheck.yml`, files an issue rather than failing) — write links as `<https://…>`.

## Environment

- **Julia 1.13** is required (`[compat] julia = "1.13"`). CI reads the exact version from `julia_version` in
  `Manifest.toml` (currently 1.13.3) and installs that.
- Root `Project.toml` is a **Pkg workspace** (`[workspace] projects = ["Startup"]` + `[sources]`). `Startup/` is a
  real package serving as the place to add project dependencies and precompilation; add deps to
  `Startup/Project.toml`, not only the root. `Startup/Manifest.toml` is gitignored; the **root `Manifest.toml` is
  committed on purpose** (static app environment, refreshed by `update-manifest.yml`) — do not delete it.
- `PythonPlot` pulls matplotlib through CondaPkg. CI sets `JULIA_CONDAPKG_ENV=@mpl`, a shared env at
  `~/.julia/conda_environments/mpl`. Export it locally too or CondaPkg silently builds a per-project env.
  `GKSwstype=100` (headless GR for Plots) is set inside `ci.jl`, not in the shell.
- **Quarto is a standalone tarball, not an apt package** — no sudo, no `quarto-actions/setup@v2`. `quarto.sh` resolves
  `.../releases/latest` at runtime (a 302 to the tag; `curl -I` needs `-L` to follow it), maps `uname -m` to
  `amd64`/`arm64`, downloads `quarto-<ver>-linux-<arch>.tar.gz`, and verifies it against that release's own
  `quarto-<ver>-checksums.txt` via `grep -F " $name" ... | sha256sum --check --status`. **There is deliberately no
  version pin.** Note the checksum comes from the same origin as the binary, so it proves integrity of the download,
  not authenticity of the release. Extract with `--strip-components=1` (the archive contains only `bin/` and `share/`),
  into `$RUNNER_TEMP` (fallback `$TMPDIR`, then `/tmp`); an existing `bin/quarto` there skips the download. Locally it
  lives in `~/.local/share/quarto-1.10.20` with `~/.local/bin/quarto` symlinked to its `bin/quarto`.
- **`$GITHUB_PATH` additions do not apply to the rest of the same step** — only to later steps, and inside `quarto.sh`
  there is no later step at all. The script therefore does `export PATH="$qroot/bin:$PATH"` itself; without it the
  `quarto --version` self-check and the render die with 127. Keep both lines when editing that section.
- **Rendering `.ipynb` here needs no Jupyter and no Julia kernel.** The notebooks arrive pre-executed from Literate, so
  Quarto's native renderer handles them; verified rendering all five pages with `jupyter` absent from `PATH`. Do not
  "fix" missing pages by installing Jupyter or IJulia — check the `.jl` sibling gotcha first.
- For iterating on notebook code without paying package startup cost, `jld eval '...'` (persistent Revise daemon,
  auto-detects this project) is much faster than a fresh `julia --project=@.`; `--project` needs a real path, not `@.`.

## CI / publishing

- `ci.yml` runs on `ubuntu-26.04-arm`; deploy runs on `ubuntu-slim` and only on `refs/heads/main`. GitHub Pages
  source must be set to *GitHub Actions* in repo settings.
- Notebook caching is aggressive: a `notebook-*` cache hit (keyed on `hashFiles('docs/**/*.jl')` plus
  `Project.toml`/`Manifest.toml`/`Startup/**`) skips Julia setup, instantiation, *and* execution. Bump `CACHE_NUM`
  in `ci.yml` or delete caches via `clear-cache.yml` when results look stale.
- `update-manifest.yml` opens and auto-merges a weekly Manifest PR using a GitHub App token (`APP_ID` 189113) so
  downstream workflows re-trigger. Dependabot covers **github-actions only** (the `julia` ecosystem is commented out).
  Auto-merge is handled by Kodiak (`.github/.kodiak.toml`, squash) and needs the `automerge` label.
- Everything after **Run notebooks** except the upload is one `Build site` step running `bash .github/quarto.sh`, and it
  has no `if:` guard at all — unlike the Julia setup/instantiation steps, so self-hosted runners download Quarto too.
- Quarto is **unpinned by design**: every run takes whatever `releases/latest` returns, so a bad upstream release
  breaks CI with no rollback lever. To pin, replace the `ver=$(curl ...)` line in `quarto.sh` with a literal.

## Style

`.editorconfig`: 4-space indent for `.jl` (and `.sh`, via the `*` rule); 2-space for `.yml`, `.toml`, `.md`, `.json`;
UTF-8, final newline, no trailing whitespace. Keep `.github/quarto.sh` shellcheck-clean (`shellcheck .github/quarto.sh`
reports nothing today).
