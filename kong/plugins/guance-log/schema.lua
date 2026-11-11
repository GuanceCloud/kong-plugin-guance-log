local typedefs = require "kong.db.schema.typedefs"
local url = require "socket.url"

local function validate_endpoint(value)
  local parsed = url.parse(value)
  if not parsed or not parsed.host or parsed.host == "" or
     (parsed.scheme ~= "http" and parsed.scheme ~= "https") then
    return false, "endpoint must be an absolute HTTP or HTTPS URL"
  end
  if parsed.userinfo or parsed.query or parsed.fragment or value:find("[%s%c?#]") then
    return false, "endpoint must not contain credentials, query parameters, fragments, or whitespace"
  end
  if parsed.port and (not tonumber(parsed.port) or tonumber(parsed.port) < 1 or
                     tonumber(parsed.port) > 65535 or not parsed.port:match("^%d+$")) then
    return false, "endpoint port must be between 1 and 65535"
  end
  if parsed.path and parsed.path ~= "/" and parsed.path ~= "/v1/write/logstreaming" then
    return false, "endpoint path must be empty, /, or /v1/write/logstreaming"
  end
  return true
end

local function validate_header(value)
  if not value:match("^[!#$%%&'*+.^_`|~%w%-]+$") then
    return false, "invalid HTTP header name"
  end
  local name = value:lower()
  if name == "authorization" or name == "proxy-authorization" or
     name == "cookie" or name == "set-cookie" or name == "x-api-key" then
    return false, "credential headers cannot be collected"
  end
  return true
end

return {
  name = "guance-log",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
        { endpoint = { type = "string", required = true, custom_validator = validate_endpoint } },
        { source = { type = "string", default = "kong", len_min = 1, len_max = 256,
                     match_none = { { pattern = "[%c]", err = "control characters are not allowed" } } } },
        { service = { type = "string", default = "kong", len_min = 1, len_max = 256,
                      match_none = { { pattern = "[%c]", err = "control characters are not allowed" } } } },
        { pipeline = { type = "string", len_min = 1, len_max = 256 } },
        { storage_index = { type = "string", len_max = 256, match = "^[a-z][a-z0-9_]*$" } },
        { tags = { type = "map", default = {},
          keys = { type = "string", len_max = 128, match = "^[%a_][%w_.%-]*$",
            custom_validator = function(key)
              if key == "source" or key == "service" or key == "status" or
                 key == "collector_source_ip" or key == "ip_or_hostname" then
                return false, "reserved DataKit tag name"
              end
              return true
            end,
          },
          values = { type = "string", len_min = 1, len_max = 512,
                     match_none = { { pattern = "[,=%c]",
                       err = "tag values must not contain commas, equals signs, or control characters" } } },
        } },
        { request_headers_allowlist = { type = "array", default = {},
          elements = { type = "string", len_min = 1, len_max = 128, custom_validator = validate_header } } },
        { response_headers_allowlist = { type = "array", default = {},
          elements = { type = "string", len_min = 1, len_max = 128, custom_validator = validate_header } } },
        { connect_timeout = { type = "integer", default = 1000, between = { 1, 60000 } } },
        { send_timeout = { type = "integer", default = 5000, between = { 1, 60000 } } },
        { read_timeout = { type = "integer", default = 5000, between = { 1, 60000 } } },
        { keepalive = { type = "integer", default = 60000, between = { 0, 3600000 } } },
        { ssl_verify = { type = "boolean", default = true } },
        { max_entry_bytes = { type = "integer", default = 65536, between = { 1024, 1048576 } } },
        { max_payload_bytes = { type = "integer", default = 1048576, between = { 1024, 8388608 } } },
        { queue = {
          type = "record",
          required = true,
          default = {},
          fields = {
            { max_batch_size = { type = "integer", default = 100, between = { 1, 1000 } } },
            { max_coalescing_delay = { type = "number", default = 1, between = { 0, 60 } } },
            { max_entries = { type = "integer", default = 10000, between = { 1, 1000000 } } },
            { max_bytes = { type = "integer", default = 10485760, between = { 1024, 1073741824 } } },
            { initial_retry_delay = { type = "number", default = 0.1, between = { 0.001, 60 } } },
            { max_retry_delay = { type = "number", default = 10, between = { 0.001, 300 } } },
            { max_retry_time = { type = "number", default = 60, between = { 0, 3600 } } },
          },
        } },
      },
      custom_validator = function(config)
        if config.max_entry_bytes + 1 > config.max_payload_bytes then
          return false, "max_payload_bytes must fit max_entry_bytes plus a newline"
        end
        if config.max_entry_bytes > config.queue.max_bytes then
          return false, "queue.max_bytes must be at least max_entry_bytes"
        end
        if config.queue.initial_retry_delay > config.queue.max_retry_delay then
          return false, "queue.initial_retry_delay must not exceed queue.max_retry_delay"
        end
        return true
      end,
    } },
  },
}
