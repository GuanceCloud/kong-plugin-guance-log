# Changelog

## v0.1.0 — 2026-11-12

Initial release of the `guance-log` Kong Gateway plugin.

### Features

- Send HTTP access logs to DataKit Log Streaming as batched NDJSON.
- Bound worker-local queues by entry count and bytes; send asynchronously with
  configurable timeouts and exponential retry for network errors, HTTP 429 and 5xx.
- Split oversized batches and retain successful sub-batch progress across retries.
- Isolate queues by workspace, plugin instance and configuration.
- Configure source, service, custom tags, Pipeline and storage index.
- Collect selected access-log fields and explicitly allowlisted headers; omit
  request/response bodies and query parameters, and reject credential header names.
- Include valid incoming W3C trace context for correlation; no span generation or export.
- Supply a DataKit Pipeline to extract fields and retain the original request time.
- Provide a Dockerfile, binary LuaRocks package, configuration examples and English/Chinese docs.

### Compatibility and validation

- Tested on official Kong 3.9.1 (one worker) and 3.9.4 (two workers), DB-less mode.
- Unit/schema tests, real Gateway integration tests, lint and packaging run in GitHub Actions.
- The supplied Pipeline was validated separately with DataKit 2.17.1.

### Known limitations

- Only the DataKit Log Streaming ingestion path is supported; no direct DataWay mode.
- No standalone tracing exporter or Kong/Nginx process error-log collection.
- Queues are in memory; crashes can lose logs and ambiguous acknowledgements can cause duplicates.
- Traditional/hybrid topology, Konnect, other Kong versions, sustained load and
  end-to-end ingestion into a real Guance workspace have not been verified.
- Distributed through GitHub Releases; not published to the LuaRocks registry or Kong Plugin Hub.
