# Development

[Quick start](../README.md) · [简体中文](development.zh-CN.md)

Run the commands below from the repository root. End-user installation is covered
by the [quick start](../README.md#install).

## Source installation

Check out the release source, then install into your Kong environment:

```sh
git clone --branch v0.1.0 --depth 1 https://github.com/GuanceCloud/kong-plugin-guance-log.git
cd kong-plugin-guance-log
luarocks make kong-plugin-guance-log-0.1.0-1.rockspec
```

Alternatively, unpack the Release source archive and run `luarocks make` in its
root. The repository rockspec is the build definition; it is not a separate
prerequisite for installing the complete `.all.rock` package.

## Docker image

Build the supplied Dockerfile from the repository root:

```sh
docker build --build-arg KONG_IMAGE=kong:3.9.4 -t kong-guance-log:0.1.0 .
```

It copies the modules into Kong and sets `KONG_PLUGINS=bundled,guance-log`.
Use that image in your deployment and keep other existing custom plugins when
overriding `KONG_PLUGINS`.

To extend an existing Gateway Dockerfile using the published package:

```dockerfile
FROM kong:3.9.4
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip ca-certificates \
    && luarocks install https://github.com/GuanceCloud/kong-plugin-guance-log/releases/download/v0.1.0/kong-plugin-guance-log-0.1.0-1.all.rock \
    && rm -rf /var/lib/apt/lists/*
ENV KONG_PLUGINS=bundled,guance-log
USER kong
```

The dependency installation above targets the Ubuntu-based image shown. Use the
package manager appropriate to any other base image. Install the same plugin
version on every applicable node; self-managed hybrid mode requires the control
plane and all data planes. Traditional/hybrid deployments have not been tested.

## Packaging

The packaging environment needs `zip`:

```sh
luarocks make --pack-binary-rock kong-plugin-guance-log-0.1.0-1.rockspec
```

The result is `kong-plugin-guance-log-0.1.0-1.all.rock`. Before a new release,
update the handler version, rockspec filename/version/source tag, installation
URLs, and changelog together. Keep the release tag pinned to the validated commit.

## Development and tests

Requires Docker and Python 3.9+. The black-box suite uses Linux host networking,
random loopback ports, and an HTTP receiver fixture; no Guance token is needed.
It removes its own containers and temporary files on completion.

```sh
docker run --rm --user root -v "$PWD:/plugin:ro" -w /plugin \
  --entrypoint resty kong:3.9.4 --errlog-level error spec/unit.lua
python3 spec/integration.py --image kong:3.9.4 --workers 2
luacheck kong spec/unit.lua
```

The integration suite validates real Gateway plugin loading, field mapping,
batching, credential exclusion, retries, permanent rejections, redirect handling,
slow receivers, size limits, retry exhaustion, and configuration queue isolation.
An optional isolated check of the bundled Pipeline uses an existing DataKit binary:

```sh
python3 spec/datakit_pipeline.py --binary /usr/local/datakit/datakit
```

This check mounts only the binary and sample Pipeline in a network-disabled
container. It does not read or change your host DataKit configuration.
Actual Guance workspace ingestion requires a separate deployment test.
