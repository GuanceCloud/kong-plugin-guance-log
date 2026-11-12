# 配置参考

[快速开始](../README.zh-CN.md) · [English](configuration.md)

## 主要参数

下表参数均位于 `config`，完整约束与字段表见 [英文说明](configuration.md#configuration)。

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
