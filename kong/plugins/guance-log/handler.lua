local cjson = require "cjson.safe"
local Queue = require "kong.tools.queue"
local record = require "kong.plugins.guance-log.record"
local transport = require "kong.plugins.guance-log.transport"
local report = require "kong.plugins.guance-log.report"

-- Weak values as well as keys: runtime.config refers back to the key, and Lua
-- 5.1 weak-key tables alone would retain obsolete configurations indefinitely.
local runtimes = setmetatable({}, { __mode = "kv" })

local GuanceLog = { PRIORITY = 10, VERSION = "0.1.0" }

local function get_runtime(conf)
  local runtime = runtimes[conf]
  if runtime then
    return runtime
  end
  local encoded = assert(cjson.encode(conf))
  local queue = {}
  for key, value in pairs(conf.queue) do
    queue[key] = value
  end
  -- New configuration gets a new queue so existing batches keep their original
  -- destination and transport options. No raw URL/tags appear in queue names.
  queue.name = "guance-log:" .. kong.plugin.get_id() .. ":" .. ngx.md5(encoded)
  queue.log_tag = "guance-log"
  queue.concurrency_limit = 1
  runtime = { config = conf, endpoint = transport.endpoint(conf), queue = queue }
  runtimes[conf] = runtime
  return runtime
end

local function enqueue(conf)
  local encoded = record.encode(kong.log.serialize(), conf, kong.request.get_header("traceparent"))
  if not encoded then
    report("JSON serialization failed", 1)
    return
  end
  if #encoded > conf.max_entry_bytes then
    report("entry exceeds max_entry_bytes", 1)
    return
  end
  local runtime = get_runtime(conf)
  local ok = Queue.enqueue(runtime.queue, transport.send, runtime, encoded)
  if not ok then
    report("queue enqueue failed", 1)
  end
end

function GuanceLog.log(_, conf)
  -- Logging must never fail a request, including when another plugin modifies
  -- the shared serialized log into an unexpected shape.
  local ok = pcall(enqueue, conf)
  if not ok then
    report("log processing failed", 1)
  end
end

return GuanceLog
