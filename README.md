# Guance Log for Kong Gateway

[简体中文](README.zh-CN.md)

Send Kong HTTP access logs to Guance through a local or remote **DataKit Log
Streaming** collector. Plugin name: `guance-log`. LuaRocks package name:
`kong-plugin-guance-log`.

```text
Kong log phase -> bounded worker-local queue -> NDJSON POST -> DataKit -> Guance
```

Version 0.1.0 targets Kong Gateway 3.9.x. Automated tests cover official images
`kong:3.9.1` (one worker) and `kong:3.9.4` (two workers), using DB-less mode.
Traditional and hybrid deployments use the same plugin code but have not been
integration-tested. Kong 2.x, other 3.x releases, Konnect, and stream protocols
are not currently verified. HTTP/HTTPS access logging is the initial scope.
This plugin does not collect Kong/Nginx process error logs.

## Install

### Build an image

From this repository:

```sh
docker build --build-arg KONG_IMAGE=kong:3.9.4 -t kong-guance-log:0.1.0 .
```

The Dockerfile copies the plugin modules and sets `KONG_PLUGINS=bundled,guance-log`.
If you override this environment variable, retain `guance-log` alongside any
other custom plugins. Install the same plugin version on every applicable
Gateway node before enabling it. In self-managed hybrid mode, install it on the
control plane and all data planes.

### Install from local source

Inside a Kong installation with LuaRocks:

```sh
luarocks make kong-plugin-guance-log-0.1.0-1.rockspec
```

Add `guance-log` to Kong's `plugins` setting, then restart/reload Kong. Installing
the package makes the plugin available; creating a plugin entity enables it for
traffic. The package has **not** been published to LuaRocks or the Kong Plugin Hub.

### Build a binary rock

The packaging environment must have `zip` installed:

```sh
luarocks make --pack-binary-rock kong-plugin-guance-log-0.1.0-1.rockspec
```

Install the resulting file in your Kong installation:

```sh
luarocks install ./kong-plugin-guance-log-0.1.0-1.all.rock
```

The checked-in rockspec uses `file://.` for local development. Before public
distribution, update `source.url` to the actual public source repository and
`source.tag` to its matching immutable release tag. Verify an installation from
that release source before uploading it. No public repository is assumed here.

## Prepare DataKit

1. Configure DataKit's workspace/DataWay connection through its normal setup.
2. Enable Log Streaming using [examples/datakit/logstreaming.conf](examples/datakit/logstreaming.conf).
   Copy it under `<DataKit>/conf.d/log/`. Keep `ignore_url_tags=false` and
   `json_as_fields=false` when using the supplied Pipeline.
3. Copy [examples/datakit/guance-log.p](examples/datakit/guance-log.p) to
   `<DataKit>/pipeline/guance-log.p` and restart DataKit.
4. Ensure Kong can reach DataKit's HTTP listener (normally port 9529). In a
   container, `127.0.0.1` means that container's own network namespace; use the
   DataKit service address for a separate container or Kubernetes deployment.

DataKit's default text mode stores each NDJSON line in `message`. The supplied
Pipeline extracts the documented fields, retains the original message, and sets
the log timestamp from the original request's `timestamp_ms`. Without a Pipeline,
logs are still accepted as text but use the collector's ingestion time.
Allowlisted header objects are extracted as JSON strings.

Direct DataWay Log Streaming is deliberately outside this version's scope. The
documented DataKit endpoint is `/v1/write/logstreaming`; do not substitute a
DataWay address or assume its `/v1/write/logging` interface accepts this payload.

## Enable

DB-less example (replace the endpoint with your reachable DataKit address):

```yaml
_format_version: "3.0"
plugins:
  - name: guance-log
    config:
      endpoint: http://datakit:9529
      source: kong
      service: api-gateway
      pipeline: guance-log.p
      tags:
        env: production
      queue:
        max_batch_size: 100
        max_coalescing_delay: 1
```

Merge this with your Service/Route configuration; a complete example is in
[examples/kong.yml](examples/kong.yml). The example upstream `httpbin:8000` must
be replaced with or resolve to your upstream service.

Admin API example for a global plugin:

```sh
curl --fail-with-body -X POST http://localhost:8001/plugins \
  -H 'Content-Type: application/json' \
  --data '{"name":"guance-log","config":{"endpoint":"http://datakit:9529","service":"api-gateway","pipeline":"guance-log.p"}}'
```

For a Service or Route plugin, use the corresponding scoped Admin API endpoint.

## Configuration

All fields are under `config`.

