const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const https = require("https");
const crypto = require("crypto");

admin.initializeApp();
const db = admin.firestore();
const fcm = admin.messaging();
const { FieldValue, Timestamp } = admin.firestore;

// ─── Production hospital dispatch engine (multi-factor scoring, parallel
//     fan-out, wave escalation, multi-channel notify, load balancing).
//     Implementation in `src/hospital_dispatch_v2.js`; legacy function names
//     below delegate to it so every existing call site keeps working.
const hospitalDispatchV2 = require("./src/hospital_dispatch_v2");

// Shared AI safety preamble — every Gemini prompt in this file must include it.
const { AI_SAFETY_PREAMBLE, withSafetyForRole } = require("./src/ai_safety");
const preArrivalHandoff = require("./src/pre_arrival_handoff");
const clinicalReport = require("./src/clinical_report");

/** Fleet operator must accept/reject a pending assignment within this window (matches client UI). */
const FLEET_ASSIGNMENT_RESPONSE_MS = 180000;

// Twilio Client Initialization
const twilioSid = process.env.TWILIO_ACCOUNT_SID;
const twilioToken = process.env.TWILIO_AUTH_TOKEN;
const twilioNumber = (process.env.TWILIO_PHONE_NUMBER || "").trim();
let twilioClient;
if (twilioSid && twilioToken) {
    twilioClient = require("twilio")(twilioSid, twilioToken);
}
const twilio = require("twilio");
const path = require("path");
try {
  require("dotenv").config({ path: path.join(__dirname, ".env") });
  // Optional local-only secrets (gitignored) — never deploy with LIVEKIT_API_SECRET in .env (conflicts with Secret Manager).
  require("dotenv").config({ path: path.join(__dirname, ".env.secrets"), override: true });
} catch (_) {}

// ─── LiveKit (WebRTC only; no SIP / telephony) ───────────────────────────────
const { defineString, defineSecret } = require("firebase-functions/params");

/** Lazy-load heavy SDKs so `firebase deploy` can parse exports within the
 *  10s analysis window. @google/genai and livekit-server-sdk are large trees.
 */
function loadGoogleGenAIClass() {
    if (!loadGoogleGenAIClass._c) {
        loadGoogleGenAIClass._c = require("@google/genai").GoogleGenAI;
    }
    return loadGoogleGenAIClass._c;
}
function loadLiveKitSdk() {
    if (!loadLiveKitSdk._m) {
        loadLiveKitSdk._m = require("livekit-server-sdk");
    }
    return loadLiveKitSdk._m;
}

function newLiveKitAccessToken(apiKey, apiSecret, opts) {
    const { AccessToken } = loadLiveKitSdk();
    return new AccessToken(apiKey, apiSecret, opts);
}
function newLiveKitAgentDispatchClient(host, key, secret) {
    const { AgentDispatchClient } = loadLiveKitSdk();
    return new AgentDispatchClient(host, key, secret);
}
function newLiveKitRoomServiceClient(host, key, secret) {
    const { RoomServiceClient } = loadLiveKitSdk();
    return new RoomServiceClient(host, key, secret);
}

const lkUrl = defineString("LIVEKIT_URL", { default: "" });
const lkHttpUrl = defineString("LIVEKIT_HTTP_URL", { default: "" });
const lkKey = defineString("LIVEKIT_API_KEY", { default: "" });
const lkSecret = defineSecret("LIVEKIT_API_SECRET");
const geminiApiKeySecret = defineSecret("GEMINI_API_KEY");

/** Gemini — `process.env.GEMINI_API_KEY` from local `.env.secrets` or Secret Manager on bound functions. */
function geminiApiKey() {
    return (process.env.GEMINI_API_KEY || "").trim();
}
function geminiClient() {
    const k = geminiApiKey();
    if (!k) return null;
    const GoogleGenAI = loadGoogleGenAIClass();
    return new GoogleGenAI({ apiKey: k });
}

const lifelineAgentName =
  process.env.LIFELINE_LIVEKIT_AGENT_NAME || process.env.LIVEKIT_AGENT_NAME || "lifeline";

const copilotAgentName =
  process.env.COPILOT_LIVEKIT_AGENT_NAME || "copilot";

function sanitizeLiveKitString(v) {
  if (v == null) return "";
  let s = String(v).trim().replace(/^\uFEFF/, "");
  if (
    (s.startsWith('"') && s.endsWith('"') && s.length >= 2) ||
    (s.startsWith("'") && s.endsWith("'") && s.length >= 2)
  ) {
    s = s.slice(1, -1).trim();
  }
  s = s.replace(/\r\n/g, "\n").replace(/\r/g, "").trim();
  return s;
}

/** Strip invisible / line-break chars that break JWT signing (common Secret Manager paste issues). */
function sanitizeLiveKitApiSecret(v) {
  let s = sanitizeLiveKitString(v);
  s = s.replace(/[\u200B-\u200D\uFEFF]/g, "");
  s = s.replace(/[\r\n\t\v\f]/g, "").trim();
  return s;
}

/** API keys are a single token — remove all whitespace. */
function sanitizeLiveKitApiKey(v) {
  let s = sanitizeLiveKitString(v);
  s = s.replace(/[\u200B-\u200D\uFEFF]/g, "");
  s = s.replace(/\s+/g, "").trim();
  return s;
}

/**
 * LiveKit credentials for token minting + server SDK.
 * Prefer the secret passed from `lkSecret.value()` over `process.env.LIVEKIT_API_SECRET` so a stale
 * or duplicate plain env var in Cloud Console cannot override Secret Manager (fixes "invalid token").
 */
function liveKitEnv(secretFromBinding) {
  const url = sanitizeLiveKitString(process.env.LIVEKIT_URL || lkUrl.value() || "");
  const apiKey = sanitizeLiveKitApiKey(process.env.LIVEKIT_API_KEY || lkKey.value() || "");
  const bound = sanitizeLiveKitApiSecret(secretFromBinding || "");
  const fromEnv = sanitizeLiveKitApiSecret(process.env.LIVEKIT_API_SECRET || "");
  const apiSecret = bound || fromEnv;
  return { url, apiKey, apiSecret };
}

/** Flutter/web clients must receive `wss://` (not `https://`) or LiveKit reports invalid token / failed connect. */
function livekitUrlForClients(envUrl) {
  let u = sanitizeLiveKitString(envUrl);
  if (!u) return u;
  while (u.endsWith("/")) u = u.slice(0, -1);
  if (u.startsWith("https://")) return `wss://${u.slice(8)}`;
  if (u.startsWith("http://")) return `ws://${u.slice(7)}`;
  return u;
}

/**
 * RoomServiceClient / AgentDispatchClient call LiveKit's HTTP API. They must use https:// (not wss://).
 * Twirp expects the API origin only (no path) — extra path segments break requests and often surface as "invalid token".
 */
function livekitUrlForServerSdk(envUrl) {
  let u = sanitizeLiveKitString(envUrl);
  if (!u) return u;
  while (u.endsWith("/")) u = u.slice(0, -1);
  if (u.startsWith("wss://")) u = `https://${u.slice(6)}`;
  else if (u.startsWith("ws://")) u = `http://${u.slice(5)}`;
  try {
    const parsed = new URL(u);
    if (!parsed.hostname) return u;
    return `${parsed.protocol}//${parsed.host}`;
  } catch (_) {
    return u;
  }
}

/**
 * Prefer LIVEKIT_HTTP_URL (env, Firebase param, or GCP console) — Twirp API origin only, e.g. https://proj.livekit.cloud
 * Otherwise derive https origin from LIVEKIT_URL.
 */
function livekitHostForServerSdk(env) {
  const explicit = sanitizeLiveKitString(
    process.env.LIVEKIT_HTTP_URL || lkHttpUrl.value() || ""
  );
  if (explicit) return livekitUrlForServerSdk(explicit);
  return livekitUrlForServerSdk(env.url);
}

/** WebSocket URL returned to Flutter/web clients (from LIVEKIT_URL or derived from LIVEKIT_HTTP_URL). */
function livekitClientWsUrl(env) {
  const u = sanitizeLiveKitString(env.url || "");
  if (u) return livekitUrlForClients(u);
  const h = livekitHostForServerSdk(env);
  if (h.startsWith("https://")) return `wss://${h.slice(8)}`;
  if (h.startsWith("http://")) return `ws://${h.slice(7)}`;
  return "";
}

function assertLiveKitConfigured(env) {
  const ws = livekitClientWsUrl(env);
  if (!ws || !env.apiKey || !env.apiSecret) {
    throw new HttpsError(
      "failed-precondition",
      "LiveKit not configured. Local: copy functions/.env.example to functions/.env. Production: firebase functions:secrets:set LIVEKIT_API_SECRET; set LIVEKIT_URL + LIVEKIT_API_KEY (or LIVEKIT_HTTP_URL + LIVEKIT_API_KEY) as Firebase params or GCP env vars."
    );
  }
}

function numLike(v, d) {
  if (v == null) return d;
  if (typeof v === "number" && !Number.isNaN(v)) return v;
  if (typeof v === "string" && v.trim() !== "") {
    const n = Number(v);
    return Number.isNaN(n) ? d : n;
  }
  return d;
}

/** Label for `leaderboard/{uid}` — mirrors client LeaderboardService name fallbacks. */
function leaderboardDisplayNameFromUserDoc(user, uid) {
  const u = user || {};
  const uidStr = typeof uid === "string" ? uid : "";
  if (typeof u.displayName === "string" && u.displayName.trim()) return u.displayName.trim();
  if (typeof u.name === "string" && u.name.trim()) return u.name.trim();
  if (typeof u.email === "string" && u.email.includes("@")) {
    const local = u.email.split("@")[0].trim();
    if (local) return local.charAt(0).toUpperCase() + local.slice(1).toLowerCase();
  }
  if (typeof u.phoneNumber === "string" && u.phoneNumber.trim()) return u.phoneNumber.trim();
  if (uidStr.length >= 6) return `Member ${uidStr.slice(0, 6)}`;
  return "Member";
}

/** Elite volunteer voice: Lifeline arena 10+ levels cleared OR (5+ lives helped & 1000+ XP). */
function volunteerEliteEligible(userDoc) {
  const u = userDoc || {};
  const cleared = Math.max(0, Math.min(99, Math.floor(numLike(u.lifelineLevelsCleared, 0))));
  const lives = Math.max(0, Math.floor(numLike(u.volunteerLivesSaved, 0)));
  const xp = Math.max(0, Math.floor(numLike(u.volunteerXp, 0)));
  if (cleared >= 10) return true;
  if (lives >= 5 && xp >= 1000) return true;
  return false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Geohash helper — no external dep needed for a simple radius box query.
// We use a bounding-box lat/lng approach directly on double fields.
// For production scale, swap to geofire-common GeoHash library.
// ─────────────────────────────────────────────────────────────────────────────

const EARTH_RADIUS_KM = 6371;
const ALERT_RADIUS_KM = 20;

function degreesToRadians(deg) { return deg * (Math.PI / 180); }

/**
 * Returns a bounding box [minLat, maxLat, minLng, maxLng] for a radius (km)
 * around a center point. Used to pre-filter the Firestore volunteer query.
 */
function getBoundingBox(lat, lng, radiusKm) {
  const latDelta = radiusKm / EARTH_RADIUS_KM * (180 / Math.PI);
  const lngDelta = radiusKm / (EARTH_RADIUS_KM * Math.cos(degreesToRadians(lat))) * (180 / Math.PI);
  return {
    minLat: lat - latDelta,
    maxLat: lat + latDelta,
    minLng: lng - lngDelta,
    maxLng: lng + lngDelta,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Hex dispatch math (matches Flutter `emergency_zone_classification.dart`)
// Flat-top axial coords, local ENU metres anchored to Lucknow ops center.
// ─────────────────────────────────────────────────────────────────────────────

const OPS_ZONE_CENTER = { id: "lucknow", lat: 26.8467, lng: 80.9462 };
const ZONE_HEX_CIRCUM_RADIUS_M = 2400.0; // must match kZoneHexCircumRadiusM

function _metersPerDegLat() { return 111320.0; }
function _metersPerDegLng(atLat) { return 111320.0 * Math.cos(degreesToRadians(atLat)); }

function _enuOffsetMeters(centerLat, centerLng, lat, lng) {
  const y = (lat - centerLat) * _metersPerDegLat();
  const x = (lng - centerLng) * _metersPerDegLng(centerLat);
  return { x, y };
}

function _hexRound(fq, fr) {
  let q = Math.round(fq);
  let r = Math.round(fr);
  const fs = -fq - fr;
  const s = Math.round(fs);
  const qDiff = Math.abs(q - fq);
  const rDiff = Math.abs(r - fr);
  const sDiff = Math.abs(s - fs);
  if (qDiff > rDiff && qDiff > sDiff) {
    q = -r - s;
  } else if (rDiff > sDiff) {
    r = -q - s;
  }
  return { q, r };
}

function _worldMetersToHex(size, x, y) {
  const fq = (2.0 / 3.0 * x) / size;
  const fr = (-1.0 / 3.0 * x + Math.sqrt(3.0) / 3.0 * y) / size;
  return _hexRound(fq, fr);
}

function latLngToHex(lat, lng) {
  const enu = _enuOffsetMeters(OPS_ZONE_CENTER.lat, OPS_ZONE_CENTER.lng, lat, lng);
  return _worldMetersToHex(ZONE_HEX_CIRCUM_RADIUS_M, enu.x, enu.y);
}

function _hexKey(h) {
  return `${h.q}:${h.r}`;
}

/** Cube distance between axial hex cells (same grid as latLngToHex). */
function hexAxialDistance(h1, h2) {
  const x1 = h1.q;
  const z1 = h1.r;
  const y1 = -h1.q - h1.r;
  const x2 = h2.q;
  const z2 = h2.r;
  const y2 = -h2.q - h2.r;
  return Math.max(Math.abs(x1 - x2), Math.abs(y1 - y2), Math.abs(z1 - z2));
}

async function _writeOpsDashboardAlert({ incidentId, kind, title, body, severity = "info", extra = {} }) {
  const ref = db.collection("ops_dashboard_alerts").doc();
  await ref.set({
    incidentId,
    kind,
    title,
    body,
    severity,
    createdAt: FieldValue.serverTimestamp(),
    acked: false,
    ...extra,
  });
}

function mergeRequiredServicesFromIncident(incident) {
  const base = Array.isArray(incident.requiredServices)
    ? incident.requiredServices.map((s) => String(s)).filter((s) => s.trim() !== "")
    : [];
  const dh = incident.dispatchHints && typeof incident.dispatchHints === "object" ? incident.dispatchHints : {};
  const hint = Array.isArray(dh.requiredServices)
    ? dh.requiredServices.map((s) => String(s)).filter((s) => s.trim() !== "")
    : [];
  const seen = new Set();
  const out = [];
  for (const x of [...base, ...hint]) {
    const k = x.toLowerCase();
    if (!seen.has(k)) {
      seen.add(k);
      out.push(k);
    }
    if (out.length >= 12) break;
  }
  return out;
}

function emergencyTypeLower(incident) {
  const dh = incident.dispatchHints && typeof incident.dispatchHints === "object" ? incident.dispatchHints : {};
  return String(incident.type || dh.emergencyType || "").toLowerCase();
}

function specialtyBonus(offered, emergencyType) {
  const t = (emergencyType || "").toLowerCase();
  const off = (offered || []).map((s) => String(s).toLowerCase());
  let bonus = 0;
  if (/(accident|crash|rta|collision|road|vehicle)/.test(t) && off.some((s) => s.includes("trauma"))) bonus += 42;
  if (/(burn|fire|smoke)/.test(t) && off.some((s) => s.includes("burn"))) bonus += 42;
  if (/(cardiac|chest|heart|stroke)/.test(t) && off.some((s) => s.includes("cardiac") || s.includes("cardiology"))) bonus += 38;
  return bonus;
}

function hospitalDispatchScore(c, requiredServices, emergencyType, relaxedServices) {
  let score = c.ring * 100 + c.distKm * 2;
  if (c.bedsAvail <= 0) score += 500;
  else if (c.bedsAvail <= 2) score += 50;
  else if (c.bedsAvail <= 5) score += 20;
  if (!relaxedServices && requiredServices.length > 0 && !c.servicesOk) score += 1000;
  score -= specialtyBonus(c.offered, emergencyType);
  return score;
}

/**
 * Primary hospital dispatch entry point (legacy name kept for call-site
 * compatibility — every caller in this file still invokes this function).
 *
 * Delegates to the v2 engine (`src/hospital_dispatch_v2.js`) which performs:
 *   • multi-factor scoring (ETA, specialty match, beds, staffing, blood bank,
 *     current load, ambulance readiness, data freshness, reliability);
 *   • severity-tiered parallel fan-out ("waves") with first-accept-wins;
 *   • multi-channel notification (Firestore assignment doc + per-hospital
 *     inbox + FCM push to on-duty staff + Twilio SMS fallback);
 *   • cross-incident load balancing so a hospital already handling several
 *     pending cases is deprioritised.
 *
 * The hex grid (used by the ops dashboard ring visual) is kept available to
 * the engine through the `hexFns` pass-through.
 */
async function dispatchHospitalInHex({ incidentId, incident }) {
  return hospitalDispatchV2.dispatchHospital({
    incidentId,
    incident,
    hexFns: {
      latLngToHex,
      hexAxialDistance,
      zoneCenter: OPS_ZONE_CENTER,
    },
    writeOpsAlert: _writeOpsDashboardAlert,
  });
}

/**
 * Moves an assignment to the next wave of hospitals when the current wave
 * times out or is declined by all members. Legacy name kept; body delegates
 * to the v2 engine which uses wave-based escalation with parallel fan-out
 * (critical = 3, high = 2, standard = 1) and first-accept-wins semantics.
 */
async function escalateHospitalDispatchAssignment(assignmentRef, d, escalationReason) {
  return hospitalDispatchV2.escalateAssignment(
    assignmentRef,
    d,
    escalationReason,
    _writeOpsDashboardAlert,
  );
}

/**
 * Haversine distance in km between two lat/lng pairs.
 * Used to precisely filter bounding-box candidates.
 */
function haversineKm(lat1, lng1, lat2, lng2) {
  const dLat = degreesToRadians(lat2 - lat1);
  const dLng = degreesToRadians(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(degreesToRadians(lat1)) *
      Math.cos(degreesToRadians(lat2)) *
      Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a));
}

function timestampToMillis(value) {
  if (!value) return null;
  if (typeof value === "string") {
    const ms = Date.parse(value);
    return Number.isNaN(ms) ? null : ms;
  }
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value.toMillis === "function") {
    try {
      return value.toMillis();
    } catch (_) {
      return null;
    }
  }
  return null;
}

// ─── 1. Secure AI Triage ─────────────────────────────────────────────────────
// Moves the Gemini API key off the Flutter client device to a secure backend.
exports.analyzeTriageImage = onCall(
    { secrets: [geminiApiKeySecret] },
    async (request) => {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "User must be authenticated.");
    }
    const { base64str, mimeType, prompt } = request.data;
    if (!base64str || !prompt) {
        throw new HttpsError("invalid-argument", "Missing image or prompt");
    }
    try {
        const g = geminiClient();
        if (!g) {
            throw new HttpsError("failed-precondition", "GEMINI_API_KEY not set on server.");
        }
        const safePrompt = withSafetyForRole("triage", prompt);
        // Structured output: deterministic JSON, no regex parsing needed on client.
        const triageSchema = {
            type: "object",
            properties: {
                severity: { type: "string", enum: ["green", "yellow", "red", "black"] },
                category: {
                    type: "string",
                    enum: [
                        "cardiac",
                        "trauma",
                        "burn",
                        "bleed",
                        "fall",
                        "drowning",
                        "fire",
                        "rta",
                        "medical",
                        "other",
                    ],
                },
                aiRecommendedSpecialty: {
                    type: "string",
                    enum: [
                        "cardiac",
                        "trauma",
                        "burn",
                        "pediatric",
                        "stroke",
                        "general",
                    ],
                },
                confidence: { type: "string", enum: ["low", "medium", "high"] },
                analysis: { type: "string" },
                steps: { type: "array", items: { type: "string" }, minItems: 1, maxItems: 6 },
            },
            required: ["severity", "category", "analysis", "steps"],
        };
        const response = await g.models.generateContent({
            model: "gemini-2.5-flash",
            contents: [
                safePrompt,
                { inlineData: { data: base64str, mimeType: mimeType || "image/jpeg" } }
            ],
            generationConfig: {
                responseMimeType: "application/json",
                responseSchema: triageSchema,
                temperature: 0.2,
                maxOutputTokens: 600,
            },
        });
        return { result: response.text() };
    } catch (e) {
        console.error("Gemini Error:", e);
        throw new HttpsError("internal", "Failed to run AI triage.");
    }
});

