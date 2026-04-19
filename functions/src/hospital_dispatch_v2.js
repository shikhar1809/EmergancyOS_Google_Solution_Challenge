/* eslint-disable no-param-reassign */
/**
 * EmergencyOS — Hospital Dispatch Engine (v2)
 * ─────────────────────────────────────────────
 *
 * Production-grade escalation + matching engine. Replaces the single-hospital,
 * one-factor score used by the legacy `dispatchHospitalInHex` path.
 *
 * Design goals:
 *   1. Multi-factor matching (distance/ETA, specialty, beds, staffing, blood
 *      bank, current load, ambulance readiness, data freshness, reliability).
 *   2. Severity-aware parallel fan-out ("waves") with first-accept-wins.
 *   3. Deterministic escalation when the nearest hospital does not respond.
 *   4. Multi-channel notification: Firestore dashboard doc, per-hospital inbox,
 *      FCM push to on-duty staff, Twilio SMS fallback, ops alert trail.
 *   5. Load-aware across concurrent incidents (hospitals already handling
 *      several pending cases are deprioritised).
 *   6. Google Maps Routes API integration for real ETA when configured; safe
 *      haversine fallback otherwise (works in emulator / offline CI).
 *
 * Firestore schema (all writes are merge-safe, backward-compatible with v1):
 *   ops_incident_hospital_assignments/{incidentId}
 *     incidentId, zoneId, incidentHex:{q,r}
 *     severityTier           : "critical" | "high" | "standard"
 *     parallelPerWave        : number
 *     waveTimeoutMs          : number
 *     maxWaves               : number
 *     escalateAfterMs        : number  (duplicate for legacy UI)
 *     rankedCandidates[]     : [{ id, name, score, distKm, etaSec, rank,
 *                                 factors:{proximity,specialty,capacity,
 *                                          staffing,bloodBank,load,ambulance,
 *                                          freshness,reliability}, lat, lng,
 *                                 bedsAvailable, offeredServices[], ring }]
 *     orderedHospitalIds[]   : ids in priority order (kept for old UIs)
 *     candidateHospitalIds[] : truncated preview (kept for old UIs)
 *     waves[]                : [{ waveIndex, hospitalIds[], startedAt,
 *                                 timeoutAt, reason, outcome:
 *                                 "accepted"|"timeout"|"declined"|"superseded"
 *                                 |"pending" }]
 *     currentWaveIndex       : 0-based index of active wave
 *     currentWaveHospitalIds : array of hospital ids notified right now
 *     notifyIndex            : position in orderedHospitalIds of wave primary
 *     notifiedHospitalId     : primary hospital of current wave (legacy UI)
 *     notifiedHospitalName/Lat/Lng  (legacy UI)
 *     notifiedHospitalIds[]  : cumulative union of everyone ever notified
 *     notifiedAt             : wave start time
 *     dispatchStatus         : pending_acceptance | accepted | exhausted |
 *                              no_candidates | failed_to_assist
 *     acceptedHospitalId/Name/Lat/Lng/acceptedAt/acceptedByUid
 *     reason, lastEscalationReason
 *     requiredServices[]
 *     assignedAt, updatedAt
 *
 *   hospital_inbox/{hospitalId}/incidents/{incidentId}
 *     Per-hospital persistent inbox (lets each hospital dashboard stream its
 *     own queue without scanning the global ops collection).
 *
 *   ops_dashboard_alerts/{auto}
 *     Rolling alert trail for the ops admin console.
 *
 *   hospital_reliability/{hospitalId}                (optional, read-only here)
 *     acceptCount, declineCount, timeoutCount, rolling30dAcceptRate
 *
 * External dependencies kept to zero new npm packages; we reuse
 *   - firebase-admin (already installed)
 *   - global fetch (Node 18+/22 runtime)
 *   - twilio (already installed; optional)
 */

"use strict";

const admin = require("firebase-admin");

const db = admin.firestore();
const { FieldValue, Timestamp } = admin.firestore;

// ─────────────────────────────────────────────────────────────────────────────
// Tunable constants. These are deliberately exported so ops can override them
// via Firebase params without editing code.
// ─────────────────────────────────────────────────────────────────────────────

const EARTH_RADIUS_KM = 6371;
const DISPATCH_RADIUS_KM = 60;            // search radius for candidates
const MAX_CANDIDATES_IN_CHAIN = 24;       // cap persisted list size
const MAX_CANDIDATES_RANKED = 15;         // cap scored preview size
const URBAN_AVG_SPEED_KM_H = 30;          // fallback ETA speed

/** Severity config → fan-out parallelism + timeouts + SMS threshold. */
const SEVERITY_PROFILES = Object.freeze({
  critical: {
    parallelPerWave: 3,
    waveTimeoutMs: 45_000,
    maxWaves: 6,
    smsFallbackAfterMs: 30_000,
    strictServiceMatch: false,
  },
  high: {
    parallelPerWave: 2,
    waveTimeoutMs: 75_000,
    maxWaves: 5,
    smsFallbackAfterMs: 60_000,
    strictServiceMatch: false,
  },
  standard: {
    parallelPerWave: 1,
    waveTimeoutMs: 120_000,
    maxWaves: 4,
    smsFallbackAfterMs: 180_000,
    strictServiceMatch: true,
  },
});

/** Per-severity factor weights (should sum to ~1.0). */
const FACTOR_WEIGHTS = Object.freeze({
  critical: {
    proximity: 0.28, specialty: 0.22, capacity: 0.15, staffing: 0.10,
    bloodBank: 0.08, load: 0.07, ambulance: 0.05, freshness: 0.03,
    reliability: 0.02,
  },
  high: {
    proximity: 0.25, specialty: 0.20, capacity: 0.15, staffing: 0.10,
    bloodBank: 0.08, load: 0.08, ambulance: 0.07, freshness: 0.04,
    reliability: 0.03,
  },
  standard: {
    proximity: 0.22, specialty: 0.18, capacity: 0.18, staffing: 0.10,
    bloodBank: 0.07, load: 0.10, ambulance: 0.08, freshness: 0.04,
    reliability: 0.03,
  },
});

/** Keywords that escalate severity (checked against `type` + `dispatchHints`). */
const CRITICAL_KEYWORDS = [
  "cardiac arrest", "cardiac", "chest pain", "chest-pain", "stroke", "cva",
  "unresponsive", "unconscious", "no pulse", "not breathing", "apnea",
  "severe bleeding", "haemorrhage", "hemorrhage", "gunshot", "stab",
  "childbirth", "obstetric emergency", "anaphylaxis", "overdose",
  "triage_red", "red_zone", "mass casualty", "polytrauma",
];
const HIGH_KEYWORDS = [
  "accident", "crash", "rta", "collision", "vehicle", "road",
  "burn", "fire", "smoke inhalation", "fall from height", "fracture",
  "seizure", "convulsion", "pediatric", "allergic", "asthma attack",
  "heat stroke", "drowning", "electrocution", "triage_orange",
];

