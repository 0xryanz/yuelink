# YueLink Telemetry — Integration Roadmap

This file documents how the telemetry stream feeds downstream decision making
across the YueLink ecosystem. The ingest + dashboard pieces are already
shipped (`telemetry.py`, `dashboard.html`). The bridges below consume that
same SQLite, either directly (read-only) or via scheduled sync into
PostgreSQL-backed tools.

## Architecture

```
    YueLink clients (opt-in)
          │
          ▼  POST /api/client/telemetry
    checkin-api :8011   (one process)
          │
          ▼  SQLite: /var/lib/yuelink-telemetry/events.db
          │
          ├─── GET /api/client/telemetry/stats/*   (dashboard, BasicAuth)
          │
          ├─── GET /api/client/telemetry/flags     (clients)
          │
          ├─── POST /api/client/telemetry/nps      (clients)
          │
          ▼
    Bridges (separate processes, all read-only on telemetry SQLite):
      1. yueops Quality bridge   → PG node_user_metrics
      2. XBoard YueNodeHealth    → subscription generation filter
      3. Telegram ops bot        → daily digest
```

## Phase 1 — YueOps Quality integration

**Goal**: Let the ops dashboard see client-reported node health alongside
server-reported agent metrics. Finds "online server, unusable client"
nodes that are the single biggest user-pain source.

**Implementation** (target: `/opt/yueops/web/`):

1. New PG table `node_user_metrics_5m` (day-bucketed aggregation):
   ```sql
   CREATE TABLE node_user_metrics_5m (
     fp            VARCHAR(16) NOT NULL,
     bucket_start  TIMESTAMPTZ NOT NULL,
     tests         INT NOT NULL DEFAULT 0,
     tests_ok      INT NOT NULL DEFAULT 0,
     connects      INT NOT NULL DEFAULT 0,
     connects_ok   INT NOT NULL DEFAULT 0,
     users         INT NOT NULL DEFAULT 0,
     p50_delay_ms  INT,
     p95_delay_ms  INT,
     PRIMARY KEY (fp, bucket_start)
   );
   CREATE INDEX idx_num5m_bucket ON node_user_metrics_5m(bucket_start);
   ```

2. Scheduled job `/opt/yueops/scripts/telemetry_bridge.py` (every 5 min
   via systemd timer):
   ```python
   # Pseudocode
   sqlite_rows = read_sqlite_since(last_bucket)
   aggregated = aggregate_by_fp(sqlite_rows)
   pg.upsert_on_conflict(node_user_metrics_5m, aggregated)
   ```

3. New REST endpoint `GET /api/quality/nodes/user-metrics` in
   `/opt/yueops/web/api/quality.py`:
   ```python
   @router.get("/nodes/user-metrics")
   def nodes_user_metrics(hours: int = 24, db: Session = Depends(get_db)):
       since = datetime.utcnow() - timedelta(hours=hours)
       rows = db.execute(text("""
         SELECT nm.fp, nm.users, nm.tests_ok::float / NULLIF(nm.tests,0) AS ok_rate,
                nm.p95_delay_ms, ni.label, ni.sid
         FROM node_user_metrics_5m nm
         LEFT JOIN xboard_node_fp_map ni ON ni.fp = nm.fp
         WHERE nm.bucket_start >= :since
         GROUP BY nm.fp, ni.label, ni.sid
       """), {"since": since}).fetchall()
       return {"nodes": [dict(r) for r in rows]}
   ```

4. Frontend Quality page new tab ("真实用户视角"):
   - Each node: fp, mapped label if any, score, users, p95 delay, 7d trend
   - Red-flag badge for nodes where agent says ONLINE but users report
     <50% success

**FP → node label mapping**: new PG table `xboard_node_fp_map(fp, v2_server_id, label)`. Populate via a one-time script that parses the canonical subscription YAML with the same fp algorithm as the client (`lib/shared/node_telemetry.dart`).

## Phase 2 — XBoard YueNodeHealth plugin

**Goal**: Automatically down-rank or quarantine nodes that real users can't
use, so new users get a working subscription on first install.

**Implementation** (target: `/home/xboard/yue-to/plugins/YueNodeHealth/`):

1. New plugin directory with `Plugin.php` + config:
   ```php
   // Plugin.php — hooks into subscription generation
   class Plugin extends AbstractPlugin {
       public function boot() {
           Hook::listen('server.list.generated', [$this, 'filterAndReorder']);
       }
       public function filterAndReorder(array $servers, $user): array {
           $scores = $this->fetchScoresFromYueOps();  // internal HTTP
           $quarantined = [];
           foreach ($servers as $i => $s) {
               $fp = $this->computeFingerprint($s);
               $score = $scores[$fp]['score'] ?? null;
               if ($score !== null && $score < 40 && $scores[$fp]['streak_days'] >= 3) {
                   $quarantined[] = $i;
               }
               $servers[$i]['_health_score'] = $score;
           }
           usort($servers, fn($a, $b) => ($b['_health_score'] ?? 50) - ($a['_health_score'] ?? 50));
           foreach ($quarantined as $i) unset($servers[$i]);
           return $servers;
       }
   }
   ```

