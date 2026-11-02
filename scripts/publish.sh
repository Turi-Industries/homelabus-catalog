#!/usr/bin/env bash
#
# Signs the index CI built from main and publishes it to GitHub Pages. Run on the
# owner's machine, where the signing key is: CI builds, never signs — a key in CI is a
# key every workflow change can reach.
#
#   scripts/publish.sh <signing key file>
#
# At least monthly, merge or not: an index is valid 30 days. With nothing merged since,
# `gh workflow run index.yml` builds a fresh one to sign.
set -euo pipefail

repo=Turi-Industries/homelabus-catalog
key=${1:?usage: scripts/publish.sh <signing key file>}
cd "$(dirname "$0")/.."
die() {
    echo "🔴 $*" >&2
    exit 1
}
for tool in gh git hlb jq rsync; do
    command -v "$tool" >/dev/null || die "$tool is needed"
done
[[ -f official.pub ]] || die "official.pub is missing: \`hlb catalog key generate <file>\` prints the public key — it goes there, and into hlb_catalog::OFFICIAL_KEY"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The newest index built from main as it is now: one built from an older commit would
# publish less than what was merged.
main=$(git ls-remote "https://github.com/$repo" refs/heads/main | cut -f1)
run=$(gh run list -R "$repo" -w index.yml -b main -s success -L 30 --json databaseId,headSha \
    -q "[.[] | select(.headSha == \"$main\")][0].databaseId // empty")
[[ -n $run ]] || die "no index built from main ($main) yet: wait for the Index workflow, or \`gh workflow run index.yml -R $repo\`"
gh run download "$run" -R "$repo" -n index -D "$tmp/built"

if git ls-remote --exit-code "https://github.com/$repo" refs/heads/gh-pages >/dev/null; then
    git clone -q --depth 1 --branch gh-pages "https://github.com/$repo.git" "$tmp/pages"
    published=(--published "$tmp/pages/index.json")
else
    git init -q -b gh-pages "$tmp/pages"
    git -C "$tmp/pages" remote add origin "https://github.com/$repo.git"
    published=(--first)
fi

# Refused unless its counter rises above the published one's: a build older than the
# last publication is built again (`gh workflow run index.yml`).
hlb catalog index sign "$tmp/built" --key "$key" "${published[@]}"
hlb catalog index verify "$tmp/built" --source official --key "$(tr -d '[:space:]' <official.pub)"
counter=$(jq -r .counter "$tmp/built/index.json")

rsync -a --delete --exclude .git "$tmp/built/" "$tmp/pages/"
# Jekyll would leave out a path starting with `_`; the index names files, not pages.
touch "$tmp/pages/.nojekyll"
git -C "$tmp/pages" add -A
git -C "$tmp/pages" commit -q -m "Index $counter"
git -C "$tmp/pages" push -q origin gh-pages
if ! gh api "repos/$repo/pages" >/dev/null 2>&1; then
    gh api -X POST "repos/$repo/pages" -f 'source[branch]=gh-pages' -f 'source[path]=/' >/dev/null
fi
echo "✓ index $counter published: https://turi-industries.github.io/homelabus-catalog/index.json"
