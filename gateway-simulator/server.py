import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CREDENTIAL_FILE = os.environ.get("CREDENTIAL_FILE", "/run/powerbi-creds/credential.json")


class Handler(BaseHTTPRequestHandler):
    def send_json(self, status, body):
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path == "/health":
            return self.send_json(200, {"status": "up"})
        if self.path != "/report":
            return self.send_json(404, {"error": "not found"})
        try:
            with open(CREDENTIAL_FILE, encoding="utf-8") as handle:
                credential = json.load(handle)
            env = os.environ.copy()
            env["PGUSER"] = credential["username"]
            env["PGPASSWORD"] = credential["password"]
            query = (
                "SELECT json_agg(t) FROM ("
                "SELECT to_char(month, 'YYYY-MM') AS month, region, revenue "
                "FROM sales.monthly_sales ORDER BY month, region) t;"
            )
            result = subprocess.run(
                ["psql", "-X", "-qAt", "-c", query], env=env,
                capture_output=True, text=True, timeout=10, check=False
            )
            if result.returncode != 0:
                return self.send_json(503, {"status": "database authentication failed"})
            return self.send_json(200, {"status": "ok", "rows": json.loads(result.stdout)})
        except (OSError, KeyError, json.JSONDecodeError, subprocess.TimeoutExpired):
            return self.send_json(503, {"status": "credential unavailable"})

    def log_message(self, fmt, *args):
        print("gateway-simulator:", fmt % args, flush=True)


ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()

