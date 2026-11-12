package = "kong-plugin-guance-log"
version = "0.1.0-1"
-- Development source. Pin source.tag instead of source.branch before publishing
-- a versioned package to LuaRocks.
source = {
  url = "git+https://github.com/GuanceCloud/kong-plugin-guance-log.git",
  branch = "main",
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
