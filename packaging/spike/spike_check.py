"""Quorum sidecar contract harness (P2.0 bundling spike) — stdlib only, NO repo imports.

Proves a sidecar (frozen exe or unfrozen ``python -m services.api``) honours the full desktop
contract: stdout {port,token} handshake, /healthz, bearer auth, a cost-free demo SSE run to
``run_done``, /shutdown, and parent-PID teardown. Exits 0 iff every check passes.

Usage:
  frozen:   python spike_check.py C:/path/quorum_sidecar.exe
  unfrozen: SPIKE_CWD=<repo> python spike_check.py <repo>/.venv/Scripts/python.exe -m services.api

Mirrors apps/desktop/lib/engine/desktop_sidecar_endpoint.dart: handshake-as-first-line within the
12s budget, /healthz gate, and SSE framing (CRLF frame separators; the stream stays open after
run_done, so the reader must break on the run_done frame rather than on an empty read).
"""
import json, os, subprocess, sys, time, http.client

FAILS = []
def chk(ok, msg):
    print(("PASS" if ok else "FAIL") + " | " + msg)
    if not ok:
        FAILS.append(msg)

spawn = sys.argv[1:]
env = dict(os.environ)
env["QUORUM_PARENT_PID"] = str(os.getpid())
env.pop("QUORUM_API_PORT", None)
env.pop("QUORUM_API_TOKEN", None)
cwd = os.environ.get("SPIKE_CWD") or None
t0 = time.time()
proc = subprocess.Popen(spawn, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, text=True, cwd=cwd)

hs = None
dl = time.time() + 12
while time.time() < dl:
    line = proc.stdout.readline()
    if not line:
        if proc.poll() is not None:
            break
        continue
    line = line.strip()
    try:
        o = json.loads(line)
        if isinstance(o, dict) and o.get("quorum_api") is True:
            hs = o
            break
    except Exception:
        sys.stderr.write("[py] " + line + "\n")
cold_ms = int((time.time() - t0) * 1000)
chk(hs is not None, f"handshake received in {cold_ms}ms (Dart budget 12000ms)")
if hs is None:
    print("STDERR:", proc.stderr.read()[:3000])
    print("\n=== RESULT: HARD FAIL (no handshake) ===")
    sys.exit(1)
chk(hs.get("host") == "127.0.0.1" and isinstance(hs.get("port"), int) and hs.get("port") > 0
    and bool(hs.get("token")) and hs.get("contract_version") == 1, f"handshake shape ok: {hs}")
host, port, token = hs["host"], hs["port"], hs["token"]
auth = {"Authorization": f"Bearer {token}"}

def get(path, headers=None):
    c = http.client.HTTPConnection(host, port, timeout=10)
    c.request("GET", path, headers=headers or {})
    r = c.getresponse(); b = r.read(); c.close()
    return r.status, b

def post(path, payload, headers=None):
    c = http.client.HTTPConnection(host, port, timeout=10)
    h = {"Content-Type": "application/json"}; h.update(headers or {})
    c.request("POST", path, body=json.dumps(payload), headers=h)
    r = c.getresponse(); b = r.read(); c.close()
    return r.status, b

ok = False
hd = time.time() + 30
while time.time() < hd:
    try:
        st, _ = get("/healthz")
        if st == 200:
            ok = True
            break
    except Exception:
        pass
    time.sleep(0.4)
chk(ok, "/healthz -> 200")
st, _ = get("/catalog/providers")
chk(st == 401, f"/catalog/providers no-token -> 401 (got {st})")
st, b = get("/catalog/providers", auth)
chk(st == 200 and len(json.loads(b).get("providers", {})) > 0, f"/catalog/providers +token -> 200 non-empty (got {st})")

st, b = post("/runs", {"mode": "demo", "ticker": "NVDA", "step_delay": 0}, auth)
rid = json.loads(b).get("run_id") if st == 202 else None
chk(st == 202 and rid, f"POST /runs demo -> 202 (got {st})")

if rid:
    time.sleep(0.4)
    c = http.client.HTTPConnection(host, port, timeout=30)
    c.request("GET", f"/runs/{rid}/events", headers=auth)
    r = c.getresponse()
    buf = b""; types = []; seqs = []; rd = None; done = False
    dl2 = time.time() + 25

    def _split(bb):
        i = bb.find(b"\r\n\r\n"); j = bb.find(b"\n\n")
        if i == -1 and j == -1:
            return None, bb
        if i == -1:
            return bb[:j], bb[j + 2:]
        if j == -1 or i < j:
            return bb[:i], bb[i + 4:]
        return bb[:j], bb[j + 2:]

    while not done and time.time() < dl2:
        chunk = r.read(512)
        if not chunk:
            break
        buf += chunk
        while True:
            frame, rest = _split(buf)
            if frame is None:
                break
            buf = rest
            et = sid = data = None
            for fl in frame.replace(b"\r", b"").split(b"\n"):
                if fl.startswith(b"event:"):
                    et = fl[6:].strip().decode()
                elif fl.startswith(b"id:"):
                    sid = fl[3:].strip().decode()
                elif fl.startswith(b"data:"):
                    data = fl[5:].strip().decode()
            if et:
                types.append(et)
                if sid and sid.isdigit():
                    seqs.append(int(sid))
                if et == "run_done":
                    rd = json.loads(data)
                    done = True
                    break
    c.close()
    chk("run_started" in types and "stage_started" in types and "run_done" in types,
        f"SSE has run_started/stage_started/run_done (n={len(types)})")
    chk(bool(seqs) and seqs == sorted(seqs) and seqs[0] == 0, f"SSE seq monotonic from 0 (n={len(seqs)})")
    d = (rd or {}).get("data", {})
    chk(d.get("rating") == "Buy" and abs((d.get("confidence") or 0) - 0.72) < 0.01 and d.get("cancelled") is False,
        f"run_done rating=Buy conf~0.72 cancelled=false (rating={d.get('rating')}, conf={d.get('confidence')}, cancelled={d.get('cancelled')})")

st, _ = post("/shutdown", {}, auth)
chk(st == 200, f"/shutdown -> 200 (got {st})")
time.sleep(1.5)
chk(proc.poll() is not None, f"process exited within 1.5s of /shutdown (rc={proc.poll()})")
if proc.poll() is None:
    proc.kill()
print("\n=== RESULT:", "ALL PASS" if not FAILS else f"{len(FAILS)} FAILURE(S): {FAILS}", "===")
sys.exit(0 if not FAILS else 1)
