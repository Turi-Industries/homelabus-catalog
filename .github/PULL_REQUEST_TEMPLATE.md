## What and why

<!-- Which app, what changes for someone running it, and the reason. -->

## How it was checked

<!-- The command you ran and what it showed. A change to what an app does is best shown
on a real cluster; say if it was not. -->

- [ ] `hlb catalog validate --apps .` passes
- [ ] Every door the app leaves open at first start is closed and has an `assertion`
- [ ] The image is pinned by digest, and every variable set is one the image reads

By opening this pull request, I agree that my contribution is licensed under the
AGPL-3.0-or-later.