/** Emergency-type → preferred specialty keywords (for specialty factor). */
const SPECIALTY_MAP = Object.freeze([
  { match: /(accident|crash|rta|collision|road|vehicle|polytrauma|fall)/, tags: ["trauma", "orthopedic", "emergency"] },
  { match: /(burn|fire|smoke)/, tags: ["burn", "plastic", "emergency"] },
  { match: /(cardiac|chest|heart|arrest)/, tags: ["cardiac", "cardiology", "cath lab", "icu"] },
  { match: /(stroke|cva)/, tags: ["stroke", "neurology", "neuro"] },
  { match: /(childbirth|obstetric|labour|labor|pregnan)/, tags: ["obstetric", "maternity", "nicu"] },
  { match: /(pediatric|child|infant)/, tags: ["pediatric", "nicu"] },
  { match: /(poison|overdose|toxic)/, tags: ["toxicology", "emergency", "icu"] },
  { match: /(psychiatric|mental|suicide)/, tags: ["psychiatric", "mental health"] },
]);

// ─────────────────────────────────────────────────────────────────────────────
// Math helpers
// ─────────────────────────────────────────────────────────────────────────────

function degreesToRadians(d) { return d * (Math.PI / 180); }

function haversineKm(lat1, lng1, lat2, lng2) {
  const dLat = degreesToRadians(lat2 - lat1);
  const dLng = degreesToRadians(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(degreesToRadians(lat1)) * Math.cos(degreesToRadians(lat2))
    * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a));
}

function clamp01(v) {
  if (!Number.isFinite(v)) return 0;
  if (v < 0) return 0;
  if (v > 1) return 1;
  return v;
}

function boundingBox(lat, lng, radiusKm) {
  const latDelta = (radiusKm / EARTH_RADIUS_KM) * (180 / Math.PI);
  const cosLat = Math.max(0.0001, Math.cos(degreesToRadians(lat)));
  const lngDelta = (radiusKm / (EARTH_RADIUS_KM * cosLat)) * (180 / Math.PI);
  return { minLat: lat - latDelta, maxLat: lat + latDelta, minLng: lng - lngDelta, maxLng: lng + lngDelta };
}

// ─────────────────────────────────────────────────────────────────────────────
// Severity + services parsing
// ─────────────────────────────────────────────────────────────────────────────

function normalizeServiceList(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  const seen = new Set();
  for (const r of raw) {
    const k = String(r || "").trim().toLowerCase();
    if (!k || seen.has(k)) continue;
    seen.add(k);
    out.push(k);
  }
  return out;
}

function extractRequiredServices(incident) {
  const base = normalizeServiceList(incident.requiredServices);
  const dh = incident.dispatchHints && typeof incident.dispatchHints === "object" ? incident.dispatchHints : {};
  const hint = normalizeServiceList(dh.requiredServices);
  const seen = new Set();
  const out = [];
  for (const s of [...base, ...hint]) {
    if (seen.has(s)) continue;
    seen.add(s);
    out.push(s);
    if (out.length >= 12) break;
  }
  return out;
}

function classifySeverity(incident) {
  const type = String(incident.type || "").toLowerCase();
  const dh = incident.dispatchHints && typeof incident.dispatchHints === "object" ? incident.dispatchHints : {};
  const hintType = String(dh.emergencyType || "").toLowerCase();
  const triageColor = String(dh.triageColor || incident.triageColor || "").toLowerCase();
  const explicit = String(dh.severity || incident.severity || "").toLowerCase();

  if (explicit === "critical" || explicit === "high" || explicit === "standard") return explicit;

  if (triageColor === "red" || triageColor === "immediate") return "critical";
  if (triageColor === "orange" || triageColor === "urgent") return "high";

  const haystack = `${type} ${hintType}`;
  for (const kw of CRITICAL_KEYWORDS) if (haystack.includes(kw)) return "critical";
  for (const kw of HIGH_KEYWORDS) if (haystack.includes(kw)) return "high";

  // Vitals-driven (optional fields on dispatchHints)
  const spo2 = Number(dh.spo2);
  const hr = Number(dh.heartRate);
  const bp = Number(dh.systolicBp);
  if (Number.isFinite(spo2) && spo2 < 90) return "critical";
  if (Number.isFinite(hr) && (hr < 40 || hr > 150)) return "critical";
  if (Number.isFinite(bp) && (bp < 80 || bp > 200)) return "high";

  return "standard";
}

function emergencySpecialtyTags(type) {
  const t = String(type || "").toLowerCase();
  const set = new Set();
  for (const entry of SPECIALTY_MAP) {
    if (entry.match.test(t)) entry.tags.forEach((tag) => set.add(tag));
  }
  // Always include generic "emergency" as a mild preference.
  set.add("emergency");
  return set;
}

// ─────────────────────────────────────────────────────────────────────────────
// Google Routes API — optional real ETA
// Endpoint: https://routes.googleapis.com/directions/v2:computeRoutes
// Uses global fetch (Node 18+). Falls back silently on any error.
// ─────────────────────────────────────────────────────────────────────────────

function routesApiKey() {
  return String(process.env.GOOGLE_ROUTES_API_KEY
    || process.env.GOOGLE_MAPS_API_KEY
    || "").trim();
}

/**
 * Returns drive-time in seconds (rounded) + distance in km for origin→dest.
 * Returns `null` when API unavailable so callers can use haversine fallback.
 */
async function googleRouteEta(originLat, originLng, destLat, destLng) {
  const key = routesApiKey();
  if (!key) return null;
  if (typeof fetch !== "function") return null;

  const body = {
    origin: { location: { latLng: { latitude: originLat, longitude: originLng } } },
    destination: { location: { latLng: { latitude: destLat, longitude: destLng } } },
    travelMode: "DRIVE",
    routingPreference: "TRAFFIC_AWARE",
    extraComputations: [],
  };

  try {
    const controller = typeof AbortController === "function" ? new AbortController() : null;
    const timeout = controller ? setTimeout(() => controller.abort(), 2500) : null;
    const resp = await fetch("https://routes.googleapis.com/directions/v2:computeRoutes", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": key,
        "X-Goog-FieldMask": "routes.duration,routes.distanceMeters",
      },
      body: JSON.stringify(body),
      signal: controller ? controller.signal : undefined,
    });
    if (timeout) clearTimeout(timeout);
    if (!resp.ok) return null;
    const json = await resp.json();
    const r = Array.isArray(json.routes) && json.routes[0];
    if (!r) return null;
    const durStr = String(r.duration || "").replace("s", "");
    const durSec = Number(durStr);
    const distKm = Number(r.distanceMeters) / 1000;
    if (!Number.isFinite(durSec) || !Number.isFinite(distKm)) return null;
    return { durationSec: Math.round(durSec), distKm };
  } catch (e) {
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hospital registry fetch (bounding-box + in-memory haversine refinement).
// Keeps compat with legacy `ops_hospitals` schema (lat/lng/bedsAvailable/…).
// ─────────────────────────────────────────────────────────────────────────────

async function fetchCandidateHospitalRows(lat, lng) {
  const box = boundingBox(lat, lng, DISPATCH_RADIUS_KM);
  // Fetch a superset using Firestore lat range; refine in memory.
  // NOTE: Using limit(450) is consistent with legacy `dispatchHospitalInHex`.
  const snap = await db.collection("ops_hospitals")
    .where("lat", ">=", box.minLat)
    .where("lat", "<=", box.maxLat)
    .limit(450)
    .get();

  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    if (typeof d.lat !== "number" || typeof d.lng !== "number") continue;
    if (d.lng < box.minLng || d.lng > box.maxLng) continue;
    const distKm = haversineKm(lat, lng, d.lat, d.lng);
    if (distKm > DISPATCH_RADIUS_KM) continue;
    rows.push({ id: doc.id, data: d, distKm });
  }
  return rows;
}

