#!/bin/zsh
# Publish a built release: dmg to GitHub Releases, appcast to the repo.
#
#   publish.sh <version>        (after scripts/release.sh <version>)
#
# Two consumers read what this uploads:
#   - Sparkle, via dist/updates/appcast.xml committed here and served raw
#   - Homebrew, via the cask in packaging/opencodego.rb pointing at the
#     release asset
set -euo pipefail

SCRIPT_DIR=${0:a:h}
ROOT=${SCRIPT_DIR:h}
DIST="$ROOT/dist"
VERSION="${1:-}"
[[ -n "$VERSION" ]] || { echo "usage: publish.sh <version>" >&2; exit 2; }

DMG="$DIST/OpenCodeGo.dmg"
[[ -f "$DMG" ]] || { echo "publish: no dmg — run scripts/release.sh $VERSION first" >&2; exit 1; }

SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
echo "==> sha256 $SHA"

echo "==> Creating GitHub release v$VERSION"
gh release create "v$VERSION" "$DMG" \
  --title "Go for OpenCode $VERSION" \
  --notes "Mac companion $VERSION. Install: \`brew install --cask tjameswilliams/tap/opencodego\`"

# The cask's sha256 must match the artifact users actually download.
echo "==> Updating cask checksum"
sed -i '' \
  -e "s/version \".*\"/version \"$VERSION\"/" \
  -e "s/sha256 \".*\"/sha256 \"$SHA\"/" \
  "$ROOT/packaging/opencodego.rb"

echo "==> Committing appcast + cask"
git -C "$ROOT" add dist/updates/appcast.xml packaging/opencodego.rb
git -C "$ROOT" commit -m "Release $VERSION"
git -C "$ROOT" push

echo "==> Done. Copy packaging/opencodego.rb into the homebrew-tap repo:"
echo "    tjameswilliams/homebrew-tap → Casks/opencodego.rb"
