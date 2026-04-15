"""
YueLink telemetry — ingest + stats + feature flags + NPS + dashboard.

Drop-in FastAPI APIRouter mounted alongside the existing checkin-api
service on 23.80.91.14.

Storage: **PostgreSQL 16** on the shared yueops database
(66.55.76.208:5432/yueops, schema `telemetry`). The `TELEMETRY_DATABASE_URL`
env var is a standard libpq DSN — defaults to the same DSN yueops uses.
Tables live in the `telemetry` schema so they don't collide with yueops'
own models.

Why PG instead of the earlier sqlite build:
- MVCC: concurrent writers don't block each other while prune runs.
- GIN indexes on JSONB props: O(log n) instead of table-scan json_extract.
- Same cluster yueops already uses → zero extra ops surface.
- Quality-plane bridge (see ROADMAP.md) needs to JOIN node_events with
  yueops.server_nodes — same-DB joins are O(index) instead of cross-process.

Routes (all under /api/client/telemetry):

    POST /                         ingest a batch (what the app sends)
    GET  /flags                    feature flag evaluation for a client_id
    POST /nps                      NPS score + comment submission
    GET  /stats/summary            top events + counts               (BasicAuth)
    GET  /stats/dau                daily active clients              (BasicAuth)
    GET  /stats/crash_free         crash-free session rate           (BasicAuth)
    GET  /stats/startup_funnel     8-step funnel ok vs fail          (BasicAuth)
    GET  /stats/errors             top error types                   (BasicAuth)
    GET  /stats/versions           platform × version                (BasicAuth)
    GET  /stats/nodes              node fingerprint health scores    (BasicAuth)
    GET  /stats/nps                NPS aggregate + last comments     (BasicAuth)
    GET  /admin/flags              admin JSON view of current flags  (BasicAuth)
    POST /admin/flags              write a flag value                (BasicAuth)
    GET  /dashboard                single-page HTML dashboard        (BasicAuth)
"""

from __future__ import annotations

import hashlib
import json
import os
import secrets
import time
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from typing import Iterator, Optional

import psycopg2
import psycopg2.extras
import psycopg2.pool
from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials

# ── Configuration ───────────────────────────────────────────────────────

# Default matches yueops own DATABASE_URL (same cluster, same DB, different schema).
DEFAULT_DSN = (
    "host=66.55.76.208 port=5432 user=root password=jim@8858 dbname=yueops"
)
DSN = os.environ.get("TELEMETRY_DATABASE_DSN", DEFAULT_DSN)
SCHEMA = os.environ.get("TELEMETRY_SCHEMA", "telemetry")

DASHBOARD_USER = os.environ.get("TELEMETRY_DASHBOARD_USER", "")
DASHBOARD_PASSWORD = os.environ.get("TELEMETRY_DASHBOARD_PASSWORD", "")
RETENTION_DAYS = int(os.environ.get("TELEMETRY_RETENTION_DAYS", "90"))

MAX_EVENTS_PER_REQUEST = 200
MAX_EVENT_NAME_LEN = 64
MAX_PROP_VALUE_LEN = 200
MAX_INVENTORY_NODES = 200

router = APIRouter(prefix="/api/client/telemetry", tags=["telemetry"])
security = HTTPBasic()


# ── DB plumbing ─────────────────────────────────────────────────────────

