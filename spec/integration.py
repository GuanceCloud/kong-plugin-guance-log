#!/usr/bin/env python3
"""Black-box tests using a real Kong and a local HTTP Log Streaming receiver.

Requires Python 3.9+, Docker, and Linux host networking. No workspace token.
All containers and temporary files created by this test are removed on exit.
"""
import argparse
import collections
import concurrent.futures
import http.server
import json
import pathlib
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid


ROOT = pathlib.Path(__file__).resolve().parents[1]


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def request(url, method="GET", data=None, headers=None):
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def wait_for(predicate, description, timeout=15):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError("timed out waiting for " + description)


class Receiver(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    events = []
    lock = threading.Lock()
    attempts = collections.Counter()

    def log_message(self, *args):
        pass

    def do_GET(self):
        self.reply(200, b"upstream ok")

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        path = urllib.parse.urlsplit(self.path)
        if path.path != "/v1/write/logstreaming":
            self.reply(200, b"upstream ok")
            return
        query = urllib.parse.parse_qs(path.query)
        source = query["source"][0]
        with self.lock:
            self.attempts[source] += 1
            attempt = self.attempts[source]
        status = 200
        if source == "retry" and attempt == 1:
            status = 503
        elif source == "split" and attempt == 2:
            status = 503
        elif source == "reject":
            status = 400
        elif source == "redirect":
            status = 302
        elif source == "exhaust":
            status = 503
        elif source == "slow":
            time.sleep(1)
        records = [json.loads(line) for line in body.decode().splitlines() if line]
        with self.lock:
            self.events.append({"source": source, "status": status, "body": body,
                                "query": query, "records": records,
                                "content_type": self.headers.get("Content-Type")})
        self.reply(status, b'{"status":"success"}')

    def reply(self, status, body):
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Content-Type", "text/plain")
        self.send_header("Set-Cookie", "secret-cookie")
        if status == 302:
            self.send_header("Location", "/v1/write/logstreaming?source=redirect_target")
        self.end_headers()
        self.wfile.write(body)


def events(source, successful=False):
    with Receiver.lock:
        return [event for event in Receiver.events if event["source"] == source and
                (not successful or event["status"] == 200)]


def records(source):
    return [record for event in events(source, True) for record in event["records"]]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", default="kong:3.9.1")
    parser.add_argument("--workers", type=int, default=1)
    parser.add_argument("--installed", action="store_true", help="test modules installed in the image")
    args = parser.parse_args()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Receiver)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    receiver_port = server.server_port
    proxy_port, admin_port = free_port(), free_port()
    proxy = f"http://127.0.0.1:{proxy_port}"
    admin = f"http://127.0.0.1:{admin_port}"
    name = "guance-log-test-" + uuid.uuid4().hex[:12]
    configuration = {"_format_version": "3.0", "services": []}
    for source in ("batch", "retry", "reject", "redirect", "slow", "oversize", "split", "exhaust"):
        config = {
            "endpoint": f"http://127.0.0.1:{receiver_port}",
            "source": source, "service": "gateway",
            "tags": {"env": "test", "team": "研发 space"},
            "pipeline": "guance-log.p", "storage_index": "gateway_logs",
            "request_headers_allowlist": ["x-allowed"],
            "response_headers_allowlist": ["content-type"],
            "queue": {"max_batch_size": 1, "max_coalescing_delay": 0.2,
                      "initial_retry_delay": 0.05, "max_retry_delay": 0.1, "max_retry_time": 1},
        }
        if source == "batch":
            config["queue"]["max_batch_size"] = 100
        if source == "split":
            config.update(max_entry_bytes=1024, max_payload_bytes=1100)
            config["queue"].update(max_batch_size=100, max_coalescing_delay=0.5)
        if source == "oversize":
            config.update(max_entry_bytes=1024, max_payload_bytes=2048)
        if source == "exhaust":
            config["queue"]["max_retry_time"] = 0.25
        configuration["services"].append({
            "name": "service-" + source,
            "url": f"http://127.0.0.1:{receiver_port}/upstream",
            "routes": [{"name": "route-" + source, "paths": ["/" + source]}],
            "plugins": [{"name": "guance-log", "config": config}],
        })

    with tempfile.TemporaryDirectory(prefix="guance-log-test-") as tmp:
        config_file = pathlib.Path(tmp) / "kong.json"
        config_file.write_text(json.dumps(configuration))
        config_file.chmod(0o644)
        command = [
            "docker", "run", "-d", "--name", name, "--network", "host",
            "-v", f"{config_file}:/etc/kong/test.json:ro",
            "-e", "KONG_DATABASE=off", "-e", "KONG_DECLARATIVE_CONFIG=/etc/kong/test.json",
            "-e", "KONG_PLUGINS=bundled,guance-log",
            "-e", f"KONG_PROXY_LISTEN=127.0.0.1:{proxy_port}",
            "-e", f"KONG_ADMIN_LISTEN=127.0.0.1:{admin_port}",
            "-e", f"KONG_NGINX_WORKER_PROCESSES={args.workers}", "-e", "KONG_LOG_LEVEL=notice",
            "-e", "KONG_PROXY_ACCESS_LOG=off", "-e", "KONG_ADMIN_ACCESS_LOG=off",
            "-e", "KONG_ANONYMOUS_REPORTS=off", args.image,
        ]
        if not args.installed:
            command[-1:-1] = ["-v", f"{ROOT}:/plugin:ro", "-e", "KONG_LUA_PACKAGE_PATH=/plugin/?.lua;;"]
        try:
            subprocess.run(command, check=True, capture_output=True, text=True)

            def ready():
                try:
                    return request(admin + "/status")[0] == 200
                except (OSError, urllib.error.URLError):
                    return False

            wait_for(ready, "Kong startup", 30)
            enabled = json.loads(request(admin + "/plugins/enabled")[1])["enabled_plugins"]
            assert "guance-log" in enabled
            print("PASS: real Kong loads schema and handler", flush=True)

            traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
            headers = {"Authorization": "Bearer secret-auth", "Cookie": "secret-cookie",
                       "X-Allowed": "hello", "Traceparent": traceparent}

            def send_batch(index):
                return request(proxy + f"/batch/item-{index}?password=secret-query", "POST",
                               b"secret-body", headers)[0]

            with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
                assert all(code == 200 for code in pool.map(send_batch, range(30)))
            wait_for(lambda: len(records("batch")) == 30, "30 batched records")
            assert any(len(event["records"]) > 1 for event in events("batch"))
            for event in events("batch"):
                assert event["body"].endswith(b"\n")
                assert event["content_type"].startswith("text/plain")
                assert event["query"]["tags"] == ["env=test,team=研发 space"]
                assert event["query"]["pipeline"] == ["guance-log.p"]
                assert event["query"]["storage_index"] == ["gateway_logs"]
                assert b"secret" not in event["body"]
            assert len({record["request_id"] for record in records("batch")}) == 30
            for record in records("batch"):
                assert record["http_status"] == 200
                assert record["http_path"].startswith("/batch/item-")
                assert record["kong_service_name"] == "service-batch"
                assert record["trace_id"] == "4bf92f3577b34da6a3ce929d0e0e4736"
                assert record["parent_span_id"] == "00f067aa0ba902b7"
                assert record["request_headers"] == {"x-allowed": "hello"}
                assert set(record["response_headers"]) == {"content-type"}
                assert record["response_headers"]["content-type"].startswith("text/plain")
                assert record["duration"] >= 0
            print("PASS: NDJSON batching, field mapping, URL tags, and secret exclusion", flush=True)

            assert request(proxy + "/retry")[0] == 200
            wait_for(lambda: len(records("retry")) == 1, "retry recovery")
            assert len(events("retry")) == 2
            assert request(proxy + "/reject")[0] == 200
            assert request(proxy + "/redirect")[0] == 200
            wait_for(lambda: len(events("reject")) == 1 and len(events("redirect")) == 1, "permanent errors")
            time.sleep(0.3)
            assert len(events("reject")) == 1 and len(events("redirect")) == 1
            assert not events("redirect_target")
            print("PASS: transient retry, permanent rejection, and no redirects", flush=True)

            start = time.monotonic()
            assert request(proxy + "/slow")[0] == 200
            assert time.monotonic() - start < 0.75, "collector delayed proxy response"
            wait_for(lambda: len(records("slow")) == 1, "asynchronous slow receiver")
            assert request(proxy + "/oversize", headers={"X-Allowed": "x" * 3000})[0] == 200
            time.sleep(0.3)
            assert not events("oversize")
            print("PASS: slow receiver does not block requests; oversized record dropped", flush=True)

            with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
                assert all(code == 200 for code, _ in pool.map(lambda _: request(proxy + "/split"), range(5)))
            wait_for(lambda: len(records("split")) == 5, "byte-split batch retry")
            assert all(len(event["body"]) <= 1100 for event in events("split"))
            assert len({record["request_id"] for record in records("split")}) == 5
            assert len(events("split")) == 6  # one failed sub-batch retried
            print("PASS: payload byte limits and successful sub-batch checkpointing", flush=True)

            assert request(proxy + "/exhaust")[0] == 200
            wait_for(lambda: len(events("exhaust")) >= 2, "retry exhaustion")
            time.sleep(0.6)
            count = len(events("exhaust"))
            time.sleep(0.3)
            assert len(events("exhaust")) == count
            logs = subprocess.check_output(["docker", "logs", name], stderr=subprocess.STDOUT).decode()
            assert "max_retry_time exceeded" in logs
            assert "entry exceeds max_entry_bytes" in logs
            print("PASS: bounded retries and drop diagnostics", flush=True)

            # Reconfigure the same plugin entity while one old batch is pending.
            plugin = configuration["services"][0]["plugins"][0]
            plugin["id"] = "713c60cd-c993-4e93-a489-e270e51c98db"
            plugin["config"]["source"] = "old_config"
            plugin["config"]["queue"]["max_coalescing_delay"] = 2
            status, body = request(admin + "/config", "POST", json.dumps(configuration).encode(),
                                   {"Content-Type": "application/json"})
            assert status in (200, 201), body
            time.sleep(0.2)  # DB-less worker events update the plugin iterator asynchronously.
            assert request(proxy + "/batch/old")[0] == 200
            time.sleep(0.1)
            plugin["config"]["source"] = "new_config"
            status, body = request(admin + "/config", "POST", json.dumps(configuration).encode(),
                                   {"Content-Type": "application/json"})
            assert status in (200, 201), body
            time.sleep(0.2)
            assert request(proxy + "/batch/new")[0] == 200
            wait_for(lambda: len(records("old_config")) == 1 and len(records("new_config")) == 1,
                     "configuration-isolated queue drain")
            assert records("old_config")[0]["http_path"] == "/batch/old"
            assert records("new_config")[0]["http_path"] == "/batch/new"
            print("PASS: pending logs retain destination on configuration reload", flush=True)
            print("PASS: integration suite on " + args.image, flush=True)
        except Exception:
            print("Captured records by source:", {source: [record.get("http_path") for record in records(source)]
                  for source in ("batch", "old_config", "new_config")}, flush=True)
            subprocess.run(["docker", "logs", "--tail", "60", name], check=False)
            raise
        finally:
            subprocess.run(["docker", "rm", "-f", name], capture_output=True, check=False)
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    main()