/** Load map { hospitalId → activeCaseCount }. Uses the global assignments col. */
async function loadHospitalWorkloadMap(excludeIncidentId) {
  const snap = await db.collection("ops_incident_hospital_assignments")
    .where("dispatchStatus", "in", ["pending_acceptance", "accepted"])
    .limit(400)
    .get();
  const out = new Map();
  for (const doc of snap.docs) {
    if (doc.id === excludeIncidentId) continue;
    const d = doc.data() || {};
    const ids = new Set();
    if (d.acceptedHospitalId) ids.add(String(d.acceptedHospitalId));
    if (Array.isArray(d.currentWaveHospitalIds)) {
      for (const h of d.currentWaveHospitalIds) ids.add(String(h));
    } else if (d.notifiedHospitalId) {
      ids.add(String(d.notifiedHospitalId));
    }
    for (const id of ids) out.set(id, (out.get(id) || 0) + 1);
  }
  return out;
}

/** Count of fresh medical fleet units stationed at each hospital. */
async function loadAmbulanceReadinessMap(hospitalIds) {
  if (hospitalIds.length === 0) return new Map();
  const out = new Map();
  const chunks = [];
  for (let i = 0; i < hospitalIds.length; i += 10) chunks.push(hospitalIds.slice(i, i + 10));
  const nowMs = Date.now();
  const ttlMs = 90_000;
  for (const chunk of chunks) {
    const [a, b] = await Promise.all([
      db.collection("ops_fleet_units").where("stationedHospitalId", "in", chunk).where("available", "==", true).limit(100).get(),
      db.collection("ops_fleet_units").where("assignedHospitalId", "in", chunk).where("available", "==", true).limit(100).get(),
    ]);
    for (const snap of [a, b]) {
      for (const doc of snap.docs) {
        const u = doc.data() || {};
        const ts = u.updatedAt;
        if (!ts || typeof ts.toMillis !== "function") continue;
        if (nowMs - ts.toMillis() > ttlMs) continue;
        const vt = String(u.vehicleType || "").toLowerCase();
        if (vt !== "medical" && vt !== "ambulance") continue;
        const hid = String(u.stationedHospitalId || u.assignedHospitalId || "");
        if (!hid) continue;
        out.set(hid, (out.get(hid) || 0) + 1);
      }
    }
  }
  return out;
}

