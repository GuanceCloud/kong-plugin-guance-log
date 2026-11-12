# Kong 观测云日志插件

[English](README.md)

通过 **DataKit Log Streaming** 将 Kong HTTP 访问日志上报到观测云。
插件名：`guance-log`，已验证 Kong Gateway **3.9.1 和 3.9.4**。

```text
Kong → DataKit Log Streaming → 观测云日志
```

## 开始之前

- 已有连接到目标工作空间的 DataKit。按 [DataKit 配置说明](docs/datakit.zh-CN.md)
  开启 Log Streaming，并安装配套 `guance-log.p` Pipeline。
- 在 Kong 运行环境中执行安装命令，需要 LuaRocks、`curl` 或 `wget`、`unzip`，以及
  安装 Lua 模块的权限。Ubuntu/Debian 下载依赖：
  `apt-get update && apt-get install -y curl unzip`。
- Docker/Kubernetes 部署请将插件安装到 Gateway 镜像中，参见
  [Docker 安装示例](docs/development.zh-CN.md#docker-镜像)。

## 安装

### 1. 安装插件

直接从 GitHub Release 安装完整安装包：

```sh
luarocks install https://github.com/GuanceCloud/kong-plugin-guance-log/releases/download/v0.1.0/kong-plugin-guance-log-0.1.0-1.all.rock
```

不需要单独下载 rockspec，也不需要编译源码。当前尚未上架 LuaRocks 仓库，
离线环境见 [离线安装](#离线安装)。

### 2. 加载插件

在 `kong.conf` 中添加插件，保留已有的其他自定义插件：

```ini
plugins = bundled,guance-log
```

然后重启 Kong：

```sh
kong restart
```

容器部署在部署配置中设置 `KONG_PLUGINS=bundled,guance-log`，并发布已安装插件的
镜像。每个相关 Gateway 节点都应安装相同版本。

### 3. 启用日志采集

按部署方式选择以下一种配置。将下面的 `http://datakit:9529` 替换为
**Kong 可以访问的 DataKit 地址**。

**有数据库模式：通过 Admin API 全局启用**

```sh
curl --fail-with-body -X POST http://localhost:8001/plugins \
  --data 'name=guance-log' \
  --data 'config.endpoint=http://datakit:9529' \
  --data 'config.service=api-gateway' \
  --data 'config.pipeline=guance-log.p'
```

**DB-less 模式：合并到声明式配置**

```yaml
_format_version: "3.0"
plugins:
  - name: guance-log
    config:
      endpoint: http://datakit:9529
      service: api-gateway
      pipeline: guance-log.p
```

保留已有 Service 和 Route，通过现有部署流程重新加载配置。DB-less 模式不能使用
上面的单实体 Admin API 写入命令。完整示例见 [examples/kong.yml](examples/kong.yml)。

### 4. 验证日志

1. 检查返回的 `enabled_plugins` 中包含 `guance-log`：

   ```sh
   curl --fail --silent --show-error http://localhost:8001/plugins/enabled
   ```

2. 通过已有的 Kong Route 发起一次请求，将 `your-route` 替换为实际路径：

   ```sh
   curl -i http://localhost:8000/your-route
   ```

3. 在观测云 **日志** 中选择 DataKit 对应工作空间和最近时间范围，筛选
   `source=kong`、`service=api-gateway`。等待正常批量发送及转发延迟后，检查
   `http_path`、`http_status`、`request_id` 等字段。

`enabled_plugins` 只表示插件已加载；日志入库还需要插件实例配置和 DataKit 转发连接
正常。未看到日志时，按 [常见问题](#常见问题) 排查。

## 作用域

在有数据库模式下，使用以下 Admin API 路径，并传入步骤 3 中的插件配置：

| 作用域 | 接口 | 采集范围 |
| --- | --- | --- |
| 全局 | `POST /plugins` | 所有适用请求 |
| Service | `POST /services/{service}/plugins` | 指定 Service 的请求 |
| Route | `POST /routes/{route}/plugins` | 匹配指定 Route 的请求 |
| Consumer | `POST /consumers/{consumer}/plugins` | 认证为指定 Consumer 的请求 |

`config.service` 是观测云服务标签，真正的作用域由插件挂载位置决定。
例如，仅采集名为 `example-api` 的 Service：

```sh
curl --fail-with-body -X POST http://localhost:8001/services/example-api/plugins \
  --data 'name=guance-log' \
  --data 'config.endpoint=http://datakit:9529' \
  --data 'config.service=example-api' \
  --data 'config.pipeline=guance-log.p'
```

<details>
<summary>Route 和 Consumer 配置示例</summary>

将实体名称替换为已有实体的名称或 ID。
Consumer 作用域需要配合能够识别 Consumer 的认证插件。

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

## 离线安装

从 [v0.1.0 Release](https://github.com/GuanceCloud/kong-plugin-guance-log/releases/tag/v0.1.0)
下载 `kong-plugin-guance-log-0.1.0-1.all.rock` 和 `SHA256SUMS`，复制到 Kong 环境。
根据校验文件核对安装包的 SHA-256 后执行：

```sh
luarocks install ./kong-plugin-guance-log-0.1.0-1.all.rock
```

之后继续步骤 2–4。其他 Release 文件供源码构建使用。

## 常见问题

| 现象 | 检查项 |
| --- | --- |
| LuaRocks 提示缺少下载或解包工具 | 在安装环境中补充 `curl` 或 `wget`，以及 `unzip` |
| 插件已启用但未安装 | 确认 Kong 镜像/每个节点均已安装，随后重启 |
| `enabled_plugins` 中没有插件 | 检查 `plugins` / `KONG_PLUGINS`，重启或重新部署 |
| Admin API 写入返回 405 | DB-less 部署应使用声明式配置 |
| 请求正常，但看不到日志 | 检查实例作用域、Kong 到 DataKit 的连通性和 DataKit 转发/错误日志 |
| JSON 只有 `message`，没有独立字段 | 安装 `guance-log.p` 并设置 `config.pipeline=guance-log.p`，参见 [DataKit 配置](docs/datakit.zh-CN.md) |
| 容器访问不到 `127.0.0.1:9529` | 使用可达的 DataKit 主机/服务地址，回环地址指向容器自身 |

## 更多配置

只有 `endpoint` 为必填项。快速开始额外配置了服务标签和配套 Pipeline，便于直接检索
日志字段，并使用原始请求时间。

- [完整配置、日志字段与发送行为](docs/configuration.zh-CN.md)
- [DataKit 配置](docs/datakit.zh-CN.md)
- [源码安装、镜像构建、打包与测试](docs/development.zh-CN.md)
- [变更记录](CHANGELOG.md) · [验证范围](VALIDATION.md)

队列位于内存中。本版不提供 DataWay 直连、Trace 导出及进程错误日志采集。
传统/混合部署、Konnect 和真实观测云工作空间入库尚未验证。

采用 [Apache License 2.0](LICENSE)。