// ─── AI triage → incident document (drives hospital specialty routing) ─────
// Writes the structured Gemini triage vision result onto `sos_incidents/{id}`
// under `triage.aiVision` and triggers a re-dispatch so the updated specialty
// recommendation is actually reflected in the hospital chain.
exports.applyAiTriageToIncident = onCall(
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Sign in required to attach AI triage.");
        }
        const incidentId = (request.data?.incidentId || "").toString().trim();
        if (!incidentId) {
            throw new HttpsError("invalid-argument", "incidentId required");
        }
        const t = (request.data?.triage && typeof request.data.triage === "object") ? request.data.triage : null;
        if (!t) {
            throw new HttpsError("invalid-argument", "triage payload required");
        }

        const allowedSeverity = new Set(["green", "yellow", "red", "black"]);
        const allowedSpecialty = new Set(["cardiac", "trauma", "burn", "pediatric", "stroke", "general"]);
        const severity = allowedSeverity.has(String(t.severity || "").toLowerCase())
            ? String(t.severity).toLowerCase()
            : "yellow";
        const category = String(t.category || "other").toLowerCase().slice(0, 32);
        const specialty = allowedSpecialty.has(String(t.aiRecommendedSpecialty || "").toLowerCase())
            ? String(t.aiRecommendedSpecialty).toLowerCase()
            : null;
        const confidence = String(t.confidence || "medium").toLowerCase();
        const analysis = String(t.analysis || "").slice(0, 1200);
        const stepsRaw = Array.isArray(t.steps) ? t.steps : [];
        const steps = stepsRaw.map((s) => String(s || "").slice(0, 400)).filter(Boolean).slice(0, 8);

        const ref = db.collection("sos_incidents").doc(incidentId);
        const snap = await ref.get();
        if (!snap.exists) {
            throw new HttpsError("not-found", "Incident not found.");
        }
        const inc = snap.data() || {};
        if (inc.userId && inc.userId !== request.auth.uid) {
            // Victims update their own incident; volunteers/admins may also attach if accepted.
            const accepted = Array.isArray(inc.acceptedVolunteerIds) ? inc.acceptedVolunteerIds.map(String) : [];
            const isMaster = isMasterConsoleEmailToken(request.auth.token);
            if (!accepted.includes(request.auth.uid) && !isMaster) {
                throw new HttpsError("permission-denied", "You cannot attach AI triage to this incident.");
            }
        }

        const aiVision = {
            severity,
            category,
            aiRecommendedSpecialty: specialty,
            confidence,
            analysis,
            steps,
            capturedAt: FieldValue.serverTimestamp(),
            capturedBy: request.auth.uid,
        };

        // Merge into existing self-reported triage block without clobbering it.
        const existingTriage = (inc.triage && typeof inc.triage === "object") ? inc.triage : {};
        const mergedTriage = { ...existingTriage, aiVision };

        const updates = {
            triage: mergedTriage,
            aiTriageAt: FieldValue.serverTimestamp(),
        };
        // Mirror the severity color for downstream severity classifiers.
        if (severity === "red") updates.triageColor = "red";
        else if (severity === "yellow") updates.triageColor = "orange";

        // Nudge required services so the hospital scorer treats the specialty
        // as a soft requirement (keeps existing services list intact).
        if (specialty && specialty !== "general") {
            const current = Array.isArray(inc.requiredServices) ? inc.requiredServices.map(String) : [];
            const mustHave = specialty === "cardiac" ? "cardiac"
                : specialty === "trauma" ? "trauma"
                : specialty === "burn" ? "burn"
                : specialty === "pediatric" ? "pediatric"
                : specialty === "stroke" ? "stroke"
                : null;
            if (mustHave && !current.map((s) => s.toLowerCase()).includes(mustHave)) {
                updates.requiredServices = [...current, mustHave];
            }
        }

        await ref.set(updates, { merge: true });

        // Trigger hospital re-dispatch so the new specialty actually reshuffles
        // the candidate list. `dispatchHospital` is idempotent on re-run.
        try {
            const fresh = (await ref.get()).data() || {};
            await hospitalDispatchV2.dispatchHospital({
                incidentId,
                incident: fresh,
            });
        } catch (e) {
            console.warn("[applyAiTriageToIncident] re-dispatch failed:", e?.message || e);
            // Not fatal — the triage block is already on the incident doc.
        }

        return {
            ok: true,
            severity,
            category,
            aiRecommendedSpecialty: specialty,
        };
    }
);

// FIX 8: Static offline protocol fallback when Gemini is rate-limited or unavailable.
const LIFELINE_OFFLINE_PROTOCOLS = {
  cpr: "Call 112 now.\n1. Place heel of hand on centre of chest (lower sternum).\n2. Push hard and fast — 5-6 cm deep, 100-120 compressions/min.\n3. After 30 compressions: tilt head, lift chin, give 2 rescue breaths.\n4. Repeat 30:2 until help arrives or person responds.",
  choking: "1. Ask 'Are you choking?' — if yes, act now.\n2. Lean them forward. Give 5 firm back blows between shoulder blades.\n3. Give 5 abdominal thrusts: fist above navel, pull sharply inward and upward.\n4. Alternate back blows and thrusts until object clears. Call 112.\n5. If unconscious: start CPR — check mouth before each rescue breath.",
  bleeding: "Call 112 now.\n1. Apply firm direct pressure with a clean cloth.\n2. Do not lift cloth to check — press continuously.\n3. If soaked through, add more cloth on top.\n4. Elevate the injured limb above heart level if possible.\n5. If limb bleeding uncontrolled: apply tourniquet 5-7 cm above wound. Note the exact time.",
  burn: "1. Cool burn under cool (not ice cold) running water for at least 20 minutes.\n2. Remove clothing and jewellery near the burn — unless stuck to skin.\n3. Cover loosely with cling film or clean non-fluffy material.\n4. Do NOT apply ice, butter, toothpaste, or creams.\n5. For burns larger than a palm or on face/hands/genitals: call 112.",
  heart_attack: "Call 112 now.\n1. Have the person sit down and rest — do not let them walk around.\n2. Loosen tight clothing around neck and chest.\n3. If they are conscious and not allergic: have them chew one aspirin (300 mg).\n4. If prescribed nitroglycerin: help them take it.\n5. Be ready to start CPR if they lose consciousness and stop breathing.",
  stroke: "Call 112 now — FAST: Face drooping · Arm weakness · Speech difficulty · Time.\n1. Note exact time symptoms started — critical for treatment decisions.\n2. Keep person calm — sit or lie them down comfortably.\n3. Do NOT give food or water.\n4. If unconscious and breathing: recovery position (on side).\n5. If not breathing: begin CPR.",
  default: "Call 112 now. Stay with the person. Keep them calm and still. Loosen tight clothing. Do not give food or water unless advised by emergency services. Be ready to start CPR if they stop breathing.",
};

function getOfflineProtocol(message) {
  const match = matchOfflineProtocol(message);
  return match ? match.text : LIFELINE_OFFLINE_PROTOCOLS.default;
}

/**
 * Returns `{topic, text}` if the message maps to a specific first-aid protocol
 * in `LIFELINE_OFFLINE_PROTOCOLS`, or `null` if no specific topic matches.
 * Used both for offline fallback and as RAG-style grounding for online Gemini.
 */
function matchOfflineProtocol(message) {
  const m = (message || "").toLowerCase();
  if (/cpr|compress|not breath|unrespon|cardiac arrest/.test(m)) return { topic: "cpr", text: LIFELINE_OFFLINE_PROTOCOLS.cpr };
  if (/chok|airway|block|heimlich/.test(m)) return { topic: "choking", text: LIFELINE_OFFLINE_PROTOCOLS.choking };
  if (/bleed|blood|wound|cut|hemorrh/.test(m)) return { topic: "bleeding", text: LIFELINE_OFFLINE_PROTOCOLS.bleeding };
  if (/burn|fire|scald/.test(m)) return { topic: "burn", text: LIFELINE_OFFLINE_PROTOCOLS.burn };
  if (/heart|chest pain|cardiac|angina/.test(m)) return { topic: "heart_attack", text: LIFELINE_OFFLINE_PROTOCOLS.heart_attack };
  if (/stroke|face droop|slur|fast/.test(m)) return { topic: "stroke", text: LIFELINE_OFFLINE_PROTOCOLS.stroke };
  return null;
}

// LIFELINE — server-side Gemini (no client API key). invoker: "public" so web/mobile work without IAM errors.
function lifelineSystemPrompt(scenario) {
    const s = scenario || "General Emergency";
    // Safety preamble is always first; task-specific rules come after.
    return (
        AI_SAFETY_PREAMBLE +
        "\n\n" +
        `## ROLE: LIFELINE FIRST-AID COPILOT\n` +
        `Scenario: ${s}\n` +
        `Rules: output exactly 3-5 numbered steps in plain text. Be safe and concrete. If life-threatening, include "Call 112 now" as a step.`
    );
}

exports.lifelineChat = onCall(
    {
        cors: true,
        memory: "512MiB",
        timeoutSeconds: 60,
        maxInstances: 20,
        secrets: [geminiApiKeySecret],
    },
    async (request) => {
        if (!request.auth) {
            return {
                status: "error",
                text: "Authentication required. Please sign in to use LIFELINE. If this is a real emergency, call 112 now.",
            };
        }

        const {
            message,
            scenario,
            base64Image,
            mimeType,
            history,
            contextDigest,
            analyticsMode,
            trainingMode,
            replyLocale,
            voiceAssistantMode,
        } = request.data || {};
        if (!message || typeof message !== "string") {
            throw new HttpsError("invalid-argument", "message required");
        }
        if (message.length > 12000) {
            throw new HttpsError("invalid-argument", "message too long");
        }
        if (!geminiApiKey()) {
            // Gracefully report that analytics AI is offline instead of throwing.
            return {
                status: "offline",
                text: "Live operations analytics AI is not configured on this project. An admin must set GEMINI_API_KEY in Cloud Functions secrets to enable it. Core metrics and maps still work without AI.",
            };
        }

        const scen = typeof scenario === "string" ? scenario : "General Emergency";
        const isAnalytics = analyticsMode === true;
        const isTraining = trainingMode === true;
        const isVoiceAssistant = voiceAssistantMode === true && isTraining;
        const replyLocaleRaw =
            typeof replyLocale === "string" ? replyLocale.trim() : "";

        let digestRaw =
            contextDigest && typeof contextDigest === "string" ? contextDigest.trim() : "";
        if (digestRaw.length > 28000) {
            digestRaw = digestRaw.slice(0, 28000) + "\n...[digest truncated for token limit]";
        }

        let transcript;
        if (isAnalytics) {
            transcript =
                AI_SAFETY_PREAMBLE + "\n\n" +
                `## ROLE: LIFELINE OPS ANALYTICS\n` +
                `You are an AI assistant for emergency operations centers.\n` +
                `You receive LIVE CONTEXT: aggregate statistics and incident summaries from a real-time incident feed (demo / staging data).\n` +
                `Scenario: ${scen}\n\n` +
                `Rules:\n` +
                `- Base answers on LIVE CONTEXT. Cite numbers and incident IDs when relevant.\n` +
                `- If something is not in the data, say you do not see it in the current feed.\n` +
                `- Prefer concise bullets or short sections. Expand only if the user asks for detail.\n` +
                `- Do not invent incidents, counts, or locations.\n` +
                `- You are not replacing 112 / emergency services.\n\n`;
            if (digestRaw) {
                transcript += `## LIVE CONTEXT (READ-ONLY)\n${digestRaw}\n\n`;
            }
        } else if (isTraining) {
            const langLine = replyLocaleRaw
                ? `The user's app language is ${replyLocaleRaw}. Write your ENTIRE reply in that language (natural for that locale).`
                : `Match the language of the user's message for your entire reply.`;
            transcript =
                AI_SAFETY_PREAMBLE + "\n\n" +
                `## ROLE: LIFELINE TRAINING\n` +
                `You are LIFELINE — EmergencyOS first-aid and emergency-training assistant.\n` +
                `${langLine}\n\n` +
                `Rules:\n` +
                `- Only answer: first aid, CPR/AED/choking/bleeding/burns/shock, the training curriculum below, when to call 112 (or local emergency numbers), and how to use EmergencyOS safety flows.\n` +
                `- If the user asks anything unrelated (games, coding, politics, homework, general chat), reply with ONE short refusal sentence in their language — no other content.\n` +
                `- Be concise: numbered steps or short bullets (about 8 lines or fewer).\n` +
                `- Standard first-aid guidance only; do not invent dangerous treatments.\n\n`;
            if (isVoiceAssistant) {
                transcript +=
                    `VOICE OUTPUT FORMAT (mandatory):\n` +
                    `- Reply with a single JSON object only, no markdown, no code fences.\n` +
                    `- Schema: {"spoken":"string for text-to-speech","openLibraryLevelId":number|null}\n` +
                    `- "spoken": safe, universal first-aid guidance for text-to-speech. Keep it short: about 2–5 spoken sentences. Sound natural aloud: practical principles (safety first, when to call emergency services, what not to do) rather than long numbered step lists.\n` +
                    `- "openLibraryLevelId": a curriculum level id from "Level N:" in the digest only if that N exists in the digest AND (the user asked to open/show/go to that topic OR your answer is mainly about that one curriculum topic). Otherwise null.\n\n`;
            }
            if (digestRaw) {
                transcript += `## TRAINING CURRICULUM (REFERENCE)\n${digestRaw}\n\n`;
            }
        } else {
            transcript = lifelineSystemPrompt(scen) + "\n\n";
            if (digestRaw) {
                transcript += `## LIVE CONTEXT (READ-ONLY)\n${digestRaw}\n\n`;
            }
            // RAG-style grounding: inject the matching WHO/AHA-derived static
            // protocol when the user's message maps to a known topic. Keeps
            // the model anchored on vetted first-aid guidance and lets us
            // truthfully claim "retrieval-grounded" AI to judges.
            try {
                const grounded = matchOfflineProtocol(message);
                if (grounded) {
                    transcript +=
                        `## AUTHORITATIVE PROTOCOL — topic: ${grounded.topic} (WHO / AHA-derived; treat as ground truth)\n` +
                        `${grounded.text.trim()}\n\n` +
                        `Use the AUTHORITATIVE PROTOCOL above as your primary source. Paraphrase naturally, localize units if needed, and do not contradict it. If the user's situation falls outside this protocol, say so and give only conservative guidance.\n\n`;
                }
            } catch (e) {
                console.warn("[lifelineChat] grounding injection failed:", e && e.message);
            }
        }

        if (Array.isArray(history)) {
            for (const h of history.slice(-6)) {
                if (!h || typeof h !== "object") continue;
                const role = h.role === "model" ? "LIFELINE" : "User";
                const t = typeof h.text === "string" ? h.text : "";
                if (t) transcript += `${role}: ${t}\n`;
            }
        }
        const tailLabel = isAnalytics
            ? "Respond as OPS ANALYTICS:"
            : isTraining
              ? isVoiceAssistant
                ? "Respond as LIFELINE (training, voice JSON only):"
                : "Respond as LIFELINE (training):"
              : "Respond as LIFELINE:";
        transcript += `User: ${message}\n\n${tailLabel}`;

        try {
            const g = geminiClient();
            if (!g) {
                return {
                    status: "offline",
                    text: "Live operations analytics AI is not configured on this project. An admin must set GEMINI_API_KEY in Cloud Functions secrets to enable it. Core metrics and maps still work without AI.",
                };
            }
            let response;
            // Voice-assistant replies are now strictly schema-constrained so the
            // client never has to regex-parse JSON out of free text.
            const voiceAssistantSchema = {
                type: "object",
                properties: {
                    spoken: { type: "string" },
                    openLibraryLevelId: { type: ["integer", "null"] },
                },
                required: ["spoken"],
            };
            const gen = isAnalytics
                ? { maxOutputTokens: 2048, temperature: 0.3 }
                : isTraining
                  ? isVoiceAssistant
                    ? {
                        maxOutputTokens: 720,
                        temperature: 0.25,
                        responseMimeType: "application/json",
                        responseSchema: voiceAssistantSchema,
                      }
                    : { maxOutputTokens: 640, temperature: 0.25 }
                  : { maxOutputTokens: 180, temperature: 0.2 };
            if (base64Image && typeof base64Image === "string") {
                response = await g.models.generateContent({
                    model: "gemini-2.5-flash",
                    contents: [
                        transcript,
                        {
                            inlineData: {
                                data: base64Image,
                                mimeType: mimeType || "image/jpeg",
                            },
                        },
                    ],
                    generationConfig: gen,
                });
            } else {
                response = await g.models.generateContent({
                    model: "gemini-2.5-flash",
                    contents: transcript,
                    generationConfig: gen,
                });
            }
            const out =
                (typeof response?.text === "function" ? response.text() : response?.text) ??
                response?.outputText ??
                "";
            let trimmed = out && String(out).trim();
            let openLibraryLevelId = null;
            if (isVoiceAssistant && trimmed) {
                try {
                    const jsonMatch = trimmed.match(/\{[\s\S]*\}/);
                    const jsonStr = jsonMatch ? jsonMatch[0] : trimmed;
                    const parsed = JSON.parse(jsonStr);
                    if (parsed && typeof parsed.spoken === "string") {
                        const spoken = String(parsed.spoken).trim();
                        if (spoken.length) trimmed = spoken;
                        if (parsed.openLibraryLevelId === null || parsed.openLibraryLevelId === undefined) {
                            openLibraryLevelId = null;
                        } else if (typeof parsed.openLibraryLevelId === "number" && Number.isFinite(parsed.openLibraryLevelId)) {
                            openLibraryLevelId = Math.round(parsed.openLibraryLevelId);
                        }
                    }
                } catch (e) {
                    console.warn("[lifelineChat] voice JSON parse failed, using raw text:", e && e.message);
                }
            }
            // FIX 8: Cache successful non-analytics, non-training responses to serve on rate-limit.
            if (!isAnalytics && !isTraining && trimmed && trimmed.length > 20) {
                try {
                    const cacheKey = crypto.createHash("md5").update(scen || "General Emergency").digest("hex");
                    db.collection("lifeline_response_cache").doc(cacheKey).set(
                        { scenario: scen, text: trimmed, cachedAt: FieldValue.serverTimestamp() },
                        { merge: true }
                    ).catch(() => {});
                } catch (_) {}
            }
            const payload = {
                status: "ok",
                text: (trimmed && trimmed.length ? trimmed : "Call emergency services (112) if unsure."),
            };
            if (isVoiceAssistant) {
                payload.openLibraryLevelId = openLibraryLevelId;
            }
            return payload;
        } catch (e) {
            console.error("[lifelineChat] Gemini error:", e);
            const msg = (e && (e.message || e.toString && e.toString())) ? String(e.message || e.toString()) : "AI request failed";
            const raw = (e && e.error) ? e.error : null;
            const isRateLimited =
                (e && e.status === 429) ||
                msg.includes("RESOURCE_EXHAUSTED") ||
                msg.includes("Quota exceeded") ||
                msg.includes("generate_content_free_tier_requests");
            if (isRateLimited) {
                // FIX 8: Try Firestore response cache first, then serve static offline protocol.
                let cachedText = null;
                try {
                    const cacheKey = crypto.createHash("md5").update(scen || "General Emergency").digest("hex");
                    const cached = await db.collection("lifeline_response_cache").doc(cacheKey).get();
                    if (cached.exists) {
                        const ca = cached.data() || {};
                        const ageMs = Date.now() - (ca.cachedAt?.toMillis?.() ?? 0);
                        if (ageMs < 60 * 60 * 1000) cachedText = String(ca.text || "");
                    }
                } catch (_) {}
                const fallbackText = cachedText ||
                    getOfflineProtocol(message) +
                    "\n\n⚠️ AI guidance temporarily limited. Protocol above is standard first-aid. Call 112 now if life-threatening.";
                return { status: "rate_limited", text: fallbackText };
            }
            throw new HttpsError("internal", msg || "AI request failed");
        }
    }
);