2. Hysteresis state machine to prevent reverse-flip-flop:
   - Enter `quarantined` when `score < 40` for **3 consecutive days**
   - Exit `quarantined` when `score > 60` for **2 consecutive days**
   - Tracked in `yueops.node_quarantine_state(fp, state, since, last_check)`

3. Settings in panel admin UI:
   - `health_score_threshold` (default 40)
   - `quarantine_enter_days` (default 3)
   - `quarantine_exit_score` (default 60)
   - `quarantine_exit_days` (default 2)

**Why a plugin not a patch**: upstream XBoard updates won't trample our logic. Same pattern as existing `YueOnlineCount`.

## Phase 3 — Telegram ops bot daily digest

**Goal**: Ops sees trends without opening the dashboard.

Add to `/opt/telegram-bot/yue/main.py`:

```python
@scheduler.scheduled_job('cron', hour=9, minute=0, timezone='Asia/Shanghai')
async def morning_digest():
    stats = httpx.get(
        "https://yue.yuebao.website/api/client/telemetry/stats/summary?days=1",
        auth=(TEL_USER, TEL_PASS)
    ).json()
    crash_free = httpx.get(
        "https://yue.yuebao.website/api/client/telemetry/stats/crash_free?days=1",
        auth=(TEL_USER, TEL_PASS)
    ).json()
    nodes = httpx.get(
        "https://yue.yuebao.website/api/client/telemetry/stats/nodes?days=1",
        auth=(TEL_USER, TEL_PASS)
    ).json()
    bottom = [n for n in nodes['nodes'] if not n['insufficient_data']][-5:]
    msg = (
        f"📊 YueLink 昨日\n"
        f"DAU: {stats['unique_clients']}\n"
        f"Events: {stats['total_events']}\n"
        f"Crash-free: {crash_free['crash_free_rate']*100:.2f}%\n\n"
        f"⚠️ 表现最差 5 节点：\n"
    )
    for n in bottom:
        msg += f"  {n['region']} {n['type']} · score {n['score']} · {n['users']} users\n"
    await bot.send_message(OPS_GROUP_ID, msg)
```

## Phase 4 — Cross-service user journey (future)

Once `client_id` is correlated with `user_id` (only after login, via the
existing Auth token), the Telegram bot / checkin API / XBoard panel can
emit events to the same telemetry endpoint with `client_id`, yielding
single-user lifetime view:

```
session_start → login_success → subscription_sync → connect_ok → checkin_ok → ...
```

**NOT** done today. Requires:
1. Post-login call from client: `Telemetry.setUserHint(hashed_email)` — **the hash only**, never the email itself.
2. Server services emit with the same hash.
3. Opt-in checkbox on the auth page.

## Deploy checklist

- [ ] `scp server/telemetry/telemetry.py root@23.80.91.14:/opt/checkin-api/`
- [ ] `scp server/telemetry/dashboard.html root@23.80.91.14:/opt/checkin-api/`
- [ ] Add to `/opt/checkin-api/main.py`:
      ```python
      from telemetry import router as telemetry_router
      app.include_router(telemetry_router)
      ```
- [ ] Create SQLite dir: `mkdir -p /var/lib/yuelink-telemetry && chown checkin-api:checkin-api /var/lib/yuelink-telemetry`
- [ ] Set env vars in `systemctl edit --full checkin-api`:
      ```
      Environment=TELEMETRY_DASHBOARD_USER=yuelink
      Environment=TELEMETRY_DASHBOARD_PASSWORD=<openssl rand -hex 16>
      ```
- [ ] `systemctl restart checkin-api`
- [ ] Visit `https://yue.yuebao.website/api/client/telemetry/dashboard`
      to verify. Tabs: Overview / Nodes / NPS / Feature Flags.
- [ ] Seed default flags via Flags tab:
      ```
      smart_node_recommend  → false, 0%
      scene_presets         → true,  10%   (gradual rollout)
      health_card           → true,  100%
      onboarding_split      → false, 0%
      auto_fallback         → false, 0%
      nps_enabled           → true,  100%
      ```

After deploy, v1.0.16 client will start populating:
- `node_inventory` (once per subscription sync)
- `node_urltest` (every URL test)
- `node_connect` (every real connection)
- `nps_shown` / `nps_submit` / `nps_dismiss`
- flag evaluation events