_SCHEMA_SQL = f"""
CREATE SCHEMA IF NOT EXISTS {SCHEMA};
SET LOCAL search_path TO {SCHEMA}, public;

CREATE TABLE IF NOT EXISTS {SCHEMA}.events (
    id          BIGSERIAL PRIMARY KEY,
    ts          BIGINT NOT NULL,
    server_ts   BIGINT NOT NULL,
    day         DATE NOT NULL,
    event       TEXT NOT NULL,
    client_id   TEXT,
    session_id  TEXT,
    platform    TEXT,
    version     TEXT,
    props       JSONB
);
CREATE INDEX IF NOT EXISTS idx_events_day       ON {SCHEMA}.events(day);
CREATE INDEX IF NOT EXISTS idx_events_event     ON {SCHEMA}.events(event);
CREATE INDEX IF NOT EXISTS idx_events_client    ON {SCHEMA}.events(client_id);
CREATE INDEX IF NOT EXISTS idx_events_session   ON {SCHEMA}.events(session_id);
CREATE INDEX IF NOT EXISTS idx_events_day_event ON {SCHEMA}.events(day, event);
CREATE INDEX IF NOT EXISTS idx_events_props     ON {SCHEMA}.events USING GIN(props);

CREATE TABLE IF NOT EXISTS {SCHEMA}.node_events (
    id          BIGSERIAL PRIMARY KEY,
    ts          BIGINT NOT NULL,
    day         DATE NOT NULL,
    client_id   TEXT,
    platform    TEXT,
    version     TEXT,
    event       TEXT NOT NULL,
    fp          TEXT,
    type        TEXT,
    region      TEXT,
    delay_ms    INTEGER,
    ok          SMALLINT,
    reason      TEXT,
    group_name  TEXT
);
CREATE INDEX IF NOT EXISTS idx_node_events_fp_day ON {SCHEMA}.node_events(fp, day);
CREATE INDEX IF NOT EXISTS idx_node_events_day    ON {SCHEMA}.node_events(day);
CREATE INDEX IF NOT EXISTS idx_node_events_event  ON {SCHEMA}.node_events(event);

CREATE TABLE IF NOT EXISTS {SCHEMA}.node_identity (
    identity_id  BIGSERIAL PRIMARY KEY,
    current_fp   TEXT UNIQUE,
    label        TEXT,
    protocol     TEXT,
    region       TEXT,
    sid          TEXT,
    xb_server_id INTEGER,
    first_seen   BIGINT NOT NULL,
    last_seen    BIGINT NOT NULL,
    retired_at   BIGINT
);

CREATE TABLE IF NOT EXISTS {SCHEMA}.node_fp_history (
    fp          TEXT PRIMARY KEY,
    identity_id BIGINT NOT NULL REFERENCES {SCHEMA}.node_identity(identity_id),
    bound_at    BIGINT NOT NULL,
    retired_at  BIGINT
);

CREATE TABLE IF NOT EXISTS {SCHEMA}.feature_flags (
    key         TEXT PRIMARY KEY,
    value_json  TEXT NOT NULL,
    rollout_pct INTEGER DEFAULT 100,
    updated_at  BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS {SCHEMA}.nps_responses (
    id          BIGSERIAL PRIMARY KEY,
    ts          BIGINT NOT NULL,
    day         DATE NOT NULL,
    client_id   TEXT,
    platform    TEXT,
    version     TEXT,
    score       SMALLINT NOT NULL,
    comment     TEXT
);
CREATE INDEX IF NOT EXISTS idx_nps_day ON {SCHEMA}.nps_responses(day);
"""


_pool: Optional[psycopg2.pool.ThreadedConnectionPool] = None


def _get_pool() -> psycopg2.pool.ThreadedConnectionPool:
    global _pool
    if _pool is None:
        _pool = psycopg2.pool.ThreadedConnectionPool(
            minconn=1,
            maxconn=10,
            dsn=DSN,
        )
    return _pool


def _ensure_schema() -> None:
    conn = psycopg2.connect(DSN)
    try:
        conn.autocommit = True
        with conn.cursor() as cur:
            for stmt in _SCHEMA_SQL.strip().split(";\n"):
                stmt = stmt.strip()
                if stmt:
                    cur.execute(stmt)
    finally:
        conn.close()


try:
    _ensure_schema()
except Exception as e:  # pragma: no cover — startup-time, log and continue
    print(f"[telemetry] schema init failed: {e}")


@contextmanager
def db() -> Iterator[psycopg2.extensions.connection]:
    """Borrow a connection from the pool. Auto-commit on success, rollback on err."""
    pool = _get_pool()
    conn = pool.getconn()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        pool.putconn(conn)


def _dict_cursor(conn):
    return conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)


