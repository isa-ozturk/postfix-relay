#!/usr/bin/env python3
"""
Postfix Outbound Relay — Mail Log Viewer
Yazar: Isa Öztürk
"""

import os
import re
import ipaddress
import subprocess
from datetime import datetime
from collections import defaultdict
from functools import wraps
from flask import Flask, render_template, request, jsonify, abort

app = Flask(__name__)

APP_TITLE = os.getenv("APP_TITLE", "Mail Log Viewer")
BASE_PATH = os.getenv("BASE_PATH", "/maillog")

LOG_PATHS = [
    "/var/log/postfix/mail.log",
    "/var/log/mail.log",
    "/var/log/syslog",
]

STATUS_COLORS = {
    "sent":      "#22c55e",
    "bounced":   "#ef4444",
    "deferred":  "#f59e0b",
    "rejected":  "#8b5cf6",
    "expired":   "#6b7280",
    "queued":    "#3b82f6",
}
STATUS_ICONS = {
    "sent":      "✅",
    "bounced":   "❌",
    "deferred":  "⏳",
    "rejected":  "🚫",
    "expired":   "💀",
    "queued":    "📤",
}


def get_allowed_networks():
    raw = os.getenv("ALLOWED_NETWORKS", "0.0.0.0/0")
    nets = []
    for cidr in raw.split(","):
        cidr = cidr.strip()
        if cidr:
            try:
                nets.append(ipaddress.ip_network(cidr, strict=False))
            except ValueError:
                pass
    return nets


def ip_allowed(ip: str) -> bool:
    if ip in ("127.0.0.1", "::1"):
        return True
    try:
        addr = ipaddress.ip_address(ip)
        return any(addr in net for net in get_allowed_networks())
    except ValueError:
        return True


