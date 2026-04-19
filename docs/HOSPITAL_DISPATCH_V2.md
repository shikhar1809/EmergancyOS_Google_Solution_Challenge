# EmergencyOS — Hospital Dispatch & Escalation (v2)

> Authoritative engine: [`functions/src/hospital_dispatch_v2.js`](../functions/src/hospital_dispatch_v2.js)
> Client mirror (UI preview only): [`lib/services/hospital_match_service.dart`](../lib/services/hospital_match_service.dart)

This document describes how EmergencyOS picks a hospital for an incoming SOS,
how the nearest hospital is notified, what happens when it does not respond
in time, how multiple concurrent incidents are balanced across facilities,
and which factors drive the match.

The system ships as a drop-in replacement for the legacy single-hospital
`dispatchHospitalInHex` code path. The old Firestore schema continues to work
— every additive field is optional, every legacy field keeps its meaning.

---

## 1. Lifecycle overview

```
 victim creates sos_incidents/{id}
            │
            ▼
 onDocumentCreated  ──►  dispatchHospitalInHex()            (delegates to v2)
            │
            ▼
 ops_incident_hospital_assignments/{id}                     (created + wave 1)
            │
            ├──►  hospital_inbox/{hid}/incidents/{id}       (per-hospital push)
            ├──►  FCM multicast to on-duty staff            (Android + iOS)
            ├──►  ops_dashboard_alerts                      (audit trail)
            └──►  Twilio SMS fallback after `smsFallbackAfterMs`
                                                            (critical = 30s)
            │
            ▼
 hospital presses ACCEPT  ──►  acceptHospitalDispatch()
            │                       │
            ▼                       ▼
 assignment.dispatchStatus =   sos_incidents.{assignedHospitalId,...}
 "accepted"                    ambulance dispatch pipeline fires
            │
 hospital presses DECLINE     (or no response before wave timeout)
            │
            ▼
 declineAssignmentMember()    hospitalDispatchEscalation (cron, 1 min)
            │                       │
            └──────►  escalateAssignment()  ──►  next wave fans out
                             │
                             ▼
                   until max waves reached or
                   ordered chain exhausted
                             │
                             ▼
                 dispatchStatus = "exhausted"
                 ops_dashboard_alerts (critical)
```

---

## 2. Severity tiers

Severity is derived from `incident.type`, `incident.dispatchHints.emergencyType`,
`triageColor`, and optional vitals (`spo2`, `heartRate`, `systolicBp`). The
classifier is a mirror of `classifySeverity()` in the engine.

| Tier      | Examples                                         | Parallel/wave | Wave timeout | Max waves | SMS fallback |
|-----------|--------------------------------------------------|---------------|--------------|-----------|--------------|
| critical  | cardiac arrest, stroke, severe bleeding, triage_red | **3**         | **45 s**     | 6         | 30 s         |
| high      | accident, burn, seizure, pediatric, triage_orange | **2**         | **75 s**     | 5         | 60 s         |
| standard  | everything else                                  | **1**         | **120 s**    | 4         | 180 s        |

**Why parallel waves?** For a cardiac arrest the cost of a missed minute is
measured in lives. Rather than call one hospital and wait 120 s, the v2
engine notifies the top three candidates *simultaneously* and lets the first
one to accept win the case. The other two are auto-superseded in their
hospital inbox, so no one wastes time driving toward an ambiguous dispatch.

---

## 3. Matching factors

Each candidate hospital gets nine factor scores (each in `[0, 1]`), combined
with severity-specific weights.