def _maybe_prune() -> None:
    if secrets.randbelow(1000) != 0:
        return
    cutoff = (datetime.now(timezone.utc) - timedelta(days=RETENTION_DAYS)).date()
    with db() as c, c.cursor() as cur:
        cur.execute(f"DELETE FROM {SCHEMA}.events WHERE day < %s", (cutoff,))
        cur.execute(f"DELETE FROM {SCHEMA}.node_events WHERE day < %s", (cutoff,))
        cur.execute(f"DELETE FROM {SCHEMA}.nps_responses WHERE day < %s", (cutoff,))


# ── Auth ────────────────────────────────────────────────────────────────


def require_dashboard_auth(
    credentials: HTTPBasicCredentials = Depends(security),
) -> str:
    if not DASHBOARD_USER or not DASHBOARD_PASSWORD:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Dashboard credentials not configured",
        )
    ok_u = secrets.compare_digest(credentials.username, DASHBOARD_USER)
    ok_p = secrets.compare_digest(credentials.password, DASHBOARD_PASSWORD)
    if not (ok_u and ok_p):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials.username


# ── Ingest ──────────────────────────────────────────────────────────────

_RESERVED_KEYS = {
    "event",
    "ts",
    "client_id",
    "session_id",
    "platform",
    "version",
    "seq",
}


def _is_simple_scalar(v) -> bool:
    return v is None or isinstance(v, (str, int, float, bool))


def _truncate_str(v: Optional[object], limit: int = MAX_PROP_VALUE_LEN) -> Optional[str]:
    if v is None:
        return None
    s = str(v)
    return s[:limit] if len(s) > limit else s


def _extract_node_rows(event_name: str, body: dict, day) -> list[tuple]:
    """Fan-out node_* events into flat node_events rows. Receives the RAW
    event dict so numeric/bool types are intact."""
    rows: list[tuple] = []
    ts_raw = body.get("ts")
    ts = int(ts_raw) if isinstance(ts_raw, (int, float)) else 0
    cid = _truncate_str(body.get("client_id"))
    platform = _truncate_str(body.get("platform"))
    version = _truncate_str(body.get("version"))

    def row(ev, fp, typ, region=None, delay_ms=None, ok=None, reason=None, group=None):
        return (
            ts, day, cid, platform, version, ev,
            _truncate_str(fp, 32),
            _truncate_str(typ, 24),
            _truncate_str(region, 16),
            int(delay_ms) if isinstance(delay_ms, (int, float)) else None,
            (1 if ok is True else (0 if ok is False else None)),
            _truncate_str(reason, 80),
            _truncate_str(group, 64),
        )

    if event_name == "node_inventory":
        nodes = body.get("nodes")
        if isinstance(nodes, list):
            for item in nodes[:MAX_INVENTORY_NODES]:
                if isinstance(item, dict):
                    rows.append(row(
                        "inventory_item",
                        item.get("fp"),
                        item.get("type"),
                        region=item.get("region"),
                    ))
    elif event_name == "node_urltest":
        rows.append(row(
            "urltest",
            body.get("fp"),
            body.get("type"),
            delay_ms=body.get("delay_ms"),
            ok=body.get("ok"),
        ))
    elif event_name == "node_connect":
        rows.append(row(
            "connect",
            body.get("fp"),
            body.get("type"),
            ok=body.get("ok"),
            reason=body.get("reason"),
            delay_ms=body.get("handshake_ms"),
        ))
    elif event_name == "node_select":
        rows.append(row(
            "select",
            body.get("fp"),
            body.get("type"),
            group=body.get("group"),
        ))
    return rows


