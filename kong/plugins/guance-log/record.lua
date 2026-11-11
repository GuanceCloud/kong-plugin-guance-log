local cjson = require "cjson.safe"

local _M = {}

local function object(value)
  return type(value) == "table" and value or {}
end

local function number(value)
  return type(value) == "number" and value or nil
end

local function headers(values, allowlist)
  local result = {}
  for _, name in ipairs(allowlist) do
    local key = name:lower()
    local value = values[key]
    if value == nil then
      -- Serialized headers normally use lowercase; tolerate other log plugins.
      for candidate, entry in pairs(values) do
        if type(candidate) == "string" and candidate:lower() == key then
          value = entry
          break
        end
      end
    end
    if type(value) == "string" or type(value) == "table" then
      result[key] = value
    end
  end
  return next(result) and result or nil
end

local function trace_context(value)
  if type(value) ~= "string" then
    return
  end
  local version, trace_id, span_id, flags = value:match("^(%x%x)%-(%x+)%-(%x+)%-(%x%x)$")
  if version ~= "00" or not trace_id or #trace_id ~= 32 or #span_id ~= 16 or
     trace_id:match("^0+$") or span_id:match("^0+$") then
    return
  end
  return trace_id:lower(), span_id:lower(), flags:lower()
end

-- Select fields into a new object. Never mutate Kong's shared serialization table
-- or forward credentials, query strings, arbitrary custom fields, or bodies.
function _M.build(serialized, conf, traceparent)
  local request = object(serialized.request)
  local response = object(serialized.response)
  local latencies = object(serialized.latencies)
  local service = object(serialized.service)
  local route = object(serialized.route)
  local consumer = object(serialized.consumer)
  local status_code = number(response.status)
  local level = "info"
  if status_code and status_code >= 500 then
    level = "error"
  elseif status_code and status_code >= 400 then
    level = "warning"
  end
  local path = type(request.uri) == "string" and request.uri:match("^[^?]*") or nil
  local duration_ms = number(latencies.request)
  local started_at = number(serialized.started_at)
  local result = {
    schema_version = 1,
    timestamp_ms = started_at and math.floor(started_at),
    status = level,
    request_id = request.id,
    http_method = request.method,
    http_path = path,
    http_status = status_code,
    request_bytes = number(request.size),
    response_bytes = number(response.size),
    client_ip = serialized.client_ip,
    duration = duration_ms and math.floor(duration_ms * 1000000),
    request_time_ms = duration_ms,
    kong_latency_ms = number(latencies.kong),
    upstream_latency_ms = number(latencies.proxy),
    receive_time_ms = number(latencies.receive),
    kong_service_id = service.id,
    kong_service_name = service.name,
    kong_route_id = route.id,
    kong_route_name = route.name,
    consumer_id = consumer.id,
    workspace_id = serialized.workspace,
    workspace_name = serialized.workspace_name,
    response_source = serialized.source,
    request_headers = headers(object(request.headers), conf.request_headers_allowlist),
    response_headers = headers(object(response.headers), conf.response_headers_allowlist),
  }
  local trace_id, span_id, flags = trace_context(traceparent)
  if trace_id then
    result.trace_id = trace_id
    result.parent_span_id = span_id
    result.trace_flags = flags
    result.trace_id_source = "incoming_traceparent"
  end
  return result
end

function _M.encode(serialized, conf, traceparent)
  return cjson.encode(_M.build(serialized, conf, traceparent))
end

return _M
