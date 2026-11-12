# Validation record

Date: 2026-11-11 (Asia/Shanghai).

## Completed

| Check | Result |
| --- | --- |
| Unit tests and actual Kong schema validation | 71 assertions passed on Kong 3.9.4; earlier 70-assertion suite also passed on 3.9.1 |
| LuaCheck 1.2.0 | Zero warnings, zero errors across plugin modules and unit tests |
| Kong 3.9.1, DB-less, one worker | Real Gateway integration suite passed |
| Kong 3.9.4, DB-less, two workers | Real Gateway integration suite passed |
| Installed custom image, Kong 3.9.4, two workers | Integration suite passed without mounting plugin source into Lua's search path |
| Binary LuaRocks package | Built, installed in a clean Kong container, and required modules loaded |
| DataKit 2.17.1 Pipeline | Original millisecond timestamp, numeric status, log level, path, JSON header string, and original message verified |
| Python test scripts | Syntax compilation passed |
| GitHub Actions | Unit tests, both Kong integration jobs, lint and packaging passed for the initial public source commit; [run 43149282378](https://github.com/GuanceCloud/kong-plugin-guance-log/actions/runs/43149282378) |

Integration checks include:

- Thirty requests, unique IDs, batched NDJSON, UTF-8 URL tags, Pipeline/index parameters.
- Expected field mapping, incoming W3C trace IDs, header allowlists, and exclusion
  of credentials, query values, and bodies.
- Transient HTTP 503 recovery, permanent HTTP 400 rejection, no redirect following.
- Slow receiver without delaying proxy responses and oversized-entry rejection.
- Byte-limited sub-batches; retries do not resend previously acknowledged sub-batches.
- Retry-budget exhaustion with queue loss diagnostics.
- DB-less reconfiguration while an old batch is pending, preserving old/new destinations.

The integration receiver is an HTTP fixture implementing the documented Log
Streaming wire contract. The DataKit Pipeline check uses the actual installed
binary in a network-disabled container with no host configuration or credentials.

## Not verified

- End-to-end storage in a real Guance workspace, dashboard queries, or workspace-specific indexes.
- Full live DataKit forwarding to DataWay; the standalone Pipeline check validates
  field/time parsing, not the entire ingestion path.
- Kong versions outside the tested 3.9.x images, traditional/hybrid topology, or Konnect.
- Performance benchmarks, sustained production load, and guaranteed delivery on worker crashes.
- Public LuaRocks registry installation or Plugin Hub acceptance.

No real workspace token was used. Existing host services and DataKit configuration
were not changed. Test containers were removed; local build images and development
artifacts are retained for further use.