@router.post("")
async def ingest(request: Request) -> JSONResponse:
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="invalid json")
    events = body.get("events")
    if not isinstance(events, list):
        raise HTTPException(status_code=400, detail="events[] required")
    events = events[:MAX_EVENTS_PER_REQUEST]

    server_ts = int(time.time() * 1000)
    today = datetime.now(timezone.utc).date()

    event_rows: list[tuple] = []
    node_rows: list[tuple] = []

    for e in events:
        if not isinstance(e, dict):
            continue
        name = (e.get("event") or "").strip()
        if not name or len(name) > MAX_EVENT_NAME_LEN:
            continue
        ts = e.get("ts")
        if not isinstance(ts, (int, float)):
            ts = server_ts

        # Props stay JSON — Postgres JSONB preserves types, unlike our
        # earlier stringify-everything sqlite path.
        props: dict = {}
        for k, v in e.items():
            if k in _RESERVED_KEYS:
                continue
            if _is_simple_scalar(v):
                # Clamp string length, keep numeric/bool/null as-is.
                props[k] = _truncate_str(v) if isinstance(v, str) else v
            elif isinstance(v, list):
                cleaned = []
                for item in v[:MAX_INVENTORY_NODES]:
                    if isinstance(item, dict):
                        inner = {}
                        for ik, iv in item.items():
                            if not isinstance(ik, str):
                                continue
                            if _is_simple_scalar(iv):
                                inner[ik] = _truncate_str(iv) if isinstance(iv, str) else iv
                        if inner:
                            cleaned.append(inner)
                if cleaned:
                    props[k] = cleaned

        event_rows.append((
            int(ts),
            server_ts,
            today,
            name,
            _truncate_str(e.get("client_id")),
            _truncate_str(e.get("session_id")),
            _truncate_str(e.get("platform")),
            _truncate_str(e.get("version")),
            json.dumps(props, ensure_ascii=False) if props else None,
        ))

        if name.startswith("node_"):
            node_rows.extend(_extract_node_rows(name, e, today))

    if not event_rows:
        return JSONResponse({"ok": True, "count": 0})

    with db() as c, c.cursor() as cur:
        psycopg2.extras.execute_values(
            cur,
            f"INSERT INTO {SCHEMA}.events(ts, server_ts, day, event, client_id, "
            f"session_id, platform, version, props) VALUES %s",
            event_rows,
        )
        if node_rows:
            psycopg2.extras.execute_values(
                cur,
                f"INSERT INTO {SCHEMA}.node_events(ts, day, client_id, platform, version, "
                f"event, fp, type, region, delay_ms, ok, reason, group_name) VALUES %s",
                node_rows,
            )
            # node_identity upsert — region/protocol only update when incoming
            # value is non-null (urltest/connect rows carry no region).
            for r in node_rows:
                fp, typ, region = r[6], r[7], r[8]
                if not fp:
                    continue
                cur.execute(
                    f"""
                    INSERT INTO {SCHEMA}.node_identity(current_fp, protocol, region,
                                                       first_seen, last_seen)
                    VALUES (%s, %s, %s, %s, %s)
                    ON CONFLICT (current_fp) DO UPDATE SET
                      last_seen = EXCLUDED.last_seen,
                      protocol  = COALESCE(EXCLUDED.protocol, {SCHEMA}.node_identity.protocol),
                      region    = COALESCE(EXCLUDED.region,   {SCHEMA}.node_identity.region)
                    """,
                    (fp, typ, region, server_ts, server_ts),
                )

    _maybe_prune()
    return JSONResponse({"ok": True, "count": len(event_rows)})


# ── Feature flags ───────────────────────────────────────────────────────


@router.get("/flags")
def get_flags(client_id: str = "", platform: str = "", version: str = ""):
    """Return the effective flags for [client_id]."""
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(f"SELECT key, value_json, rollout_pct FROM {SCHEMA}.feature_flags")
        rows = cur.fetchall()
    out: dict[str, object] = {}
    for r in rows:
        pct = int(r["rollout_pct"] or 0)
        bucket = _bucket(client_id, r["key"])
        if bucket < pct:
            try:
                out[r["key"]] = json.loads(r["value_json"])
            except Exception:
                out[r["key"]] = r["value_json"]
    return {"flags": out}


def _bucket(client_id: str, key: str) -> int:
    h = hashlib.sha1(f"{key}|{client_id}".encode("utf-8")).digest()
    return h[0] % 100


@router.get("/admin/flags")
def admin_list_flags(_user: str = Depends(require_dashboard_auth)):
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"SELECT key, value_json, rollout_pct, updated_at "
            f"FROM {SCHEMA}.feature_flags ORDER BY key"
        )
        return {"flags": cur.fetchall()}