def require_allowed_ip(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        forwarded = request.headers.get("X-Forwarded-For", "").split(",")
        real_ip = forwarded[0].strip() or request.remote_addr
        if not ip_allowed(real_ip):
            abort(403)
        return f(*args, **kwargs)
    return decorated


def read_log_lines(n: int = 10000) -> list[str]:
    for path in LOG_PATHS:
        if os.path.exists(path) and os.path.getsize(path) > 0:
            try:
                result = subprocess.run(
                    ["tail", "-n", str(n), path],
                    capture_output=True, text=True, timeout=5
                )
                if result.stdout.strip():
                    return result.stdout.splitlines()
            except Exception:
                continue
    return []


def parse_postfix_log(lines: list[str], limit: int = 500) -> list[dict]:
    queue_map: dict[str, dict] = {}
    noqueue_events: list[dict] = []

    # Timestamp: "Jul  8 18:13:00" veya "Jul 08 18:13:00"
    TS = r"(\w{3}\s+\d{1,2}\s+[\d:]+)"

    # qmgr satırı: from + size — en güvenilir kaynak
    re_qmgr = re.compile(
        TS + r".*postfix/qmgr\[\d+\]:\s+([0-9A-F]{6,12}):\s+"
        r"from=<([^>]*)>,\s+size=(\d+)"
    )
    # smtp/lmtp satırı: teslim durumu
    re_to = re.compile(
        TS + r".*postfix/(?:smtp|lmtp|local|virtual)\[\d+\]:\s+"
        r"([0-9A-F]{6,12}):\s+to=<([^>]*)>,"
        r".*?(?:relay=([^,]+),.*?)?status=(\w+)\s*\(([^)]*)\)"
    )
    # smtpd satırı: kaynak IP
    re_client = re.compile(
        r"([0-9A-F]{6,12}): client=([^\[]+)\[([^\]]+)\]"
    )
    # NOQUEUE reject
    re_reject = re.compile(
        TS + r".*NOQUEUE: reject:.*?from=<([^>]*)>.*?to=<([^>]*)>:.*?(\d{3}[^;]*)"
    )

    # 1. pass — client IP map
    client_map: dict[str, str] = {}
    for line in lines:
        m = re_client.search(line)
        if m:
            qid, hostname, ip = m.groups()
            client_map[qid] = f"{hostname.strip()}[{ip}]"

    # 2. pass — olayları topla
    for line in lines:
        # qmgr → from + size
        m = re_qmgr.search(line)
        if m:
            ts, qid, sender, size = m.groups()
            if qid not in queue_map:
                queue_map[qid] = {
                    "queue_id":   qid,
                    "timestamp":  ts.strip(),
                    "from":       sender or "<>",
                    "size":       int(size),
                    "recipients": [],
                    "client":     client_map.get(qid, ""),
                }
            continue

        # smtp → to + status
        m = re_to.search(line)
        if m:
            ts, qid, recipient, relay, status, detail = m.groups()
            if qid in queue_map:
                queue_map[qid]["recipients"].append({
                    "to":     recipient,
                    "relay":  (relay or "").strip(),
                    "status": status.lower(),
                    "detail": (detail or "").strip()[:300],
                    "time":   ts.strip(),
                })
            continue

        # NOQUEUE reject
        m = re_reject.search(line)
        if m:
            ts, sender, recipient, reason = m.groups()
            noqueue_events.append({
                "queue_id":   "NOQUEUE",
                "timestamp":  ts.strip(),
                "from":       sender or "<>",
                "size":       0,
                "client":     "",
                "recipients": [{
                    "to":     recipient,
                    "relay":  "—",
                    "status": "rejected",
                    "detail": reason.strip()[:300],
                    "time":   ts.strip(),
                }],
            })

    events: list[dict] = list(noqueue_events)
    for qid, data in queue_map.items():
        if not data["recipients"]:
            data["recipients"] = [{
                "to": "—", "relay": "—", "status": "queued",
                "detail": "Kuyruğa alındı, henüz teslim edilmedi",
                "time": data["timestamp"],
            }]
        events.append(data)

    events.sort(key=lambda x: x.get("timestamp", ""), reverse=True)
    return events[:limit]


def get_stats(events: list[dict]) -> dict:
    stats: dict = defaultdict(int)
    for event in events:
        for r in event.get("recipients", []):
            stats[r.get("status", "unknown")] += 1
            stats["total"] += 1
    return dict(stats)


@app.route("/")
@require_allowed_ip
def index():
    filter_status = request.args.get("status", "")
    filter_from   = request.args.get("from",   "").strip()
    filter_to     = request.args.get("to",     "").strip()
    limit = min(int(request.args.get("limit", 200)), 1000)

    lines  = read_log_lines(15000)
    events = parse_postfix_log(lines, limit=2000)
    stats  = get_stats(events)

    if filter_status:
        events = [e for e in events if any(r["status"] == filter_status for r in e["recipients"])]
    if filter_from:
        events = [e for e in events if filter_from.lower() in e.get("from", "").lower()]
    if filter_to:
        events = [e for e in events if any(filter_to.lower() in r["to"].lower() for r in e["recipients"])]

    events = events[:limit]
    log_source = next(
        (p for p in LOG_PATHS if os.path.exists(p) and os.path.getsize(p) > 0),
        None
    )

    return render_template(
        "index.html",
        events=events,
        stats=stats,
        status_colors=STATUS_COLORS,
        status_icons=STATUS_ICONS,
        filter_status=filter_status,
        filter_from=filter_from,
        filter_to=filter_to,
        refresh_interval=int(os.getenv("LOG_REFRESH_INTERVAL", 30)),
        now=datetime.now().strftime("%d.%m.%Y %H:%M:%S"),
        total_shown=len(events),
        log_source=log_source,
        app_title=APP_TITLE,
        base_path=BASE_PATH,
    )


@app.route("/api/events")
@require_allowed_ip
def api_events():
    lines  = read_log_lines(3000)
    events = parse_postfix_log(lines, limit=100)
    return jsonify({"stats": get_stats(events), "events": events})


@app.route("/health")
def health():
    return jsonify({"status": "ok", "time": datetime.now().isoformat()})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)