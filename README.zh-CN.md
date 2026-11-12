# Kong 观测云日志插件

[English](README.md)

插件名：`guance-log`。安装包名：`kong-plugin-guance-log`。

将 Kong HTTP 访问日志通过 DataKit Log Streaming 上报至观测云：

```text
Kong log 阶段 → 有界内存队列 → 后台批量 NDJSON → DataKit → 观测云
```

当前版本 `0.1.0` 面向 Kong Gateway 3.9.x，已验证官方镜像 `kong:3.9.1`
的单 worker 和 `kong:3.9.4` 的双 worker、DB-less 部署。其他 Kong 版本、
传统部署、混合部署及 Konnect 尚未实测。当前采集 HTTP/HTTPS 访问日志，
不采集 Kong/Nginx 进程错误日志，也不提供 DataWay 直连模式。

## 安装

在仓库目录构建包含插件的镜像：

```sh
docker build --build-arg KONG_IMAGE=kong:3.9.4 -t kong-guance-log:0.1.0 .
```

Dockerfile 已设置 `KONG_PLUGINS=bundled,guance-log`。如果已有其他自定义插件，
请在覆盖该环境变量时同时保留它们。

也可以在 Kong 环境中从本地源码安装：

```sh
luarocks make kong-plugin-guance-log-0.1.0-1.rockspec
```

设置 `KONG_PLUGINS=bundled,guance-log` 后重启或重新加载 Kong。在每个相关节点安装
相同版本；自建混合部署需要在控制面和所有数据面安装。安装完成后，还需创建插件配置
才能对流量生效。

