#!/bin/bash
# Builds the Haiku package (.hpkg) for a published release, attaches it to the
# GitHub release and adds it to the package repository
# (github.com/Techniix/haiku-packages). Run on Haiku, from a clone of this
# repository, after the release workflow has published the zip.
#
#   ./haiku/publish-hpkg.sh [haiku-vX.Y.Z]      default: the latest release
#
# Needs:
#   - haikuporter set up (TREE_PATH in ~/config/settings/haikuports.conf);
#   - a clone of the package repository: SDV_PKG_REPO, default ~/haiku-packages;
#   - a GitHub token with Contents read/write on this repository and on
#     haiku-packages, in GITHUB_TOKEN or saved by git's credential helper.
#
# It also updates the recipe (version and checksum) and pushes that change.
# To rebuild the same version with only recipe changes, raise REVISION in the
# recipe first.
set -euo pipefail

OWNER_REPO="Techniix/Stardew-Valley_HaikuOS"
PKG="stardew_valley_haiku"
CATEGORY="games-simulation"
ZIP_NAME="StardewValley-haiku.zip"

die() { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "== $*"; }

[ "$(uname)" = Haiku ] || die "run this on Haiku (it needs haikuporter and package_repo)."
for cmd in git curl jq sha256sum haikuporter; do
  command -v "$cmd" >/dev/null || die "$cmd not found."
done

HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
RECIPE_DIR="$HERE/haiku/haikuports/$CATEGORY/$PKG"
PKG_REPO="${SDV_PKG_REPO:-$HOME/haiku-packages}"
[ -x "$PKG_REPO/update-repo.sh" ] \
  || die "no package repository at $PKG_REPO. Clone it: git clone https://github.com/Techniix/haiku-packages.git $PKG_REPO"

TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  TOKEN="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null \
    | sed -n 's/^password=//p')" || true
fi
[ -n "$TOKEN" ] || die "no GitHub token: set GITHUB_TOKEN, or push once with git so its credential helper saves one."
api() {
  curl -sSf -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" "$@"
}

# --- Release -----------------------------------------------------------------
step "Release"
if [ $# -ge 1 ]; then
  tag="$1"
else
  tag="$(api "https://api.github.com/repos/$OWNER_REPO/releases/latest" | jq -r .tag_name)"
fi
case "$tag" in haiku-v[0-9]*.[0-9]*.[0-9]*) ;; *) die "unexpected release tag: $tag" ;; esac
version="${tag#haiku-v}"
release_json="$(api "https://api.github.com/repos/$OWNER_REPO/releases/tags/$tag")" \
  || die "no GitHub release $tag. Publish it first (Actions -> Haiku package -> Run workflow)."
release_id="$(jq -r .id <<<"$release_json")"
zip_url="https://github.com/$OWNER_REPO/releases/download/$tag/$ZIP_NAME"
zip_sha="$(curl -sSfL "$zip_url" | sha256sum | cut -d' ' -f1)"
echo "$tag: $ZIP_NAME sha256 $zip_sha"

# --- Recipe ------------------------------------------------------------------
step "Recipe"
cd "$HERE"
shopt -s nullglob
recipes=("$RECIPE_DIR/$PKG"-*.recipe)
shopt -u nullglob
[ ${#recipes[@]} -eq 1 ] || die "expected exactly one recipe in $RECIPE_DIR."
recipe="$RECIPE_DIR/$PKG-$version.recipe"
if [ "${recipes[0]}" != "$recipe" ]; then
  git mv "${recipes[0]}" "$recipe"
  sed -i 's/^REVISION=.*/REVISION="1"/' "$recipe"
  echo "Renamed $(basename "${recipes[0]}") -> $(basename "$recipe"), REVISION 1"
fi
sed -i "s/^CHECKSUM_SHA256=\".*\"/CHECKSUM_SHA256=\"$zip_sha\"/" "$recipe"
revision="$(sed -n 's/^REVISION="\([0-9]*\)"/\1/p' "$recipe")"
[ -n "$revision" ] || die "can't read REVISION from $recipe."

# --- Build -------------------------------------------------------------------
step "Build $PKG-$version-$revision"
conf="$HOME/config/settings/haikuports.conf"
tree="$(sed -n 's/^TREE_PATH="\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' "$conf" 2>/dev/null | head -1)"
tree="${tree:-$HOME/haikuports}"
[ -d "$tree" ] || die "haikuporter tree not found ($tree); see docs/Packaging.md."
dest="$tree/$CATEGORY/$PKG"
if git -C "$tree" ls-files --error-unmatch "$dest" >/dev/null 2>&1; then
  die "$dest is tracked in $tree (a feature branch?). Check out master there first."
fi
rm -rf "$dest"
mkdir -p "$tree/$CATEGORY"
cp -r "$RECIPE_DIR" "$dest"
# The copy is temporary; don't leave it in the haikuports tree.
trap 'rm -rf "$dest"' EXIT
(cd "$tree" && haikuporter -S -j"$(nproc)" --no-source-packages --get-dependencies "$PKG")
hpkg="$tree/packages/$PKG-$version-$revision-x86_64.hpkg"
[ -f "$hpkg" ] || die "build finished but $hpkg is missing."
hpkg_name="$(basename "$hpkg")"

# --- Package repository ------------------------------------------------------
step "Package repository"
# update-repo.sh force-pushes a single commit, so match the remote exactly
# instead of pulling.
git -C "$PKG_REPO" fetch -q origin
git -C "$PKG_REPO" checkout -q -B main origin/main
git -C "$PKG_REPO" reset -q --hard origin/main
"$PKG_REPO/update-repo.sh" "$hpkg"

# --- Release asset -----------------------------------------------------------
step "Attach $hpkg_name to $tag"
old_id="$(jq -r --arg n "$hpkg_name" '.assets[] | select(.name == $n) | .id' <<<"$release_json")"
if [ -n "$old_id" ]; then
  api -X DELETE "https://api.github.com/repos/$OWNER_REPO/releases/assets/$old_id" >/dev/null
fi
api -X POST -H "Content-Type: application/octet-stream" --data-binary @"$hpkg" \
  "https://uploads.github.com/repos/$OWNER_REPO/releases/$release_id/assets?name=$hpkg_name" >/dev/null

# Add install instructions to the release notes, once.
body="$(jq -r '.body // ""' <<<"$release_json")"
if ! grep -q "pkgman add-repo" <<<"$body"; then
  note="$(cat <<EOF

## Install as a Haiku package

Add the package repository once, then install from HaikuDepot or with pkgman:

\`\`\`sh
pkgman add-repo https://techniix.github.io/haiku-packages/x86_64/current
pkgman install $PKG
\`\`\`

Or install \`$hpkg_name\` from this release directly: \`pkgman install $hpkg_name\`. The package keeps game files, saves, mods and settings in \`~/config/settings/StardewValley\`.
EOF
)"
  jq -n --arg body "$body$note" '{body: $body}' \
    | api -X PATCH "https://api.github.com/repos/$OWNER_REPO/releases/$release_id" -d @- >/dev/null
fi

# --- Recipe change -----------------------------------------------------------
step "Recipe commit"
git add -A "$RECIPE_DIR"
if git diff --cached --quiet -- "$RECIPE_DIR"; then
  echo "Recipe unchanged."
else
  git commit -qm "Recipe: $PKG $version (revision $revision)" -- "$RECIPE_DIR"
  git push -q
  echo "Committed and pushed the recipe update."
fi

echo
echo "Done: $hpkg_name is attached to $tag and published in the package repository."