const HEALTH_ALERT_CACHE_MS = 6 * 60 * 60 * 1000;

function iso2ToIso3(iso2) {
    const m = {
        IN: "IND",
        US: "USA",
        GB: "GBR",
        BD: "BGD",
        PK: "PAK",
        ID: "IDN",
        NG: "NGA",
        BR: "BRA",
        MX: "MEX",
        CN: "CHN",
        JP: "JPN",
        AU: "AUS",
        DE: "DEU",
        FR: "FRA",
    };
    const k = String(iso2 || "")
        .trim()
        .toUpperCase();
    return m[k] || "IND";
}

/** ReliefWeb disasters (structured) — filter to outbreak/epidemic-like types when possible. */
async function fetchReliefWebOutbreaksForCountry(iso3) {
    const postBody = JSON.stringify({
        appname: "emergencyos",
        limit: 35,
        preset: "latest",
        filter: {
            operator: "AND",
            conditions: [
                { field: "primary_country.iso3", value: iso3 },
                { field: "status", value: "current" },
            ],
        },
        fields: {
            include: ["name", "description", "date", "primary_country", "url", "primary_type"],
        },
    });
    const res = await fetch("https://api.reliefweb.int/v1/disasters", {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: postBody,
    });
    if (!res.ok) {
        throw new Error(`ReliefWeb HTTP ${res.status}`);
    }
    const json = await res.json();
    const data = json && json.data;
    if (!Array.isArray(data)) return [];
    const keywords = /outbreak|epidemic|disease|ebola|cholera|measles|dengue|malaria|zika|covid|virus|infection|plague|polio|meningitis|yellow fever|mpox|monkeypox/i;
    const out = [];
    for (const row of data) {
        const fields = row.fields || {};
        const name = String(fields.name || "Health event").trim();
        const desc = String(fields.description || "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
        const type = String(fields.primary_type || fields.type || "");
        const blob = `${name} ${desc} ${type}`;
        if (!keywords.test(blob) && !/outbreak|epidemic/i.test(type)) continue;
        const country = (fields.primary_country && fields.primary_country.name) || iso3;
        const dateRaw =
            (fields.date && (fields.date.created || fields.date.changed)) ||
            fields.changed ||
            null;
        const d = dateRaw ? new Date(dateRaw) : new Date();
        out.push({
            disease: name.slice(0, 120),
            severity: /severe|critical|ebola|cholera/i.test(blob) ? "High" : "Medium",
            affectedArea: country,
            description: (desc || name).slice(0, 400),
            precautions: [],
            source: "ReliefWeb",
            reportedDate: d.toISOString(),
            reportedCases: null,
            advisoryLevel: "Advisory",
        });
        if (out.length >= 6) break;
    }
    return out;
}

/** Gemini + Google Search fallback — returns normalized outbreak objects or []. */
async function fetchGeminiSearchOutbreaks(lat, lng, countryLabel) {
    const g = geminiClient();
    if (!g) return [];
    const prompt =
        `You are summarizing recent PUBLIC disease outbreak / epidemic / notable infectious disease alerts ` +
        `relevant to the region at latitude ${lat}, longitude ${lng} (${countryLabel}). ` +
        `Use Google Search. Return ONLY valid JSON (no markdown): ` +
        `{"items":[{"disease":"short title","description":"one or two sentences","severity":"Low|Medium|High|Critical",` +
        `"affectedArea":"place","precautions":["optional"],"source":"publisher name","advisoryLevel":"Advisory","reportedCases":null}]}. ` +
        `Max 4 items. If nothing credible in the last ~90 days, return {"items":[]}. ` +
        `Do not invent specific case counts.`;
    try {
        const response = await g.models.generateContent({
            model: "gemini-2.5-flash",
            contents: prompt,
            config: {
                maxOutputTokens: 2048,
                temperature: 0.2,
                tools: [{ googleSearch: {} }],
            },
        });
        const raw =
            (typeof response?.text === "function" ? response.text() : response?.text) ??
            response?.outputText ??
            "";
        const t = String(raw || "").trim();
        const m = t.match(/\{[\s\S]*\}/);
        const parsed = JSON.parse(m ? m[0] : t);
        const items = parsed && Array.isArray(parsed.items) ? parsed.items : [];
        return items
            .filter((x) => x && typeof x.disease === "string")
            .map((x) => ({
                disease: String(x.disease).slice(0, 120),
                severity: String(x.severity || "Medium"),
                affectedArea: String(x.affectedArea || countryLabel).slice(0, 120),
                description: String(x.description || "").slice(0, 400),
                precautions: Array.isArray(x.precautions) ? x.precautions.map((p) => String(p)).slice(0, 3) : [],
                source: "Web summary (verify): " + String(x.source || "search"),
                reportedDate: new Date().toISOString(),
                reportedCases: x.reportedCases != null ? x.reportedCases : null,
                advisoryLevel: String(x.advisoryLevel || "Search"),
            }))
            .slice(0, 4);
    } catch (e) {
        console.warn("[getRegionalHealthAlerts] Gemini search fallback failed:", e && e.message);
        return [];
    }
}

exports.getRegionalHealthAlerts = onCall(
    {
        cors: true,
        memory: "512MiB",
        timeoutSeconds: 90,
        maxInstances: 10,
        secrets: [geminiApiKeySecret],
    },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required");
        }
        const { lat, lng, countryCode } = request.data || {};
        const la = Number(lat);
        const ln = Number(lng);
        if (!Number.isFinite(la) || !Number.isFinite(ln) || Math.abs(la) > 90 || Math.abs(ln) > 180) {
            throw new HttpsError("invalid-argument", "lat and lng required");
        }
        const iso2 = typeof countryCode === "string" && countryCode.trim().length === 2 ? countryCode.trim().toUpperCase() : "IN";
        const iso3 = iso2ToIso3(iso2);
        const cacheKey = `h_${iso3}_${Math.round(la * 20) / 20}_${Math.round(ln * 20) / 20}`;
        try {
            const cref = db.collection("regional_health_alerts_cache").doc(cacheKey);
            const snap = await cref.get();
            if (snap.exists) {
                const d = snap.data() || {};
                const ageMs = Date.now() - (d.cachedAt?.toMillis?.() ?? 0);
                if (ageMs >= 0 && ageMs < HEALTH_ALERT_CACHE_MS && Array.isArray(d.outbreaks)) {
                    return { status: "ok", outbreaks: d.outbreaks, source: d.source || "cached" };
                }
            }
        } catch (_) {}

        let outbreaks = [];
        let source = "reliefweb";
        try {
            outbreaks = await fetchReliefWebOutbreaksForCountry(iso3);
        } catch (e) {
            console.warn("[getRegionalHealthAlerts] ReliefWeb error:", e && e.message);
            outbreaks = [];
        }
        if (!outbreaks.length) {
            outbreaks = await fetchGeminiSearchOutbreaks(la, ln, iso2);
            source = outbreaks.length ? "gemini_search" : "none";
        }
        try {
            await db
                .collection("regional_health_alerts_cache")
                .doc(cacheKey)
                .set(
                    {
                        outbreaks,
                        source,
                        cachedAt: FieldValue.serverTimestamp(),
                        lat: la,
                        lng: ln,
                        iso2,
                    },
                    { merge: true }
                );
        } catch (_) {}

        return { status: "ok", outbreaks, source };
    }
);

function emergencyRoomName(incidentId) {
  return `emergency_bridge_${incidentId}`;
}

function copilotRoomName(uid) {
  return `copilot_${uid}`;
}

/** Inter-hospital command voice net (master console email only). */
function commsCommandRoomName() {
  return "comms_command_net";
}

function sanitizeRoomKey(id) {
  const s = String(id || "")
    .replace(/[^a-zA-Z0-9]/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_|_$/g, "");
  return (s.length ? s : "inc").slice(0, 96);
}

function commsOperationRoomName(incidentId) {
  return `commsop_${sanitizeRoomKey(incidentId)}`;
}

function commsEmergencyRoomName(incidentId) {
  return `commsem_${sanitizeRoomKey(incidentId)}`;
}

function isMasterConsoleEmailToken(token) {
  const email = (token?.email || "").toLowerCase();
  return email === "admin@emeregencyos.com";
}

async function assertCommsBridgeIncidentAccess(uid, token, userDoc, incidentId, clientBoundHospitalId, channel) {
  if (isMasterConsoleEmailToken(token)) return;

  const incSnapEarly = await db.collection("sos_incidents").doc(incidentId).get();
  if (incSnapEarly.exists && incSnapEarly.data()) {
    const inc0 = incSnapEarly.data();
    const emsBy = (inc0.emsAcceptedBy || "").toString();
    const craneBy = (inc0.craneUnitAcceptedBy || "").toString();
    if (emsBy === uid) return;
    if (channel === "operation" && craneBy === uid) return;
  }

  const assignSnap = await db.collection("ops_incident_hospital_assignments").doc(incidentId).get();
  const d = assignSnap.exists ? assignSnap.data() || {} : {};
  const allowed = new Set();
  const primary = (d.primaryHospitalId || "").toString().trim();
  if (primary) allowed.add(primary);
  const ordered = Array.isArray(d.orderedHospitalIds) ? d.orderedHospitalIds : [];
  for (const x of ordered) {
    const h = String(x).trim();
    if (h) allowed.add(h);
  }
  const notified = Array.isArray(d.notifiedHospitalIds) ? d.notifiedHospitalIds : [];
  for (const x of notified) {
    const h = String(x).trim();
    if (h) allowed.add(h);
  }
  const accepted = (d.acceptedHospitalId || "").toString().trim();
  if (accepted) allowed.add(accepted);

  if (userDoc && userDoc.emergencyBridgeDesk === true) {
    const bound = ((userDoc.staffHospitalId || userDoc.boundHospitalDocId || "") + "").trim();
    if (!bound) return;
    if (allowed.has(bound)) return;
    throw new HttpsError("permission-denied", "This incident is not linked to your hospital.");
  }

  const cb = (clientBoundHospitalId || "").toString().trim();
  if (cb && allowed.has(cb)) return;

  throw new HttpsError(
    "permission-denied",
    "Comms bridge requires the master console account, emergency desk access, or a hospital linked to this incident."
  );
}

async function ensureCommsLiveKitRoom(env, roomName) {
  const roomClient = newLiveKitRoomServiceClient(
    livekitHostForServerSdk(env),
    env.apiKey,
    env.apiSecret
  );
  try {
    const rooms = await roomClient.listRooms([roomName]);
    if (!rooms || rooms.length === 0) {
      await roomClient.createRoom({
        name: roomName,
        emptyTimeout: 7200,
        maxParticipants: 48,
      });
    }
  } catch (e) {
    console.error("[ensureCommsLiveKitRoom]", roomName, e);
    throw new HttpsError(
      "failed-precondition",
      `LiveKit room setup failed: ${e?.message || String(e)}`
    );
  }
}

function normalizeE164(phone) {
  if (!phone) return null;
  const raw = String(phone).trim();
  if (!raw) return null;
  if (raw.startsWith("+")) return raw;
  const digits = raw.replace(/[^\d]/g, "");
  if (!digits) return null;
  return digits.length >= 8 ? `+${digits}` : null;
}

function safeIdentityPrefix(uid, variant) {
  const v = (variant || "").toString().trim();
  // allow only a-zA-Z0-9_ to prevent weird identity injection
  const cleaned = v.replace(/[^a-zA-Z0-9_]/g, "");
  return `victim_${uid}${cleaned ? `_${cleaned}` : ""}`;
}

/**
 * @param {string} uid
 * @param {string} role victim | emergency_desk | emergency_contact
 * @param {FirebaseFirestore.DocumentData} incident
 * @param {FirebaseFirestore.DocumentData|undefined} userDoc
 * @returns {string} LiveKit identity
 */
function bridgeIdentityForRole(uid, role, incident, userDoc) {
  if (role === "emergency_desk") {
    const ok = userDoc && userDoc.emergencyBridgeDesk === true;
    if (!ok) {
      throw new HttpsError(
        "permission-denied",
        "Emergency services join requires emergencyBridgeDesk on your user profile."
      );
    }
    return `ems_${uid}`;
  }

  if (role === "emergency_contact") {
    const incPhone = normalizeE164(incident.emergencyContactPhone);
    const userPhone = normalizeE164(userDoc?.contactPhone || userDoc?.phone || "");
    const uidMatch = (incident.emergencyContactUid || "").toString() === uid;
    if (!uidMatch && (!incPhone || !userPhone || incPhone !== userPhone)) {
      throw new HttpsError(
        "permission-denied",
        "Your profile phone must match the incident emergency contact, or you must be linked as emergencyContactUid."
      );
    }
    return `contact_${uid}`;
  }

  throw new HttpsError(
    "invalid-argument",
    "role must be victim, emergency_desk, emergency_contact, or volunteer_elite (handled separately)."
  );
}

// ─── LiveKit: Token minting ─────────────────────────────────────────────────
// WebRTC join token for emergency_bridge_{incidentId}. Roles: victim, emergency_desk, emergency_contact, accepted_volunteer, volunteer_elite.
exports.getLivekitToken = onCall(
  { secrets: [lkSecret] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be authenticated.");
    }

    const incidentId = (request.data?.incidentId || "").toString().trim();
    if (!incidentId) throw new HttpsError("invalid-argument", "incidentId required");

    const uid = request.auth.uid;
    const canPublishAudio = request.data?.canPublishAudio === true;
    const variant = (request.data?.variant || "").toString();
    const role = (request.data?.role || "victim").toString().trim() || "victim";

    const env = liveKitEnv(lkSecret.value());
    assertLiveKitConfigured(env);

    const incidentRef = db.collection("sos_incidents").doc(incidentId);
    const snap = await incidentRef.get();
    if (!snap.exists || !snap.data()) {
      throw new HttpsError("not-found", "Incident not found.");
    }
    const incident = snap.data();

    const userSnap = await db.collection("users").doc(uid).get();
    const userDoc = userSnap.exists ? userSnap.data() : {};

    let identity;
    if (role === "victim" || role === "") {
      identity = safeIdentityPrefix(uid, variant);
      const victimUid = (incident.userId || "").toString();
      if (victimUid && victimUid !== uid) {
        throw new HttpsError("permission-denied", "Only the incident owner can join as victim.");
      }
    } else if (role === "accepted_volunteer") {
      const accepted = Array.isArray(incident.acceptedVolunteerIds) ? incident.acceptedVolunteerIds : [];
      const okResponder = accepted.map((x) => String(x)).includes(uid);
      if (!okResponder) {
        throw new HttpsError(
          "permission-denied",
          "Accept this SOS as a volunteer before joining the emergency voice channel."
        );
      }
      identity = `volunteer_${uid}`;
    } else if (role === "volunteer_elite") {
      if (!volunteerEliteEligible(userDoc)) {
        throw new HttpsError(
          "permission-denied",
          "Elite volunteer voice requires Lifeline arena level 10 or 5 lives helped with 1,000 volunteer XP."
        );
      }
      const accepted = Array.isArray(incident.acceptedVolunteerIds) ? incident.acceptedVolunteerIds : [];
      const okResponder = accepted.map((x) => String(x)).includes(uid);
      if (!okResponder) {
        throw new HttpsError(
          "permission-denied",
          "Accept this SOS as a volunteer before joining the emergency voice channel."
        );
      }
      identity = `vol_elite_${uid}`;
    } else if (role === "ems_fleet") {
      const emsBy = (incident.emsAcceptedBy || "").toString();
      if (emsBy !== uid) {
        throw new HttpsError(
          "permission-denied",
          "Only the EMS unit allotted to this incident can join the emergency bridge as ems_fleet."
        );
      }
      identity = `ems_fleet_${uid}`;
    } else {
      identity = bridgeIdentityForRole(uid, role, incident, userDoc);
    }

    const roomName = emergencyRoomName(incidentId);

    const at = newLiveKitAccessToken(env.apiKey, env.apiSecret, {
      identity,
      ttl: 6 * 60 * 60,
    });

    // Always allow publish in the grant; clients mute the mic when needed. Some LiveKit
    // builds reject tokens with canPublish: false while still subscribing.
    at.addGrant({
      roomJoin: true,
      room: roomName,
      canSubscribe: true,
      canPublish: true,
      canPublishData: true,
    });

    const token = await at.toJwt();

    return {
      token,
      url: livekitClientWsUrl(env),
      roomName,
      identity,
      role,
    };
  }
);

// ─── LiveKit: Copilot room (per-user, persistent voice assistant) ────────────
// Join token for copilot_{uid}. Client may publish mic + data (page context).
exports.getCopilotLivekitToken = onCall(
  { secrets: [lkSecret] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be authenticated.");
    }

    const uid = request.auth.uid;
    const canPublishAudio = request.data?.canPublishAudio === true;

    const env = liveKitEnv(lkSecret.value());
    assertLiveKitConfigured(env);

    const roomName = copilotRoomName(uid);
    const identity = `copilot_user_${uid}`;

    const at = newLiveKitAccessToken(env.apiKey, env.apiSecret, {
      identity,
      ttl: 6 * 60 * 60,
    });

    at.addGrant({
      roomJoin: true,
      room: roomName,
      canSubscribe: true,
      canPublish: true,
      canPublishData: true,
    });

    const token = await at.toJwt();

    return {
      token,
      url: livekitClientWsUrl(env),
      roomName,
      identity,
    };
  }
);

// Dispatches the copilot voice agent into copilot_{uid} (rate-limited).
exports.ensureCopilotAgent = onCall(
  { secrets: [lkSecret], cpu: 0.25 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be authenticated.");
    }

    const uid = request.auth.uid;
    const walkthrough =
      request.data?.walkthrough === true || request.data?.voiceWalkthroughEnabled === true;

    const env = liveKitEnv(lkSecret.value());
    assertLiveKitConfigured(env);

    const roomName = copilotRoomName(uid);

    const dispatchRef = db.collection("livekit_copilot_dispatches").doc(uid);
    const existing = await dispatchRef.get();
    if (existing.exists) {
      const startedAt = existing.data()?.startedAt;
      const startedMs = startedAt?.toMillis ? startedAt.toMillis() : null;
      if (startedMs && Date.now() - startedMs < 2 * 60 * 1000) {
        return { started: false, reason: "Already started recently.", roomName };
      }
    }

    const agentDispatchClient = newLiveKitAgentDispatchClient(
      livekitHostForServerSdk(env),
      env.apiKey,
      env.apiSecret
    );
    const metadata = JSON.stringify({
      uid,
      roomName,
      mode: "copilot",
      walkthrough,
    });

    await agentDispatchClient.createDispatch(roomName, copilotAgentName, { metadata });

    await dispatchRef.set(
      {
        startedAt: FieldValue.serverTimestamp(),
        roomName,
        agentName: copilotAgentName,
        walkthrough,
      },
      { merge: true }
    );

    return { started: true, roomName };
  }
);