@router.post("/admin/flags")
async def admin_set_flag(
    request: Request,
    _user: str = Depends(require_dashboard_auth),
):
    body = await request.json()
    key = (body.get("key") or "").strip()
    if not key or len(key) > 64:
        raise HTTPException(status_code=400, detail="key required (≤64 chars)")
    value = body.get("value")
    rollout_pct = int(body.get("rollout_pct", 100))
    rollout_pct = max(0, min(100, rollout_pct))
    with db() as c, c.cursor() as cur:
        cur.execute(
            f"""
            INSERT INTO {SCHEMA}.feature_flags(key, value_json, rollout_pct, updated_at)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (key) DO UPDATE SET
              value_json = EXCLUDED.value_json,
              rollout_pct = EXCLUDED.rollout_pct,
              updated_at = EXCLUDED.updated_at
            """,
            (key, json.dumps(value), rollout_pct, int(time.time())),
        )
    return {"ok": True, "key": key}


# ── NPS ─────────────────────────────────────────────────────────────────


@router.post("/nps")
async def nps_submit(request: Request) -> JSONResponse:
    body = await request.json()
    score = body.get("score")
    if not isinstance(score, (int, float)) or score < 0 or score > 10:
        raise HTTPException(status_code=400, detail="score must be 0-10")
    today = datetime.now(timezone.utc).date()
    with db() as c, c.cursor() as cur:
        cur.execute(
            f"""
            INSERT INTO {SCHEMA}.nps_responses(ts, day, client_id, platform, version,
                                               score, comment)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            """,
            (
                int(body.get("ts") or time.time() * 1000),
                today,
                _truncate_str(body.get("client_id")),
                _truncate_str(body.get("platform")),
                _truncate_str(body.get("version")),
                int(score),
                _truncate_str(body.get("comment"), 500),
            ),
        )
    return JSONResponse({"ok": True})


# ── Stats ───────────────────────────────────────────────────────────────


def _day_window(days: int):
    end = datetime.now(timezone.utc).date()
    start = end - timedelta(days=max(1, days) - 1)
    return start, end


@router.get("/stats/summary")
def stats_summary(days: int = 7, _user: str = Depends(require_dashboard_auth)):
    start, end = _day_window(days)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT event, COUNT(*)::int AS n FROM {SCHEMA}.events
                WHERE day BETWEEN %s AND %s
                GROUP BY event ORDER BY n DESC LIMIT 30""",
            (start, end),
        )
        top = cur.fetchall()
        cur.execute(
            f"SELECT COUNT(*)::int AS n FROM {SCHEMA}.events WHERE day BETWEEN %s AND %s",
            (start, end),
        )
        total = cur.fetchone()["n"]
        cur.execute(
            f"""SELECT COUNT(DISTINCT client_id)::int AS n FROM {SCHEMA}.events
                WHERE day BETWEEN %s AND %s AND client_id IS NOT NULL""",
            (start, end),
        )
        clients = cur.fetchone()["n"]
    return {
        "window_days": days,
        "total_events": total,
        "unique_clients": clients,
        "top_events": top,
    }


@router.get("/stats/dau")
def stats_dau(days: int = 30, _user: str = Depends(require_dashboard_auth)):
    start, end = _day_window(days)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT to_char(day, 'YYYY-MM-DD') AS day,
                       COUNT(DISTINCT client_id)::int AS dau
                FROM {SCHEMA}.events
                WHERE day BETWEEN %s AND %s AND client_id IS NOT NULL
                GROUP BY day ORDER BY day""",
            (start, end),
        )
        return {"series": cur.fetchall()}


