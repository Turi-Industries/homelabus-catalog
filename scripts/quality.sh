#!/usr/bin/env bash
#
# Proves one app's cycle on this machine, a fresh single-node house: installs the
# version published before (when there is one), updates it to this checkout's, backs it
# up, restores every volume and database, holds its assertions, and removes it. Writes
# `<out>/<app>.json`, the run `hlb catalog index build --quality <out>` gathers into the
# signed `quality-v1.json`.
#
#   sudo scripts/quality.sh <app> <out> [<published index directory>]
#
# 🔴 Run it only on a machine made for it — a CI runner or a throwaway VM: it makes a
# Swarm of it and installs PostgreSQL, Stalwart, PocketID and the rest.
#
# A step that fails stops the cycle; those after it are `notRun`. Exits 0 when every
# step that ran passed, 1 otherwise — the file is written either way.
set -uo pipefail

app=${1:?usage: quality.sh <app> <out> [<published index directory>]}
out=${2:?usage: quality.sh <app> <out> [<published index directory>]}
published=${3:-}
repo=$(cd "$(dirname "$0")/.." && pwd)
die() {
    echo "🔴 $*" >&2
    exit 2
}
[[ $EUID -eq 0 ]] || die "run as root: hlb makes a Swarm of this machine"
[[ -f $repo/$app/manifest.yaml ]] || die "$app is no app of this catalog"
# Docker is `hlb cluster init`'s to install, where it is missing.
for tool in hlb jq; do
    command -v "$tool" >/dev/null || die "$tool is needed"
done
mkdir -p "$out"
out=$(cd "$out" && pwd)

export HLB_STATE=/var/lib/homelabus/hlb.db HLB_MASTER_KEY=/var/lib/homelabus/hlb-master.key
[[ -e $HLB_STATE ]] && die "$HLB_STATE exists: this machine is a house already, not a fresh one"
install -d -m 700 "$(dirname "$HLB_STATE")"
work=$(mktemp -d)
export HLB_CATALOG=$work/catalog
domain=qa.test
node=$(hostname)

declare -A outcome=([install]=notRun [update]=notRun [backup]=notRun [restore]=notRun [uninstall]=notRun)
# The image's tag, from the one line the catalog writes it on: `image: { repo, tag, digest }`.
version=$(sed -nE 's/^  image: \{.*tag: "?([^",} ]+).*/\1/p' "$repo/$app/manifest.yaml" | head -1)
write() {
    jq -n --arg version "$version" --arg hlb "$(hlb --version | awk '{print $2}')" \
        --arg date "$(date -u +%F)" \
        --arg install "${outcome[install]}" --arg update "${outcome[update]}" \
        --arg backup "${outcome[backup]}" --arg restore "${outcome[restore]}" \
        --arg uninstall "${outcome[uninstall]}" \
        '{version: $version, hlb: $hlb, date: $date, install: $install, update: $update,
          backup: $backup, restore: $restore, uninstall: $uninstall}' >"$out/$app.json"
    echo "── $app: $(jq -c 'del(.version, .hlb, .date)' "$out/$app.json")"
}
# Each step is judged where it runs; the first that fails writes the run and stops.
fail() {
    outcome[$1]=failed
    echo "🔴 $1 failed: $2" >&2
    write
    exit 1
}
step() {
    echo "── $*"
    "$@"
}

# The catalog this run reads: the platform this hlb carries, and the app alone — at the
# version published before, then at this checkout's.
step hlb catalog export "$HLB_CATALOG" >/dev/null || die "the carried catalog could not be written"
rm -rf "${HLB_CATALOG:?}/apps"
mkdir -p "$HLB_CATALOG/apps"
put() {
    rm -rf "${HLB_CATALOG:?}/apps/$app"
    cp -r "$1" "$HLB_CATALOG/apps/$app"
}
base=
if [[ -n $published && -f $published/index.json ]]; then
    newest=$(jq -r --arg app "$app" '.apps[$app][-1].version // empty' "$published/index.json")
    [[ -n $newest ]] && base=$published/apps/$app/$newest
fi
# The same files as published: there is no update to prove, and none is claimed.
if [[ -n $base ]] && diff -rq "$base" "$repo/$app" >/dev/null; then
    base=
fi
put "${base:-$repo/$app}"

# A house of one node, its routes on a domain nobody resolves.
addr=$(hostname -I | awk '{print $1}')
# Labelling the node right after `swarm init` can meet "update out of sequence" (fixed
# in 0.4.1): a second run takes it.
step hlb cluster init --no-mesh --advertise-addr "$addr" --apply ||
    step hlb cluster init --no-mesh --advertise-addr "$addr" --apply ||
    die "the house could not be made"
# Read as the hlb row a published index would overlay: the app would be the published
# one, never this checkout's.
if hlb catalog source list 2>/dev/null | grep -q '^ *official\b'; then
    die "the official source is in the state: this run would install the published apps"
fi
step hlb node tier "$node" --set heavy --apply || die "the node could not be made heavy"
step hlb config exposure --domain "$domain" --node "$node" --internal --apply ||
    die "the exposure could not be set"
# Bulwark and Seafile read it at their first start, and refuse to install without one.
step hlb config timezone UTC --apply || die "the time zone could not be set"

# The platform services the app depends on, and Caddy, in the order they deploy.
mapfile -t order < <(hlb order | sed -nE 's/^ *[0-9]+\. ([a-z0-9-]+).*/\1/p')
declare -A deps
while IFS='|' read -r name list; do
    deps[$name]=$list
