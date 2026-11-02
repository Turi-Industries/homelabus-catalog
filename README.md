# Homelabus catalog

The applications [Homelabus](https://github.com/Turi-Industries/Homelabus) installs: one
folder per app, its `manifest.yaml` and, when it needs steps after it starts, its
`guide.yaml`. An app enters by a pull request here, and reaches every installation
**without a release of `hlb`**.

## How an app reaches a house

1. A pull request adds or changes a folder. CI validates it with a released `hlb`,
   against the platform services (PostgreSQL, PocketID, Caddy…) that release carries —
   they move with `hlb`, never here.
2. CI proves the app on a fresh single-node house (`scripts/quality.sh`): installed,
   updated from the version published, backed up, restored, its assertions held,
   removed. Every app again each week — an image moving under its tag breaks without a
   commit here.
3. Merged, CI builds the next signed **index**: every file of every app hashed, each
   version kept so an older `hlb` still finds the last one its range accepts — and
   beside it `quality-v1.json`, each app's last run and the day it entered, which the
   interface shows as *proven, maintained for N months*.
4. The owner signs both on their own machine (`scripts/publish.sh`) and publishes it to
   GitHub Pages, at <https://turi-industries.github.io/homelabus-catalog>.
5. Each installation fetches it every night, checks its signature against the key
   compiled into `hlb`, refuses an index older than the last one it read, and offers
   what is new.

An index is valid 30 days: the owner signs at least monthly, and a mirror can hide a fix
for a month at most. An expired index blocks what is new, never what runs.

## Withdrawing a version

`revoked.yaml` names a version that must not be installed any more, and why:

```yaml
gitea: [ { version: "1.27.3", why: "loses repositories on upgrade" } ]
```

It is signed with the index, carried by every later one and never dropped. An
installation running a revoked version says so, critically, until it is moved.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) holds the rules a manifest keeps. A contribution is
licensed under the AGPL-3.0-or-later; each app's logo stays its project's
(`REUSE.toml`).