@router.get("/stats/crash_free")
def stats_crash_free(days: int = 7, _user: str = Depends(require_dashboard_auth)):
    """1 - (sessions with ≥1 crash) / (total sessions). 2026 mobile baseline."""
    start, end = _day_window(days)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT COUNT(DISTINCT session_id)::int AS n
                FROM {SCHEMA}.events
                WHERE day BETWEEN %s AND %s AND session_id IS NOT NULL""",
            (start, end),
        )
        total = cur.fetchone()["n"]
        cur.execute(
            f"""SELECT COUNT(DISTINCT session_id)::int AS n
                FROM {SCHEMA}.events
                WHERE day BETWEEN %s AND %s AND session_id IS NOT NULL
                AND event='crash'""",
            (start, end),
        )
        crashed = cur.fetchone()["n"]
        cur.execute(
            f"""SELECT to_char(e.day, 'YYYY-MM-DD') AS day,
                       COUNT(DISTINCT e.session_id)::int AS sessions,
                       COUNT(DISTINCT CASE WHEN c.session_id IS NOT NULL
                                           THEN e.session_id END)::int AS crashed
                FROM {SCHEMA}.events e
                LEFT JOIN {SCHEMA}.events c
                  ON c.session_id = e.session_id AND c.event='crash'
                WHERE e.day BETWEEN %s AND %s AND e.session_id IS NOT NULL
                GROUP BY e.day ORDER BY e.day""",
            (start, end),
        )
        daily = cur.fetchall()
    return {
        "sessions": total,
        "crashed_sessions": crashed,
        "crash_free_rate": (1 - (crashed / total)) if total else None,
        "series": [
            {
                "day": r["day"],
                "sessions": r["sessions"],
                "crashed": r["crashed"],
                "rate": (1 - (r["crashed"] / r["sessions"])) if r["sessions"] else None,
            }
            for r in daily
        ],
    }


@router.get("/stats/startup_funnel")
def stats_startup_funnel(days: int = 7, _user: str = Depends(require_dashboard_auth)):
    start, end = _day_window(days)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT COUNT(*)::int AS n FROM {SCHEMA}.events
                WHERE event='startup_ok' AND day BETWEEN %s AND %s""",
            (start, end),
        )
        ok = cur.fetchone()["n"]
        cur.execute(
            f"""SELECT props->>'step' AS step,
                       props->>'code' AS code,
                       COUNT(*)::int AS n
                FROM {SCHEMA}.events
                WHERE event='startup_fail' AND day BETWEEN %s AND %s
                GROUP BY step, code ORDER BY n DESC""",
            (start, end),
        )
        fails = cur.fetchall()
    total = ok + sum(r["n"] for r in fails)
    return {
        "window_days": days,
        "total": total,
        "ok": ok,
        "failures": fails,
        "ok_rate": (ok / total) if total else None,
    }


@router.get("/stats/errors")
def stats_errors(days: int = 7, _user: str = Depends(require_dashboard_auth)):
    start, end = _day_window(days)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT props->>'type' AS type,
                       props->>'src' AS src,
                       COUNT(*)::int AS n
                FROM {SCHEMA}.events
                WHERE event='crash' AND day BETWEEN %s AND %s
                GROUP BY type, src ORDER BY n DESC LIMIT 30""",
            (start, end),
        )
        return {"top_errors": cur.fetchall()}


@router.get("/stats/versions")
def stats_versions(days: int = 7, _user: str = Depends(require_dashboard_auth)):
    start, end = _day_window(days)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT platform, version, COUNT(DISTINCT client_id)::int AS clients
                FROM {SCHEMA}.events
                WHERE day BETWEEN %s AND %s AND client_id IS NOT NULL
                GROUP BY platform, version ORDER BY platform, clients DESC""",
            (start, end),
        )
        return {"distribution": cur.fetchall()}


