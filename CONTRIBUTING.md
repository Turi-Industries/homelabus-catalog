# Adding an app to the catalog

An app is a folder named as its `metadata.name`, holding its `manifest.yaml` and, if it
needs one, a `guide.yaml`. CI runs `hlb catalog validate --apps .`, which refuses a typo
with its line number; run it yourself first:

```sh
hlb catalog validate --apps .        # this checkout's apps over your hlb's platform
```

- **Needs, never addresses.** `requires` says what the app needs (`database`, `sso`,
  `smtp`, `storage`…); `env` and `files` receive it through tokens —
  `{{ db.url }}`, `{{ oidc.client_id }}`, `{{ smtp.from }}`. A capability no token reads
  is refused: what is provisioned for it would reach nothing. A value Homelabus should
  invent is `{{ secret.<name> }}` (`:hex`, `:bcrypt` for the forms some software wants).
- **A platform service is not an app.** A database server, the identity provider, the
  ingress move with `hlb` and live in its repository; one here is refused.
- **Say which `hlb` reads it.** `metadata.hlb: ">=0.4.0"` — the first release whose
  schema holds every field the manifest uses. An older `hlb` keeps the last version it
  accepts.
- **Read the image, not its documentation.** Every setting is checked against the
  source of the version pinned: a variable the image does not read is a declaration
  nobody reads, and the app runs on its default. Look at its entrypoint too — an image
  whose entrypoint is a bare CLI runs nothing without its arguments (`args`, which
  follow the entrypoint; `command` replaces it, and drops whatever it started first).
- **Pin the image by digest**: `image: { repo, tag, digest }` on one line, which
  Renovate moves in a pull request per app.
- **Close every door, and declare it.** Sign-up, local passwords, a default
  administrator, a first-run wizard: each one closed by the configuration has an
  `assertion` that reads it back from the running app — its own endpoint, its task's
  environment, or one `SELECT` on its database. If the app makes its first visitor the
  administrator, the guide's `api` step makes that account at the install, with a
  `probe` so it is never replayed.
- **A secret reaches a container as a file**, never through its environment, which
  `docker inspect` shows to anyone reading the Swarm.

Keep a pull request to one app, and say in it how it was checked: the command, and what
it showed. A change to what an app does is best shown on a real cluster; say if it was
not.

By opening a pull request, you agree that your contribution is licensed under the
AGPL-3.0-or-later.
