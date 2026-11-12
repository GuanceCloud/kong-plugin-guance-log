# 开发说明

[快速开始](../README.zh-CN.md) · [English](development.md)

以下命令在仓库根目录执行。普通用户安装见 [快速开始](../README.zh-CN.md#安装)。

## 源码安装

获取版本源码，然后在 Kong 环境安装：

```sh
git clone --branch v0.1.0 --depth 1 https://github.com/GuanceCloud/kong-plugin-guance-log.git
cd kong-plugin-guance-log
luarocks make kong-plugin-guance-log-0.1.0-1.rockspec
```

也可以解压 Release 中的源码包，在根目录执行 `luarocks make`。
仓库中的 rockspec 是构建定义；安装完整 `.all.rock` 包不需要额外下载它。

## Docker 镜像

在仓库根目录使用已有 Dockerfile 构建：

```sh
docker build --build-arg KONG_IMAGE=kong:3.9.4 -t kong-guance-log:0.1.0 .
```

该镜像复制插件模块，并设置 `KONG_PLUGINS=bundled,guance-log`。
在部署配置中使用该镜像，覆盖插件列表时保留已有的其他自定义插件。

也可以在已有 Gateway Dockerfile 中安装 Release 包：

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

以上依赖安装针对示例中的 Ubuntu 基础镜像；使用其他基础镜像时选择对应包管理器。
每个相关节点均应安装相同版本，自建混合部署包括控制面和所有数据面。
传统及混合部署尚未实测。

## 打包与版本维护

打包环境需要 `zip`：

```sh
luarocks make --pack-binary-rock kong-plugin-guance-log-0.1.0-1.rockspec
```

输出为 `kong-plugin-guance-log-0.1.0-1.all.rock`。发布新版本时，同步更新 handler 版本、
rockspec 文件名/版本/源码 tag、安装链接和变更记录，并将 tag 固定到已验证提交。

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
