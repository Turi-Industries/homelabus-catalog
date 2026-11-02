#!/usr/bin/env bash
#
# Mirrors a release of `hlb` into this repository's releases, for its CI: Homelabus's
# releases are not public yet, and a pull request from a fork gets no token to read
# them. Verified before it is mirrored — the release's own install.sh checks the
# signature of SHA256SUMS by Homelabus's release workflow — and again by CI, which
# pins install.sh by the sum this writes into `hlb.env`.
#
#   scripts/mirror-hlb.sh v0.4.0      then push the commit it makes
set -euo pipefail

version=${1:?usage: scripts/mirror-hlb.sh <version, e.g. v0.4.0>}
repo=Turi-Industries/homelabus-catalog
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

gh release download "$version" -R Turi-Industries/Homelabus -D "$tmp/release"
HLB_RELEASE_URL="file://$tmp/release" HLB_INSTALL_DIR="$tmp/bin" sh "$tmp/release/install.sh"

gh release create "hlb-$version" -R "$repo" --title "hlb $version" \
    --notes "hlb $version, mirrored from Homelabus's release for this repository's CI. Its SHA256SUMS is signed by Homelabus's release workflow, which install.sh checks." \
    "$tmp/release/"*

cat >hlb.env <<END
# The hlb CI validates and builds the index with — mirrored by scripts/mirror-hlb.sh.
HLB_VERSION=$version
INSTALL_SH_SHA256=$(sha256sum "$tmp/release/install.sh" | cut -d' ' -f1)
END
git add hlb.env
git commit -q -m "Validate with hlb $version"
echo "✓ hlb $version mirrored; push the commit: git push"
