# sports-store-frontend

React + Vite frontend for CloudCart

Part of the [CloudCart](https://github.com/pyly-devops) polyrepo — see [sports-store-deployments](https://github.com/pyly-devops/sports-store-deployments) for how this service fits into the overall system.

## Branching

- `feature/*` — new work
- `bugfix/*` — non-urgent fixes
- `hotfix/*` — urgent production fixes

`main` is protected: all changes land via pull request with at least one approval.

## Development

<!-- TODO: local setup, env vars, how to run tests -->

## The Docker image is a build artifact, not a service

`docker build` here does **not** produce something you run. It produces a
`scratch` image whose entire contents are `/dist` — the compiled Vite bundle —
for the gateway to consume:

```dockerfile
FROM ${FRONTEND_IMAGE} AS frontend
COPY --from=frontend /dist /usr/share/nginx/html
```

The gateway is what serves this bundle and reverse-proxies `/api/*` to the
backend services. Nothing ever starts this image; it has no entrypoint and no
shell, so `docker run` on it does nothing.

Why it exists at all: the gateway used to pull the frontend in as a BuildKit
named build context pointing at a sibling checkout of this repo. That works on
a laptop where both repos sit side by side and nowhere else — in CI each repo
builds alone. Publishing the bundle as its own image is how it travels.

To look inside it, export the build output straight to a directory — no
container involved:

```bash
docker build --output type=local,dest=./out .
ls ./out/dist        # index.html, assets/, favicon.svg, robots.txt, ...
```

If you would rather inspect the built image itself, `docker create` works but
needs a dummy command argument: the image has no `CMD`, and `docker create`
refuses without one even though the container is never started.

```bash
docker build -t frontend-artifact .
docker create --name fe frontend-artifact /x   # /x is never executed
docker cp fe:/dist ./out && docker rm fe
```

**The bundle is host-agnostic — build it once, serve it anywhere.** Every API
call goes through the single `apiFetch` helper in `src/api.js`, which uses the
root-relative path `` `/api${path}` ``. There are no `VITE_*` variables and no
absolute URLs anywhere in `src/`, so the browser resolves `/api/*` against
whatever origin served `index.html`. Changing the hostname the app is served
from needs no rebuild. Please keep it that way: introducing a build-time API
base URL would mean one image per environment and would undo this.

## CI/CD

<!-- TODO: what the GitHub Actions workflow does on PR vs. push to main -->

Images are tagged `<semver>-<7-char-git-hash>` and pushed to the
`sports-store/frontend` ECR repository. Tags there are **immutable** — a given
tag can never be repointed, which is what makes a rollback by Git revert
meaningful.
