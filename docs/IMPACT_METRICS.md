# Impact Metrics — EmergencyOS

This file documents **what we measure, why, and where it comes from** so a
reviewer can audit the numbers quoted in the pitch against live Firebase
telemetry without asking us for a database dump.

All metrics are computed server-side in
`functions/src/impact/compute_impact_metrics.ts` (scheduled every 15 min) and
cached in the `impact_dashboard_public/{city}` Firestore doc. Clients read
that pre-computed doc — they never crunch raw incidents — so values are
idempotent and tamper-proof for the in-app `/impact` dashboard.

---

## 1 · North-star metrics

| # | Metric | Formula | What a good number looks like |
|---|---|---|---|
| N1 | **Median SOS completion time** | `median(tsSosCompleted − tsSosStarted)` | ≤ 20 s |
| N2 | **Median time-to-first-guidance** | `median(tsLifelineFirstCardShown − tsSosStarted)` | ≤ 45 s |
| N3 | **Median volunteer-accept latency** | `median(tsFirstAccept − tsDispatched)` — geo-multicast radius only | ≤ 120 s |
| N4 | **Hospital-ready ratio** | `count(incidentsWithHospitalAssignedBeforeArrival) / count(totalDispatched)` | ≥ 80 % |
| N5 | **Offline-mode success rate** | `count(sosPathsCompletedWhileOffline) / count(sosPathsStartedWhileOffline)` | ≥ 90 % |

## 2 · Supporting metrics

| # | Metric | Formula |
|---|---|---|
| S1 | Accept-within-5-min coverage | `count(acceptsBefore300s) / count(dispatched)` |
| S2 | On-scene-volunteer ratio | `count(incidentsWithVolunteerOnScene) / count(totalDispatched)` |
| S3 | False-alarm rate | `count(statusCancelled)+count(archivedReasonFalseAlarm) / count(sosCreated)` |
| S4 | SMS-fallback usage | `count(incidentsCreatedViaGeoSms) / count(sosCreated)` |
| S5 | Languages active this week | `distinct(userLocale)` where `lastActive > now − 7d` |
| S6 | Peak concurrent volunteers | `max(watchActiveVolunteerCount)` over 30-day window |
| S7 | Gemini-brief adoption | `count(opsReadGeminiHospitalBrief) / count(dispatchedIncidents)` |

## 3 · Reliability / SLO metrics

| # | Metric | Formula | SLO |
|---|---|---|---|
| R1 | Dispatch CF p95 latency | percentile-95(`cf.dispatchIncidentInjection.duration`) | ≤ 2.5 s |
| R2 | FCM delivery success | `count(fcmDelivered) / count(fcmAttempted)` | ≥ 99 % |
| R3 | LIFELINE Gemini availability | `count(geminiOkResponses) / count(geminiRequests)` | ≥ 99 % (offline fallback absorbs failures) |
| R4 | Rules-denied read rate | Firestore `security_rules.deny_count` per 10k reads | ≤ 5 |

## 4 · Live values (snapshot — 18 Apr 2026, pilot-only)

> Snapshot is from the small-N Lucknow pilot (see `PILOT_STUDY.md`). Replace
> once Phase-2 hospital study telemetry lands.

| Metric | Target | Observed |
|---|---|---|
| N1 — SOS completion time | ≤ 20 s | **15.0 s** |
| N2 — Time-to-first-guidance | ≤ 45 s | **27 s** |
| N3 — Accept latency | ≤ 120 s | **96 s** |
| N4 — Hospital-ready ratio | ≥ 80 % | 81 % |
| N5 — Offline success | ≥ 90 % | 100 % (n = 6) |
| S3 — False alarm | ≤ 5 % | 0 / 64 |
| S4 — SMS fallback usage | — | 2 / 64 |
| S5 — Languages active | — | 4 of 12 |
| R2 — FCM delivery | ≥ 99 % | 99.6 % |
| R3 — Gemini availability | ≥ 99 % | 99.4 % |

## 5 · Event taxonomy (what the app emits)

The client writes to `analytics_events/{eventId}` with this schema:

```json
{
  "name": "sos_started | sos_completed | lifeline_card_shown | volunteer_accepted | hospital_assigned | gemini_brief_viewed | sms_fallback_used | offline_path_completed",
  "ts": "Timestamp",
  "incidentId": "string?",
  "userId": "string?",
  "role": "victim | volunteer | hospital | ems | ops",
  "city": "string",
  "locale": "string",
  "pilotCohort": "string?"
}
```

CFs aggregate by day / city / cohort and never read personally-identifiable
location data out of incidents — aggregation uses H3 hex-bucketing at
resolution 7 (~5 km²) so a single victim's coordinates can't be recovered
from the impact view.

## 6 · How to reproduce the numbers

```bash
# From functions/
npm run impact:recompute -- --cohort=lko-apr26
# Writes impact_dashboard_public/lko-apr26
# View in the in-app /impact dashboard
```

*Last updated 18 Apr 2026.*
