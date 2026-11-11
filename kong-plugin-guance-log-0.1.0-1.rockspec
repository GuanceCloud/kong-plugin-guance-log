package = "kong-plugin-guance-log"
version = "0.1.0-1"
-- Local source for development. Before public distribution, replace this with
-- the real repository URL and the corresponding immutable release tag.
source = { url = "file://." }
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
