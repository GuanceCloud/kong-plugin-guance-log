package = "kong-plugin-guance-log"
version = "0.1.0-1"
-- Versioned source is pinned to the corresponding release tag.
source = {
  url = "git+https://github.com/GuanceCloud/kong-plugin-guance-log.git",
  tag = "v0.1.0",
}
description = {
  summary = "Send Kong access logs to Guance through DataKit Log Streaming",
  license = "Apache-2.0",
}
dependencies = { "lua >= 5.1, < 5.5" }
build = {
  type = "builtin",
  modules = {
    ["kong.plugins.guance-log.handler"] = "kong/plugins/guance-log/handler.lua",
    ["kong.plugins.guance-log.schema"] = "kong/plugins/guance-log/schema.lua",
    ["kong.plugins.guance-log.record"] = "kong/plugins/guance-log/record.lua",
    ["kong.plugins.guance-log.transport"] = "kong/plugins/guance-log/transport.lua",
    ["kong.plugins.guance-log.report"] = "kong/plugins/guance-log/report.lua",
  },
}