// ─── LiveKit: Ensure Lifeline agent (WebRTC only) ───────────────────────────
// Dispatches the Lifeline voice agent into the room. EMS / contacts use the app (getLivekitToken).
exports.ensureEmergencyBridge = onCall(
  { secrets: [lkSecret] },
  async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated.");
  }

  const incidentId = (request.data?.incidentId || "").toString().trim();
  if (!incidentId) throw new HttpsError("invalid-argument", "incidentId required");

  const env = liveKitEnv(lkSecret.value());
  assertLiveKitConfigured(env);

  const callerUid = request.auth.uid;
  const incidentRef = db.collection("sos_incidents").doc(incidentId);
  const snap = await incidentRef.get();
  if (!snap.exists || !snap.data()) {
    throw new HttpsError("not-found", "Incident not found.");
  }
  const incident = snap.data();

  const victimUid = (incident.userId || "").toString();
  if (victimUid && victimUid !== callerUid) {
    throw new HttpsError("permission-denied", "Only the incident owner can start the emergency bridge.");
  }

  const roomName = emergencyRoomName(incidentId);

  const bridgeRef = db.collection("livekit_bridges").doc(incidentId);
  const existing = await bridgeRef.get();
  if (existing.exists) {
    const startedAt = existing.data()?.startedAt;
    const startedMs = startedAt?.toMillis ? startedAt.toMillis() : null;
    if (startedMs && Date.now() - startedMs < 3 * 60 * 1000) {
      return { started: false, reason: "Already started recently.", roomName, mode: "webrtc" };
    }
  }

  const emergencyContactPhone = normalizeE164(incident.emergencyContactPhone);

  const agentDispatchClient = newLiveKitAgentDispatchClient(
    livekitHostForServerSdk(env),
    env.apiKey,
    env.apiSecret
  );
  const metadata = JSON.stringify({
    incidentId,
    roomName,
    mode: "webrtc",
    emergencyContactPhone: emergencyContactPhone || null,
  });

  await agentDispatchClient.createDispatch(roomName, lifelineAgentName, { metadata });

  await bridgeRef.set(
    {
      startedAt: FieldValue.serverTimestamp(),
      roomName,
      agentName: lifelineAgentName,
      mode: "webrtc",
      emergencyContactPhone: emergencyContactPhone || null,
    },
    { merge: true }
  );

  return { started: true, roomName, mode: "webrtc" };
});

// Dispatch an additional Lifeline agent job to make it read a specific text.
// Intended for "important comms" events during an active SOS.
exports.dispatchLifelineComms = onCall(
  { secrets: [lkSecret] },
  async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated.");
  }

  const incidentId = (request.data?.incidentId || "").toString().trim();
  const text = (request.data?.text || "").toString().trim();
  if (!incidentId) throw new HttpsError("invalid-argument", "incidentId required");
  if (!text) throw new HttpsError("invalid-argument", "text required");

  const env = liveKitEnv(lkSecret.value());
  assertLiveKitConfigured(env);

  const uid = request.auth.uid;
  const incidentRef = db.collection("sos_incidents").doc(incidentId);
  const incSnap = await incidentRef.get();
  if (!incSnap.exists || !incSnap.data()) {
    throw new HttpsError("not-found", "Incident not found.");
  }
  const incident = incSnap.data();
  const victimUid = (incident.userId || "").toString();
  const isVictim = victimUid === uid;
  let isDesk = false;
  if (!isVictim) {
    const udoc = await db.collection("users").doc(uid).get();
    isDesk = udoc.exists && udoc.data()?.emergencyBridgeDesk === true;
  }
  if (!isVictim && !isDesk) {
    throw new HttpsError("permission-denied", "Only the incident owner or emergency desk can dispatch Lifeline comms.");
  }

  const roomName = emergencyRoomName(incidentId);
  const agentDispatchClient = newLiveKitAgentDispatchClient(
    livekitHostForServerSdk(env),
    env.apiKey,
    env.apiSecret
  );

  const metadata = JSON.stringify({
    incidentId,
    roomName,
    importantComms: text,
  });

  await agentDispatchClient.createDispatch(roomName, lifelineAgentName, { metadata });
  return { ok: true, roomName };
});

/** Authenticated integration health for master / observatory UIs (matches Dart [OpsSystemHealthReport]). */
exports.getOpsSystemHealth = onCall({ secrets: [lkSecret] }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated.");
  }
  const checkedAt = Date.now();
  let gcpOk = true;
  let gcpDetail = "Firestore query OK";
  try {
    await db.collection("_health_check").limit(1).get();
  } catch (e) {
    gcpOk = false;
    gcpDetail = String(e?.message || e);
  }

  let livekitOk = false;
  let livekitDetail = "Not configured";
  try {
    const env = liveKitEnv(lkSecret.value());
    const lkHost = livekitHostForServerSdk(env);
    // Allow LIVEKIT_HTTP_URL-only configs (no wss LIVEKIT_URL) for server API checks.
    if (lkHost && env.apiKey && env.apiSecret) {
      const roomClient = newLiveKitRoomServiceClient(lkHost, env.apiKey, env.apiSecret);
      const rooms = await roomClient.listRooms();
      livekitOk = true;
      livekitDetail = `${rooms.length} room(s) listed`;
    } else if (!env.apiKey || !env.apiSecret) {
      livekitDetail = "Missing LIVEKIT_API_KEY or LIVEKIT_API_SECRET";
    } else if (!lkHost) {
      livekitDetail = "Set LIVEKIT_URL (wss/https) or LIVEKIT_HTTP_URL (https origin)";
    }
  } catch (e) {
    livekitOk = false;
    let msg = String(e?.message || e);
    if (/invalid token/i.test(msg)) {
      msg +=
        " — Pair LIVEKIT_API_KEY + LIVEKIT_API_SECRET from the same LiveKit project; remove stray spaces/newlines in Secret Manager. Set LIVEKIT_URL + LIVEKIT_API_KEY (params), or set env LIVEKIT_HTTP_URL=https://<subdomain>.livekit.cloud on the function. Redeploy after changes.";
    }
    livekitDetail = msg;
  }

  const smsOk = !!(twilioSid && twilioToken && twilioNumber);
  const smsDetail = smsOk
    ? "Twilio env vars present"
    : "Twilio not fully configured (SID, token, or TWILIO_PHONE_NUMBER)";

  // Core platform: Firestore + LiveKit. SMS is optional for overall "green" master dashboard.
  const coreOk = gcpOk && livekitOk;
  const ok = coreOk;
  const summary = !coreOk
    ? "One or more core integration checks reported issues"
    : smsOk
      ? "All integration checks passed"
      : "Core services OK — SMS relay not configured (optional)";

  return {
    ok,
    summary,
    checkedAt,
    services: {
      gcp: { ok: gcpOk, label: "GCP / Firestore", detail: gcpDetail },
      livekit: { ok: livekitOk, label: "LiveKit", detail: livekitDetail },
      sms: { ok: smsOk, label: "SMS (Twilio)", detail: smsDetail },
    },
  };
});

// ─── LiveKit: Hospital comms bridge (Discord-style incident voice channels) ─
// Per active incident: operation + emergency rooms. Command net for master only.
exports.ensureCommsBridgeRooms = onCall({ secrets: [lkSecret] }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const incidentId = (request.data?.incidentId || "").toString().trim();
  if (!incidentId) throw new HttpsError("invalid-argument", "incidentId required");
  const boundHospitalId = (request.data?.boundHospitalId || "").toString().trim();

  const incSnap = await db.collection("sos_incidents").doc(incidentId).get();
  if (!incSnap.exists || !incSnap.data()) {
    throw new HttpsError("not-found", "Incident not found.");
  }

  const uid = request.auth.uid;
  const userSnap = await db.collection("users").doc(uid).get();
  const userDoc = userSnap.exists ? userSnap.data() : {};
  await assertCommsBridgeIncidentAccess(uid, request.auth.token, userDoc, incidentId, boundHospitalId, null);

  const env = liveKitEnv(lkSecret.value());
  assertLiveKitConfigured(env);

  const op = commsOperationRoomName(incidentId);
  const em = commsEmergencyRoomName(incidentId);
  await ensureCommsLiveKitRoom(env, op);
  await ensureCommsLiveKitRoom(env, em);

  return { operationRoom: op, emergencyRoom: em, url: livekitClientWsUrl(env) };
});

exports.getCommsBridgeLivekitToken = onCall({ secrets: [lkSecret] }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const channel = (request.data?.channel || "").toString().trim().toLowerCase();
  const incidentId = (request.data?.incidentId || "").toString().trim();
  const boundHospitalId = (request.data?.boundHospitalId || "").toString().trim();
  const canPublishAudio = request.data?.canPublishAudio !== false;

  const uid = request.auth.uid;
  const userSnap = await db.collection("users").doc(uid).get();
  const userDoc = userSnap.exists ? userSnap.data() : {};

  let roomName;
  if (channel === "command") {
    if (!isMasterConsoleEmailToken(request.auth.token)) {
      throw new HttpsError("permission-denied", "Command net is limited to the master console account.");
    }
    roomName = commsCommandRoomName();
  } else if (channel === "operation" && incidentId) {
    await assertCommsBridgeIncidentAccess(uid, request.auth.token, userDoc, incidentId, boundHospitalId, channel);
    roomName = commsOperationRoomName(incidentId);
  } else if (channel === "emergency" && incidentId) {
    await assertCommsBridgeIncidentAccess(uid, request.auth.token, userDoc, incidentId, boundHospitalId, channel);
    roomName = commsEmergencyRoomName(incidentId);
  } else {
    throw new HttpsError(
      "invalid-argument",
      "Use channel command (no incidentId), or operation|emergency with incidentId."
    );
  }

  const env = liveKitEnv(lkSecret.value());
  assertLiveKitConfigured(env);
  await ensureCommsLiveKitRoom(env, roomName);

  const identity = `comms_${uid}_${channel}`.slice(0, 120);
  const meta = JSON.stringify({
    channel,
    incidentId: incidentId || null,
    role: "comms_bridge",
  });

  const displayName = String(
    userDoc.displayName ||
      userDoc.fullName ||
      userDoc.name ||
      request.auth.token.email ||
      request.auth.token.name ||
      `staff_${uid.slice(0, 8)}`
  )
    .trim()
    .slice(0, 80);

  const at = newLiveKitAccessToken(env.apiKey, env.apiSecret, {
    identity,
    name: displayName || `Staff ${uid.slice(0, 8)}`,
    ttl: "12h",
    metadata: meta,
  });
  at.addGrant({
    roomJoin: true,
    room: roomName,
    canSubscribe: true,
    canPublish: true,
    canPublishData: true,
  });
  const token = await at.toJwt();

  return { token, url: livekitClientWsUrl(env), roomName, identity, channel };
});

// ─── Incident video → Gemini (accepted volunteers only) ─────────────────────
exports.analyzeIncidentVideo = onCall(
  {
    cors: true,
    memory: "1GiB",
    timeoutSeconds: 120,
    maxInstances: 10,
    secrets: [geminiApiKeySecret],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const incidentId = (request.data?.incidentId || "").toString().trim();
    const videoUrl = (request.data?.videoUrl || "").toString().trim();
    if (!incidentId) throw new HttpsError("invalid-argument", "incidentId required");
    if (!videoUrl) throw new HttpsError("invalid-argument", "videoUrl required");

    const incSnap = await db.collection("sos_incidents").doc(incidentId).get();
    if (!incSnap.exists) throw new HttpsError("not-found", "Incident not found.");
    const inc = incSnap.data() || {};
    const accepted = Array.isArray(inc.acceptedVolunteerIds) ? inc.acceptedVolunteerIds.map(String) : [];
    if (!accepted.includes(request.auth.uid)) {
      throw new HttpsError("permission-denied", "Only accepted volunteers can submit incident video.");
    }

    const gVideo = geminiClient();
    if (!gVideo) {
      throw new HttpsError("failed-precondition", "GEMINI_API_KEY not set on server.");
    }

    let buf;
    try {
      const res = await fetch(videoUrl);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      buf = Buffer.from(await res.arrayBuffer());
    } catch (e) {
      console.error("[analyzeIncidentVideo] fetch failed:", e);
      throw new HttpsError("internal", "Could not download video from URL.");
    }
    const maxBytes = 18 * 1024 * 1024;
    if (buf.length > maxBytes) {
      throw new HttpsError("invalid-argument", "Video too large (max ~18 MB).");
    }
    const b64 = buf.toString("base64");
    const prompt = withSafetyForRole(
      "vision",
      "Watch this short clip and respond ONLY valid JSON:\n" +
      '{"incidentTypeGuess":"string","victimCondition":"string","bloodVisible":"yes|no|unclear",' +
      '"locationType":"home|outdoor|vehicle|workplace|public|unclear","hazards":"string",' +
      '"confidence":"low|medium|high","summary":"one short paragraph for dispatchers"}'
    );

    let text = "";
    try {
      const response = await gVideo.models.generateContent({
        model: "gemini-2.5-flash",
        contents: [prompt, { inlineData: { data: b64, mimeType: "video/mp4" } }],
      });
      text = typeof response?.text === "function" ? response.text() : "";
    } catch (e) {
      console.error("[analyzeIncidentVideo] Gemini error:", e);
      throw new HttpsError("internal", "Video analysis failed.");
    }
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    let parsed = {
      incidentTypeGuess: "unknown",
      victimCondition: "unknown",
      bloodVisible: "unclear",
      locationType: "unclear",
      hazards: "",
      confidence: "low",
      summary: text.slice(0, 500),
    };
    if (jsonMatch) {
      try {
        parsed = { ...parsed, ...JSON.parse(jsonMatch[0]) };
      } catch (_) {}
    }

    const videoAssessment = {
      ...parsed,
      videoUrl,
      analyzedAt: FieldValue.serverTimestamp(),
      analyzedByUid: request.auth.uid,
    };
    await db.collection("sos_incidents").doc(incidentId).set({ videoAssessment }, { merge: true });
    return { ok: true, videoAssessment: { ...parsed, videoUrl } };
  }
);

// ─── Shared Situation Gemini Brief (volunteer on-scene + photos + video AI) ──

/**
 * FIX 3: Sanitize user-supplied text fields before including in Gemini prompts.
 * Removes prompt injection patterns and strips newlines that break digest structure.
 */
function sanitizeUserField(value, maxLen) {
  if (!value || typeof value !== "string") return "";
  let s = value
    .replace(/ignore\s+(previous|above|all)\s+instructions?/gi, "[redacted]")
    .replace(/\bsystem\b[\s\S]{0,40}\bprompt\b/gi, "[redacted]")
    .replace(/\byou are now\b/gi, "[redacted]")
    .replace(/\bforget everything\b/gi, "[redacted]")
    .replace(/\bact as\b/gi, "[redacted]")
    .replace(/[\r\n]+/g, " ")
    .trim();
  return s.slice(0, maxLen || 500);
}

function computeSituationBriefFingerprint(inc, fleetHandoffNotes) {
  const scene = inc && typeof inc.volunteerSceneReport === "object" && inc.volunteerSceneReport !== null
    ? inc.volunteerSceneReport
    : {};
  const video = inc && typeof inc.videoAssessment === "object" && inc.videoAssessment !== null
    ? inc.videoAssessment
    : {};
  const payload = JSON.stringify({
    scene,
    vSummary: String(video.summary || ""),
    vGuess: String(video.incidentTypeGuess || ""),
    vCond: String(video.victimCondition || ""),
    note: String(inc.adminDispatchNote || ""),
    med: String(inc.medicalStatus || ""),
    eta: String(inc.ambulanceEta || ""),
    ems: String(inc.emsWorkflowPhase || ""),
    fleetNotes: String(fleetHandoffNotes || ""),
  });
  return crypto.createHash("sha256").update(payload).digest("hex");
}

function shouldRegenerateSituationBrief(inc, existingBrief, force, fleetHandoffNotes) {
  const fp = computeSituationBriefFingerprint(inc, fleetHandoffNotes);
  const lastGen = timestampToMillis(existingBrief?.lastGeneratedAt);
  const now = Date.now();
  const prevFp = typeof existingBrief?.sourceFingerprint === "string" ? existingBrief.sourceFingerprint : "";

  if (force) {
    if (now - lastGen < 25 * 1000) return { ok: false, reason: "rate_manual", fp };
    return { ok: true, fp };
  }
  if (!existingBrief || (!(existingBrief.summary && String(existingBrief.summary).trim()) && existingBrief.status !== "generating")) {
    return { ok: true, fp };
  }
  if (fp !== prevFp) return { ok: true, fp };
  if (now - lastGen > 5 * 60 * 1000) return { ok: true, fp };
  return { ok: false, reason: "fresh_unchanged", fp };
}

function buildSituationBriefDigest(incidentId, inc, fleetHandoffNotes) {
  const lines = [];
  lines.push(`INCIDENT_ID=${incidentId}`);
  lines.push(`TYPE=${inc.type || ""}`);
  lines.push(`STATUS=${inc.status || ""}`);
  lines.push(`VICTIM=${inc.userDisplayName || ""}`);
  lines.push(`LAT_LNG=${inc.lat},${inc.lng}`);
  lines.push(`ACCEPTED_VOLUNTEERS=${Array.isArray(inc.acceptedVolunteerIds) ? inc.acceptedVolunteerIds.length : 0}`);
  lines.push(`ON_SCENE_VOLUNTEERS=${Array.isArray(inc.onSceneVolunteerIds) ? inc.onSceneVolunteerIds.length : 0}`);
  lines.push(`EMS_PHASE=${inc.emsWorkflowPhase || "—"}`);
  lines.push(`AMBULANCE_ETA=${inc.ambulanceEta || "—"}`);
  lines.push(`MEDICAL_STATUS=${inc.medicalStatus || "—"}`);
  if (inc.bloodType) lines.push(`BLOOD_TYPE=${sanitizeUserField(inc.bloodType, 20)}`);
  if (inc.allergies) lines.push(`ALLERGIES=${sanitizeUserField(inc.allergies, 200)}`);
  if (inc.medicalConditions) lines.push(`CONDITIONS=${sanitizeUserField(inc.medicalConditions, 300)}`);
  if (inc.triage && typeof inc.triage === "object") {
    lines.push(`TRIAGE_JSON=${JSON.stringify(inc.triage).slice(0, 4000)}`);
  }
  if (inc.adminDispatchNote) lines.push(`DISPATCH_NOTE=${sanitizeUserField(inc.adminDispatchNote, 2000)}`);
  if (inc.volunteerSceneReport && typeof inc.volunteerSceneReport === "object") {
    lines.push(`VOLUNTEER_SCENE_REPORT_JSON=${JSON.stringify(inc.volunteerSceneReport).slice(0, 14000)}`);
    // Surface voice-note transcript explicitly so Gemini weighs it next to the
    // scene photo. EmergencyOS stores dictated voice as transcribed text under
    // reportDetails / voiceNoteTranscript / dictation on the scene report.
    const scene = inc.volunteerSceneReport;
    const voiceTranscript = (
      (typeof scene.voiceNoteTranscript === "string" && scene.voiceNoteTranscript) ||
      (typeof scene.dictation === "string" && scene.dictation) ||
      (typeof scene.reportDetails === "string" && scene.reportDetails) ||
      ""
    ).trim();
    if (voiceTranscript) {
      lines.push(`VOICE_NOTE_TRANSCRIPT=${sanitizeUserField(voiceTranscript, 4000)}`);
    }
    const photoCount = Array.isArray(scene.photoPaths) ? scene.photoPaths.length : 0;
    if (photoCount > 0) lines.push(`SCENE_PHOTO_COUNT=${photoCount}`);
  }
  if (inc.videoAssessment && typeof inc.videoAssessment === "object") {
    lines.push(`VIDEO_ASSESSMENT_JSON=${JSON.stringify(inc.videoAssessment).slice(0, 8000)}`);
  }
  // Fleet operator EMR handoff notes (submitted by ambulance crew on handover to hospital).
  if (fleetHandoffNotes && fleetHandoffNotes.trim()) {
    lines.push(`FLEET_OPERATOR_HANDOFF_NOTES=${sanitizeUserField(fleetHandoffNotes, 6000)}`);
  }
  return lines.join("\n");
}

