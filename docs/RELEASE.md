# RelayTV Release Notes and Compliance Checklist

This document records the release inputs and checks for official RelayTV
artifacts.

## Official Container Image

The public image is:

```text
ghcr.io/mcgeezy/relaytv:latest
```

The image is built from `main` by GitHub Actions. The Dockerfile pins its base
image by digest:

```text
python:3.13-slim@sha256:d168b8d9eb761f4d3fe305ebd04aeb7e7f2de0297cec5fb2f8f6403244621664
```

Base digest lookup used for this pin:

```bash
docker buildx imagetools inspect python:3.13-slim
```

## Build Arguments

Official image build arguments:

```text
RELAYTV_INSTALL_QT=1
RELAYTV_INSTALL_X11_OVERLAY=0
RELAYTV_INSTALL_HEADLESS=0
RELAYTV_INSTALL_NODE=1
RELAYTV_INSTALL_IDLE_BROWSER=0
RELAYTV_INSTALL_OPS_TOOLS=0
RELAYTV_IMAGE_SOURCE=https://github.com/mcgeezy/relaytv
RELAYTV_IMAGE_REVISION=<git sha>
RELAYTV_IMAGE_VERSION=<git ref name>
```

Local builds may override optional runtime bundles with `docker compose build`
or `docker compose up -d --build`. Those local overrides are not the official
release image profile unless documented in a release.

## OCI Labels

Official images should expose these labels:

```text
org.opencontainers.image.title
org.opencontainers.image.description
org.opencontainers.image.source
org.opencontainers.image.revision
org.opencontainers.image.version
org.opencontainers.image.created
org.opencontainers.image.licenses
```

Inspect labels with:

```bash
docker inspect ghcr.io/mcgeezy/relaytv:latest
```

## License and Notice Files

The image includes RelayTV license and notice files under:

```text
/usr/share/doc/relaytv/LICENSE
/usr/share/doc/relaytv/THIRD_PARTY_LICENSES.md
/usr/share/doc/relaytv/ASSETS.md
```

Generate the release-time third-party inventory with:

```bash
./scripts/generate-third-party-licenses.sh
```

## Runtime Mutation Policy

Official release images disable `yt-dlp` auto-update by default:

```text
RELAYTV_YTDLP_AUTO_UPDATE=0
```

Users may opt in to runtime updates, but audited/reproducible build claims only
cover the image as built and published. Runtime auto-update changes playback
resolver behavior after the image is built and is not part of the audited
release state.

## Source Mapping

For immutable releases, prefer this process:

1. Tag the source revision, for example `vX.Y.Z`.
2. Build/publish the image from that tag or record the exact `main` revision.
3. Attach a source tarball and generated third-party inventory to the GitHub
   Release.
4. Ensure the image label `org.opencontainers.image.revision` matches the source
   revision used for the build.

`latest` is convenient for normal installs, but immutable tags are preferred for
audited deployments.