| Factor       | Source fields                              | Notes                                                       |
|--------------|--------------------------------------------|-------------------------------------------------------------|
| proximity    | haversine + **Google Routes API**          | Real drive-time ETA when `GOOGLE_ROUTES_API_KEY` is set     |
| specialty    | `offeredServices`, `requiredServices`, type| Coverage ratio + keyword bonus (trauma, cardiac, burn…)     |
| capacity     | `bedsAvailable`, `bedsTotal`               | Diminishing returns; occupancy > 85 % applies a dampener    |
| staffing     | `doctorsOnDuty`, `specialistsOnCall`       | Specialists weighted 1.5×                                   |
| blood bank   | `hasBloodBank`, `bloodUnitsAvailable`      | Matters for trauma/cardiac/obstetric                        |
| load         | active assignments for this hospital       | Cross-incident distribution (see §5)                        |
| ambulance    | fresh `ops_fleet_units` at the hospital    | Stationed **or** assigned, `updatedAt` ≤ 90 s               |
| freshness    | `ops_hospitals.updatedAt` age              | Stale data (>30 min) loses confidence                       |
| reliability  | `hospital_reliability.rolling30dAcceptRate`| Defaults to 0.7 when no history exists                      |

Weights per severity (see `FACTOR_WEIGHTS` in the engine):

| Factor        | critical | high | standard |
|---------------|----------|------|----------|
| proximity     | 0.28     | 0.25 | 0.22     |
| specialty     | 0.22     | 0.20 | 0.18     |
| capacity      | 0.15     | 0.15 | 0.18     |
| staffing      | 0.10     | 0.10 | 0.10     |
| blood bank    | 0.08     | 0.08 | 0.07     |
| load          | 0.07     | 0.08 | 0.10     |
| ambulance     | 0.05     | 0.07 | 0.08     |
| freshness     | 0.03     | 0.04 | 0.04     |
| reliability   | 0.02     | 0.03 | 0.03     |

### Hard disqualifiers

- `mapListingOnline == false` → excluded entirely (hospital toggled offline).
- `bedsAvailable == 0` and `bedsTotal > 0` → excluded for `standard` severity.
  For `critical` / `high` the candidate is kept but given a 0.2× weight, so
  a full ER still beats *nothing* when every nearby facility is saturated.

---

## 4. Notification channels

Every hospital in the current wave is notified through **four independent
paths** so a downed device or app never silences a critical dispatch:

1. **Assignment doc** — `ops_incident_hospital_assignments/{id}` is merged
   with the new wave. The hospital dashboard already streams this doc.
2. **Per-hospital inbox** — `hospital_inbox/{hospitalId}/incidents/{id}` is
   written in the same batch. Lets the hospital UI keep a simple queue list
   without scanning the global ops collection.
3. **FCM push** — `sendEachForMulticast` to every `users/*.fcmToken` that has
   `staffHospitalId == hospitalId` (or `boundHospitalDocId`) AND whose
   `dutyStatus` is not `off_duty`/`offline`. Android uses `priority: "high"`;
   iOS uses `apns-priority: 10` so the notification bypasses Focus modes.
4. **SMS fallback** — after `smsFallbackAfterMs` elapsed without accept, the
   cron calls Twilio and sends `hospital.contactPhone` a short escalation
   text. Only fires once per wave (`smsFallbackSent` flag).

Ops admins additionally receive a row in `ops_dashboard_alerts` for auditing.

---

## 5. Cross-incident load balancing

Before ranking, the engine scans all `ops_incident_hospital_assignments`
docs whose `dispatchStatus` is `pending_acceptance` or `accepted`, and
counts how many each hospital is currently on the hook for. That count is
fed into the `load` factor:

| Active assignments | Score |
|--------------------|-------|
| 0                  | 1.00  |
| 1                  | 0.85  |
| 2                  | 0.65  |
| 3                  | 0.35  |
| 4+                 | 0.00  |

A hospital with 3+ live cases effectively drops to the bottom of the
ranking. Combined with the 60 km search radius and 3-way parallel fan-out,
this is enough to spread demand without ever refusing the closest facility
a hard request.

---

## 6. Accept & decline semantics (race-safe)

Both callables run inside a Firestore transaction:

- **`acceptHospitalDispatch`** requires the caller to be staff at the
  hospital (`users/{uid}.staffHospitalId`) AND the hospital must be one of
  `currentWaveHospitalIds`. First accept wins: the transaction flips
  `dispatchStatus` to `accepted`, records the accepting hospital, and the
  post-commit cleanup marks every other wave member's inbox row as
  `superseded` so their UI clears.

