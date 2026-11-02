#!/usr/bin/env bash
#
# Installs the `hlb` that `hlb.env` names, from this repository's mirror of its release,
# for CI. Nothing downloaded runs unchecked: install.sh against the sum written in
# `hlb.env`, then install.sh checks SHA256SUMS's signature by Homelabus's release
# workflow and the binary against it.
set -euo pipefail

if [[ ! -f hlb.env ]]; then
    echo "::error::no hlb mirrored yet — the owner runs scripts/mirror-hlb.sh <version>"
    exit 1
fi
# shellcheck source=/dev/null
. ./hlb.env
repo=${GITHUB_REPOSITORY:-Turi-Industries/homelabus-catalog}
base="https://github.com/$repo/releases/download/hlb-$HLB_VERSION"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 -o "$tmp/install.sh" "$base/install.sh"
echo "$INSTALL_SH_SHA256  $tmp/install.sh" | sha256sum -c --quiet
HLB_RELEASE_URL="$base" HLB_INSTALL_DIR="$HOME/.local/bin" sh "$tmp/install.sh"
if [[ -n ${GITHUB_PATH:-} ]]; then
    echo "$HOME/.local/bin" >>"$GITHUB_PATH"
fi