async function loadReliabilityMap(hospitalIds) {
  if (hospitalIds.length === 0) return new Map();
  const out = new Map();
  // Best-effort; don't fail scoring if collection absent.
  try {
    const chunks = [];
    for (let i = 0; i < hospitalIds.length; i += 10) chunks.push(hospitalIds.slice(i, i + 10));
    for (const chunk of chunks) {
      const snap = await db.collection("hospital_reliability")
        .where(admin.firestore.FieldPath.documentId(), "in", chunk)
        .get();
      for (const doc of snap.docs) {
        const d = doc.data() || {};
        const rate = Number(d.rolling30dAcceptRate);
        if (Number.isFinite(rate)) out.set(doc.id, Math.max(0, Math.min(1, rate)));
      }
    }
  } catch (_) {
    // collection may not exist yet — ignore.
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Multi-factor scoring
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Compute a 0..1 score per candidate, plus a factors breakdown that the UI
 * can show to the ops operator for transparency / debugging.
 */
function scoreCandidate({
  hospital,
  distKm,
  etaSec,
  requiredServices,
  emergencySpecialties,
  workload,
  ambulanceReady,
  reliability,
  severity,
}) {
  const weights = FACTOR_WEIGHTS[severity] || FACTOR_WEIGHTS.standard;
  const offered = Array.isArray(hospital.offeredServices)
    ? hospital.offeredServices.map((s) => String(s).toLowerCase())
    : [];
  const bedsAvail = Number.isFinite(hospital.bedsAvailable) ? hospital.bedsAvailable : 0;
  const bedsTotal = Number.isFinite(hospital.bedsTotal) ? hospital.bedsTotal : 0;
  const doctors = Number.isFinite(hospital.doctorsOnDuty) ? hospital.doctorsOnDuty : 0;
  const specialists = Number.isFinite(hospital.specialistsOnCall) ? hospital.specialistsOnCall : 0;
  const bloodUnits = Number.isFinite(hospital.bloodUnitsAvailable) ? hospital.bloodUnitsAvailable : 0;
  const hasBloodBank = hospital.hasBloodBank === true;

  // 1. Proximity: normalize on wave-time window. < 5min = 1.0, > 30min = 0.0
  const etaMin = etaSec != null ? etaSec / 60 : (distKm / URBAN_AVG_SPEED_KM_H) * 60;
  const proximity = clamp01(1 - Math.max(0, etaMin - 3) / 27);

  // 2. Specialty match: combination of (a) required-services coverage ratio
  //    and (b) specialty keyword match against emergency type.
  let specialty;
  if (requiredServices.length === 0) {
    // No hard requirement → partial credit if hospital offers *anything*
    // relevant to the emergency type.
    let rel = 0;
    for (const tag of emergencySpecialties) {
      if (offered.some((o) => o.includes(tag))) rel++;
    }
    const relMax = Math.max(1, emergencySpecialties.size);
    specialty = clamp01(0.5 + 0.5 * (rel / relMax));
  } else {
    let hits = 0;
    for (const rs of requiredServices) if (offered.some((o) => o.includes(rs))) hits++;
    const coverage = hits / requiredServices.length;
    // Bonus if hospital additionally advertises the emergency-type specialty.
    let bonus = 0;
    for (const tag of emergencySpecialties) {
      if (offered.some((o) => o.includes(tag))) { bonus += 0.05; if (bonus >= 0.15) break; }
    }
    specialty = clamp01(coverage * 0.85 + bonus);
  }

  // 3. Capacity: bedsAvailable on a diminishing-returns curve. 0 = 0; 1-2 = 0.4;
  //    3-5 = 0.7; 6-10 = 0.9; >=11 = 1.0. Penalty if occupancy > 95%.
  let capacity;
  if (bedsTotal === 0) {
    // Unknown total → trust bedsAvailable only.
    capacity = clamp01(bedsAvail / 6);
  } else if (bedsAvail <= 0) {
    capacity = 0;
  } else if (bedsAvail <= 2) capacity = 0.4;
  else if (bedsAvail <= 5) capacity = 0.7;
  else if (bedsAvail <= 10) capacity = 0.9;
  else capacity = 1.0;
  // Dampen capacity if the facility is operating near saturation.
  if (bedsTotal > 0) {
    const occupancy = 1 - bedsAvail / bedsTotal;
    if (occupancy >= 0.95) capacity *= 0.5;
    else if (occupancy >= 0.85) capacity *= 0.8;
  }

  // 4. Staffing: saturating linear. 0 = 0.2 (assume skeleton crew reachable).
  const staffPoints = doctors + specialists * 1.5;
  const staffing = clamp01(0.2 + staffPoints / 12);

  // 5. Blood bank — weighted higher for trauma/cardiac/obstetric.
  let bloodBank = hasBloodBank ? 0.6 : 0.2;
  if (bloodUnits >= 10) bloodBank = 1.0;
  else if (bloodUnits >= 4) bloodBank = 0.85;
  else if (bloodUnits >= 1) bloodBank = 0.7;

  // 6. Load distribution: 0 active = 1.0, 1 = 0.85, 2 = 0.65, 3 = 0.35, ≥4 = 0.0
  const load = workload <= 0 ? 1.0
    : workload === 1 ? 0.85
    : workload === 2 ? 0.65
    : workload === 3 ? 0.35
    : 0.0;

  // 7. Ambulance readiness: 0=0.2 (may still get mutual-aid unit), 1=0.7, ≥2=1.0
  const ambulance = ambulanceReady <= 0 ? 0.2
    : ambulanceReady === 1 ? 0.7
    : 1.0;

  // 8. Data freshness: <5min=1, <30m=0.8, <3h=0.5, <24h=0.2, else 0
  const updatedMs = hospital._updatedAtMs || 0;
  const ageMin = updatedMs > 0 ? (Date.now() - updatedMs) / 60000 : 999;
  const freshness = ageMin < 5 ? 1 : ageMin < 30 ? 0.8 : ageMin < 180 ? 0.5 : ageMin < 1440 ? 0.2 : 0;

  // 9. Reliability: unknown (no history) → 0.7 neutral optimism.
  const reliabilityScore = reliability != null ? reliability : 0.7;

  const factors = {
    proximity: Number(proximity.toFixed(3)),
    specialty: Number(specialty.toFixed(3)),
    capacity: Number(capacity.toFixed(3)),
    staffing: Number(staffing.toFixed(3)),
    bloodBank: Number(bloodBank.toFixed(3)),
    load: Number(load.toFixed(3)),
    ambulance: Number(ambulance.toFixed(3)),
    freshness: Number(freshness.toFixed(3)),
    reliability: Number(reliabilityScore.toFixed(3)),
  };

  const weighted = (proximity * weights.proximity)
    + (specialty * weights.specialty)
    + (capacity * weights.capacity)
    + (staffing * weights.staffing)
    + (bloodBank * weights.bloodBank)
    + (load * weights.load)
    + (ambulance * weights.ambulance)
    + (freshness * weights.freshness)
    + (reliabilityScore * weights.reliability);

  // Hard disqualifier: facility self-reported offline.
  if (hospital.mapListingOnline === false) {
    return { score: 0, factors, disqualified: "offline" };
  }
  // Hard disqualifier: zero capacity AND total > 0 (only if standard severity
  // with strict match; for critical we still consider and rely on relaxed fallback).
  if (severity === "standard" && bedsTotal > 0 && bedsAvail <= 0) {
    return { score: weighted * 0.2, factors, disqualified: "full" };
  }

  return { score: Math.round(weighted * 1000) / 1000, factors, disqualified: null };
}

// ─────────────────────────────────────────────────────────────────────────────
// Main entry: dispatchHospital (replaces legacy dispatchHospitalInHex)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @param {{incidentId: string, incident: any, hexFns?: { latLngToHex: Function, hexAxialDistance: Function, zoneCenter: {id:string,lat:number,lng:number} }, writeOpsAlert?: Function }} args
 */
async function dispatchHospital({ incidentId, incident, hexFns, writeOpsAlert }) {
  const lat = Number(incident.lat);
  const lng = Number(incident.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    console.warn(`[hospitalDispatchV2] ${incidentId}: invalid lat/lng`);
    return { status: "invalid_location" };
  }

  const severity = classifySeverity(incident);
  const profile = SEVERITY_PROFILES[severity];
  const requiredServices = extractRequiredServices(incident);
  const emergencyType = String(incident.type || (incident.dispatchHints || {}).emergencyType || "").toLowerCase();
  const specialtyTags = emergencySpecialtyTags(emergencyType);

  const zone = hexFns && hexFns.zoneCenter ? hexFns.zoneCenter : null;
  const incidentHex = hexFns && hexFns.latLngToHex ? hexFns.latLngToHex(lat, lng) : null;

  const rows = await fetchCandidateHospitalRows(lat, lng);
  if (rows.length === 0) {
    await persistNoCandidates({ incidentId, lat, lng, incidentHex, zone, severity, requiredServices, writeOpsAlert });
    return { status: "no_candidates" };
  }

  const hospitalIds = rows.map((r) => r.id);
  const [workloadMap, ambulanceMap, reliabilityMap] = await Promise.all([
    loadHospitalWorkloadMap(incidentId),
    loadAmbulanceReadinessMap(hospitalIds),
    loadReliabilityMap(hospitalIds),
  ]);

  // Optional: call Routes API only for the nearest top-K rows to control cost.
  const prelim = rows.map((r) => ({
    id: r.id,
    name: String(r.data.name || r.id),
    lat: r.data.lat,
    lng: r.data.lng,
    distKm: r.distKm,
    data: r.data,
  }));
  prelim.sort((a, b) => a.distKm - b.distKm);
  const routesBudget = Math.min(10, prelim.length);
  const etaResults = new Map();
  if (routesApiKey()) {
    await Promise.all(prelim.slice(0, routesBudget).map(async (p) => {
      const r = await googleRouteEta(lat, lng, p.lat, p.lng);
      if (r) etaResults.set(p.id, r.durationSec);
    }));
  }

  const scored = [];
  for (const p of prelim) {
    const h = p.data;
    const updatedMs = h.updatedAt && typeof h.updatedAt.toMillis === "function" ? h.updatedAt.toMillis() : 0;
    const enrich = Object.assign({}, h, { _updatedAtMs: updatedMs });
    const etaSec = etaResults.get(p.id) || null;
    const offered = Array.isArray(h.offeredServices) ? h.offeredServices.map((s) => String(s).toLowerCase()) : [];
    const { score, factors, disqualified } = scoreCandidate({
      hospital: enrich,
      distKm: p.distKm,
      etaSec,
      requiredServices,
      emergencySpecialties: specialtyTags,
      workload: workloadMap.get(p.id) || 0,
      ambulanceReady: ambulanceMap.get(p.id) || 0,
      reliability: reliabilityMap.get(p.id),
      severity,
    });
    let ring = 0;
    if (hexFns && hexFns.latLngToHex && hexFns.hexAxialDistance && incidentHex) {
      const hex = hexFns.latLngToHex(h.lat, h.lng);
      ring = hexFns.hexAxialDistance(incidentHex, hex);
    }
    scored.push({
      id: p.id,
      name: p.name,
      lat: p.lat,
      lng: p.lng,
      distKm: Number(p.distKm.toFixed(3)),
      etaSec,
      ring,
      score,
      factors,
      disqualified,
      bedsAvailable: Number.isFinite(h.bedsAvailable) ? h.bedsAvailable : 0,
      bedsTotal: Number.isFinite(h.bedsTotal) ? h.bedsTotal : 0,
      offeredServices: offered,
      workload: workloadMap.get(p.id) || 0,
      ambulanceReady: ambulanceMap.get(p.id) || 0,
      hasBloodBank: h.hasBloodBank === true,
      bloodUnitsAvailable: Number.isFinite(h.bloodUnitsAvailable) ? h.bloodUnitsAvailable : 0,
      doctorsOnDuty: Number.isFinite(h.doctorsOnDuty) ? h.doctorsOnDuty : 0,
      specialistsOnCall: Number.isFinite(h.specialistsOnCall) ? h.specialistsOnCall : 0,
    });
  }

  // Keep disqualified=offline out entirely; disqualified=full only if there are
  // enough alternatives — otherwise include at end with half-weight.
  const usable = scored.filter((c) => c.disqualified !== "offline" && c.score > 0);
  if (usable.length === 0) {
    await persistNoCandidates({ incidentId, lat, lng, incidentHex, zone, severity, requiredServices, writeOpsAlert });
    return { status: "no_candidates" };
  }
  usable.sort((a, b) => b.score - a.score);

  const orderedIds = usable.map((c) => c.id);
  const preview = usable.slice(0, MAX_CANDIDATES_RANKED).map((c, idx) => ({
    id: c.id,
    name: c.name,
    rank: idx + 1,
    score: c.score,
    distKm: c.distKm,
    etaSec: c.etaSec,
    ring: c.ring,
    bedsAvailable: c.bedsAvailable,
    bedsTotal: c.bedsTotal,
    offeredServices: c.offeredServices,
    hasBloodBank: c.hasBloodBank,
    bloodUnitsAvailable: c.bloodUnitsAvailable,
    doctorsOnDuty: c.doctorsOnDuty,
    specialistsOnCall: c.specialistsOnCall,
    workload: c.workload,
    ambulanceReady: c.ambulanceReady,
    disqualified: c.disqualified,
    factors: c.factors,
    lat: c.lat,
    lng: c.lng,
  }));

  // Fan-out first wave.
  const parallel = Math.min(profile.parallelPerWave, usable.length);
  const waveHospitalIds = usable.slice(0, parallel).map((c) => c.id);
  const primary = usable[0];
  const waveStart = Date.now();
  const timeoutAt = waveStart + profile.waveTimeoutMs;

  const now = FieldValue.serverTimestamp();
  const assignmentData = {
    incidentId,
    zoneId: zone ? zone.id : null,
    incidentLat: lat,
    incidentLng: lng,
    incidentHex,
    requiredServices,
    severityTier: severity,
    parallelPerWave: profile.parallelPerWave,
    waveTimeoutMs: profile.waveTimeoutMs,
    maxWaves: profile.maxWaves,
    escalateAfterMs: profile.waveTimeoutMs,
    smsFallbackAfterMs: profile.smsFallbackAfterMs,
    candidateHospitalIds: orderedIds.slice(0, MAX_CANDIDATES_IN_CHAIN),
    orderedHospitalIds: orderedIds,
    rankedCandidates: preview,
    currentWaveIndex: 0,
    currentWaveHospitalIds: waveHospitalIds,
    waves: [{
      waveIndex: 0,
      hospitalIds: waveHospitalIds,
      startedAt: Timestamp.fromMillis(waveStart),
      timeoutAt: Timestamp.fromMillis(timeoutAt),
      outcome: "pending",
      reason: "initial",
    }],
    notifyIndex: 0,
    notifiedHospitalId: primary.id,
    notifiedHospitalName: primary.name,
    notifiedHospitalLat: primary.lat,
    notifiedHospitalLng: primary.lng,
    notifiedHospitalIds: waveHospitalIds,
    notifiedAt: now,
    dispatchStatus: "pending_acceptance",
    assignedAt: now,
    updatedAt: now,
    reason: `wave_1_${severity}`,
    primaryHospitalId: null,
    primaryHospitalName: null,
    primaryDistanceKm: null,
    lastEscalationReason: null,
    engineVersion: 2,
  };

  await db.collection("ops_incident_hospital_assignments").doc(incidentId).set(assignmentData, { merge: true });

  await fanOutHospitalNotifications({
    incidentId,
    incident,
    severity,
    hospitalIds: waveHospitalIds,
    waveIndex: 0,
    rankedLookup: usable,
  });

  if (typeof writeOpsAlert === "function") {
    await writeOpsAlert({
      incidentId,
      kind: "hospital_dispatch_notify",
      title: `Hospital dispatch wave 1 (${severity})`,
      body: `Notified ${waveHospitalIds.length} hospital(s): ${waveHospitalIds.join(", ")}. Timeout ${Math.round(profile.waveTimeoutMs / 1000)}s.`,
      severity: severity === "critical" ? "critical" : "info",
      extra: { severityTier: severity, waveHospitalIds, requiredServices },
    });
  }

  return { status: "dispatched", severity, waveHospitalIds, orderedHospitalIds: orderedIds };
}

async function persistNoCandidates({ incidentId, lat, lng, incidentHex, zone, severity, requiredServices, writeOpsAlert }) {
  await db.collection("ops_incident_hospital_assignments").doc(incidentId).set({
    incidentId,
    zoneId: zone ? zone.id : null,
    incidentLat: lat,
    incidentLng: lng,
    incidentHex,
    requiredServices,
    severityTier: severity,
    candidateHospitalIds: [],
    orderedHospitalIds: [],
    rankedCandidates: [],
    waves: [],
    dispatchStatus: "no_candidates",
    assignedAt: FieldValue.serverTimestamp(),
    reason: "no_eligible_hospital",
    engineVersion: 2,
  }, { merge: true });
  if (typeof writeOpsAlert === "function") {
    await writeOpsAlert({
      incidentId,
      kind: "hospital_dispatch_failed",
      title: "No eligible hospital found",
      body: requiredServices.length
        ? `No hospital within ${DISPATCH_RADIUS_KM} km reports capacity + required services (${requiredServices.join(", ")}).`
        : `No hospital within ${DISPATCH_RADIUS_KM} km reports capacity.`,
      severity: "critical",
      extra: { requiredServices, incidentHex, severityTier: severity },
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification fan-out
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Performs three things for every hospital in the wave:
 *   (1) writes `hospital_inbox/{hid}/incidents/{incidentId}` for the hospital
 *       dashboard to stream;
 *   (2) pushes FCM to users with `staffHospitalId == hid` AND on-duty flag;
 *   (3) (optional — handled by a later timer) SMS via Twilio after threshold.
 */
async function fanOutHospitalNotifications({ incidentId, incident, severity, hospitalIds, waveIndex, rankedLookup }) {
  const batch = db.batch();
  const hospitalMetaById = new Map();
  for (const h of rankedLookup || []) hospitalMetaById.set(h.id, h);

  for (const hid of hospitalIds) {
    const meta = hospitalMetaById.get(hid) || {};
    const inboxRef = db.collection("hospital_inbox").doc(hid)
      .collection("incidents").doc(incidentId);
    batch.set(inboxRef, {
      incidentId,
      hospitalId: hid,
      severity,
      waveIndex,
      status: "pending_acceptance",
      notifiedAt: FieldValue.serverTimestamp(),
      distKm: meta.distKm || null,
      etaSec: meta.etaSec || null,
      score: meta.score || null,
      incidentType: String(incident.type || ""),
      requiredServices: extractRequiredServices(incident),
      lat: Number(incident.lat) || null,
      lng: Number(incident.lng) || null,
    }, { merge: true });
  }
  await batch.commit();

  // FCM push — batched multicast per hospital (parallel).
  await Promise.all(hospitalIds.map((hid) =>
    pushToHospitalStaff({ hospitalId: hid, incidentId, severity, incident })
      .catch((e) => console.error(`[hospitalDispatchV2] FCM push to ${hid}:`, e))
  ));
}

async function pushToHospitalStaff({ hospitalId, incidentId, severity, incident }) {
  // Grab staff users bound to this hospital.
  const [q1, q2] = await Promise.all([
    db.collection("users").where("staffHospitalId", "==", hospitalId).limit(50).get(),
    db.collection("users").where("boundHospitalDocId", "==", hospitalId).limit(50).get(),
  ]);
  const tokens = new Set();
  for (const snap of [q1, q2]) {
    for (const doc of snap.docs) {
      const u = doc.data() || {};
      if (!u.fcmToken) continue;
      // Accept on-duty OR explicit hospital-dashboard flag OR (no duty field set at all).
      const duty = String(u.dutyStatus || "").toLowerCase();
      if (duty === "off_duty" || duty === "offline") continue;
      tokens.add(String(u.fcmToken));
    }
  }
  if (tokens.size === 0) {
    console.warn(`[hospitalDispatchV2] no FCM tokens for hospital ${hospitalId}`);
    return { sent: 0 };
  }
  const fcm = admin.messaging();
  const tokenArr = Array.from(tokens).slice(0, 500);
  const data = {
    kind: "hospital_dispatch",
    incidentId: String(incidentId),
    hospitalId: String(hospitalId),
    severity,
    type: String(incident.type || ""),
    lat: String(incident.lat || ""),
    lng: String(incident.lng || ""),
  };
  try {
    const resp = await fcm.sendEachForMulticast({
      tokens: tokenArr,
      data,
      notification: {
        title: severity === "critical" ? "🚨 CRITICAL hospital dispatch" : "Hospital dispatch request",
        body: `Incident ${incidentId.slice(0, 8)} — accept or decline.`,
      },
      android: { priority: "high" },
      apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default" } } },
    });
    return { sent: resp.successCount, failed: resp.failureCount };
  } catch (e) {
    console.error(`[hospitalDispatchV2] multicast to ${hospitalId} failed:`, e);
    return { sent: 0, failed: tokenArr.length };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Escalation — next wave after timeout/decline
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Advances assignment to the next wave. Called from:
 *   - hospitalDispatchEscalation scheduler (on wave timeout)
 *   - declineHospitalDispatch callable (on explicit decline of all members)
 */
async function escalateAssignment(assignmentRef, beforeData, escalationReason, writeOpsAlert) {
  const incidentId = assignmentRef.id;
  const d = beforeData || {};
  const ordered = Array.isArray(d.orderedHospitalIds) ? d.orderedHospitalIds.map(String) : [];
  const alreadyNotified = new Set(
    (Array.isArray(d.notifiedHospitalIds) ? d.notifiedHospitalIds.map(String) : [])
  );
  const currentWave = (d.currentWaveIndex == null ? 0 : Number(d.currentWaveIndex));
  const severity = String(d.severityTier || "standard").toLowerCase();
  const profile = SEVERITY_PROFILES[severity] || SEVERITY_PROFILES.standard;

  // Mark the previous wave outcome.
  const waves = Array.isArray(d.waves) ? [...d.waves] : [];
  if (waves[currentWave]) {
    waves[currentWave] = Object.assign({}, waves[currentWave], {
      outcome: escalationReason === "declined" ? "declined" : "timeout",
      closedAt: FieldValue.serverTimestamp(),
    });
  }

  // Exhaustion check — either ran out of candidates OR hit max waves.
  const remaining = ordered.filter((id) => !alreadyNotified.has(id));
  const nextWaveIndex = currentWave + 1;
  if (remaining.length === 0 || nextWaveIndex >= profile.maxWaves) {
    waves.push({
      waveIndex: nextWaveIndex,
      hospitalIds: [],
      outcome: "exhausted",
      reason: escalationReason || "exhausted",
      startedAt: FieldValue.serverTimestamp(),
    });
    await assignmentRef.set({
      dispatchStatus: "exhausted",
      dispatchExhaustedAt: FieldValue.serverTimestamp(),
      lastEscalationReason: escalationReason || "exhausted",
      waves,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    if (typeof writeOpsAlert === "function") {
      await writeOpsAlert({
        incidentId,
        kind: "hospital_dispatch_exhausted",
        title: "No hospital accepted dispatch",
        body: `All eligible hospitals notified (${alreadyNotified.size}); none accepted in time. Reason: ${escalationReason || "exhausted"}.`,
        severity: "critical",
        extra: { severityTier: severity },
      });
    }
    return { status: "exhausted" };
  }

  const nextSize = Math.min(profile.parallelPerWave, remaining.length);
  const nextWaveHospitalIds = remaining.slice(0, nextSize);
  // Pull hospital metadata for the legacy `notifiedHospitalId` fields.
  const primaryId = nextWaveHospitalIds[0];
  let primaryName = primaryId;
  let primaryLat = null;
  let primaryLng = null;
  try {
    const hs = await db.collection("ops_hospitals").doc(primaryId).get();
    if (hs.exists) {
      const hd = hs.data() || {};
      primaryName = String(hd.name || primaryId);
      if (typeof hd.lat === "number") primaryLat = hd.lat;
      if (typeof hd.lng === "number") primaryLng = hd.lng;
    }
  } catch (_) {}

  const nextPatch = {
    currentWaveIndex: nextWaveIndex,
    currentWaveHospitalIds: nextWaveHospitalIds,
    notifyIndex: ordered.indexOf(primaryId),
    notifiedHospitalId: primaryId,
    notifiedHospitalName: primaryName,
    notifiedHospitalLat: primaryLat,
    notifiedHospitalLng: primaryLng,
    notifiedHospitalIds: FieldValue.arrayUnion(...nextWaveHospitalIds),
    notifiedAt: FieldValue.serverTimestamp(),
    dispatchStatus: "pending_acceptance",
    lastEscalationReason: escalationReason || "timeout",
    updatedAt: FieldValue.serverTimestamp(),
  };
  waves.push({
    waveIndex: nextWaveIndex,
    hospitalIds: nextWaveHospitalIds,
    startedAt: Timestamp.fromMillis(Date.now()),
    timeoutAt: Timestamp.fromMillis(Date.now() + profile.waveTimeoutMs),
    outcome: "pending",
    reason: escalationReason || "timeout",
  });
  nextPatch.waves = waves;

  await assignmentRef.set(nextPatch, { merge: true });

  // Re-fetch current doc to pass into the fan-out with rankedLookup.
  const after = (await assignmentRef.get()).data() || {};
  const rankedLookup = Array.isArray(after.rankedCandidates) ? after.rankedCandidates : [];

  // Fetch incident for the notification payload.
  let incident = {};
  try {
    const incSnap = await db.collection("sos_incidents").doc(incidentId).get();
    if (incSnap.exists) incident = incSnap.data() || {};
  } catch (_) {}

  await fanOutHospitalNotifications({
    incidentId,
    incident,
    severity,
    hospitalIds: nextWaveHospitalIds,
    waveIndex: nextWaveIndex,
    rankedLookup,
  });

  if (typeof writeOpsAlert === "function") {
    await writeOpsAlert({
      incidentId,
      kind: "hospital_dispatch_notify",
      title: `Hospital dispatch wave ${nextWaveIndex + 1} (${severity})`,
      body: `Escalated to ${nextWaveHospitalIds.length} more hospital(s): ${nextWaveHospitalIds.join(", ")}. Reason: ${escalationReason || "timeout"}.`,
      severity: "info",
      extra: { severityTier: severity, waveIndex: nextWaveIndex, nextWaveHospitalIds },
    });
  }

  return { status: "escalated", waveIndex: nextWaveIndex, hospitalIds: nextWaveHospitalIds };
}

// ─────────────────────────────────────────────────────────────────────────────
// Accept transaction — first-accept-wins across wave members
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Accepts the incident on behalf of `hospitalId`. Caller authorisation is the
 * responsibility of the HTTPS callable wrapper in `index.js`.
 *
 * Throws a plain Error with `.code` set to one of:
 *   not_found | already_accepted | not_member | wrong_status
 */
async function acceptAssignmentTx(incidentId, hospitalId, acceptorUid) {
  const ref = db.collection("ops_incident_hospital_assignments").doc(incidentId);
  const result = await db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (!snap.exists) {
      const e = new Error("Assignment not found."); e.code = "not_found"; throw e;
    }
    const d = snap.data() || {};
    const status = String(d.dispatchStatus || "");
    if (status === "accepted") {
      const e = new Error("Incident already accepted."); e.code = "already_accepted"; throw e;
    }
    if (status !== "pending_acceptance") {
      const e = new Error(`Dispatch not awaiting acceptance (status=${status}).`); e.code = "wrong_status"; throw e;
    }
    const waveMembers = Array.isArray(d.currentWaveHospitalIds)
      ? d.currentWaveHospitalIds.map(String)
      : [String(d.notifiedHospitalId || "")];
    if (!waveMembers.includes(hospitalId)) {
      const e = new Error("Hospital is not in the current notification wave."); e.code = "not_member"; throw e;
    }

    let hname = hospitalId;
    let hLat = null;
    let hLng = null;
    const hs = await t.get(db.collection("ops_hospitals").doc(hospitalId));
    if (hs.exists) {
      const hd = hs.data() || {};
      hname = String(hd.name || hospitalId);
      if (typeof hd.lat === "number") hLat = hd.lat;
      if (typeof hd.lng === "number") hLng = hd.lng;
    }

    const waves = Array.isArray(d.waves) ? [...d.waves] : [];
    const idx = waves.findIndex((w) => w && w.outcome === "pending");
    if (idx >= 0) {
      waves[idx] = Object.assign({}, waves[idx], {
        outcome: "accepted",
        acceptedHospitalId: hospitalId,
        closedAt: Timestamp.fromMillis(Date.now()),
      });
    }

    t.set(ref, {
      dispatchStatus: "accepted",
      acceptedHospitalId: hospitalId,
      acceptedHospitalName: hname,
      acceptedHospitalLat: hLat,
      acceptedHospitalLng: hLng,
      acceptedAt: FieldValue.serverTimestamp(),
      acceptedByUid: acceptorUid || null,
      primaryHospitalId: hospitalId,
      primaryHospitalName: hname,
      reason: "accepted",
      waves,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    return { hospitalId, name: hname, lat: hLat, lng: hLng, waveMembers };
  });

  // Outside the transaction: mark the other wave members' inbox rows as superseded.
  try {
    const others = result.waveMembers.filter((h) => h !== result.hospitalId);
    const batch = db.batch();
    for (const hid of others) {
      const ref2 = db.collection("hospital_inbox").doc(hid).collection("incidents").doc(incidentId);
      batch.set(ref2, {
        status: "superseded",
        supersededBy: result.hospitalId,
        supersededAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    const ref3 = db.collection("hospital_inbox").doc(result.hospitalId).collection("incidents").doc(incidentId);
    batch.set(ref3, {
      status: "accepted",
      acceptedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    await batch.commit();
  } catch (e) {
    console.warn(`[hospitalDispatchV2] inbox supersede cleanup: ${e.message || e}`);
  }

  return result;
}

/**
 * Record a decline from `hospitalId`. In parallel-wave dispatch a single
 * decline must NOT immediately escalate — we should wait for the remaining
 * wave members (or the timeout). Only when every member of the current wave
 * has declined do we advance to the next wave.
 *
 * Caller authorisation (verifying hospital staff binding) is enforced in the
 * callable wrapper in `index.js`.
 */
async function declineAssignmentMember(incidentId, hospitalId, reason, writeOpsAlert) {
  const ref = db.collection("ops_incident_hospital_assignments").doc(incidentId);
  const result = await db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (!snap.exists) { const e = new Error("Assignment not found."); e.code = "not_found"; throw e; }
    const d = snap.data() || {};
    const status = String(d.dispatchStatus || "");
    if (status === "accepted") { const e = new Error("Already accepted."); e.code = "already_accepted"; throw e; }
    if (status !== "pending_acceptance") { const e = new Error(`Wrong status: ${status}`); e.code = "wrong_status"; throw e; }

    const waveMembers = Array.isArray(d.currentWaveHospitalIds)
      ? d.currentWaveHospitalIds.map(String)
      : [String(d.notifiedHospitalId || "")];
    if (!waveMembers.includes(hospitalId)) {
      const e = new Error("Hospital is not in the current wave."); e.code = "not_member"; throw e;
    }

    const waves = Array.isArray(d.waves) ? [...d.waves] : [];
    const curIdx = waves.findIndex((w) => w && w.outcome === "pending");
    const declinedBy = curIdx >= 0 && Array.isArray(waves[curIdx].declinedBy)
      ? new Set(waves[curIdx].declinedBy.map(String))
      : new Set();
    declinedBy.add(hospitalId);

    const allDeclined = waveMembers.every((m) => declinedBy.has(m));
    if (curIdx >= 0) {
      waves[curIdx] = Object.assign({}, waves[curIdx], {
        declinedBy: Array.from(declinedBy),
      });
    }

    t.set(ref, { waves, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return { d, allDeclined };
  });

  // Mark the decliner's inbox row as `declined` so their UI clears.
  try {
    await db.collection("hospital_inbox").doc(hospitalId)
      .collection("incidents").doc(incidentId)
      .set({ status: "declined", declinedAt: FieldValue.serverTimestamp(), declineReason: reason || "declined" }, { merge: true });
  } catch (_) {}

  if (result.allDeclined) {
    return escalateAssignment(ref, result.d, reason || "all_declined", writeOpsAlert);
  }
  return { status: "partial_decline", hospitalId };
}

// ─────────────────────────────────────────────────────────────────────────────
// SMS fallback (optional — run from scheduler when wave has been pending
// longer than `smsFallbackAfterMs`)
// ─────────────────────────────────────────────────────────────────────────────

let twilioClient = null;
(function initTwilio() {
  const sid = process.env.TWILIO_ACCOUNT_SID;
  const tok = process.env.TWILIO_AUTH_TOKEN;
  if (sid && tok) {
    try { twilioClient = require("twilio")(sid, tok); } catch (_) { twilioClient = null; }
  }
})();

async function smsFallbackForWave(assignmentRef, d) {
  if (!twilioClient) return { sent: 0, reason: "no_twilio" };
  const from = (process.env.TWILIO_PHONE_NUMBER || "").trim();
  if (!from) return { sent: 0, reason: "no_from" };

  const sentFlag = d.smsFallbackSent === true;
  if (sentFlag) return { sent: 0, reason: "already_sent" };

  const hospitalIds = Array.isArray(d.currentWaveHospitalIds) ? d.currentWaveHospitalIds : [];
  if (hospitalIds.length === 0) return { sent: 0, reason: "no_targets" };

  const incidentId = assignmentRef.id;
  const severity = String(d.severityTier || "standard");
  let sent = 0;
  await Promise.all(hospitalIds.map(async (hid) => {
    try {
      const hs = await db.collection("ops_hospitals").doc(hid).get();
      if (!hs.exists) return;
      const hd = hs.data() || {};
      const phone = String(hd.contactPhone || hd.phone || "").trim();
      if (!phone) return;
      await twilioClient.messages.create({
        from,
        to: phone,
        body: `EmergencyOS ${severity.toUpperCase()} dispatch ${incidentId}. Please open the hospital console and accept or decline. This case will escalate in ${Math.round((d.waveTimeoutMs || 120_000) / 1000)}s.`,
      });
      sent += 1;
    } catch (e) {
      console.warn(`[hospitalDispatchV2] SMS to hospital ${hid} failed: ${e.message || e}`);
    }
  }));
  await assignmentRef.set({ smsFallbackSent: true, smsFallbackSentAt: FieldValue.serverTimestamp() }, { merge: true });
  return { sent };
}

// ─────────────────────────────────────────────────────────────────────────────
// Scheduler-friendly batch escalation. Called from `hospitalDispatchEscalation`
// cron in index.js every minute.
// ─────────────────────────────────────────────────────────────────────────────

async function runScheduledEscalation(writeOpsAlert) {
  const snap = await db.collection("ops_incident_hospital_assignments")
    .where("dispatchStatus", "==", "pending_acceptance")
    .limit(80)
    .get();
  if (snap.empty) return { processed: 0, escalated: 0 };

  const now = Date.now();
  let processed = 0;
  let escalated = 0;
  for (const doc of snap.docs) {
    processed += 1;
    const d = doc.data() || {};
    const waveMs = Number(d.waveTimeoutMs || d.escalateAfterMs || 120_000);
    const notifiedAt = d.notifiedAt;
    const notifiedMs = notifiedAt && typeof notifiedAt.toMillis === "function" ? notifiedAt.toMillis() : 0;
    if (!notifiedMs) continue;
    const elapsed = now - notifiedMs;

    // SMS fallback trigger — before full wave timeout.
    const smsThreshold = Number(d.smsFallbackAfterMs || 0);
    if (smsThreshold > 0 && elapsed >= smsThreshold && !d.smsFallbackSent) {
      try { await smsFallbackForWave(doc.ref, d); } catch (e) { console.error("[sms_fallback]", doc.id, e); }
    }

    if (elapsed >= waveMs) {
      try {
        await escalateAssignment(doc.ref, d, "timeout", writeOpsAlert);
        escalated += 1;
      } catch (e) {
        console.error(`[runScheduledEscalation] ${doc.id}:`, e);
      }
    }
  }
  return { processed, escalated };
}

// ─────────────────────────────────────────────────────────────────────────────
// Exports
// ─────────────────────────────────────────────────────────────────────────────

module.exports = {
  // Public engine entry points (all idempotent).
  dispatchHospital,
  escalateAssignment,
  acceptAssignmentTx,
  declineAssignmentMember,
  runScheduledEscalation,
  smsFallbackForWave,
  fanOutHospitalNotifications,
  pushToHospitalStaff,

  // Pure functions (exported for unit tests / client-side mirroring).
  classifySeverity,
  extractRequiredServices,
  emergencySpecialtyTags,
  scoreCandidate,
  haversineKm,
  clamp01,
  SEVERITY_PROFILES,
  FACTOR_WEIGHTS,
  DISPATCH_RADIUS_KM,
};