- **`declineHospitalDispatch`** records the decline against the caller's
  hospital and updates `waves[current].declinedBy[]`. The wave escalates
  *only* when every member has declined (or the timer fires). This matches
  real-world triage practice: hospital A saying "no" should not force the
  wave to move forward if hospital B is still reviewing.

---

## 7. Google APIs in use

- **Cloud Firestore** — source of truth for all dispatch state.
- **Firebase Cloud Messaging** — multicast push to hospital staff + fleet.
- **Firebase Cloud Functions v2** — `us-east1` for hospital callables,
  `us-central1` for the dispatch pipeline.
- **Google Maps Routes API** — optional, traffic-aware ETA scoring. The call
  is server-side with `X-Goog-FieldMask: routes.duration,routes.distanceMeters`
  and a 2.5 s abort timeout. Budget is limited to the top-10 nearest hospitals
  per dispatch to keep cost low.
- **Geofire / bounding-box** — candidate pre-filter (`lat` range on Firestore
  + haversine refinement in memory, 60 km radius, max 450 rows per query).
- **Twilio** (optional) — SMS fallback channel; skipped cleanly when creds
  are absent.

---

## 8. Backward compatibility

The v2 engine continues to populate every field the legacy schema exposed:

- `orderedHospitalIds` — full ranked chain (engine's `usable.map(id)`).
- `candidateHospitalIds` — truncated preview (20 max).
- `notifiedHospitalId` / `notifiedHospitalName` / …Lat / …Lng — **primary** of
  the current wave (highest-ranked hospital of the wave).
- `notifyIndex` — position of that primary in `orderedHospitalIds`.
- `notifiedHospitalIds[]` — cumulative union of everyone ever notified.
- `escalateAfterMs` — duplicate of `waveTimeoutMs` for old UIs.
- `tier1EndIndex` / `tier2EndIndex` — no longer written (they tracked hex
  rings which the v2 engine replaces with a continuous score). Existing docs
  keep their legacy values; the hex ring number is still available on each
  ranked candidate's `ring` field.

Net effect: the current Flutter hospital console and fleet dashboards keep
working with zero code changes, while ops operators who *opt in* can surface
the new `severityTier`, `rankedCandidates[]`, `waves[]`, and the per-factor
breakdown to build richer UI (factor bar chart, wave timeline, etc.).

---

## 9. Environment setup

```bash
# Required for Google Routes API (recommended, not mandatory):
firebase functions:secrets:set GOOGLE_ROUTES_API_KEY

# Required for SMS fallback (optional):
firebase functions:secrets:set TWILIO_ACCOUNT_SID
firebase functions:secrets:set TWILIO_AUTH_TOKEN
# + plain env var:
#   TWILIO_PHONE_NUMBER=+15551234567
```

Or populate `functions/.env` for local emulator runs (see `.env.example`).

---

## 10. Testing checklist

1. **Happy path (standard severity):** create a `Trauma` incident → nearest
   online hospital gets notified → accept → `sos_incidents` picks up
   `assignedHospitalId` → ambulance dispatch pipeline fires.
2. **Parallel fan-out (critical severity):** create a `Cardiac Arrest`
   incident → three hospitals in `currentWaveHospitalIds` simultaneously →
   hospital #2 accepts → hospitals #1 and #3 see `superseded` in their
   inbox within 2 s.
3. **Escalation (nearest offline):** mark the top hospital
   `mapListingOnline = false` → it is dropped from the ranked list.
4. **Escalation (nearest doesn't respond):** simulate no response → after
   the wave timeout the next wave fans out → eventually exhaustion fires a
   critical `ops_dashboard_alerts` row.
5. **Load balancing:** create three concurrent critical incidents → verify
   each gets different primary hospitals (score's `load` factor should push
   later incidents toward under-utilized facilities).