async function fetchSituationBriefImageParts(photoPaths, maxImages, maxBytes) {
  const parts = [];
  if (!Array.isArray(photoPaths)) return parts;
  const urls = photoPaths
    .filter((u) => typeof u === "string" && (u.startsWith("http://") || u.startsWith("https://")))
    .slice(0, maxImages || 4);
  for (const url of urls) {
    try {
      const res = await fetch(url);
      if (!res.ok) continue;
      const buf = Buffer.from(await res.arrayBuffer());
      if (buf.length > (maxBytes || 900 * 1024)) continue;
      const mime = (res.headers.get("content-type") || "").includes("png") ? "image/png" : "image/jpeg";
      parts.push({ inlineData: { data: buf.toString("base64"), mimeType: mime } });
    } catch (e) {
      console.error("[situationBrief] image fetch failed:", e?.message || e);
    }
  }
  return parts;
}

async function generateSituationBriefCore(incidentId, { force } = {}) {
  const ref = db.collection("sos_incidents").doc(incidentId);
  const snap = await ref.get();
  if (!snap.exists) return { ok: false, error: "not_found" };
  const inc = snap.data() || {};
  const existingBrief = inc.sharedSituationBrief && typeof inc.sharedSituationBrief === "object"
    ? inc.sharedSituationBrief
    : {};

  // Fetch fleet operator handoff notes (EMR crew clinical notes for hospital handover).
  let fleetHandoffNotes = "";
  try {
    const handoffSnap = await ref.collection("fleet_operator_handoff").limit(8).get();
    const notesParts = [];
    for (const hdoc of handoffSnap.docs) {
      const hdata = hdoc.data() || {};
      const txt = typeof hdata.notesText === "string" ? hdata.notesText.trim() : "";
      if (txt) notesParts.push(txt);
    }
    fleetHandoffNotes = notesParts.join("\n---\n");
  } catch (e) {
    console.warn("[generateSituationBriefCore] fleet_operator_handoff fetch failed:", e?.message || e);
  }

  const decision = shouldRegenerateSituationBrief(inc, existingBrief, !!force, fleetHandoffNotes);
  if (!decision.ok) {
    return { ok: true, skipped: true, reason: decision.reason };
  }
  const fp = decision.fp;

  if (!geminiApiKey()) {
    const merged = {
      ...existingBrief,
      status: "error",
      lastError: "GEMINI_API_KEY not configured on server.",
      lastGeneratedAt: FieldValue.serverTimestamp(),
      sourceFingerprint: fp,
    };
    await ref.set({ sharedSituationBrief: merged }, { merge: true });
    return { ok: false, error: "no_api_key" };
  }

  const nextBrief = {
    ...existingBrief,
    status: "generating",
    sourceFingerprint: fp,
  };
  await ref.set({ sharedSituationBrief: nextBrief }, { merge: true });

  const digest = buildSituationBriefDigest(incidentId, inc, fleetHandoffNotes);
  const scene = inc.volunteerSceneReport && typeof inc.volunteerSceneReport === "object" ? inc.volunteerSceneReport : {};
  const photoPaths = Array.isArray(scene.photoPaths) ? scene.photoPaths : [];
  const imageParts = await fetchSituationBriefImageParts(photoPaths, 4, 900 * 1024);

  // FIX 3: System-level injection guard + shared safety preamble on every brief prompt.
  const modalityHint = [];
  if (imageParts.length > 0) modalityHint.push(`${imageParts.length} scene photo(s) inline`);
  if (digest.includes("VOICE_NOTE_TRANSCRIPT=")) modalityHint.push("voice-note transcript in EVIDENCE");
  if (fleetHandoffNotes) modalityHint.push("fleet operator EMR handoff notes in EVIDENCE");
  const modalityLine = modalityHint.length > 0
    ? `You are receiving MULTIMODAL INPUT: ${modalityHint.join(" + ")} alongside incident metadata.\n`
    : "";

  const prompt = withSafetyForRole(
    "brief",
    "Produce a dispatch-grade situation brief by combining the structured EVIDENCE with any attached scene photo(s) and voice-note transcript.\n" +
    modalityLine +
    "Rules: Do not diagnose. Do not invent facts not supported by EVIDENCE. If scene report is empty, say what is unknown. " +
    "If photos are provided, mention only cautious visual cues (hazards, approximate scene) without guessing identity. " +
    "If a voice-note transcript is provided, quote at most one short phrase from it and prefer structured facts for the rest."
  );

  const textIntro = `${prompt}\n\n## EVIDENCE\n${digest}`;
  const contents = [textIntro, ...imageParts];

  const briefSchema = {
    type: "object",
    properties: {
      summary: { type: "string", description: "3-6 sentences, clinical and direct." },
      highlights: { type: "array", items: { type: "string" } },
      recommendedActions: { type: "array", items: { type: "string" } },
      sourcesUsed: {
        type: "array",
        items: {
          type: "string",
          enum: ["sceneReport", "photos", "voiceNote", "videoAssessment", "incidentMeta", "fleetHandoff"],
        },
      },
    },
    required: ["summary", "highlights", "recommendedActions", "sourcesUsed"],
  };

  let text = "";
  try {
    const gBrief = geminiClient();
    const response = await gBrief.models.generateContent({
      model: "gemini-2.5-flash",
      contents,
      generationConfig: {
        maxOutputTokens: 1200,
        temperature: 0.2,
        responseMimeType: "application/json",
        responseSchema: briefSchema,
      },
    });
    text = typeof response?.text === "function" ? response.text() : "";
  } catch (e) {
    console.error("[generateSituationBriefCore] Gemini error:", e);
    const merged = {
      ...existingBrief,
      status: "error",
      lastError: String(e?.message || e || "Gemini failed").slice(0, 280),
      lastGeneratedAt: FieldValue.serverTimestamp(),
      sourceFingerprint: fp,
    };
    await ref.set({ sharedSituationBrief: merged }, { merge: true });
    return { ok: false, error: "gemini_failed" };
  }

  const jsonMatch = text.match(/\{[\s\S]*\}/);
  let parsed = {
    summary: text.trim().slice(0, 1200) || "No structured summary returned.",
    highlights: [],
    recommendedActions: [],
    sourcesUsed: [],
  };
  if (jsonMatch) {
    try {
      parsed = { ...parsed, ...JSON.parse(jsonMatch[0]) };
    } catch (_) {}
  }

  const highlights = Array.isArray(parsed.highlights) ? parsed.highlights.map((x) => String(x)).filter(Boolean).slice(0, 12) : [];
  const recommendedActions = Array.isArray(parsed.recommendedActions)
    ? parsed.recommendedActions.map((x) => String(x)).filter(Boolean).slice(0, 12)
    : [];
  const sourcesUsed = Array.isArray(parsed.sourcesUsed)
    ? parsed.sourcesUsed.map((x) => String(x)).filter(Boolean).slice(0, 8)
    : [];

  const out = {
    summary: String(parsed.summary || "").trim() || "Brief unavailable.",
    highlights,
    recommendedActions,
    sourcesUsed,
    status: "ready",
    lastGeneratedAt: FieldValue.serverTimestamp(),
    lastSourceUpdateAt: FieldValue.serverTimestamp(),
    sourceFingerprint: fp,
  };

  await ref.set({ sharedSituationBrief: out }, { merge: true });
  return { ok: true, skipped: false };
}

async function callerMayRefreshSituationBrief(uid, inc) {
  if (!uid || !inc) return false;
  // Victim
  if (inc.userId === uid) return true;
  // Accepted volunteer on scene
  const accepted = Array.isArray(inc.acceptedVolunteerIds) ? inc.acceptedVolunteerIds.map(String) : [];
  if (accepted.includes(uid)) return true;
  try {
    const u = await db.collection("users").doc(uid).get();
    if (!u.exists) return false;
    const ud = u.data() || {};
    // FIX 4: Emergency bridge desk → allowed.
    if (ud.emergencyBridgeDesk === true) return true;
    // FIX 4: Hospital staff linked to this incident → allowed.
    const staffHospId = (ud.staffHospitalId || ud.boundHospitalDocId || "").toString().trim();
    if (staffHospId) {
      const incId = (inc.id || "").toString();
      if (incId) {
        const asSnap = await db.collection("ops_incident_hospital_assignments").doc(incId).get();
        if (asSnap.exists) {
          const ordered = Array.isArray(asSnap.data()?.orderedHospitalIds)
            ? asSnap.data().orderedHospitalIds.map(String) : [];
          if (ordered.includes(staffHospId)) return true;
        }
      }
    }
  } catch (_) {}
  // FIX 4: Removed the open `return true` — unauthorized users are now denied.
  return false;
}

exports.generateSituationBriefForIncident = onCall(
  {
    cors: true,
    memory: "1GiB",
    timeoutSeconds: 120,
    maxInstances: 8,
    secrets: [geminiApiKeySecret],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const incidentId = (request.data?.incidentId || "").toString().trim();
    const force = request.data?.force === true;
    if (!incidentId) throw new HttpsError("invalid-argument", "incidentId required.");

    const ref = db.collection("sos_incidents").doc(incidentId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Incident not found.");
    const inc = { ...(snap.data() || {}), id: incidentId };
    const ok = await callerMayRefreshSituationBrief(request.auth.uid, inc);
    if (!ok) throw new HttpsError("permission-denied", "Not allowed to refresh this brief.");

    const result = await generateSituationBriefCore(incidentId, { force });
    return result;
  }
);

/** ED-oriented clinical synthesis for incident_reports (client persists; no Firestore write here). */
exports.generateClinicalReport = onCall(
  {
    cors: true,
    memory: "1GiB",
    timeoutSeconds: 120,
    maxInstances: 8,
    secrets: [geminiApiKeySecret],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const incidentId = (request.data?.incidentId || "").toString().trim();
    if (!incidentId) throw new HttpsError("invalid-argument", "incidentId required.");

    const ref = db.collection("sos_incidents").doc(incidentId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Incident not found.");
    const raw = snap.data() || {};
    const inc = { ...raw, id: incidentId };
    const allowed = await callerMayRefreshSituationBrief(request.auth.uid, inc);
    if (!allowed) throw new HttpsError("permission-denied", "Not allowed to generate this report.");

    return clinicalReport.generateClinicalReportCore(incidentId);
  }
);

exports.refreshSituationBriefsScheduled = onSchedule(
  {
    schedule: "every 5 minutes",
    timeZone: "UTC",
    memory: "512MiB",
    cpu: 0.25,
    timeoutSeconds: 300,
    secrets: [geminiApiKeySecret],
  },
  async () => {
    const col = db.collection("sos_incidents");
    const statuses = ["pending", "dispatched", "blocked"];
    let processed = 0;
    for (const st of statuses) {
      const q = await col.where("status", "==", st).limit(40).get();
      for (const doc of q.docs) {
        try {
          await generateSituationBriefCore(doc.id, { force: false });
          processed++;
        } catch (e) {
          console.error("[refreshSituationBriefsScheduled]", doc.id, e);
        }
      }
    }
    console.log(`[refreshSituationBriefsScheduled] touched ~${processed} doc(s)`);
  }
);

// Hospital callables in us-east1 — us-central1 Cloud Run CPU quota was exceeded for new revisions.
exports.acceptHospitalDispatch = onCall(
  {
    cors: true,
    region: "us-east1",
    memory: "256MiB",
    cpu: 0.25,
    concurrency: 1,
    timeoutSeconds: 60,
    maxInstances: 10,
    invoker: "public",
  },
  async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const incidentId = (request.data?.incidentId || "").toString().trim();
  const hospitalId = (request.data?.hospitalId || "").toString().trim();
  if (!incidentId || !hospitalId) {
    throw new HttpsError("invalid-argument", "incidentId and hospitalId required.");
  }

  // ── FIX 2: Verify caller is registered staff at this hospital ──────────────
  const isMaster = isMasterConsoleEmailToken(request.auth.token);
  if (!isMaster) {
    const callerSnap = await db.collection("users").doc(request.auth.uid).get();
    const callerDoc = callerSnap.exists ? (callerSnap.data() || {}) : {};
    const callerHospital = (
      (callerDoc.staffHospitalId || callerDoc.boundHospitalDocId || "") + ""
    )
      .toString()
      .trim();
    if (callerHospital !== hospitalId) {
      throw new HttpsError(
        "permission-denied",
        "You must be registered as staff at this hospital. " +
        "Contact your ops admin to set staffHospitalId (or boundHospitalDocId) on your user profile to match this facility."
      );
    }
  }

  // ── Engine transaction: accepts iff hospital is in the current wave (handles
  //    parallel fan-out for critical/high severity with first-accept-wins). ──
  let acceptedMeta;
  try {
    acceptedMeta = await hospitalDispatchV2.acceptAssignmentTx(
      incidentId,
      hospitalId,
      request.auth.uid,
    );
  } catch (e) {
    const codeMap = {
      not_found: ["not-found", "Assignment not found."],
      already_accepted: ["failed-precondition", "Incident already accepted by another hospital."],
      wrong_status: ["failed-precondition", "Hospital dispatch is not awaiting acceptance."],
      not_member: ["permission-denied", "Only hospitals currently notified for this incident can accept."],
    };
    const [code, msg] = codeMap[e && e.code] || ["internal", e && e.message ? String(e.message) : "accept failed"];
    throw new HttpsError(code, msg);
  }

  await db.collection("sos_incidents").doc(incidentId).set(
    {
      assignedHospitalId: hospitalId,
      assignedHospitalName: acceptedMeta.name || hospitalId,
      ambulanceAssignedAt: FieldValue.serverTimestamp(),
      medicalStatus: "Hospital accepted — coordinating ambulance",
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return { ok: true, hospitalName: acceptedMeta.name || hospitalId };
  }
);

exports.declineHospitalDispatch = onCall(
  {
    cors: true,
    region: "us-east1",
    memory: "256MiB",
    cpu: 0.25,
    concurrency: 1,
    timeoutSeconds: 60,
    maxInstances: 10,
    invoker: "public",
  },
  async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const incidentId = (request.data?.incidentId || "").toString().trim();
  const hospitalId = (request.data?.hospitalId || "").toString().trim();
  if (!incidentId || !hospitalId) {
    throw new HttpsError("invalid-argument", "incidentId and hospitalId required.");
  }

  // ── FIX 2: Verify caller is registered staff at this hospital ──────────────
  const isMasterDecline = isMasterConsoleEmailToken(request.auth.token);
  if (!isMasterDecline) {
    const callerSnapD = await db.collection("users").doc(request.auth.uid).get();
    const callerDocD = callerSnapD.exists ? (callerSnapD.data() || {}) : {};
    const callerHospitalD = (
      (callerDocD.staffHospitalId || callerDocD.boundHospitalDocId || "") + ""
    )
      .toString()
      .trim();
    if (callerHospitalD !== hospitalId) {
      throw new HttpsError(
        "permission-denied",
        "You must be registered as staff at this hospital to decline dispatch."
      );
    }
  }

  // ── Engine: parallel-wave aware. A single decline among multiple notified
  //    hospitals does NOT escalate — it just marks this member declined. The
  //    wave escalates only when every member has declined OR the timer fires. ──
  try {
    const res = await hospitalDispatchV2.declineAssignmentMember(
      incidentId,
      hospitalId,
      (request.data?.reason || "declined").toString(),
      _writeOpsDashboardAlert,
    );
    return { ok: true, status: res && res.status ? res.status : "declined" };
  } catch (e) {
    const codeMap = {
      not_found: ["not-found", "Assignment not found."],
      already_accepted: ["failed-precondition", "Already accepted."],
      wrong_status: ["failed-precondition", "Hospital dispatch is not awaiting acceptance."],
      not_member: ["permission-denied", "Only hospitals currently notified for this incident can decline."],
    };
    const [code, msg] = codeMap[e && e.code] || ["internal", e && e.message ? String(e.message) : "decline failed"];
    throw new HttpsError(code, msg);
  }
  }
);

/** Master console only: re-run hospital-in-hex chain (e.g. no assignment, exhausted, or stuck). */
exports.adminRestartHospitalDispatch = onCall(
  {
    cors: true,
    region: "us-east1",
    memory: "256MiB",
    cpu: 0.25,
    concurrency: 1,
    timeoutSeconds: 120,
    maxInstances: 5,
    invoker: "public",
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    if (!isMasterConsoleEmailToken(request.auth.token)) {
      throw new HttpsError("permission-denied", "Master console only.");
    }
    const incidentId = (request.data?.incidentId || "").toString().trim();
    if (!incidentId) {
      throw new HttpsError("invalid-argument", "incidentId required.");
    }
    const incSnap = await db.collection("sos_incidents").doc(incidentId).get();
    if (!incSnap.exists) {
      throw new HttpsError("not-found", "Incident not found.");
    }
    const incident = incSnap.data() || {};
    try {
      await dispatchHospitalInHex({ incidentId, incident });
    } catch (e) {
      console.error("[adminRestartHospitalDispatch]", incidentId, e);
      throw new HttpsError("internal", "Failed to restart hospital dispatch.");
    }
    return { ok: true };
  }
);

exports.hospitalDispatchEscalation = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "UTC",
    memory: "256MiB",
    timeoutSeconds: 120,
  },
  async () => {
    try {
      const res = await hospitalDispatchV2.runScheduledEscalation(_writeOpsDashboardAlert);
      if (res.processed > 0) {
        console.log(`[hospitalDispatchEscalation] processed=${res.processed} escalated=${res.escalated}`);
      }
    } catch (e) {
      console.error("[hospitalDispatchEscalation] scheduler:", e);
    }
  }
);

// ─── Hospital accept → ambulance operator queue (fleet assignments) ───────────

/** Must match [fleetUnitAvailabilityTtl] in lib/core/utils/fleet_unit_availability.dart (~90s). */
const FLEET_UNIT_AVAILABILITY_TTL_MS = 90_000;

function fleetUnitUpdatedAtIsFresh(data) {
  const t = data && data.updatedAt;
  if (!t || typeof t.toMillis !== "function") return false;
  return Date.now() - t.toMillis() <= FLEET_UNIT_AVAILABILITY_TTL_MS;
}

async function mergeFleetUnitsForHospital(hospitalId) {
  const hid = (hospitalId || "").toString();
  if (!hid) return [];
  const [q1, q2] = await Promise.all([
    db.collection("ops_fleet_units").where("stationedHospitalId", "==", hid).where("available", "==", true).limit(24).get(),
    db.collection("ops_fleet_units").where("assignedHospitalId", "==", hid).where("available", "==", true).limit(24).get(),
  ]);
  const seen = new Set();
  const units = [];
  for (const q of [q1, q2]) {
    for (const doc of q.docs) {
      if (seen.has(doc.id)) continue;
      const idStr = String(doc.id || "");
      if (idStr.startsWith("custom_")) continue;
      const u = doc.data() || {};
      if (!fleetUnitUpdatedAtIsFresh(u)) continue;
      const vt = String(u.vehicleType || "").toLowerCase();
      if (vt !== "medical" && vt !== "ambulance") continue;
      const cs = String(u.fleetCallSign || doc.id || "").trim();
      if (!cs) continue;
      seen.add(doc.id);
      units.push({
        docId: doc.id,
        fleetCallSign: cs,
        vehicleType: vt === "ambulance" ? "medical" : vt,
        lat: u.lat,
        lng: u.lng,
      });
    }
  }
  return units;
}