| Field | Default | Meaning |
| --- | --- | --- |
| `endpoint` | required | HTTP(S) origin or full `/v1/write/logstreaming` URL; no credentials, query, or fragment |
| `source` | `kong` | DataKit log source |
| `service` | `kong` | Observability service tag; independent of the Kong Service entity name |
| `pipeline` | unset | DataKit Pipeline name, e.g. `guance-log.p` |
| `storage_index` | unset | Log index; lowercase letter followed by lowercase letters, digits, or underscores |
| `tags` | `{}` | String tags; values cannot contain commas, equals signs, or control characters |
| `request_headers_allowlist` | `[]` | Request headers to include, matched case-insensitively |
| `response_headers_allowlist` | `[]` | Response headers to include, matched case-insensitively |
| `connect_timeout` | `1000` | HTTP connection timeout, milliseconds |
| `send_timeout` | `5000` | HTTP send timeout, milliseconds |
| `read_timeout` | `5000` | HTTP response read timeout, milliseconds |
| `keepalive` | `60000` | Idle connection lifetime, milliseconds; `0` disables reuse |
| `ssl_verify` | `true` | Verify HTTPS receiver certificate; configure Kong's trusted CA store for private CAs |
| `max_entry_bytes` | `65536` | Drop larger serialized records; no silent truncation |
| `max_payload_bytes` | `1048576` | Maximum HTTP body bytes, including newline separators |
| `queue.max_batch_size` | `100` | Maximum records per queue callback; byte limits may split it further |
| `queue.max_coalescing_delay` | `1` | Maximum batching delay, seconds; ineffective for batches of one |
| `queue.max_entries` | `10000` | Maximum waiting entries per queue per worker |
| `queue.max_bytes` | `10485760` | Maximum waiting serialized bytes per queue per worker |
| `queue.initial_retry_delay` | `0.1` | Initial retry delay, seconds |
| `queue.max_retry_delay` | `10` | Maximum exponential retry delay, seconds |
| `queue.max_retry_time` | `60` | Retry budget, seconds, after which Kong drops the failed batch |

`max_payload_bytes` must fit `max_entry_bytes` plus one newline. `queue.max_bytes`
must fit one maximum-sized entry. Tag names `source`, `service`, `status`,
`collector_source_ip`, and `ip_or_hostname` are reserved. Use `config.service`
for the service tag. URL parameters are encoded by the plugin.

## Log fields

Each request becomes one UTF-8 JSON object followed by `\n`, sent with
`Content-Type: text/plain; charset=utf-8`. Multiple records are **not** a JSON array.

| Fields | Meaning |
| --- | --- |
| `schema_version` | Payload schema version, currently `1` |
| `timestamp_ms` | Original request start, Unix milliseconds |
| `status`, `http_status` | Log level (`info`, `warning` for 4xx, `error` for 5xx) and numeric HTTP status |
| `request_id` | Kong request ID |
| `http_method`, `http_path` | Method and path without query parameters |
| `request_bytes`, `response_bytes` | Kong serialized request/response byte counts |
| `client_ip` | Client address from Kong's serialized access log |
| `duration` | Total request duration in nanoseconds |
| `request_time_ms`, `kong_latency_ms`, `upstream_latency_ms`, `receive_time_ms` | Kong's latency measurements, milliseconds; `-1` can mean unavailable |
| `kong_service_id`, `kong_service_name`, `kong_route_id`, `kong_route_name` | Kong Service/Route identity |
| `consumer_id` | Authenticated Consumer ID when present |
| `workspace_id`, `workspace_name` | Workspace identity when available |
| `response_source` | Kong's response origin, e.g. `kong` or `upstream` |
| `request_headers`, `response_headers` | Explicitly allowlisted headers only |
| `trace_id`, `parent_span_id`, `trace_flags`, `trace_id_source` | Valid incoming W3C version-00 `traceparent` context, when present |

Missing fields are omitted. `parent_span_id` is the incoming caller's span ID,
**not** a span generated by Kong. The plugin neither creates spans nor claims to
capture trace context generated by another plugin; `trace_id_source` is
`incoming_traceparent`. No request/response bodies or query parameters are sent.
Authorization, Proxy-Authorization, Cookie, Set-Cookie, and X-API-Key are rejected
in header allowlists. Other headers can also contain sensitive data: allowlist
only fields you intend to collect. Values inside paths are not redacted.

## Delivery behavior

- The `log` phase serializes and enqueues; HTTP I/O runs in a background timer.
- Queues are isolated by workspace, plugin instance, and configuration fingerprint.
  Pending entries retain their original destination when configuration changes.
- Network/TLS/timeouts, HTTP 429, and HTTP 5xx use Kong's bounded queue retry.
  Other non-2xx responses, including redirects, are dropped with diagnostics.
  Redirects are not followed. `Retry-After` is not currently interpreted.
- Successful byte-split sub-batches are checkpointed during retries. Timeouts
  after receiver acceptance can still cause duplicates; exactly-once delivery
  and deduplication are not provided.
- Queues are in worker memory, with one sender timer per active queue. Oldest
  waiting entries are evicted when full; entries can be lost on worker crashes.
  Queue limits exclude in-flight batches and Lua object overhead, so total memory
  exceeds the configured byte cap. Capacity is multiplied by workers and instances.
- Plugin-generated drops are counted and reported at most once per reason per
  60 seconds per worker, on the next occurrence. Kong separately reports queue
  capacity and retry-exhaustion losses. There is no public metrics endpoint yet.
- HTTP 2xx acknowledges DataKit acceptance, not successful Guance storage. DataKit
  forwarding, Pipeline errors, and workspace ingestion must be monitored separately.

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

## References and license

- [Kong custom plugins](https://developer.konghq.com/custom-plugins/)
- [Kong plugin queues](https://developer.konghq.com/plugins/http-log/#queuing)
- [DataKit Log Streaming](https://docs.guance.com/integrations/logstreaming/)

Apache License 2.0; see [LICENSE](LICENSE). This is an independently maintained
plugin; inclusion in the Kong Plugin Hub is not implied.
