# Guance Log for Kong Gateway

[简体中文](README.zh-CN.md)

Send Kong HTTP access logs to Guance through **DataKit Log Streaming**.
Plugin name: `guance-log`. Tested with Kong Gateway **3.9.1 and 3.9.4**.

```text
Kong → DataKit Log Streaming → Guance logs
```

## Before you start

- Have a DataKit connected to your Guance workspace. Enable Log Streaming and
  install `guance-log.p` using the [DataKit setup guide](docs/datakit.md).
- Run installation commands in your Kong environment with LuaRocks, `curl` or
  `wget`, `unzip`, and permission to install Lua modules. Ubuntu/Debian download
  dependencies: `apt-get update && apt-get install -y curl unzip`.
- For Docker/Kubernetes, include the plugin in the Gateway image using the
  [Docker installation example](docs/development.md#docker-image).

## Install

### 1. Install the plugin

Install the complete package directly from the GitHub Release:

```sh
luarocks install https://github.com/GuanceCloud/kong-plugin-guance-log/releases/download/v0.1.0/kong-plugin-guance-log-0.1.0-1.all.rock
```

No separate rockspec download or source compilation is needed. This package is
not yet in the LuaRocks registry. For offline environments, see
[Offline installation](#offline-installation).

### 2. Load the plugin

Add `guance-log` to `kong.conf`, keeping other custom plugins already listed:

```ini
plugins = bundled,guance-log
```

Restart Kong:

```sh
kong restart
```

In containers, set `KONG_PLUGINS=bundled,guance-log` in the deployment and roll out
an image containing the plugin. Install the same version on every applicable node.

### 3. Enable logging

Choose the method for your deployment. Replace `http://datakit:9529` below with
the DataKit address **reachable from Kong**.

**Database-backed Kong: enable globally through the Admin API**

```sh
curl --fail-with-body -X POST http://localhost:8001/plugins \
  --data 'name=guance-log' \
  --data 'config.endpoint=http://datakit:9529' \
  --data 'config.service=api-gateway' \
  --data 'config.pipeline=guance-log.p'
```

**DB-less Kong: merge into your declarative configuration**

```yaml
_format_version: "3.0"
plugins:
  - name: guance-log
    config:
      endpoint: http://datakit:9529
      service: api-gateway
      pipeline: guance-log.p
```

Keep your existing Services/Routes and reload through your normal deployment
process. DB-less Kong does not support the per-entity Admin API writes above.
A complete example is in [examples/kong.yml](examples/kong.yml).

### 4. Verify

1. Check that `guance-log` appears in `enabled_plugins`:

   ```sh
   curl --fail --silent --show-error http://localhost:8001/plugins/enabled
   ```

2. Send a request through an existing Route, replacing `your-route`:

   ```sh
   curl -i http://localhost:8000/your-route
   ```

3. In Guance **Logs**, select the DataKit workspace and a recent time range.
   Filter by `source=kong` and `service=api-gateway`. After normal batching and
   forwarding delays, check `http_path`, `http_status`, and `request_id`.

`enabled_plugins` confirms loading; logs also require a configured plugin instance
and a working DataKit forwarding connection. See [Troubleshooting](#troubleshooting).

## Plugin scopes

For database-backed Kong, use these endpoints with the configuration in step 3:

| Scope | Endpoint | Requests logged |
| --- | --- | --- |
| Global | `POST /plugins` | All applicable requests |
| Service | `POST /services/{service}/plugins` | Requests to that Service |
| Route | `POST /routes/{route}/plugins` | Requests matching that Route |
| Consumer | `POST /consumers/{consumer}/plugins` | Requests authenticated as that Consumer |

`config.service` is a Guance service tag; the entity you attach the plugin to
determines its scope. For example, log only the Service named `example-api`:

```sh
curl --fail-with-body -X POST http://localhost:8001/services/example-api/plugins \
  --data 'name=guance-log' \
  --data 'config.endpoint=http://datakit:9529' \
  --data 'config.service=example-api' \
  --data 'config.pipeline=guance-log.p'
```

<details>
<summary>Route and Consumer examples</summary>

Replace the entity names with existing names or IDs. Consumer scope needs an
authentication plugin that identifies the Consumer.

```sh
curl --fail-with-body -X POST http://localhost:8001/routes/example-route/plugins \
  --data 'name=guance-log' \
  --data 'config.endpoint=http://datakit:9529' \
  --data 'config.pipeline=guance-log.p'

curl --fail-with-body -X POST http://localhost:8001/consumers/example-consumer/plugins \
  --data 'name=guance-log' \
  --data 'config.endpoint=http://datakit:9529' \
  --data 'config.pipeline=guance-log.p'
```

</details>

## Offline installation

Download `kong-plugin-guance-log-0.1.0-1.all.rock` and `SHA256SUMS` from
[v0.1.0](https://github.com/GuanceCloud/kong-plugin-guance-log/releases/tag/v0.1.0).
Copy them into the Kong environment, verify the package against its SHA-256
entry, and install:

```sh
luarocks install ./kong-plugin-guance-log-0.1.0-1.all.rock
```

Then continue with steps 2–4. Other Release files are for source builds.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| No downloader/unpacker | Install `curl` or `wget`, and `unzip`, in the installation environment |
| Plugin enabled but not installed | Install it in the Kong image/on every node and restart |
| Plugin absent from `enabled_plugins` | Check `plugins` / `KONG_PLUGINS` and restart/redeploy |
| Admin API write returns 405 | Use declarative configuration for DB-less deployments |
| Requests work but no logs appear | Check instance scope, Kong-to-DataKit connectivity, and DataKit forwarding/error logs |
| JSON appears only in `message` | Install `guance-log.p` and set `config.pipeline=guance-log.p`; see [DataKit setup](docs/datakit.md) |
| Container cannot reach `127.0.0.1:9529` | Use a reachable DataKit host/service address; loopback belongs to the container |

## Configuration

Only `endpoint` is required. The quick start also sets a service tag and the
Pipeline so logs have searchable fields and original request timestamps.

- [All configuration options, log fields, and delivery behavior](docs/configuration.md)
- [DataKit setup](docs/datakit.md)
- [Source installation, Docker builds, packaging, and tests](docs/development.md)
- [Changelog](CHANGELOG.md) · [Validation scope](VALIDATION.md)

Queues are in memory. Direct DataWay ingestion, trace exporting, and process
error logs are outside this version's scope. Traditional/hybrid topology,
Konnect, and end-to-end storage in a real workspace have not been verified.

Apache License 2.0; see [LICENSE](LICENSE).