也可以从 [v0.1.0 Release](https://github.com/GuanceCloud/kong-plugin-guance-log/releases/tag/v0.1.0)
下载 `kong-plugin-guance-log-0.1.0-1.all.rock` 和 `SHA256SUMS`，核对安装包的
SHA-256 校验值后，在目标 Kong 环境安装。发布范围与兼容性见 [CHANGELOG.md](CHANGELOG.md)。

自行构建二进制安装包（打包环境需要 `zip`）：

```sh
luarocks make --pack-binary-rock kong-plugin-guance-log-0.1.0-1.rockspec
```

在目标 Kong 环境安装：

```sh
luarocks install ./kong-plugin-guance-log-0.1.0-1.all.rock
```

当前 rockspec 指向[公开源码仓库](https://github.com/GuanceCloud/kong-plugin-guance-log)，
固定使用 `v0.1.0` 版本 tag，不跟随分支变化。
目前未发布到 LuaRocks 或 Plugin Hub。

## 配置 DataKit

1. 按常规方式配置 DataKit 到工作空间的 DataWay 连接。
2. 将 [logstreaming.conf](examples/datakit/logstreaming.conf) 放到
   `<DataKit>/conf.d/log/`，启用 Log Streaming。
3. 将 [guance-log.p](examples/datakit/guance-log.p) 放到
   `<DataKit>/pipeline/guance-log.p`，重启 DataKit。
4. 确保 Kong 可以访问 DataKit HTTP 端口，通常为 `9529`。不同容器之间应使用
   DataKit 的可达服务地址；`127.0.0.1` 指向容器自身。

配套 Pipeline 要求 `ignore_url_tags=false`、`json_as_fields=false`。它会保留原始
`message`，提取访问日志字段，并使用原始请求时间作为日志时间；Header 对象提取为
JSON 字符串。不配置 Pipeline 也能接收文本日志，但默认使用采集器接收时间。

DataWay 文档未列出兼容的 Log Streaming 接口，因此本版只支持 DataKit，不能将接收
地址替换为 DataWay 或其 `/v1/write/logging` 接口。

## 配置 Kong

在现有 DB-less 配置中添加：

```yaml
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

完整示例见 [examples/kong.yml](examples/kong.yml)，请替换其中的上游服务地址。
也可以通过 Admin API 配置全局插件：

```sh
curl --fail-with-body -X POST http://localhost:8001/plugins \
  -H 'Content-Type: application/json' \
  --data '{"name":"guance-log","config":{"endpoint":"http://datakit:9529","service":"api-gateway","pipeline":"guance-log.p"}}'
```

支持在 Service 或 Route 上使用对应的 Admin API 配置插件。

## 主要参数

下表参数均位于 `config`，完整约束与字段表见 [英文说明](README.md#configuration)。

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `endpoint` | 必填 | DataKit HTTP(S) 地址，允许完整 `/v1/write/logstreaming` 路径；不允许凭据、查询参数或 fragment |
| `source` / `service` | 均为 `kong` | 日志来源及观测服务标签，后者与 Kong Service 实体名独立 |
| `pipeline` | 无 | DataKit Pipeline 名称，例如 `guance-log.p` |
| `storage_index` | 无 | 日志索引，以小写字母开头，仅含小写字母、数字及下划线 |
| `tags` | `{}` | 自定义标签；值不允许逗号、等号和控制字符 |
| `request_headers_allowlist` / `response_headers_allowlist` | `[]` | 请求头、响应头采集白名单，大小写不敏感 |
| `connect_timeout` / `send_timeout` / `read_timeout` | `1000` / `5000` / `5000` | 连接、发送、读取超时，单位毫秒 |
| `keepalive` | `60000` | 空闲连接保留毫秒数；`0` 关闭复用 |
| `ssl_verify` | `true` | 验证 HTTPS 接收端证书，私有 CA 通过 Kong 信任配置添加 |
| `max_entry_bytes` | `65536` | 单条序列化日志最大字节数，超限丢弃 |
| `max_payload_bytes` | `1048576` | 单次 HTTP 请求体最大字节数，含换行符 |
| `queue.max_batch_size` | `100` | 每批最大条数，超出字节限制时继续拆分 |
| `queue.max_coalescing_delay` | `1` | 最大批量等待秒数；每批一条时无效 |
| `queue.max_entries` / `queue.max_bytes` | `10000` / `10485760` | 每个 worker、每个队列的待发送容量 |
| `queue.initial_retry_delay` / `queue.max_retry_delay` | `0.1` / `10` | 指数退避初始及最大间隔，单位秒 |
| `queue.max_retry_time` | `60` | 失败批次的重试预算秒数 |

`max_payload_bytes` 至少为 `max_entry_bytes + 1`；队列字节容量至少能放下一条最大日志。
`source`、`service`、`status`、`collector_source_ip`、`ip_or_hostname` 为保留标签名。

## 日志内容和发送行为

- 默认包含时间、请求 ID、方法、无查询参数的路径、HTTP 状态码、客户端 IP、请求/响应
  字节数、延迟、Kong Service/Route/Consumer/Workspace 标识。
- `status` 为日志等级，4xx 对应 `warning`，5xx 对应 `error`；`http_status` 为数值状态码。
- `duration` 单位为纳秒；`timestamp_ms` 为 Unix 毫秒；名称以 `_ms` 结尾的延迟字段单位为毫秒。
- 合法的入站 W3C version-00 `traceparent` 会映射到 `trace_id` 和 `parent_span_id`。
  这是调用方上下文，不代表 Kong 自身创建的 span，也不承诺取得其他插件新生成的上下文。
- 不采集请求体、响应体和查询参数。Header 仅按白名单采集；禁止将 Authorization、
  Proxy-Authorization、Cookie、Set-Cookie、X-API-Key 加入白名单。路径中的敏感值不会自动脱敏。
- 每行一条 JSON，以换行结尾；批量数据不是 JSON 数组。发送在后台定时器中执行。
- 网络/TLS/超时、HTTP 429 和 5xx 触发有限重试；其他非 2xx 作为永久拒绝丢弃，
  包括重定向；不跟随重定向，暂不解析 `Retry-After`。
- 拆分批次在重试时跳过已确认成功的部分；接收后响应超时仍可能导致重复。
- 队列按工作空间、插件实例和配置指纹隔离，配置变更不会改变待发送日志的目标。
- 队列满时淘汰最旧待发送日志，worker 异常退出会丢失内存数据。容量不包含在途批次及
  Lua 对象开销，且随 worker 和插件实例数量增加；不保证不丢失或恰好一次投递。
- 插件丢弃日志按原因累计，每个 worker 每 60 秒最多在下一次同类事件时输出一次诊断；
  Kong 队列另行输出容量及重试耗尽诊断，目前没有独立指标接口。
- DataKit 的 HTTP 2xx 仅表示接收，不表示观测云已入库，需同时检查 DataKit 转发和 Pipeline。

## 开发验证

Docker 和 Python 3.9+ 即可运行，不需要真实工作空间 Token。集成测试使用 Linux host
网络、随机本地端口和模拟接收端，结束时清理自己创建的容器及临时文件。

```sh
docker run --rm --user root -v "$PWD:/plugin:ro" -w /plugin \
  --entrypoint resty kong:3.9.4 --errlog-level error spec/unit.lua
python3 spec/integration.py --image kong:3.9.4 --workers 2
luacheck kong spec/unit.lua
```

可选：使用已有 DataKit 二进制验证配套 Pipeline 的字段、Header 和原始时间解析：

```sh
python3 spec/datakit_pipeline.py --binary /usr/local/datakit/datakit
```

该验证在禁用网络的容器内执行，仅挂载二进制和示例 Pipeline，不读取、修改宿主机
DataKit 配置。真实工作空间入库需要部署后另外验证。

采用 [Apache License 2.0](LICENSE)。官方协议参考：
[Kong 插件开发](https://developer.konghq.com/custom-plugins/)、
[DataKit Log Streaming](https://docs.guance.com/integrations/logstreaming/)。