done < <(hlb order | sed -nE 's/^ *[0-9]+\. ([a-z0-9-]+)(  ← (.*))?$/\1|\3/p' | tr -d ' ' | tr ',' ' ')
declare -A needed=([caddy]=1)
visit() {
    local d
    for d in ${deps[$1]:-}; do
        [[ -n ${needed[$d]:-} ]] && continue
        needed[$d]=1
        visit "$d"
    done
}
visit "$app"

# The ids of a guide's `phase: pre-install` steps.
prerequisites() {
    local guide
    guide=$(find "$HLB_CATALOG" -path "*/$1/guide.yaml" | head -1)
    [[ -n $guide ]] || return 0
    awk '/^  - id:/ {id=$3} /^    phase: pre-install/ {print id}' "$guide"
}

# Installs, attesting the manual prerequisites a test house cannot meet — a DNS record
# under a domain nobody resolves — once, after the refusal names them. 🔴 Only those:
# `hlb todo` lists the steps after the install as blocking too, and one attested by
# force is one the executor no longer does (Mealie's default administrator).
install() {
    local out pending ids
    out=$(hlb install "$1" --apply 2>&1)
    local code=$?
    echo "$out"
    [[ $code -eq 0 ]] && return 0
    # A platform service with a route takes no default domain (oauth2-proxy).
    if grep -q 'parameter "domain" is required' <<<"$out"; then
        hlb install "$1" --domain "$1.$domain" --apply
        return
    fi
    pending=$(hlb todo | sed -nE "s/.* $1 · .*  \[([^]]+)\].*/\1/p")
    ids=$(grep -Fxf <(prerequisites "$1") <<<"$pending" || true)
    [[ -n $ids ]] || return 1
    for id in $ids; do
        step hlb ack "$1/$id" --force || return 1
    done
    hlb install "$1" --apply
}

for s in "${order[@]}"; do
    [[ -n ${needed[$s]:-} ]] || continue
    step install "$s" || die "the platform service $s could not be installed"
    # Garage stores nothing until each node has its place in the layout: an app creating
    # its buckets right after is refused "Layout not ready".
    if [[ $s == garage ]]; then
        step hlb garage init --apply || die "Garage's layout could not be applied"
    fi
done

# Its assertions, until each was read: `hlb assert` exits 2 while one is unknown (an
# app just started), 1 when one does not hold.
holds() {
    local code
    for _ in $(seq 1 30); do
        hlb assert "$app"
        code=$?
        [[ $code -ne 2 ]] && return $code
        sleep 10
    done
    echo "  still unread after five minutes" >&2
    return 2
}

step install "$app" || fail install "hlb install $app"
holds || fail install "its assertions"
outcome[install]=passed

if [[ -n $base ]]; then
    put "$repo/$app"
    step hlb upgrade "$app" --apply || fail update "hlb upgrade $app"
    holds || fail update "its assertions after the update"
    outcome[update]=passed
fi

step hlb backup dest add local --location /srv/hlb-backup --classes critical,bulky ||
    fail backup "the destination could not be added"
step hlb backup run --app "$app" --force || fail backup "hlb backup run --app $app"
outcome[backup]=passed

# Every volume and bucket it backs up, then its databases: each preview prints the
# exact line that restores the snapshot it chose.
restore_line() {
    hlb backup restore "$@" 2>&1 | sed -nE 's/^ +(hlb backup restore .* --apply)$/\1/p' | tail -1
}
listing=$(hlb backup restore "$app" 2>&1)
lines=()
if held=$(sed -nE "s/^Which of $app's\? (.*)/\1/p" <<<"$listing") && [[ -n $held ]]; then
    for v in ${held//,/ }; do
        lines+=("$(restore_line "$app" "$v")")
    done
elif line=$(sed -nE 's/^ +(hlb backup restore .* --apply)$/\1/p' <<<"$listing" | tail -1) && [[ -n $line ]]; then
    lines+=("$line")
fi
# Each database, read from the manifest — the preview of a single volume never mentions
# one — by its `name`, the app's own when it gives none.
mapfile -t databases < <(awk '/^ *- kind:/ {if (d) print "-"; d=0} /^ *- kind: database/ {d=1}
    d && /^ *name:/ {print $2; d=0} END {if (d) print "-"}' "$HLB_CATALOG/apps/$app/manifest.yaml")
for db in "${databases[@]}"; do
    if [[ $db == - ]]; then
        lines+=("$(restore_line "$app" --database)")
    else
        lines+=("$(restore_line "$app" --database "$db")")
    fi
done
# An app keeping nothing (LibreSpeed) has nothing to restore: not run, not failed.
if [[ ${#lines[@]} -eq 0 ]] && grep -q 'there is nothing to restore' <<<"$listing"; then
    echo "── $app backs up nothing: no restore to prove"
else
    [[ ${#lines[@]} -gt 0 ]] || fail restore "nothing to restore was found: $listing"
    for line in "${lines[@]}"; do
        [[ -n $line ]] || fail restore "a preview printed no line to run"
        read -ra argv <<<"$line"
        step "${argv[@]}" || fail restore "$line"
    done
    holds || fail restore "its assertions after the restore"
    outcome[restore]=passed
fi

step hlb remove "$app" --confirm "$app" --apply || fail uninstall "hlb remove $app"
if docker service ls --format '{{.Name}}' | grep -qE "^$app(-|$)"; then
    fail uninstall "a service of $app is still running"
fi
outcome[uninstall]=passed

write
