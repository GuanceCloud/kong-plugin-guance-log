local http = require "resty.http"
local report = require "kong.plugins.guance-log.report"

local _M = {}

function _M.endpoint(conf)
  local endpoint = conf.endpoint:gsub("/$", "")
  if not endpoint:match("/v1/write/logstreaming$") then
    endpoint = endpoint .. "/v1/write/logstreaming"
  end
  local args = { source = conf.source, service = conf.service }
  if type(conf.pipeline) == "string" then
    args.pipeline = conf.pipeline
  end
  if type(conf.storage_index) == "string" then
    args.storage_index = conf.storage_index
  end
  local keys, tags = {}, {}
  for key in pairs(conf.tags) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  for _, key in ipairs(keys) do
    tags[#tags + 1] = key .. "=" .. conf.tags[key]
  end
  if #tags > 0 then
    args.tags = table.concat(tags, ",")
  end
  return endpoint .. "?" .. ngx.encode_args(args)
end

-- Kong retries the same entries table. Remember completed sub-batches so that a
-- later failure does not resend sub-batches already acknowledged by DataKit.
function _M.send(runtime, entries)
  local conf = runtime.config
  local first = entries.next_index or 1
  while first <= #entries do
    local last, size = first - 1, 0
    while last < #entries and size + #entries[last + 1] + 1 <= conf.max_payload_bytes do
      last = last + 1
      size = size + #entries[last] + 1
    end
    if last < first then
      report("entry exceeds payload limit", 1)
      first = first + 1
      entries.next_index = first
    else
      local payload = table.concat(entries, "\n", first, last) .. "\n"
      local client = http.new()
      client:set_timeouts(conf.connect_timeout, conf.send_timeout, conf.read_timeout)
      local response = client:request_uri(runtime.endpoint, {
        method = "POST",
        headers = { ["Content-Type"] = "text/plain; charset=utf-8" },
        body = payload,
        ssl_verify = conf.ssl_verify,
        keepalive = conf.keepalive > 0,
        keepalive_timeout = conf.keepalive,
      })
      if not response then
        -- Do not log URL, payload, or raw client errors (which can contain data).
        return nil, "DataKit transport failure (connection, TLS, or timeout)"
      end
      local status = response.status
      if status == 429 or status >= 500 then
        return nil, "DataKit temporarily unavailable, HTTP " .. status
      end
      if status < 200 or status >= 300 then
        -- No redirects. Other 4xx are permanent; retrying blocks healthy logs.
        report("DataKit rejected batch, HTTP " .. status, last - first + 1)
      end
      first = last + 1
      entries.next_index = first
    end
  end
  return true
end

return _M
