# Prepare DataKit

[Quick start](../README.md) · [简体中文](datakit.zh-CN.md)

This is a one-time setup for a DataKit already connected to your Guance workspace.
The example paths below use the Linux installation directory `/usr/local/datakit`.
Use your actual installation paths and appropriate file permissions.

## Enable the collector

If Log Streaming is already enabled, check these values in its existing
configuration. Otherwise, create `<DataKit>/conf.d/log/logstreaming.conf` using
[the supplied configuration](../examples/datakit/logstreaming.conf):

```toml
[inputs.logstreaming]
  ignore_url_tags = false
  json_as_fields = false
```

## Install the Pipeline

Copy [guance-log.p](../examples/datakit/guance-log.p) to `<DataKit>/pipeline/guance-log.p`.
For a Linux host installation, you can download the release version directly:

```sh
curl --fail --location --output /usr/local/datakit/pipeline/guance-log.p \
  https://raw.githubusercontent.com/GuanceCloud/kong-plugin-guance-log/v0.1.0/examples/datakit/guance-log.p
datakit service restart
```

Run this with write permission to the DataKit installation and permission to
restart the service. For container DataKit, mount the collector configuration and
Pipeline into the corresponding directories and restart through your deployment.

## Make the listener reachable

The DataKit HTTP listener (normally port `9529`) must be reachable from Kong.
Update the existing `[http_api]` listener in `datakit.conf` as needed for the
chosen host/service address; installing a collector does not change its binding.

## Connection and processing notes

In a container, `127.0.0.1` means that container's own network namespace; use
the DataKit service address for a separate container or Kubernetes deployment.

DataKit's default text mode stores each NDJSON line in `message`. The supplied
Pipeline extracts the documented fields, retains the original message, and sets
the log timestamp from the original request's `timestamp_ms`. Without a Pipeline,
logs are still accepted as text but use the collector's ingestion time.
Allowlisted header objects are extracted as JSON strings.

Direct DataWay Log Streaming is deliberately outside this version's scope. The
documented DataKit endpoint is `/v1/write/logstreaming`; do not substitute a
DataWay address or assume its `/v1/write/logging` interface accepts this payload.
