-- Aggregate plugin-generated drop messages per worker. Kong's queue emits its
-- own capacity/retry-exhaustion messages independently.
local buckets = {}

return function(reason, count)
  local now = ngx.now()
  local bucket = buckets[reason]
  if not bucket then
    bucket = { next_report = 0, count = 0 }
    buckets[reason] = bucket
  end
  bucket.count = bucket.count + count
  if now >= bucket.next_report then
    kong.log.err("guance-log dropped ", bucket.count, " entries: ", reason,
                 "; further occurrences aggregated for 60s")
    bucket.count = 0
    bucket.next_report = now + 60
  end
end
