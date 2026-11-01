#!/usr/bin/env bash
# Builds the site: stages the notebooks ci.jl executed, installs the standalone
# Quarto CLI, renders docs/ and asserts that every page really exists. The tracked
# sources in docs/ are never modified: rendering happens on a throwaway copy.
# Companion to .github/ci.jl; both are driven from .github/workflows/ci.yml.
#
# Run from the repository root, after the notebooks have been executed:
#   julia --project=@. -p 4 .github/ci.jl && bash .github/quarto.sh
# Like ci.jl, honors DOCDIR (default docs) and NBCACHE (default .cache).
set -euo pipefail

docs=${DOCDIR:-docs}
nbcache=${NBCACHE:-.cache}

# Collapsible log sections on GitHub Actions, plain headers in a terminal.
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    group() { echo "::group::$1"; }
    endgroup() { echo "::endgroup::"; }
else
    group() { echo "==> $1"; }
    endgroup() { echo; }
fi

[ -f "$docs/_quarto.yml" ] || {
    echo "error: $docs/_quarto.yml not found: run this script from the repository root" >&2
    exit 1
}

group "Stage built notebooks"
cp --verbose -rf "$nbcache/$docs/"* "$docs/"
endgroup

# No apt and no quarto-dev/quarto-actions/setup@v2: the release bundles are self-contained
# archives holding only bin/ and share/. /releases/latest is a 302 to the tag, and curl -I
# needs -L to follow it, so the version comes from the redirect target. The checksum file
# comes from that same release, hence this proves the download is intact, not that the
# release is authentic.
group "Setup Quarto"
case $(uname -m) in
    x86_64 | amd64) qa=amd64 ;;
    aarch64 | arm64) qa=arm64 ;;
    *)
        echo "Unsupported machine: $(uname -m)" >&2
        exit 1
        ;;
esac
base=https://github.com/quarto-dev/quarto-cli/releases
ver=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$base/latest" | sed 's#.*/tag/v##')
[[ $ver =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "::error::could not resolve latest Quarto version" >&2
    exit 1
}
qroot=${RUNNER_TEMP:-${TMPDIR:-/tmp}}/quarto-$ver-$qa
if [ ! -x "$qroot/bin/quarto" ]; then
    echo "Latest Quarto release: v$ver ($qa)"
    tmp=$(mktemp -d)
    name=quarto-$ver-linux-$qa.tar.gz
    curl -sSLfL --retry 3 -o "$tmp/$name" "$base/download/v$ver/$name"
    curl -sSLfL --retry 3 -o "$tmp/quarto-$ver-checksums.txt" "$base/download/v$ver/quarto-$ver-checksums.txt"
    # sha256sum resolves the file name recorded in the checksums file relative to CWD.
    (
        cd "$tmp"
        grep -F " $name" "quarto-$ver-checksums.txt" | sha256sum --check --status
    )
    mkdir -p "$qroot"
    tar -xzf "$tmp/$name" -C "$qroot" --strip-components=1
    rm -rf "$tmp"
fi
# $GITHUB_PATH only applies to later steps, hence the export for quarto below.
export PATH="$qroot/bin:$PATH"
if [ -n "${GITHUB_PATH:-}" ]; then
    echo "$qroot/bin" >>"$GITHUB_PATH"
fi
quarto --version
endgroup

# Rendering .ipynb needs no Jupyter and no Julia kernel: the notebooks arrive pre-executed
# from Literate, so Quarto's native notebook renderer handles them.
#
# The .jl sources must be absent from the tree that gets rendered: Quarto treats a same-stem
# .jl sitting next to a generated .ipynb as that page's source and then silently skips the
# notebook -- it copies the raw .ipynb into the output as a static resource, exits 0, and
# leaves index.html as a redirect stub. Delete them from a throwaway copy of docs/ rather than
# deleting or renaming the tracked sources, so an interrupted build cannot leave docs/ without
# its Literate inputs. A project `render:` list in _quarto.yml does not avoid this: the
# collision is resolved before that list is consulted.
#
# Render and verify entirely inside the copy, then publish _site to docs/. Passing an
# --output-dir outside the project is what Quarto itself warns about ("did not expect the path
# configuration") and it then refuses to remove stale output there, so an old build could mask
# a broken one. docs/_site is only replaced once the fresh build has passed the checks below.
group "Render Quarto project"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp -r "$docs/." "$stage/"
rm -rf "$stage/_site" "$stage/.quarto"
find "$stage" -type f -name '*.jl' -delete
out=$stage/_site
quarto render "$stage" --to html
endgroup

# quarto exits 0 even when it silently skips every notebook, so assert each source page.
# Inputs are listed from the real docs/ (so a bad copy is caught too); outputs are the fresh
# ones in the staging dir, which nothing from a previous build has ever touched.
group "Verify rendered pages"
shopt -s nullglob globstar
pages=0
for src in "$docs"/**/*.qmd "$docs"/**/*.ipynb; do
    case ${src#"$docs"/} in
        _site/*) continue ;;
    esac
    page=${src#"$docs"/}
    page=_site/${page%.*}.html
    if [ ! -s "$stage/$page" ]; then
        echo "::error::$page was not rendered from $src"
        exit 1
    fi
    pages=$((pages + 1))
    echo "  OK   $page ($(wc -c <"$stage/$page") bytes)"
done
# Quarto's stub for a missing index is a ~230-byte page holding only a meta refresh, and
# the target it names varies (404.html, about.html), so match the refresh, not the target.
if grep -q 'http-equiv="refresh"' "$out/index.html"; then
    echo "::error::$out/index.html is a redirect stub, not a rendered page: the Literate notebooks were skipped (a .jl sibling is shadowing an .ipynb)"
    exit 1
fi
echo "Verified $pages rendered page(s)."
endgroup

group "Publish"
rm -rf "$docs/_site"
cp -r "$out" "$docs/_site"
echo "  $(find "$docs/_site" -name '*.html' | wc -l) page(s), $(du -sh "$docs/_site" | cut -f1) in $docs/_site"
endgroup
