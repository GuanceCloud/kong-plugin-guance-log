-- Run inside an official Kong image: resty spec/unit.lua
package.path = "./?.lua;" .. package.path

local Schema = require "kong.db.schema"
local definition = require "kong.plugins.guance-log.schema"
local schema = assert(Schema.new(definition))
local record = require "kong.plugins.guance-log.record"
local transport = require "kong.plugins.guance-log.transport"
local checks = 0
local function check(value, message)
  assert(value, message)
  checks = checks + 1
end

local function config(overrides)
  local data = { config = overrides or { endpoint = "http://127.0.0.1:9529" } }
  data = schema:process_auto_fields(data, "insert")
  return data, schema:validate(data)
end

local data, valid = config()
check(valid, "default configuration must validate")
check(data.config.queue.max_batch_size == 100, "batch default")
check(data.config.queue.max_bytes == 10485760, "bounded queue default")
check(data.config.ssl_verify == true, "TLS verification default")

for _, endpoint in ipairs({
  "ftp://localhost", "localhost:9529", "http://user:password@localhost",
  "http://localhost?token=secret", "http://localhost/#fragment",
  "http://localhost/wrong", "http://localhost:0", "http://localhost:99999",
  "http://localhost:abc", "http://local host", "http://localhost\n",
}) do
  local _, ok = config({ endpoint = endpoint })
  check(not ok, "must reject endpoint " .. endpoint)
end
for _, endpoint in ipairs({
  "http://localhost:9529", "https://datakit.example.com/",
  "http://[::1]:9529/v1/write/logstreaming",
}) do
  local _, ok = config({ endpoint = endpoint })
  check(ok, "must accept endpoint " .. endpoint)
end
for _, name in ipairs({ "Authorization", "COOKIE", "Set-Cookie", "X-API-Key", "bad header" }) do
  local _, ok = config({ endpoint = "http://localhost", request_headers_allowlist = { name } })
  check(not ok, "must reject unsafe header " .. name)
end
for _, tags in ipairs({ { env = "prod,team=x" }, { env = "a=b" }, { service = "override" } }) do
  local _, ok = config({ endpoint = "http://localhost", tags = tags })
  check(not ok, "must reject ambiguous or reserved tags")
end
for _, overrides in ipairs({
  { max_payload_bytes = 1024 }, { max_entry_bytes = 65536, queue = { max_bytes = 1024 } },
  { queue = { initial_retry_delay = 1, max_retry_delay = 0.1 } },
  { storage_index = "Invalid-Index" }, { queue = { max_batch_size = 0 } },
}) do
  overrides.endpoint = "http://localhost"
  local _, ok = config(overrides)
  check(not ok, "must reject invalid limits/index")
end

local conf = data.config
conf.request_headers_allowlist = { "X-Allowed" }
conf.response_headers_allowlist = { "content-type" }
local serialized = {
  started_at = 1730000000123,
  request = {
    id = "request-1", method = "GET", uri = "/hello?password=secret", size = 150,
    url = "https://secret.example/hello?password=secret", querystring = { password = "secret" },
    headers = { authorization = "secret", cookie = "secret", ["x-allowed"] = "你好\nworld" },
  },
  response = { status = 503, size = 10, headers = { ["set-cookie"] = "secret", ["content-type"] = "application/json" } },
  latencies = { request = 12.5, kong = 1, proxy = 10 },
  service = { id = "service-id", name = "service-name", host = "secret" },
  route = { id = "route-id", name = "route-name" },
  consumer = { id = "consumer-id", username = "secret" },
  authenticated_entity = { key = "secret" }, custom_secret = "secret",
}
local traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
local result = record.build(serialized, conf, traceparent)
check(result.http_path == "/hello", "strip query string")
check(result.duration == 12500000, "duration in nanoseconds")
check(result.status == "error", "HTTP 5xx is error")
check(result.timestamp_ms == 1730000000123, "preserve request start time")
serialized.started_at = 1730000000123.5
check(record.build(serialized, conf).timestamp_ms == 1730000000123, "normalize fractional milliseconds")
check(result.trace_id == "4bf92f3577b34da6a3ce929d0e0e4736", "incoming trace correlation")
check(result.parent_span_id == "00f067aa0ba902b7", "incoming parent span is not Kong span")
check(result.request_headers["x-allowed"] == "你好\nworld", "allowlisted header preserved")
local encoded = assert(record.encode(serialized, conf, traceparent))
check(not encoded:find("secret", 1, true), "no secret fields leaked")
check(not encoded:find("\n", 1, true), "each encoded record occupies one line")
check(serialized.request.headers.authorization == "secret", "shared serialization not mutated")
check(record.build(serialized, conf, "00-00000000000000000000000000000000-00f067aa0ba902b7-01").trace_id == nil,
      "zero trace ID rejected")
