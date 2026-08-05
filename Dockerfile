# Sports Store frontend - a BUILD ARTIFACT, not a runnable service.
#
# This image exists for exactly one reason: to carry the compiled Vite bundle
# into the gateway build as a `COPY --from` source. Until Milestone 5 the
# gateway got the bundle from a BuildKit named context
# (`--build-context frontend=../sports-store-frontend`), which only works when
# both repos sit side by side on one disk. In CI each repo builds alone with no
# sibling checkout, so the bundle has to travel as an image.
#
# Nothing ever runs this image. It has no entrypoint and no shell. See the
# README for how to inspect it.
#
# The bundle is host-agnostic and is built once for every environment: every
# call in src/api.js goes through one helper doing `fetch(`/api${path}`)` -
# root-relative, no import.meta.env, no VITE_* variables, no absolute URLs. The
# browser resolves /api/* against whatever origin served index.html, which is
# the ALB, which routes to the gateway. So there is nothing to templatise per
# environment and no reason to rebuild per cluster.

FROM node:20-alpine AS build

WORKDIR /build

# Manifests first, so the slow dependency layer stays cached when only
# application source changes. `npm ci` - not `npm install` - installs exactly
# what the lockfile pins, which is what a reproducible build means.
COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

# ---------------------------------------------------------------------------
# The artifact
# ---------------------------------------------------------------------------
# `scratch`: no shell, no base OS, no entrypoint. One layer holding /dist.
#
#   - it cannot be mistaken for a deployable service and started by accident
#   - it has no OS packages, so it has no CVEs of its own to track
#   - it is the smallest thing ECR can hold
#
# Two consequences, stated here rather than discovered later:
#
#   - ECR's scan-on-push reports UNSUPPORTED_IMAGE, because there is no package
#     manager for it to inspect. That is the correct result for an image that
#     contains only static JS and CSS, not a gap in coverage.
#   - `docker create` needs a dummy command argument (`docker create <img> /x`)
#     because there is no CMD to default to, even though the container is never
#     started. `docker build --output type=local,dest=./out` avoids the whole
#     question. Both are written up in the README.
#
# Rejected alternative - basing this on busybox: ~2 MB for a shell and a
# scannable OS, buying inspectability that `docker create` + `docker cp`
# already provides.
FROM scratch

# /dist, not /usr/share/nginx/html. This image does not know or care that its
# consumer happens to be NGINX - the consumer picks the destination. Keeping
# the path generic is what lets the gateway change web servers without the
# frontend repo being touched.
COPY --from=build /build/dist /dist
