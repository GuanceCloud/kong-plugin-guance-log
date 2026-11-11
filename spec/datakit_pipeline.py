#!/usr/bin/env python3
"""Validate the supplied Pipeline using an existing DataKit binary in isolation.

No host DataKit configuration, credentials, or network are mounted into Docker.
Usage: python3 spec/datakit_pipeline.py --binary /usr/local/datakit/datakit
"""
import argparse
import json
import pathlib
import subprocess


parser = argparse.ArgumentParser()
parser.add_argument("--binary", required=True)
parser.add_argument("--image", default="kong:3.9.4")
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
binary = pathlib.Path(args.binary).resolve(strict=True)
samples = [
    {"timestamp_ms": 1730000000123, "http_status": 503, "status": "error",
     "http_path": "/hello", "duration": 12500000,
     "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
     "request_headers": {"x-allowed": "你好"}},
    {"timestamp_ms": 1730000000999, "http_status": 200, "status": "info", "http_path": "/ok"},
]
for sample in samples:
    output = subprocess.check_output([
        "docker", "run", "--rm", "--user", "root", "--network", "none",
        "-v", f"{binary}:/usr/local/datakit/datakit:ro",
        "-v", f"{root / 'examples/datakit'}:/usr/local/datakit/pipeline:ro",
        "--entrypoint", "/usr/local/datakit/datakit", args.image,
        "pipeline", "-P", "guance-log.p", "-T", json.dumps(sample),
    ], text=True, stderr=subprocess.PIPE)
    result, _ = json.JSONDecoder().raw_decode(output[output.index("{"):])
    assert result["time"] == sample["timestamp_ms"] * 1000000, result
    assert result["timestamp_ms"] == sample["timestamp_ms"]
    assert result["http_status"] == sample["http_status"]
    assert result["http_path"] == sample["http_path"]
    assert result["status"] == sample["status"]
    assert json.loads(result["message"]) == sample
    if "request_headers" in sample:
        assert json.loads(result["request_headers"]) == sample["request_headers"]
print("PASS: DataKit Pipeline extracts fields, preserves message and original millisecond time")