@router.get("/stats/nodes")
def stats_nodes(
    days: int = 7, limit: int = 50,
    _user: str = Depends(require_dashboard_auth),
):
    """Per-node health score from real-user telemetry. Region sourced from
    node_identity (only inventory rows carry it)."""
    start, end = _day_window(days)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT ne.fp AS fp,
                       COALESCE(ni.protocol, ne.type) AS type,
                       ni.region AS region,
                       COUNT(*)::int AS tests,
                       COALESCE(SUM(ne.ok), 0)::int AS ok_count,
                       COUNT(DISTINCT ne.client_id)::int AS users,
                       AVG(ne.delay_ms) AS avg_delay,
                       percentile_cont(0.95) WITHIN GROUP (ORDER BY ne.delay_ms) AS p95_delay
                FROM {SCHEMA}.node_events ne
                LEFT JOIN {SCHEMA}.node_identity ni ON ni.current_fp = ne.fp
                WHERE ne.event='urltest' AND ne.day BETWEEN %s AND %s
                  AND ne.fp IS NOT NULL
                GROUP BY ne.fp, COALESCE(ni.protocol, ne.type), ni.region""",
            (start, end),
        )
        urltest = cur.fetchall()
        cur.execute(
            f"""SELECT fp, COUNT(*)::int AS attempts, COALESCE(SUM(ok),0)::int AS ok_count
                FROM {SCHEMA}.node_events
                WHERE event='connect' AND day BETWEEN %s AND %s AND fp IS NOT NULL
                GROUP BY fp""",
            (start, end),
        )
        connect = cur.fetchall()
    cmap = {r["fp"]: (r["attempts"], r["ok_count"]) for r in connect}

    out = []
    for r in urltest:
        tests = r["tests"] or 0
        oks = r["ok_count"] or 0
        users = r["users"] or 0
        success = (oks / tests) if tests else 0
        avg_delay = r["avg_delay"] or 0
        p95_delay = r["p95_delay"] or 0
        latency = max(0, 1 - (p95_delay / 2000))
        c_attempts, c_oks = cmap.get(r["fp"], (0, 0))
        connect_rate = (c_oks / c_attempts) if c_attempts else 1.0
        score = 0.45 * success + 0.35 * latency + 0.20 * connect_rate
        insufficient = users < 5 or tests < 10
        out.append({
            "fp": r["fp"],
            "type": r["type"],
            "region": r["region"],
            "users": users,
            "tests": tests,
            "success_rate": round(success, 3),
            "avg_delay_ms": round(float(avg_delay), 0),
            "p95_delay_ms": round(float(p95_delay), 0),
            "connect_attempts": c_attempts,
            "connect_ok_rate": round(connect_rate, 3),
            "score": int(round(score * 100)),
            "insufficient_data": insufficient,
        })

    out.sort(key=lambda x: (x["insufficient_data"], -x["score"]))
    return {"window_days": days, "nodes": out[:limit]}


@router.get("/stats/nps")
def stats_nps(days: int = 30, _user: str = Depends(require_dashboard_auth)):
    start, end = _day_window(days)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT COUNT(*)::int AS total,
                       COALESCE(SUM(CASE WHEN score >= 9 THEN 1 ELSE 0 END),0)::int AS promoters,
                       COALESCE(SUM(CASE WHEN score <= 6 THEN 1 ELSE 0 END),0)::int AS detractors
                FROM {SCHEMA}.nps_responses WHERE day BETWEEN %s AND %s""",
            (start, end),
        )
        agg = cur.fetchone()
        cur.execute(
            f"""SELECT ts, score, comment, platform, version
                FROM {SCHEMA}.nps_responses
                WHERE day BETWEEN %s AND %s
                  AND comment IS NOT NULL AND comment <> ''
                ORDER BY ts DESC LIMIT 20""",
            (start, end),
        )
        comments = cur.fetchall()
    total = agg["total"] or 0
    if total:
        nps = ((agg["promoters"] / total) - (agg["detractors"] / total)) * 100
    else:
        nps = None
    return {
        "total_responses": total,
        "promoters": agg["promoters"] or 0,
        "detractors": agg["detractors"] or 0,
        "nps": round(nps, 1) if nps is not None else None,
        "recent_comments": comments,
    }


# ── HTML dashboard ──────────────────────────────────────────────────────


@router.get("/dashboard", response_class=HTMLResponse)
def dashboard(_user: str = Depends(require_dashboard_auth)) -> HTMLResponse:
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "dashboard.html")
    try:
        with open(path, "r", encoding="utf-8") as f:
            return HTMLResponse(f.read())
    except FileNotFoundError:
        return HTMLResponse(
            f"<h1>Dashboard HTML not deployed.</h1><p>Expected at: {path}</p>",
            status_code=500,
        )