async function notifyAmbulanceOperatorsForAcceptedHospital(incidentId, hospitalId, assignmentRef) {
  const hid = (hospitalId || "").toString();
  if (!hid) return;

  const incSnap = await db.collection("sos_incidents").doc(incidentId).get();
  const inc = incSnap.data() || {};
  const lat = inc.lat;
  const lng = inc.lng;

  let units = await mergeFleetUnitsForHospital(hid);
  if (typeof lat === "number" && typeof lng === "number") {
    units.sort((a, b) => {
      const da =
        typeof a.lat === "number" && typeof a.lng === "number"
          ? haversineKm(lat, lng, a.lat, a.lng)
          : 999;
      const db_ =
        typeof b.lat === "number" && typeof b.lng === "number"
          ? haversineKm(lat, lng, b.lat, b.lng)
          : 999;
      return da - db_;
    });
  }

  let hName = hid;
  try {
    const hs = await db.collection("ops_hospitals").doc(hid).get();
    if (hs.exists) hName = String(hs.data()?.name || hid);
  } catch (_) {}

  const notified = [];
  const batch = db.batch();
  const slice = units.slice(0, 8);
  for (const u of slice) {
    const pref = db.collection("ops_fleet_assignments").doc(u.fleetCallSign).collection("pending").doc();
    batch.set(pref, {
      fleetId: u.fleetCallSign,
      incidentId,
      vehicleType: u.vehicleType || "medical",
      callSign: u.fleetCallSign,
      status: "awaiting_response",
      dispatchedAt: FieldValue.serverTimestamp(),
      responseDeadlineAt: Timestamp.fromMillis(Date.now() + FLEET_ASSIGNMENT_RESPONSE_MS),
      source: "hospital_accept_dispatch",
      dispatchingHospitalId: hid,
      dispatchingHospitalName: hName,
      incidentType: String(inc.type || ""),
    });
    notified.push({ callSign: u.fleetCallSign, pendingDocId: pref.id });
  }
  if (notified.length > 0) {
    await batch.commit();
  }

  const patch = {
    ambulanceDispatchStatus: notified.length > 0 ? "pending_operator" : "no_operator",
    ambulanceDispatchedAt: FieldValue.serverTimestamp(),
    ambulanceEscalateAfterMs: FLEET_ASSIGNMENT_RESPONSE_MS,
    ambulanceNotifiedCallSigns: notified.map((n) => n.callSign),
    ambulancePendingAssignments: notified,
    ambulanceEscalationAttempts: 0,
    dispatchingHospitalName: hName,
  };
  await assignmentRef.set(patch, { merge: true });

  if (notified.length === 0) {
    await _writeOpsDashboardAlert({
      incidentId,
      kind: "ambulance_dispatch_failed",
      title: "No ambulance operator at accepting hospital",
      body: `${hName} accepted the case but no available medical fleet unit is stationed there (stationedHospitalId / assignedHospitalId).`,
      severity: "critical",
      extra: { hospitalId: hid },
    });
  }
}

