import json
import sys
import unittest
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from threading import Thread

sys.path.insert(0, str(Path(__file__).parents[1] / "src"))
from litport_free_proxy_sdk import Client, HttpError, NotModifiedWithoutCacheError, SnapshotTruncatedError, to_proxy_url

ROOT = Path(__file__).parents[3]
NOW = lambda: datetime(2026, 9, 10, tzinfo=timezone.utc)
def fixture(name): return json.loads((ROOT / "fixtures" / name).read_text())
def transport(body, status=200): return lambda *_: (status, {"ETag": '"fixture"', "Cache-Control": "max-age=3600"}, body)

class SDKTest(unittest.TestCase):
    def test_both_sources_match_contract(self):
        api = Client(now=NOW, transport=transport(fixture("api-snapshot.json")))
        github = Client(source="github", now=NOW, transport=transport(fixture("github-proxies.json")))
        expected = fixture("expected-proxies.json")
        mapping = {"asnOrg": "asn_org", "latencyMs": "latency_ms", "latencyMedianMs": "latency_median_ms", "uptime24h": "uptime_24h", "uptime7d": "uptime_7d", "checks7d": "checks_7d", "exitIp": "exit_ip", "sourcesCount": "sources_count", "firstSeen": "first_seen", "lastChecked": "last_checked"}
        expected = [{mapping.get(key, key): value for key, value in row.items()} for row in expected]
        self.assertEqual([p.__dict__ for p in api.get_proxies()], expected)
        self.assertEqual([p.__dict__ for p in github.get_proxies()], expected)
    def test_filters_and_errors(self):
        client = Client(now=NOW, transport=transport(fixture("api-snapshot.json")))
        self.assertEqual([to_proxy_url(p) for p in client.pick_best(1)], ["http://8.8.8.8:8080"])
        self.assertEqual(len(client.get_proxies({"protocol": "socks5"})), 1)
        with self.assertRaises(HttpError): Client(now=NOW, transport=transport([], 429)).get_proxies()
        with self.assertRaises(NotModifiedWithoutCacheError): Client(now=NOW, transport=transport(None, 304)).get_proxies()
        with self.assertRaises(SnapshotTruncatedError): Client(now=NOW, transport=transport({"generatedAt": "2026-09-10T00:00:00Z", "proxies": [], "truncated": True})).get_proxies()
    def test_native_urllib_revalidates_local_http_snapshot(self):
        body = json.dumps(fixture("api-snapshot.json")).encode()
        class Handler(BaseHTTPRequestHandler):
            requests = 0
            def do_GET(self):
                Handler.requests += 1
                if self.headers.get("If-None-Match") == '"local"': self.send_response(304); self.send_header("ETag", '"local"'); self.send_header("Cache-Control", "max-age=0"); self.end_headers(); return
                self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("ETag", '"local"'); self.send_header("Cache-Control", "max-age=0"); self.end_headers(); self.wfile.write(body)
            def log_message(self, *args): pass
        server = HTTPServer(("127.0.0.1", 0), Handler); thread = Thread(target=server.serve_forever); thread.start()
        try:
            client = Client(api_url="http://127.0.0.1:%s/snapshot" % server.server_port, now=NOW)
            self.assertEqual(len(client.get_proxies()), 2); self.assertEqual(len(client.get_proxies()), 2); self.assertEqual(Handler.requests, 2)
        finally:
            server.shutdown(); thread.join(); server.server_close()

if __name__ == "__main__": unittest.main()
