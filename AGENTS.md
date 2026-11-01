# AGENTS.md

Template repo: a Quarto website whose pages are **Literate.jl scripts** executed in CI and published to GitHub Pages.
No tests, lint, formatter, or build system — verification means running the two pipeline steps below successfully.

## The pipeline (order matters)

The real sources are `docs/**/*.jl`. `.ipynb` files are generated artifacts and are **not committed**, yet
`docs/_quarto.yml` sidebar lists them (`index.ipynb`, `pythonplot-lit.ipynb`, `sub/plots-lit.ipynb`).
`quarto render` therefore fails until the notebooks have been built.

```sh
julia --project=@. -p 4 .github/ci.jl                        # 1. execute Literate notebooks -> .cache/docs/**
cp -rf .cache/docs/* docs/                                    # 2. stage them for Quarto
quarto render docs/ --to html                                 # 3. -> docs/_site/
```

Run `ci.jl` **from the repo root**: it calls `Literate.notebook(file, dirname(file))` with paths relative to the CWD.
`.github/workflows/ci.yml` is the source of truth; `.github/ci.jl` is the driver it invokes.

## Gotchas that will bite you

- **Stale generated notebooks survive locally.** `ci.jl` writes `.ipynb` into `docs/` *and* copies to `.cache/`; both
  are gitignored (`*.ipynb`, `.cache/`), so `git status` stays clean and hides them. `clean_cache` only prunes orphans
  inside `.cache/`, never the copies in `docs/` — so renaming or deleting a `docs/*.jl` leaves its `.ipynb` behind and
  Quarto keeps rendering it as a live page (the sidebar controls navigation, not which files render). After a rename
  or delete: `rm -rf .cache && find docs -name '*.ipynb' -delete`, then rebuild.
- **`.gitignore` hardcodes `.cache/` while the directory comes from `ENV["NBCACHE"]`** (default `.cache` in
  `.github/ci.jl`; set in `ci.yml`). If you change `NBCACHE`, add the new name to `.gitignore` too. Likewise `*.ipynb`
  is repo-wide, so committing a genuine notebook needs `git add -f`.
- **Never run the CI copy-back step locally.** `ci.yml` does `cp -rf $NBCACHE/docs/* docs/` **and then
  `find docs/ -type f -name "*.jl" -delete`**. On a fresh CI checkout that is harmless; on your machine it deletes
  the Literate sources (recover with `git checkout docs/`). There are two identically-named copy-back steps; the
  second is the effective one.
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
- The `quarto` CLI is external to the Julia environment and is installed in CI by `quarto-dev/quarto-actions/setup@v2`;
  it may be missing locally.
- `ci.jl` honors `DOCDIR` (default `docs`) and `NBCACHE` (default `.cache`).
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

## Style

`.editorconfig`: 4-space indent for `.jl`; 2-space for `.yml`, `.toml`, `.md`, `.json`; UTF-8, final newline,
no trailing whitespace.