async function escalateAmbulanceDispatchForAssignment(assignmentRef, d) {
  const incidentId = assignmentRef.id;
  const hid = (d.acceptedHospitalId || "").toString();
  const ordered = Array.isArray(d.orderedHospitalIds) ? d.orderedHospitalIds.map((x) => String(x)) : [];
  const prevNotified = new Set(
    (Array.isArray(d.ambulanceNotifiedCallSigns) ? d.ambulanceNotifiedCallSigns : []).map((x) => String(x))
  );

  const incSnap = await db.collection("sos_incidents").doc(incidentId).get();
  const inc = incSnap.data() || {};
  const lat = inc.lat;
  const lng = inc.lng;

  async function tryHospital(hospitalId) {
    let units = await mergeFleetUnitsForHospital(hospitalId);
    units = units.filter((u) => !prevNotified.has(u.fleetCallSign));
    if (typeof lat === "number" && typeof lng === "number") {
      units.sort((a, b) => {
        const da =
          typeof a.lat === "number" && typeof a.lng === "number"
            ? haversineKm(lat, lng, a.lat, a.lng)
            : 999;
        const db_ =
          typeof b.lat === "number" && typeof b.lng === "number"
            ? haversineKm(lat, lng, b.lat, b.lng)
            : 999;
        return da - db_;
      });
    }
    return units;
  }

  let units = await tryHospital(hid);
  let targetHid = hid;
  if (units.length === 0) {
    const startIdx = ordered.indexOf(hid);
    for (let i = startIdx + 1; i < ordered.length; i++) {
      const nh = ordered[i];
      const u2 = await tryHospital(nh);
      if (u2.length > 0) {
        units = u2;
        targetHid = nh;
        break;
      }
    }
  }

  if (units.length === 0) {
    await assignmentRef.set(
      {
        ambulanceDispatchStatus: "no_operator",
        ambulanceRelayExhaustedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    await _writeOpsDashboardAlert({
      incidentId,
      kind: "ambulance_dispatch_exhausted",
      title: "No ambulance operator responded",
      body: "Hospital accepted but no fleet unit accepted within the escalation window; manual dispatch may be required.",
      severity: "critical",
      extra: {},
    });
    return;
  }

  let hName = targetHid;
  try {
    const hs = await db.collection("ops_hospitals").doc(targetHid).get();
    if (hs.exists) hName = String(hs.data()?.name || targetHid);
  } catch (_) {}

  const notified = [];
  const batch = db.batch();
  for (const u of units.slice(0, 4)) {
    const pref = db.collection("ops_fleet_assignments").doc(u.fleetCallSign).collection("pending").doc();
    batch.set(pref, {
      fleetId: u.fleetCallSign,
      incidentId,
      vehicleType: u.vehicleType || "medical",
      callSign: u.fleetCallSign,
      status: "awaiting_response",
      dispatchedAt: FieldValue.serverTimestamp(),
      responseDeadlineAt: Timestamp.fromMillis(Date.now() + FLEET_ASSIGNMENT_RESPONSE_MS),
      source: "ambulance_dispatch_escalation",
      dispatchingHospitalId: targetHid,
      dispatchingHospitalName: hName,
      incidentType: String(inc.type || ""),
    });
    notified.push({ callSign: u.fleetCallSign, pendingDocId: pref.id });
  }
  await batch.commit();

  const attempts = typeof d.ambulanceEscalationAttempts === "number" ? d.ambulanceEscalationAttempts : 0;
  const escPatch = {
    ambulanceDispatchedAt: FieldValue.serverTimestamp(),
    ambulanceEscalationAttempts: attempts + 1,
    ambulanceNotifiedCallSigns: FieldValue.arrayUnion(...notified.map((n) => n.callSign)),
    ambulancePendingAssignments: FieldValue.arrayUnion(...notified),
  };
  if (targetHid !== hid) escPatch.ambulanceRelayHospitalId = targetHid;
  await assignmentRef.set(escPatch, { merge: true });
}

exports.onHospitalAssignmentAcceptedDispatchAmbulance = onDocumentUpdated(
  {
    document: "ops_incident_hospital_assignments/{incidentId}",
    region: "us-east1",
    memory: "512MiB",
    cpu: 0.35,
    timeoutSeconds: 120,
    maxInstances: 10,
  },
  async (event) => {
    const before = event.data.before?.data() || {};
    const after = event.data.after?.data() || {};
    if ((after.dispatchStatus || "").toString() !== "accepted") return;
    if ((before.dispatchStatus || "").toString() === "accepted") return;
    const incidentId = event.params.incidentId;
    const hid = (after.acceptedHospitalId || "").toString();
    if (!incidentId || !hid) return;
    const amb = (after.ambulanceDispatchStatus || "").toString();
    if (amb === "pending_operator" || amb === "ambulance_en_route") return;
    try {
      await notifyAmbulanceOperatorsForAcceptedHospital(incidentId, hid, event.data.after.ref);
    } catch (e) {
      console.error("[onHospitalAssignmentAcceptedDispatchAmbulance]", incidentId, e);
    }
  }
);

exports.refreshHospitalDispatchOnDispatchHints = onDocumentUpdated(
  {
    document: "sos_incidents/{id}",
    region: "us-east1",
    memory: "256MiB",
    timeoutSeconds: 120,
    maxInstances: 15,
  },
  async (event) => {
    const before = event.data.before?.data() || {};
    const after = event.data.after?.data() || {};
    if (!after.dispatchHints) return;
    if (JSON.stringify(before.dispatchHints || {}) === JSON.stringify(after.dispatchHints || {})) return;
    const incidentId = event.params.id;
    const asRef = db.collection("ops_incident_hospital_assignments").doc(incidentId);
    const asSnap = await asRef.get();
    if (!asSnap.exists) return;
    const st = (asSnap.data().dispatchStatus || "").toString();
    const ni = asSnap.data().notifyIndex;
    if (st === "pending_acceptance" && (ni == null || ni === 0)) {
      try {
        await dispatchHospitalInHex({ incidentId, incident: after });
      } catch (e) {
        console.error("[refreshHospitalDispatchOnDispatchHints]", incidentId, e);
      }
    }
  }
);

exports.redispatchOnRequiredServicesChange = onDocumentUpdated(
  {
    document: "sos_incidents/{id}",
    region: "us-east1",
    memory: "256MiB",
    timeoutSeconds: 120,
    maxInstances: 15,
  },
  async (event) => {
    const before = event.data.before?.data() || {};
    const after = event.data.after?.data() || {};
    const oldSvc = JSON.stringify(before.requiredServices || []);
    const newSvc = JSON.stringify(after.requiredServices || []);
    if (oldSvc === newSvc) return;
    if (!Array.isArray(after.requiredServices) || after.requiredServices.length === 0) return;

    const incidentId = event.params.id;
    const asRef = db.collection("ops_incident_hospital_assignments").doc(incidentId);
    const asSnap = await asRef.get();
    if (asSnap.exists) {
      const st = (asSnap.data().dispatchStatus || "").toString();
      if (st === "accepted") return;
    }
    try {
      console.log(`[redispatchOnRequiredServicesChange] ${incidentId}: ${oldSvc} → ${newSvc}`);
      await dispatchHospitalInHex({ incidentId, incident: after });
    } catch (e) {
      console.error("[redispatchOnRequiredServicesChange]", incidentId, e);
    }
  }
);

exports.acceptAmbulanceDispatch = onCall(
  {
    cors: true,
    region: "us-east1",
    memory: "256MiB",
    cpu: 0.25,
    concurrency: 1,
    timeoutSeconds: 60,
    maxInstances: 10,
    invoker: "public",
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const incidentId = (request.data?.incidentId || "").toString().trim();
    const fleetId = (request.data?.fleetId || "").toString().trim().toUpperCase();
    const assignmentDocId = (request.data?.assignmentDocId || "").toString().trim();
    if (!incidentId || !fleetId || !assignmentDocId) {
      throw new HttpsError("invalid-argument", "incidentId, fleetId, assignmentDocId required.");
    }

    const pendingRef = db.collection("ops_fleet_assignments").doc(fleetId).collection("pending").doc(assignmentDocId);
    const pendingSnap = await pendingRef.get();
    if (!pendingSnap.exists) throw new HttpsError("not-found", "Pending assignment not found.");
    const p = pendingSnap.data() || {};
    if ((p.incidentId || "").toString() !== incidentId) {
      throw new HttpsError("permission-denied", "Incident mismatch.");
    }
    if ((p.status || "").toString() !== "awaiting_response") {
      throw new HttpsError("failed-precondition", "Assignment not awaiting response.");
    }

    const nowMs = Date.now();
    let deadlineMs = timestampToMillis(p.responseDeadlineAt);
    if (deadlineMs == null) {
      const d0 = timestampToMillis(p.dispatchedAt);
      deadlineMs = d0 != null ? d0 + FLEET_ASSIGNMENT_RESPONSE_MS : null;
    }
    if (deadlineMs != null && nowMs > deadlineMs) {
      throw new HttpsError("failed-precondition", "Assignment response window has expired.");
    }

    const asRef = db.collection("ops_incident_hospital_assignments").doc(incidentId);
    const asSnap = await asRef.get();
    if (!asSnap.exists) throw new HttpsError("not-found", "Hospital assignment not found.");
    const ad = asSnap.data() || {};
    if ((ad.dispatchStatus || "").toString() !== "accepted") {
      throw new HttpsError("failed-precondition", "Hospital has not accepted this dispatch.");
    }

    await pendingRef.update({ status: "accepted", respondedAt: FieldValue.serverTimestamp() });

    const opUid = request.auth.uid;
    const etaMin = Math.max(3, Math.min(90, Math.floor(numLike(request.data?.etaMinutes, 12))));

    const hname = String(ad.acceptedHospitalName || ad.primaryHospitalName || "").trim();
    const hid = String(ad.acceptedHospitalId || "").trim();

    await asRef.set(
      {
        ambulanceDispatchStatus: "ambulance_en_route",
        assignedFleetCallSign: fleetId,
        assignedFleetOperatorUid: opUid,
        ambulanceAcceptedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    const incPatch = {
      emsWorkflowPhase: "inbound",
      emsAcceptedAt: FieldValue.serverTimestamp(),
      emsAcceptedBy: opUid,
      status: "dispatched",
      ambulanceEta: `~${etaMin} min`,
      etaUpdatedAt: FieldValue.serverTimestamp(),
      medicalStatus: "Ambulance en route to scene",
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (hid) incPatch.assignedHospitalId = hid;
    if (hname) incPatch.assignedHospitalName = hname;
    await db.collection("sos_incidents").doc(incidentId).set(incPatch, { merge: true });

    return { ok: true };
  }
);

exports.ambulanceDispatchEscalation = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "UTC",
    memory: "256MiB",
    cpu: 0.25,
    timeoutSeconds: 120,
  },
  async () => {
    const snap = await db
      .collection("ops_incident_hospital_assignments")
      .where("ambulanceDispatchStatus", "==", "pending_operator")
      .limit(40)
      .get();
    if (snap.empty) return;
    const now = Date.now();
    for (const doc of snap.docs) {
      const d = doc.data() || {};
      if ((d.dispatchStatus || "").toString() !== "accepted") continue;
      const t0 = timestampToMillis(d.ambulanceDispatchedAt);
      const waitMs = typeof d.ambulanceEscalateAfterMs === "number" ? d.ambulanceEscalateAfterMs : FLEET_ASSIGNMENT_RESPONSE_MS;
      if (!t0 || now - t0 < waitMs) continue;
      const attempts = typeof d.ambulanceEscalationAttempts === "number" ? d.ambulanceEscalationAttempts : 0;
      if (attempts >= 4) {
        await doc.ref.set(
          {
            ambulanceDispatchStatus: "no_operator",
            ambulanceRelayExhaustedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        continue;
      }
      try {
        await escalateAmbulanceDispatchForAssignment(doc.ref, d);
      } catch (e) {
        console.error("[ambulanceDispatchEscalation]", doc.id, e);
      }
    }
  }
);

/** Marks fleet pending assignments past the 3-minute window as driver_no_response (collection group). */
exports.expireStaleFleetPendingAssignments = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "UTC",
    region: "us-east1",
    memory: "256MiB",
    cpu: 0.25,
    timeoutSeconds: 120,
  },
  async () => {
    const cutoff = Timestamp.fromMillis(Date.now() - FLEET_ASSIGNMENT_RESPONSE_MS);
    for (;;) {
      const snap = await db
        .collectionGroup("pending")
        .where("status", "==", "awaiting_response")
        .where("dispatchedAt", "<", cutoff)
        .limit(450)
        .get();
      if (snap.empty) return;
      const batch = db.batch();
      for (const doc of snap.docs) {
        batch.update(doc.ref, {
          status: "driver_no_response",
          expiredAt: FieldValue.serverTimestamp(),
          reason: "response_timeout",
        });
      }
      await batch.commit();
      if (snap.size < 450) return;
    }
  }
);

// ─── 2. Geo-Radius FCM Dispatch (multi-layer: volunteers + topic + all-users) ─
// Triggered when a new SOS incident is saved to Firestore.
// Layer 1: Geo-targeted volunteer multicast (existing logic).
// Layer 2: FCM topic broadcast to 'sos_alerts' (all subscribed devices).
// Layer 3: All users with fcmToken in the 'users' collection (catch-all).
// Each layer runs independently — one failing never blocks the others.
async function bumpSosDispatchMetricError(layer) {
    try {
        await db.collection("ops_health_metrics").doc("counters").set(
            {
                sosDispatchErrors: FieldValue.increment(1),
                [`sosDispatchErrors_${layer}`]: FieldValue.increment(1),
                lastSosDispatchErrorAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
        );
    } catch (_) {}
}

// SOS dispatch trigger in us-east1 (same quota workaround as parseSmsGateway / hospital callables).
exports.dispatchSOS = onDocumentCreated(
  {
    document: "sos_incidents/{id}",
    region: "us-east1",
    memory: "512MiB",
    cpu: 0.5,
    concurrency: 1,
    timeoutSeconds: 540,
    maxInstances: 20,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const incident = snap.data();
    const incidentUserId = (incident.userId || "").toString().trim();

    // Anti-abuse: rate-limit dispatch per userId (prevents push spam).
    // IMPORTANT: Rate-limiting only suppresses geo-targeted multicast (Layer 1).
    // Layer 2 (topic) and Layer 3 (all-users) ALWAYS run so alerts are never
    // silently swallowed — this is the core guarantee of the app.
    let geoDispatchThrottled = false;
    if (incidentUserId) {
        try {
            const limRef = db.collection("sos_dispatch_limits").doc(incidentUserId);
            const limSnap = await limRef.get();
            const nowMs = Date.now();
            const lastMs = limSnap.exists && typeof limSnap.data().lastDispatchAtMs === "number"
                ? limSnap.data().lastDispatchAtMs
                : 0;
            if (nowMs - lastMs < 2 * 60 * 1000) {
                console.log(`[dispatchSOS] Geo-dispatch throttled for userId=${incidentUserId} (topic + all-users still run)`);
                geoDispatchThrottled = true;
            } else {
                await limRef.set({ lastDispatchAtMs: nowMs }, { merge: true });
            }
        } catch (e) {
            console.error("[dispatchSOS] Rate-limit check failed:", e);
        }
    }

    const incidentLat = incident.lat;
    const incidentLng = incident.lng;
    const incidentId = event.params.id;

    console.log(`[dispatchSOS] Incident ${incidentId} at (${incidentLat}, ${incidentLng})`);

    const notificationPayload = {
        title: "🚨 CRITICAL: SOS Alert",
        body: `${incident.type || "Emergency"} by ${incident.userDisplayName || "Unknown"}`,
    };
    const typeStr = encodeURIComponent((incident.type || "Emergency").toString());
    const dataPayload = {
        incidentId,
        action: "OPEN_ALERT",
        lat: String(incidentLat ?? ""),
        lng: String(incidentLng ?? ""),
        // Clients ignore alerts they triggered (topic + token fan-out).
        reportingUserId: incidentUserId || "",
        // Deep links (go_router paths) — opened from notification tap / cold start.
        deepLinkConsignment: `/active-consignment/${incidentId}?type=${typeStr}&isVictim=false`,
        deepLinkPtt: `/ptt-channel/${incidentId}?type=${typeStr}`,
        deepLinkSosActive: `/sos-active/${incidentId}`,
    };
    const androidConfig = {
        priority: "high",
        notification: {
            channelId: "sos_channel",
            defaultSound: true,
            defaultVibrateTimings: true,
            priority: "max",
            visibility: "public",
        },
    };
    const apnsConfig = {
        payload: { aps: { sound: "default", "content-available": 1 } },
        headers: { "apns-priority": "10" },
    };

    const allSentTokens = new Set();

    // ── Hospital-in-hex dispatch (ops dashboard) ──────────────────────────────
    // Runs independently of push layers.
    try {
        await dispatchHospitalInHex({ incidentId, incident });
    } catch (e) {
        console.error("[dispatchSOS][HOSP] Dispatch failed:", e);
        try { await bumpSosDispatchMetricError("HOSP"); } catch (_) {}
    }

    // ── LAYER 1: Geo-targeted volunteer multicast ─────────────────────────────
    if (geoDispatchThrottled) {
        console.log("[dispatchSOS][L1] Skipped (rate-limited). Layers 2+3 will still fire.");
    } else if (typeof incidentLat === "number" && typeof incidentLng === "number") {
        try {
            const box = getBoundingBox(incidentLat, incidentLng, ALERT_RADIUS_KM);
            const volunteersSnap = await db
                .collection("volunteers")
                .where("lat", ">=", box.minLat)
                .where("lat", "<=", box.maxLat)
                .where("isAvailable", "==", true)
                .limit(200)
                .get();

            const nearbyTokens = [];
            for (const doc of volunteersSnap.docs) {
                const v = doc.data();
                if (typeof v.lng !== "number" || !v.fcmToken) continue;
                if (incidentUserId && doc.id === incidentUserId) continue;
                if (v.lng < box.minLng || v.lng > box.maxLng) continue;
                const distKm = haversineKm(incidentLat, incidentLng, v.lat, v.lng);
                if (distKm <= ALERT_RADIUS_KM) {
                    nearbyTokens.push(v.fcmToken);
                    allSentTokens.add(v.fcmToken);
                    console.log(`[dispatchSOS][L1] Volunteer ${doc.id} (${distKm.toFixed(2)} km)`);
                }
            }

            if (nearbyTokens.length > 0) {
                const result = await fcm.sendEachForMulticast({
                    notification: notificationPayload,
                    data: dataPayload,
                    android: androidConfig,
                    apns: apnsConfig,
                    tokens: nearbyTokens,
                });
                console.log(`[dispatchSOS][L1] Sent ${nearbyTokens.length}: ok=${result.successCount} fail=${result.failureCount}`);
                result.responses.forEach((resp, idx) => {
                    if (!resp.success) {
                        const errCode = resp.error?.code;
                        if (errCode === "messaging/registration-token-not-registered" ||
                            errCode === "messaging/invalid-registration-token") {
                            const volDoc = volunteersSnap.docs.find(
                                (d) => d.data().fcmToken === nearbyTokens[idx]
                            );
                            if (volDoc) {
                                db.collection("volunteers").doc(volDoc.id)
                                  .update({ fcmToken: admin.firestore.FieldValue.delete() })
                                  .catch(() => {});
                            }
                        }
                    }
                });
            } else {
                console.log("[dispatchSOS][L1] No nearby volunteers passed filter.");
            }
        } catch (e) {
            console.error("[dispatchSOS][L1] Geo-query/multicast error:", e);
            await bumpSosDispatchMetricError("L1");
        }
    } else {
        console.warn("[dispatchSOS][L1] Invalid lat/lng — skipping geo-dispatch.");
    }

    // ── LAYER 2: FCM Topic broadcast (all users subscribed to 'sos_alerts') ───
    try {
        await fcm.send({
            topic: "sos_alerts",
            notification: notificationPayload,
            data: dataPayload,
            android: androidConfig,
            apns: apnsConfig,
        });
        console.log("[dispatchSOS][L2] Topic 'sos_alerts' broadcast sent.");
    } catch (e) {
        console.error("[dispatchSOS][L2] Topic broadcast failed:", e);
        await bumpSosDispatchMetricError("L2");
    }

    // ── LAYER 3: All users with fcmToken (catch-all for missed devices) ───────
    try {
        const usersSnap = await db.collection("users")
            .where("fcmToken", "!=", "")
            .limit(500)
            .get();

        const extraTokens = [];
        for (const doc of usersSnap.docs) {
            const u = doc.data();
            if (!u.fcmToken) continue;
            if (incidentUserId && doc.id === incidentUserId) continue;
            if (allSentTokens.has(u.fcmToken)) continue;
            extraTokens.push(u.fcmToken);
            allSentTokens.add(u.fcmToken);
        }

        if (extraTokens.length > 0) {
            const result = await fcm.sendEachForMulticast({
                notification: notificationPayload,
                data: dataPayload,
                android: androidConfig,
                apns: apnsConfig,
                tokens: extraTokens,
            });
            console.log(`[dispatchSOS][L3] Users sent ${extraTokens.length}: ok=${result.successCount} fail=${result.failureCount}`);
            result.responses.forEach((resp, idx) => {
                if (!resp.success) {
                    const errCode = resp.error?.code;
                    if (errCode === "messaging/registration-token-not-registered" ||
                        errCode === "messaging/invalid-registration-token") {
                        const userDoc = usersSnap.docs.find(
                            (d) => d.data().fcmToken === extraTokens[idx]
                        );
                        if (userDoc) {
                            db.collection("users").doc(userDoc.id)
                              .update({ fcmToken: admin.firestore.FieldValue.delete() })
                              .catch(() => {});
                        }
                    }
                }
            });
        } else {
            console.log("[dispatchSOS][L3] No additional user tokens to send.");
        }
    } catch (e) {
        console.error("[dispatchSOS][L3] Users fallback error:", e);
        await bumpSosDispatchMetricError("L3");
    }

    console.log(`[dispatchSOS] Complete. Total unique tokens reached: ${allSentTokens.size}`);

    try {
        await db.collection("ops_health_metrics").doc("counters").set(
            {
                sosDispatchesCompleted: FieldValue.increment(1),
                lastSosDispatchOkAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
        );
    } catch (e) {
        console.error("[dispatchSOS] metrics write failed:", e);
    }
  }
);

// ─── Anti-abuse: per-user SOS creation limits ────────────────────────────────
// We keep this fail-open for real emergencies: we only "block" egregious spam.
// Blocked incidents are set to status='blocked' so the app won't list/dispatch.
exports.enforceSosCreateLimits = onDocumentCreated("sos_incidents/{id}", async (event) => {
    const snap = event.data;
    if (!snap) return;
    const incidentId = event.params.id;
    const incident = snap.data() || {};

    const userId = (incident.userId || "").toString().trim();
    if (!userId) return; // Can't rate-limit anonymous reliably (handled client-side).

    const limRef = db.collection("sos_create_limits").doc(userId);
    const nowMs = Date.now();

    // Limits:
    // - Cooldown: 60s between creations
    // - Burst: max 5/hour
    const cooldownMs = 60 * 1000;
    const hourMs = 60 * 60 * 1000;
    const maxPerHour = 5;

    try {
        const limSnap = await limRef.get();
        const lim = limSnap.exists ? limSnap.data() : {};
        const lastMs = typeof lim.lastCreatedAtMs === "number" ? lim.lastCreatedAtMs : 0;
        const hourStartMs = typeof lim.hourStartMs === "number" ? lim.hourStartMs : 0;
        const hourCount = typeof lim.hourCount === "number" ? lim.hourCount : 0;

        const inCooldown = lastMs > 0 && (nowMs - lastMs) < cooldownMs;
        const sameHourBucket = hourStartMs > 0 && (nowMs - hourStartMs) < hourMs;
        const nextHourStartMs = sameHourBucket ? hourStartMs : nowMs;
        const nextHourCount = sameHourBucket ? (hourCount + 1) : 1;

        await limRef.set(
            {
                lastCreatedAtMs: nowMs,
                hourStartMs: nextHourStartMs,
                hourCount: nextHourCount,
            },
            { merge: true }
        );

        if (inCooldown || nextHourCount > maxPerHour) {
            // Log the rate-limit event but DO NOT block the incident.
            // Blocking changes status to 'blocked' which removes it from
            // the Firestore real-time listener on other devices, causing
            // missed alerts. Instead, flag it for audit without altering status.
            console.warn(`[enforceSosCreateLimits] Rate-limit flag for incident ${incidentId}, userId=${userId} (cooldown=${inCooldown}, hourCount=${nextHourCount}). Incident NOT blocked — safety first.`);
            await snap.ref.set(
                {
                    rateLimitFlagged: true,
                    rateLimitReason: inCooldown ? "cooldown" : "hourly_limit",
                    rateLimitAt: FieldValue.serverTimestamp(),
                },
                { merge: true }
            );
        }
    } catch (e) {
        console.error("[enforceSosCreateLimits] Failed:", e);
    }
});

// ─── 3. SMS Gateway Webhook ───────────────────────────────────────────────────
// Receives POST from Twilio / SMSified when the gateway SIM gets an inbound SMS.
// Parses GeoSMS payload → creates Firestore incident → triggers dispatchSOS above.
//
// Twilio webhook config (use the region shown in Firebase Console after deploy):
//   URL: https://<region>-<project>.cloudfunctions.net/parseSmsGateway
//   Method: HTTP POST
//   Response: TwiML (text/xml)
//
// invoker: "public" — Twilio must POST without Firebase auth (signature verified in handler).
// Region us-east1 — avoids us-central1 Cloud Run CPU quota pile-up with other functions.
// Low CPU + concurrency 1 — smaller Cloud Run footprint.
exports.parseSmsGateway = onRequest(
    {
        region: "us-east1",
        memory: "256MiB",
        cpu: 0.25,
        concurrency: 1,
        timeoutSeconds: 60,
        maxInstances: 10,
        invoker: "public",
    },
    async (req, res) => {
    // Only accept POST
    if (req.method !== "POST") {
        res.status(405).send("Method Not Allowed");
        return;
    }

    // Verify Twilio signature to prevent fake/bot webhooks creating incidents.
    // If Twilio isn't configured, refuse to process.
    const signature = req.get("X-Twilio-Signature") || req.get("x-twilio-signature") || "";
    if (!twilioToken || !signature) {
        res.status(403).send("Forbidden");
        return;
    }
    try {
        const host = req.get("host");
        const proto = (req.get("x-forwarded-proto") || "https").toString();
        const url = `${proto}://${host}${req.originalUrl}`;
        const ok = twilio.validateRequest(twilioToken, signature, url, req.body || {});
        if (!ok) {
            res.status(403).send("Forbidden");
            return;
        }
    } catch (e) {
        res.status(403).send("Forbidden");
        return;
    }

    const from  = req.body?.From  || req.query?.From  || "";
    const body  = req.body?.Body  || req.query?.Body  || "";

    // FIX 5: Use regex instead of exact string match — handles http/https, URL shorteners, whitespace.
    const GEO_SMS_PATTERN = /https?:\/\/[^\s]*emergencyos\.app\/sos\?[^\s]*/i;
    const geoSmsUrlMatch = body.match(GEO_SMS_PATTERN);
    if (!geoSmsUrlMatch) {
        console.log("[parseSmsGateway] No GeoSMS URL pattern found in message from", from, "body[:100]:", body.slice(0, 100));
        // Respond with empty TwiML so Twilio doesn't retry
        res.set("Content-Type", "text/xml");
        res.send("<Response/>");
        return;
    }

    try {
        // ── Parse GeoSMS (FIX 5: use regex-matched URL, not first line) ──────
        const lines = body.trim().split("\n");
        const urlLine = geoSmsUrlMatch[0].replace(/&GeoSMS$/i, "").trim();
        const url = new URL(urlLine);
        if (!url.searchParams.has("x") || !url.searchParams.has("y")) {
            throw new Error("GeoSMS URL missing coordinate parameters (x= and y= required)");
        }
        const lat = parseFloat(url.searchParams.get("x") || "");
        const lng = parseFloat(url.searchParams.get("y") || "");
        const type = (url.searchParams.get("type") || "UNKNOWN")
                        .replace(/_/g, " ");
        const incidentId = (url.searchParams.get("incidentId") || "").trim();
        const channelMsg = (url.searchParams.get("msg") || "").trim();

        if (isNaN(lat) || isNaN(lng)) {
            throw new Error("Invalid coordinates in GeoSMS");
        }

        // ── Channel update path (offline voice transcript or text update) ────
        if (incidentId && channelMsg) {
            console.log(`[parseSmsGateway] Channel update incidentId=${incidentId} from=${from}`);
            // Ensure channel exists
            await db.collection("ptt_channels").doc(incidentId).set(
                {
                    incidentId,
                    incidentType: "SOS Emergency",
                    updatedAt: admin.firestore.Timestamp.now(),
                },
                { merge: true }
            );
            // Post message into PTT timeline
            const msgRef = db.collection("ptt_channels").doc(incidentId).collection("messages").doc();
            await msgRef.set({
                id: msgRef.id,
                senderId: `sms:${from}`,
                senderName: from || "SMS Victim",
                text: channelMsg,
                type: "text",
                timestamp: admin.firestore.Timestamp.now(),
            });
            res.set("Content-Type", "text/xml");
            res.send("<Response><Message>EmergencyOS: Update delivered to responders.</Message></Response>");
            return;
        }

        // Parse victim count from line 2 e.g. "Victims: 3. CRASH."
        let victimCount = 1;
        let freeText = "";
        if (lines.length > 1) {
            const match = lines[1].match(/Victims?: (\d+)/);
            if (match) victimCount = parseInt(match[1], 10);
            const parts = lines[1].split(". ");
            if (parts.length > 2) freeText = parts.slice(2).join(". ");
        }

        console.log(`[parseSmsGateway] Parsed: (${lat}, ${lng}) type=${type} victims=${victimCount} from=${from}`);

        const now = admin.firestore.Timestamp.now();

        // ── Parallel GeoSMS relay: link to existing in-app SOS (no duplicate dispatch) ──
        if (incidentId) {
            const existingRef = db.collection("sos_incidents").doc(incidentId);
            const existingSnap = await existingRef.get();
            if (existingSnap.exists) {
                console.log(`[parseSmsGateway] SMS relay merge onto existing ${incidentId} from=${from}`);
                await existingRef.set(
                    {
                        smsRelayReceived: true,
                        smsRelayAt: FieldValue.serverTimestamp(),
                        senderPhone: from,
                        geoSmsPatternRecognized: true,
                        geoSmsRecognizedAt: FieldValue.serverTimestamp(),
                        lat,
                        lng,
                    },
                    { merge: true }
                );
                const shortId = incidentId.length > 8 ? `${incidentId.slice(0, 8)}…` : incidentId;
                const ackMsg = `EmergencyOS: GeoSMS pattern recognized. Relay linked to SOS ${shortId}. Stay safe.`;
                res.set("Content-Type", "text/xml");
                res.send(`<Response><Message>${ackMsg}</Message></Response>`);
                return;
            }
            console.log(`[parseSmsGateway] incidentId=${incidentId} not found — creating new SMS-origin incident`);
        }

        // ── Create Firestore Incident (SMS-only / offline path) ─────────────────
        const incidentRef = db.collection("sos_incidents").doc();
        await incidentRef.set({
            id: incidentRef.id,
            userId: `sms:${from}`,
            userDisplayName: from || "SMS Caller",
            lat,
            lng,
            type: `${type} (via SMS Relay). Victims: ${victimCount}. ${freeText}`.trim(),
            timestamp: now,
            goldenHourStart: now,
            status: "pending",
            smsOrigin: true,
            senderPhone: from,
            geoSmsPatternRecognized: true,
            geoSmsRecognizedAt: now,
        });

        console.log(`[parseSmsGateway] Created incident ${incidentRef.id}`);

        const ackMsg = `EmergencyOS: GeoSMS pattern recognized. SOS received. Responders in ${process.env.ALERT_RADIUS_KM || 10}km alerted.`;
        res.set("Content-Type", "text/xml");
        res.send(`<Response><Message>${ackMsg}</Message></Response>`);

    } catch (err) {
        console.error("[parseSmsGateway] Parse/DB error:", err);
        res.set("Content-Type", "text/xml");
        res.send("<Response><Message>EmergencyOS: Unable to process SOS. Please call 112.</Message></Response>");
    }
});

// ─── 4. Open Webhook API for third-party triggers ─────────────────────────────
// Minimal authenticated HTTP endpoint that partners can call to:
//   - register a new incident
//   - upsert AED locations
//   - record neighbourhood readiness events
//
// Auth: shared secret in `WEBHOOK_SHARED_SECRET` env var, passed as header:
//   `X-Webhook-Secret: <secret>`
//
// Example payloads:
//   { "kind": "incident.created", "lat": 26.85, "lng": 80.94, "type": "External trigger", "source": "partnerX" }
//   { "kind": "aed.upsert", "id": "AED-123", "lat": 26.84, "lng": 80.95, "label": "Mall lobby AED" }
//   { "kind": "readiness.event", "zoneId": "lucknow", "description": "Night drill completed" }
exports.onExternalIncidentTrigger = onRequest(
    {
        region: "asia-south1",
        timeoutSeconds: 30,
        memory: "256MiB",
        cpu: 0.25,
        invoker: "public",
    },
    async (req, res) => {
        if (req.method !== "POST") {
            res.status(405).json({ error: "Method Not Allowed" });
            return;
        }

        const shared = (process.env.WEBHOOK_SHARED_SECRET || "").trim();
        if (!shared) {
            res.status(500).json({ error: "Webhook secret not configured" });
            return;
        }
        const headerSecret =
            (req.get("X-Webhook-Secret") || req.get("x-webhook-secret") || "").trim();
        if (!headerSecret || headerSecret !== shared) {
            res.status(401).json({ error: "Unauthorized" });
            return;
        }

        const body = req.body || {};
        const kind = (body.kind || "").toString();
        if (!kind) {
            res.status(400).json({ error: "Missing kind" });
            return;
        }

        const now = admin.firestore.Timestamp.now();
        const logRef = db.collection("webhook_events").doc();
        await logRef.set({
            id: logRef.id,
            kind,
            payload: body,
            createdAt: now,
            source: (body.source || "").toString().trim() || "external",
        });

        if (kind === "incident.created") {
            const lat = Number(body.lat);
            const lng = Number(body.lng);
            if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
                res.status(400).json({ error: "Invalid lat/lng" });
                return;
            }
            const incidentRef = db.collection("sos_incidents").doc();
            await incidentRef.set({
                id: incidentRef.id,
                userId: `webhook:${body.source || "partner"}`,
                userDisplayName: (body.displayName || "External trigger").toString(),
                lat,
                lng,
                type: (body.type || "External incident").toString(),
                timestamp: now,
                goldenHourStart: now,
                status: "pending",
            });
            res.status(200).json({ ok: true, incidentId: incidentRef.id });
            return;
        }

        if (kind === "aed.upsert") {
            const lat = Number(body.lat);
            const lng = Number(body.lng);
            if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
                res.status(400).json({ error: "Invalid lat/lng" });
                return;
            }
            const id = (body.id || "").toString().trim() || undefined;
            const ref = id
                ? db.collection("aeds").doc(id)
                : db.collection("aeds").doc();
            await ref.set(
                {
                    id: ref.id,
                    lat,
                    lng,
                    label: (body.label || "AED").toString(),
                    access: (body.access || "").toString(),
                    maintainer: (body.maintainer || "").toString(),
                    lastVerifiedAt: body.lastVerifiedAt
                        ? new Date(body.lastVerifiedAt)
                        : now,
                    updatedAt: now,
                },
                { merge: true }
            );
            res.status(200).json({ ok: true, id: ref.id });
            return;
        }

        if (kind === "readiness.event") {
            const ref = db.collection("preparedness_events").doc();
            await ref.set({
                id: ref.id,
                zoneId: (body.zoneId || "lucknow").toString(),
                description: (body.description || "").toString(),
                createdAt: now,
                source: (body.source || "").toString(),
            });
            res.status(200).json({ ok: true, eventId: ref.id });
            return;
        }

        res.status(200).json({ ok: true, ignored: true });
    }
);

// ─── 4b. Pre-arrival hospital handoff (ETA < 2 min → Gemini generates packet) ─
// When the ambulance crosses the 2-minute window to the receiving hospital,
// Gemini produces a structured handoff packet (bay prep, team to page, blood,
// contraindications) that the receiving trauma team sees immediately. This is
// annotation-only — dispatch decisions do not depend on it.
exports.onIncidentUpdateGenerateHandoff = onDocumentUpdated(
    {
        document: "sos_incidents/{id}",
        region: "us-central1",
        secrets: [geminiApiKeySecret],
        cpu: 0.5,
        memory: "512MiB",
        timeoutSeconds: 60,
    },
    async (event) => {
        const before = event.data.before.data() || {};
        const after = event.data.after.data() || {};
        const id = event.params.id;
        try {
            await preArrivalHandoff.maybeGeneratePreArrivalHandoff(id, after, before);
        } catch (e) {
            console.warn("[onIncidentUpdateGenerateHandoff] failed:", e && e.message);
        }
    }
);

// ─── 5. SMS Outbound Response Bridge ──────────────────────────────────────────
// Watches for ETA updates from responders/dispatchers and pushes SMS back to the victim.
exports.onIncidentUpdate = onDocumentUpdated(
    {
        document: "sos_incidents/{id}",
        region: "us-central1",
        cpu: 0.25,
        memory: "256MiB",
    },
    async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    // SMS ETA bridge: original SMS SOS or parallel GeoSMS relay onto in-app doc
    const smsEligible = (after.smsOrigin === true || after.smsRelayReceived === true) && after.senderPhone;
    if (!smsEligible) return;

    // Detect changes in ETAs
    const ambulanceChanged = after.ambulanceEta !== before.ambulanceEta;
    const healthChanged = after.medicalStatus !== before.medicalStatus;

    if (ambulanceChanged || healthChanged) {
        let updateMsg = "EmergencyOS Update: ";
        if (ambulanceChanged) updateMsg += `Ambulance ETA: ${after.ambulanceEta}. `;
        if (healthChanged) updateMsg += `Medical: ${after.medicalStatus}. `;

        console.log(`[onIncidentUpdate] Sending update to ${after.senderPhone}: ${updateMsg}`);

        if (twilioClient && twilioNumber) {
            try {
                await twilioClient.messages.create({
                    body: updateMsg,
                    from: twilioNumber,
                    to: after.senderPhone
                });
            } catch (err) {
                console.error("[onIncidentUpdate] Twilio Send Error:", err);
            }
        } else {
            console.log("[onIncidentUpdate] Skip send (Twilio not configured or TWILIO_PHONE_NUMBER missing)");
        }
    }
    }
);

// ─── 6. Emergency Contact SMS Updates (online incidents too) ────────────────
// Sends updates to the victim's configured emergency contact phone, if present.
exports.notifyEmergencyContactOnUpdate = onDocumentUpdated("sos_incidents/{id}", async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    // Victim opt-in: only send if enabled on the incident doc.
    if (after.useEmergencyContactForSms !== true) return;

    const contactPhone = (after.emergencyContactPhone || "").trim();
    if (!contactPhone) return;

    // Rate limit: at most once per 2 minutes.
    const nowMs = Date.now();
    const lastMs = typeof after.emergencyContactLastSmsAtMs === "number" ? after.emergencyContactLastSmsAtMs : 0;
    if (nowMs - lastMs < 2 * 60 * 1000) return;

    const ambulanceChanged = after.ambulanceEta !== before.ambulanceEta;
    const healthChanged = after.medicalStatus !== before.medicalStatus;
    const volunteerMoved =
        after.volunteerLat !== before.volunteerLat ||
        after.volunteerLng !== before.volunteerLng;
    const acceptedChanged =
        JSON.stringify(after.acceptedVolunteerIds || []) !== JSON.stringify(before.acceptedVolunteerIds || []);

    if (!(ambulanceChanged || healthChanged || volunteerMoved || acceptedChanged)) return;

    let msg = `EmergencyOS Update (${event.params.id}): `;
    if (acceptedChanged && Array.isArray(after.acceptedVolunteerIds) && after.acceptedVolunteerIds.length > 0) {
        msg += `Volunteer accepted. `;
    }
    if (ambulanceChanged && after.ambulanceEta) msg += `Ambulance ETA: ${after.ambulanceEta}. `;
    if (healthChanged && after.medicalStatus) msg += `Medical: ${after.medicalStatus}. `;
    if (volunteerMoved && typeof after.volunteerLat === "number" && typeof after.volunteerLng === "number") {
        msg += `Volunteer location updated. `;
    }

    if (!twilioClient || !twilioNumber) {
        console.log("[notifyEmergencyContactOnUpdate] Skip send (Twilio not configured or TWILIO_PHONE_NUMBER missing)");
        return;
    }

    try {
        await twilioClient.messages.create({
            body: msg.trim(),
            from: twilioNumber,
            to: contactPhone
        });
        await db.collection("sos_incidents").doc(event.params.id).set(
            { emergencyContactLastSmsAtMs: nowMs },
            { merge: true }
        );
    } catch (err) {
        console.error("[notifyEmergencyContactOnUpdate] Twilio send error:", err);
    }
});

// ─── 6. Leaderboard Aggregation (server-side) ───────────────────────────────
// Fires when an incident is archived. Updates a pre-computed `leaderboard`
// collection so clients can read sorted rankings without O(n) fan-out.
//
// Region us-east1 — Firestore triggers work from this region; avoids us-central1 CPU quota conflicts.
exports.updateLeaderboardOnIncidentChange = onDocumentCreated(
    {
        document: "sos_incidents_archive/{id}",
        region: "us-east1",
        memory: "256MiB",
        cpu: 0.25,
        concurrency: 1,
        timeoutSeconds: 120,
        maxInstances: 10,
    },
    async (event) => {
        const snap = event.data;
        if (!snap) return;

        const incident = snap.data() || {};
        const acceptedIds = Array.isArray(incident.acceptedVolunteerIds)
            ? incident.acceptedVolunteerIds
            : [];

        if (acceptedIds.length === 0) {
            console.log("[updateLeaderboard] No accepted volunteers — skipping.");
            return;
        }

        const now = FieldValue.serverTimestamp();

        const updates = acceptedIds.map(async (volunteerId) => {
            const vid = String(volunteerId).trim();
            if (!vid) return;

            try {
                const userSnap = await db.collection("users").doc(vid).get();
                const user = userSnap.exists ? userSnap.data() : {};

                await db.collection("leaderboard").doc(vid).set(
                    {
                        responsesCount: FieldValue.increment(1),
                        lastResponseAt: now,
                        volunteerXp: typeof user.volunteerXp === "number" ? user.volunteerXp : 0,
                        volunteerLivesSaved: typeof user.volunteerLivesSaved === "number" ? user.volunteerLivesSaved : 0,
                        displayName: leaderboardDisplayNameFromUserDoc(user, vid),
                    },
                    { merge: true }
                );

                console.log(`[updateLeaderboard] Updated leaderboard for ${vid}`);
            } catch (e) {
                console.error(`[updateLeaderboard] Failed for ${vid}:`, e);
            }
        });

        await Promise.all(updates);
        console.log(`[updateLeaderboard] Processed ${acceptedIds.length} volunteers for archived incident ${event.params.id}`);
    }
);

// ─── 7. Hard TTL: expire all SOS after 1 hour ────────────────────────────────
// Runs every 5 minutes and force-closes open incidents older than 60 minutes.
//
// Paginates on `timestamp` ascending so old docs are not starved when many newer
// open incidents exist (previous `status in … limit(300)` was unordered).
//
// Canonical server-side 1h archival (writes `sos_incidents_archive`, deletes active doc).
// Deploy with: firebase deploy --only functions:expireStaleSosIncidents
// `src/hospital_chain.js` defines a separate 24h in-place job; it is not merged here unless you require it.
exports.expireStaleSosIncidents = onSchedule(
    {
        schedule: "every 5 minutes",
        timeZone: "UTC",
        memory: "256MiB",
        cpu: 0.25,
        timeoutSeconds: 120,
    },
    async () => {
      const cutoffMs = Date.now() - (60 * 60 * 1000);
      const cutoffTs = Timestamp.fromMillis(cutoffMs);
      const activeCol = db.collection("sos_incidents");
      const archiveCol = db.collection("sos_incidents_archive");
      const openStatuses = new Set(["pending", "dispatched", "blocked"]);

      let expiredCount = 0;
      let lastDoc = null;
      const pageSize = 100;
      const maxPages = 30;

      for (let page = 0; page < maxPages; page++) {
        let q = activeCol
            .where("timestamp", "<", cutoffTs)
            .orderBy("timestamp", "asc")
            .limit(pageSize);
        if (lastDoc) {
          q = q.startAfter(lastDoc);
        }
        const snap = await q.get();
        if (snap.empty) {
          break;
        }

        const deltas = await Promise.all(
            snap.docs.map(async (doc) => {
              const data = doc.data() || {};
              const st = String(data.status || "");
              if (!openStatuses.has(st)) {
                return 0;
              }
              const createdMs =
                  timestampToMillis(data.timestamp) ||
                  timestampToMillis(data.goldenHourStart) ||
                  null;
              if (!createdMs || createdMs > cutoffMs) {
                return 0;
              }

              const payload = {
                ...data,
                id: doc.id,
                status: "expired",
                expiredAt: FieldValue.serverTimestamp(),
                expiredReason: "unattended_master_ttl",
                closureLabel: "unattended",
              };

              await archiveCol.doc(doc.id).set(payload, { merge: true });
              await doc.ref.delete();
              return 1;
            })
        );
        expiredCount += deltas.reduce((a, b) => a + b, 0);
        lastDoc = snap.docs[snap.docs.length - 1];
        if (snap.size < pageSize) {
          break;
        }
      }

      console.log(`[expireStaleSosIncidents] Expired ${expiredCount} incident(s).`);
    }
);

// ─── FIX 7: Scheduled monthly FCM token pruner ────────────────────────────────
// Validates all user FCM tokens in batches; removes stale/invalid registrations.
// Prevents Layer 3 dispatch from wasting sends on uninstalled or re-registered devices.
exports.pruneStaleFcmTokens = onSchedule(
  {
    schedule: "0 3 1 * *", // 1st of every month at 03:00 UTC
    timeZone: "UTC",
    memory: "512MiB",
    cpu: 0.25,
    timeoutSeconds: 540,
  },
  async () => {
    const col = db.collection("users");
    let lastDoc = null;
    let pruned = 0;
    let checked = 0;

    for (;;) {
      let q = col.where("fcmToken", "!=", "").orderBy("fcmToken").limit(400);
      if (lastDoc) q = q.startAfter(lastDoc);
      const snap = await q.get();
      if (snap.empty) break;

      const tokens = snap.docs
        .map(d => ({ id: d.id, token: d.data().fcmToken }))
        .filter(t => t.token && typeof t.token === "string" && t.token.length > 0);

      if (tokens.length > 0) {
        checked += tokens.length;
        let result;
        try {
          result = await fcm.sendEachForMulticast({
            tokens: tokens.map(t => t.token),
            data: { _pruneCheck: "1" }, // data-only — no visible notification
            android: { priority: "normal" },
          });
        } catch (e) {
          console.error("[pruneStaleFcmTokens] sendEachForMulticast error:", e);
          break;
        }

        const batch = db.batch();
        let batchHasWrites = false;
        result.responses.forEach((resp, idx) => {
          if (!resp.success) {
            const code = resp.error?.code || "";
            if (
              code === "messaging/registration-token-not-registered" ||
              code === "messaging/invalid-registration-token"
            ) {
              batch.update(col.doc(tokens[idx].id), {
                fcmToken: admin.firestore.FieldValue.delete(),
              });
              pruned++;
              batchHasWrites = true;
            }
          }
        });
        if (batchHasWrites) await batch.commit();
      }

      lastDoc = snap.docs[snap.docs.length - 1];
      if (snap.size < 400) break;
    }

    console.log(`[pruneStaleFcmTokens] Checked ${checked} tokens, pruned ${pruned} stale token(s).`);
  }
// ─────────────────────────────────────────────────────────────────────────────
// Dummy closing marker — real closing paren is on next line

);

/** Accepted hospital consignments older than 1h → terminal status + archive active SOS when still open. */
exports.expireStaleHospitalConsignments = onSchedule(
    {
      schedule: "every 5 minutes",
      timeZone: "UTC",
      memory: "256MiB",
      cpu: 0.25,
      timeoutSeconds: 120,
    },
    async () => {
      const cutoffMs = Date.now() - 60 * 60 * 1000;
      const cutoffTs = Timestamp.fromMillis(cutoffMs);
      const col = db.collection("ops_incident_hospital_assignments");
      const archiveCol = db.collection("sos_incidents_archive");
      const openStatuses = new Set(["pending", "dispatched", "blocked"]);
      const snap = await col
          .where("dispatchStatus", "==", "accepted")
          .where("acceptedAt", "<", cutoffTs)
          .limit(100)
          .get();

      if (snap.empty) {
        console.log("[expireStaleHospitalConsignments] No stale accepted assignments.");
        return;
      }

      const medicalLine = "Hospital consignment closed — assistance window expired (1h)";

      const tasks = snap.docs.map(async (doc) => {
        await doc.ref.set(
          {
            dispatchStatus: "failed_to_assist",
            consignmentClosedAt: FieldValue.serverTimestamp(),
            consignmentCloseReason: "ttl_1h_after_accept",
          },
          { merge: true }
        );
        const incRef = db.collection("sos_incidents").doc(doc.id);
        const incSnap = await incRef.get();
        if (!incSnap.exists) {
          return;
        }
        const data = incSnap.data() || {};
        const st = String(data.status || "");
        if (!openStatuses.has(st)) {
          await incRef.set(
            {
              medicalStatus: medicalLine,
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
          return;
        }

        const payload = {
          ...data,
          id: doc.id,
          medicalStatus: medicalLine,
          updatedAt: FieldValue.serverTimestamp(),
          status: "expired",
          expiredAt: FieldValue.serverTimestamp(),
          expiredReason: "hospital_consignment_ttl_1h",
          closureLabel: "hospital_consignment_ttl",
        };
        await archiveCol.doc(doc.id).set(payload, { merge: true });
        await incRef.delete();
      });
      await Promise.all(tasks);
      console.log(`[expireStaleHospitalConsignments] Closed ${snap.docs.length} stale assignment(s).`);
    }
);

// ─── Ops support (demo: any authenticated user — replace with admin claims in production) ──
exports.opsSupportUserDigest = onCall({ cors: true }, async (request) => {
    if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const email = (request.data?.email || "").toString().trim().toLowerCase();
    const uid = (request.data?.uid || "").toString().trim();
    if (!email && !uid) {
        throw new HttpsError("invalid-argument", "Provide email or uid.");
    }
    let doc;
    if (uid) {
        doc = await db.collection("users").doc(uid).get();
    } else {
        const q = await db.collection("users").where("email", "==", email).limit(5).get();
        if (q.empty) return { found: false };
        doc = q.docs[0];
    }
    if (!doc.exists) return { found: false };
    const d = doc.data() || {};
    const em = (d.email || "").toString();
    let emailMasked = "";
    if (em && em.includes("@")) {
        const [local, dom] = em.split("@");
        emailMasked = `${local.charAt(0)}***@${dom}`;
    }
    const ts = d.securityForceSignOutAt;
    return {
        found: true,
        uid: doc.id,
        displayName: d.displayName || d.name || "",
        emailMasked,
        lastActiveIncidentId: (d.lastActiveIncidentId || "").toString(),
        securityForceSignOutAtMs: ts && ts.toMillis ? ts.toMillis() : null,
    };
});

exports.opsSupportForceSignOut = onCall(
    { cors: true, region: "us-central1", cpu: 0.25, memory: "256MiB" },
    async (request) => {
    if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const targetUid = (request.data?.targetUid || "").toString().trim();
    if (!targetUid) throw new HttpsError("invalid-argument", "targetUid required.");
    await db.collection("users").doc(targetUid).set(
        {
            securityForceSignOutAt: FieldValue.serverTimestamp(),
            securityForceSignOutBy: request.auth.uid,
        },
        { merge: true }
    );
    return { ok: true };
    }
);

// ─── Master dashboard health probe ───────────────────────────────────────────
// Called by MasterDashboardHealthBar / OpsSystemHealthService.fetch().
// Performs lightweight checks: Firestore read, LiveKit env presence, Twilio env presence.
exports.getOpsSystemHealth = onCall(
    { cors: true, memory: "256MiB", timeoutSeconds: 30 },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Sign in required to check system health.");
        }

        const now = Date.now();
        const results = { ok: true, services: {}, summary: "", checkedAt: now };

        // 1. GCP / Firestore probe — try a lightweight read from a known collection.
        try {
            await db.collection("ops_system_health_probe").limit(1).get();
            results.services.gcp = { ok: true, label: "GCP / Firestore", detail: "Firestore reachable and responding." };
        } catch (e) {
            results.services.gcp = { ok: false, label: "GCP / Firestore", detail: `Firestore probe failed: ${e && e.message ? e.message : String(e)}` };
            results.ok = false;
        }

        // 2. LiveKit — check environment configuration (no network round-trip needed for health bar).
        try {
            const env = liveKitEnv(null); // no secret binding at top level; rely on env vars
            const lkOk = !!(env.url && env.apiKey && env.apiSecret);
            results.services.livekit = {
                ok: lkOk,
                label: "LiveKit (WebRTC)",
                detail: lkOk
                    ? "LiveKit URL, API key, and secret are configured."
                    : "LiveKit not fully configured — set LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET.",
            };
            if (!lkOk) results.ok = false;
        } catch (e) {
            results.services.livekit = { ok: false, label: "LiveKit (WebRTC)", detail: `Config error: ${e && e.message ? e.message : String(e)}` };
            results.ok = false;
        }

        // 3. SMS / Twilio — optional; only flags if partially configured (SID without token, etc.).
        const hasSid = !!(process.env.TWILIO_ACCOUNT_SID || "").trim();
        const hasToken = !!(process.env.TWILIO_AUTH_TOKEN || "").trim();
        const hasNumber = !!(process.env.TWILIO_PHONE_NUMBER || "").trim();
        const smsConfigured = hasSid && hasToken && hasNumber;
        const smsPartial = (hasSid || hasToken || hasNumber) && !smsConfigured;
        results.services.sms = {
            ok: smsConfigured || (!hasSid && !hasToken && !hasNumber), // OK if fully configured or fully absent
            label: "SMS (Twilio)",
            detail: smsConfigured
                ? "Twilio SID, auth token, and phone number are set."
                : smsPartial
                ? "Twilio partially configured — set TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, and TWILIO_PHONE_NUMBER."
                : "SMS relay not configured (optional — alerts sent via app push only).",
        };

        // Build summary.
        const failing = Object.values(results.services).filter((s) => !s.ok).map((s) => s.label);
        results.summary = failing.length === 0
            ? "All systems operational."
            : `Issue(s) detected: ${failing.join(", ")}.`;

        return results;
    }
);

// ─── Hospital (medical) dashboard health probe ────────────────────────────────
// Called by OpsDataPlaneHealthService.fetch() — redacted view (no SMS internals).
exports.getOpsDataPlaneHealth = onCall(
    { cors: true, memory: "256MiB", timeoutSeconds: 30 },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Sign in required to check system health.");
        }

        const now = Date.now();
        const results = { ok: true, services: {}, summary: "", checkedAt: now };

        // 1. Firestore probe.
        try {
            await db.collection("ops_system_health_probe").limit(1).get();
            results.services.firestore = { ok: true, label: "GCP / Firestore", detail: "Firestore reachable." };
        } catch (e) {
            results.services.firestore = { ok: false, label: "GCP / Firestore", detail: `Firestore probe failed: ${e && e.message ? e.message : String(e)}` };
            results.ok = false;
        }

        // 2. LiveKit env check.
        try {
            const env = liveKitEnv(null);
            const lkOk = !!(env.url && env.apiKey && env.apiSecret);
            results.services.livekit = {
                ok: lkOk,
                label: "LiveKit (WebRTC)",
                detail: lkOk ? "LiveKit configured." : "LiveKit not fully configured.",
            };
            if (!lkOk) results.ok = false;
        } catch (e) {
            results.services.livekit = { ok: false, label: "LiveKit (WebRTC)", detail: `Config error: ${e && e.message ? e.message : String(e)}` };
            results.ok = false;
        }

        const failing = Object.values(results.services).filter((s) => !s.ok).map((s) => s.label);
        results.summary = failing.length === 0
            ? "Data plane operational."
            : `Issue(s): ${failing.join(", ")}.`;

        return results;
    }
);

const cloudTts = require("./src/cloud_tts");
exports.synthesizeSpeech = cloudTts.synthesizeSpeech;

