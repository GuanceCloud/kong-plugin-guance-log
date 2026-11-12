# 配置 DataKit

[快速开始](../README.zh-CN.md) · [English](datakit.md)

以下是已连接观测云工作空间的 DataKit 的一次性准备步骤。路径以 Linux 安装目录
`/usr/local/datakit` 为例，按实际安装位置调整，并使用相应文件及服务管理权限。

## 启用采集器

如果已启用 Log Streaming，检查现有配置中的以下两项；尚未启用时，在
`<DataKit>/conf.d/log/logstreaming.conf` 中使用 [示例配置](../examples/datakit/logstreaming.conf)：

```toml
[inputs.logstreaming]
  ignore_url_tags = false
  json_as_fields = false
```

## 安装 Pipeline

将 [guance-log.p](../examples/datakit/guance-log.p) 复制到
`<DataKit>/pipeline/guance-log.p`。Linux 主机安装可直接下载版本文件：

```sh
curl --fail --location --output /usr/local/datakit/pipeline/guance-log.p \
  https://raw.githubusercontent.com/GuanceCloud/kong-plugin-guance-log/v0.1.0/examples/datakit/guance-log.p
datakit service restart
```

命令需要安装目录写权限及服务重启权限。容器部署将采集器配置和 Pipeline 挂载到对应
目录，并通过部署流程重启 DataKit。

## 确认监听地址可达

DataKit HTTP 监听端口通常为 `9529`，应允许 Kong 通过所选主机/服务地址访问。
必要时修改 `datakit.conf` 中已有的 `[http_api]` 监听地址；启用采集器不会改变监听绑定。

## 连接及处理说明

不同容器之间应使用 DataKit 的可达服务地址，`127.0.0.1` 指向容器自身。

配套 Pipeline 要求 `ignore_url_tags=false`、`json_as_fields=false`。它会保留原始
`message`，提取访问日志字段，并使用原始请求时间作为日志时间；Header 对象提取为
JSON 字符串。不配置 Pipeline 也能接收文本日志，但默认使用采集器接收时间。

DataWay 文档未列出兼容的 Log Streaming 接口，因此本版只支持 DataKit，不能将接收
地址替换为 DataWay 或其 `/v1/write/logging` 接口。