check(record.build(serialized, conf, "invalid").trace_id == nil, "invalid traceparent rejected")
check(record.build({ request = ngx.null, response = ngx.null }, conf).http_status == nil, "null-safe record")
serialized.response.status = 404
check(record.build(serialized, conf).status == "warning", "HTTP 4xx is warning")

conf.tags = { env = "prod", team = "研发 space" }
conf.source = "kong custom"
conf.service = "gateway"
conf.pipeline = "guance-log.p"
conf.storage_index = "gateway_logs"
local endpoint = transport.endpoint(conf)
local query = ngx.decode_args(endpoint:match("%?(.*)$"))
check(query.source == "kong custom", "source URL encoded")
check(query.tags == "env=prod,team=研发 space", "tags stable and encoded")
check(query.pipeline == "guance-log.p", "pipeline forwarded")
check(query.storage_index == "gateway_logs", "index forwarded")
conf.endpoint = "http://localhost:9529/v1/write/logstreaming"
check(transport.endpoint(conf):match("/v1/write/logstreaming%?"), "full endpoint accepted without duplicate path")

local sent, statuses = {}, {}
local errors = {}
_G.kong = { log = { err = function(...) errors[#errors + 1] = table.concat({ ... }) end } }
local http = require "resty.http"
http.new = function()
  return {
    set_timeouts = function() end,
    request_uri = function(_, uri, options)
      sent[#sent + 1] = { uri = uri, options = options }
      local status = table.remove(statuses, 1)
      if status == false then
        return nil, "secret transport error"
      end
      return { status = status or 200 }
    end,
  }
end
conf.max_payload_bytes = 8
local entries = { "aaa", "bbb", "ccc" }
local runtime = { config = conf, endpoint = endpoint }
statuses = { 200, 503, 200 }
check(not transport.send(runtime, entries), "5xx triggers retry")
check(entries.next_index == 3, "acknowledged sub-batch checkpoint")
check(transport.send(runtime, entries), "retry succeeds")
check(#sent == 3 and sent[1].options.body == "aaa\nbbb\n" and
      sent[2].options.body == "ccc\n" and sent[3].options.body == "ccc\n", "no replay of acknowledged sub-batch")
check(sent[1].options.ssl_verify == true, "TLS verification passed to client")
for _, status in ipairs({ 301, 400, 401, 403, 413 }) do
  statuses = { status }
  check(transport.send(runtime, { "aaa" }), "permanent rejection consumed")
end
for _, status in ipairs({ 429, 500, 503, false }) do
  statuses = { status }
  local ok, err = transport.send(runtime, { "aaa" })
  check(not ok and not err:find("secret", 1, true), "transient error retried without sensitive details")
end

-- Exercise handler enqueue failures and queue identity without timers.
local queued = {}
local Queue = require "kong.tools.queue"
Queue.enqueue = function(queue, sender, handler_conf, entry)
  queued[#queued + 1] = { queue = queue, runtime = handler_conf, entry = entry, sender = sender }
  return true
end
_G.kong.plugin = { get_id = function() return "plugin-1" end }
_G.kong.log.serialize = function() return serialized end
_G.kong.request = { get_header = function() return traceparent end }
local handler = require "kong.plugins.guance-log.handler"
local first_config = config({ endpoint = "http://localhost:9529" })
handler:log(first_config.config)
local second_config = config({ endpoint = "http://localhost:9529", source = "changed" })
handler:log(second_config.config)
check(#queued == 2, "handler enqueues")
check(queued[1].queue.name ~= queued[2].queue.name, "configuration changes isolate queues")
check(not queued[1].queue.name:find("localhost", 1, true), "queue names hide endpoint")
check(first_config.config.queue.name == nil, "queue configuration never mutated")
local original = serialized
serialized = { request = { uri = string.rep("a", 70000) } }
handler:log(first_config.config)
check(#queued == 2, "oversized entry dropped before enqueue")
serialized = original
Queue.enqueue = function() error("secret") end
check(pcall(handler.log, handler, first_config.config), "handler failure cannot escape log phase")

print("PASS: " .. checks .. " unit checks")
