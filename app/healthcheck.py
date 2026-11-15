import os
import sys
import urllib.request

url = os.environ.get("HEALTH_URL", "http://localhost:5000/health")
try:
    with urllib.request.urlopen(url, timeout=5) as resp:
        if resp.status != 200:
            sys.exit(1)
except Exception as exc:
    print("healthcheck не прошёл:", exc, file=sys.stderr)
    sys.exit(1)
