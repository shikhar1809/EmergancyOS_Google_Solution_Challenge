const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const {
  db, FieldValue, OPS_ZONE_CENTER, getClosestOpsZone, latLngToHex,
  hexAxialDistance, haversineKm, _writeOpsDashboardAlert,
  mergeRequiredServicesFromIncident, emergencyTypeLower,
  geohashQueryBounds, distanceBetween, geohashForPoint,
} = require("./utils");

const EARTH_RADIUS_KM = 6371;
const ALERT_RADIUS_KM = 20;
function degreesToRadians(deg) { return deg * (Math.PI / 180); }

function hospitalDispatchScore(c, requiredServices, emergencyType, relaxedServices, aiSpecialty) {
  let score = c.ring * 100 + c.distKm * 2;
  if (c.bedsAvail <= 0) score += 500;
  else if (c.bedsAvail <= 2) score += 50;
  else if (c.bedsAvail <= 5) score += 20;
  if (!relaxedServices && requiredServices.length > 0 && !c.servicesOk) score += 1000;
  score -= specialtyBonus(c.offered, emergencyType, aiSpecialty);
  return score;
}

function specialtyBonus(offered, emergencyType, aiSpecialty) {
  const t = (emergencyType || "").toLowerCase();
  const off = (offered || []).map((s) => String(s).toLowerCase());
  let bonus = 0;
  if (/(accident|crash|rta|collision|road|vehicle)/.test(t) && off.some((s) => s.includes("trauma"))) bonus += 42;
  if (/(burn|fire|smoke)/.test(t) && off.some((s) => s.includes("burn"))) bonus += 42;
  if (/(cardiac|chest|heart|stroke)/.test(t) && off.some((s) => s.includes("cardiac") || s.includes("cardiology"))) bonus += 38;

  // AI triage vision (Gemini) — strong additional pull toward matching specialty.
  const ai = (aiSpecialty || "").toLowerCase();
  if (ai === "cardiac" && off.some((s) => s.includes("cardiac") || s.includes("cardiology"))) bonus += 60;
  else if (ai === "trauma" && off.some((s) => s.includes("trauma"))) bonus += 60;
  else if (ai === "burn" && off.some((s) => s.includes("burn"))) bonus += 60;
  else if (ai === "pediatric" && off.some((s) => s.includes("pediatric") || s.includes("nicu"))) bonus += 60;
  else if (ai === "stroke" && off.some((s) => s.includes("stroke") || s.includes("neuro"))) bonus += 60;
  return bonus;
}

async function dispatchHospitalInHex({ incidentId, incident }) {
  const lat = incident.lat;
  const lng = incident.lng;
  if (!(typeof lat === "number" && typeof lng === "number")) return;

  const requiredServices = mergeRequiredServicesFromIncident(incident);
  const emergencyType = emergencyTypeLower(incident);
  // AI triage vision hint (Gemini) — pulled from the incident document.
  const aiSpecialty = (() => {
    try {
      const t = incident && incident.triage;
      const av = t && t.aiVision;
      return av && String(av.aiRecommendedSpecialty || "").trim().toLowerCase();
    } catch (_) { return ""; }
  })();
  const incidentZone = getClosestOpsZone(lat, lng);
  const incidentHex = latLngToHex(lat, lng, incidentZone);

  const DISPATCH_RADIUS_KM = 60;
  const bounds = geohashQueryBounds([lat, lng], DISPATCH_RADIUS_KM * 1000);
  const snapPromises = bounds.map((b) =>
    db.collection("ops_hospitals").orderBy("geohash").startAt(b[0]).endAt(b[1]).get()
  );
  const snapshots = await Promise.all(snapPromises);

  const seenIds = new Set();
  const allDocs = [];
  for (const snap of snapshots) {
    for (const doc of snap.docs) {
      if (!seenIds.has(doc.id)) { seenIds.add(doc.id); allDocs.push(doc); }
    }
  }

  const backfillBatch = db.batch();
  let backfillCount = 0;
  const allDocsFiltered = allDocs.filter((doc) => {
    const d = doc.data() || {};
    if (typeof d.lat !== "number" || typeof d.lng !== "number") return false;
    const kmActual = distanceBetween([lat, lng], [d.lat, d.lng]);
    if (kmActual > DISPATCH_RADIUS_KM) return false;
    if (!d.geohash) {
      backfillBatch.update(doc.ref, { geohash: geohashForPoint([d.lat, d.lng]) });
      backfillCount++;
    }
    return true;
  });
  if (backfillCount > 0) backfillBatch.commit().catch((e) => console.warn("[dispatch] geohash backfill:", e));

  const candidates = [];
  for (const doc of allDocsFiltered) {
    const h = (typeof doc.data === "function" ? doc.data() : doc) || {};
    const hLat = h.lat;
    const hLng = h.lng;
    if (!(typeof hLat === "number" && typeof hLng === "number")) continue;
    const hex = latLngToHex(hLat, hLng, incidentZone);
    const offered = Array.isArray(h.offeredServices) ? h.offeredServices.map((s) => String(s)) : [];
    const bedsAvail = typeof h.bedsAvailable === "number" ? h.bedsAvailable : 0;
    const servicesOk = requiredServices.every((rs) => offered.map((o) => o.toLowerCase()).includes(String(rs).toLowerCase()));
    const ring = hexAxialDistance(incidentHex, hex);
    candidates.push({ id: doc.id, name: String(h.name || doc.id), lat: hLat, lng: hLng, hex, ring, distKm: haversineKm(lat, lng, hLat, hLng), bedsAvail, bedsTotal: typeof h.bedsTotal === "number" ? h.bedsTotal : 0, servicesOk, offered });
  }

  function isEligible(c) { const capOk = c.bedsAvail > 0 || c.bedsTotal === 0; const svcOk = requiredServices.length === 0 ? true : c.servicesOk; return capOk && svcOk; }
  function isEligibleCapacityOnly(c) { return c.bedsAvail > 0 || c.bedsTotal === 0; }

  const strictEligible = candidates.filter(isEligible);
  const relaxed = strictEligible.length === 0;
  const eligible = relaxed ? candidates.filter(isEligibleCapacityOnly) : strictEligible;

  const tier1 = eligible.filter((c) => c.ring === 0);
  const tier2 = eligible.filter((c) => c.ring >= 1 && c.ring <= 5);
  const tier3 = eligible.filter((c) => c.ring > 5);

  const sortTier = (arr) => arr.sort((a, b) => hospitalDispatchScore(a, requiredServices, emergencyType, relaxed, aiSpecialty) - hospitalDispatchScore(b, requiredServices, emergencyType, relaxed, aiSpecialty));
  sortTier(tier1); sortTier(tier2); sortTier(tier3);

  const tieredList = [...tier1, ...tier2, ...tier3];
  const tier1EndIndex = tier1.length;
  const tier2EndIndex = tier1.length + tier2.length;
  const orderedIds = tieredList.map((c) => c.id);
  const chain = orderedIds.slice(0, 20);

  if (orderedIds.length === 0) {
    await db.collection("ops_incident_hospital_assignments").doc(incidentId).set({
      incidentId, zoneId: OPS_ZONE_CENTER.id, incidentLat: lat, incidentLng: lng, incidentHex,
      requiredServices, candidateHospitalIds: chain, orderedHospitalIds: [], notifiedHospitalIds: [],
      dispatchStatus: "no_candidates", tier1EndIndex: 0, tier2EndIndex: 0,
      assignedAt: FieldValue.serverTimestamp(), reason: "no_eligible_hospital",
      primaryHospitalId: null, primaryHospitalName: null, primaryDistanceKm: null,
    }, { merge: true });
    await _writeOpsDashboardAlert({ incidentId, kind: "hospital_dispatch_failed", title: "No eligible hospital found", body: requiredServices.length ? `No nearby hospital has capacity + required services (${requiredServices.join(", ")}).` : "No nearby hospital has reported capacity.", severity: "critical", extra: { requiredServices, incidentHex, zoneId: OPS_ZONE_CENTER.id } });
    return;
  }

  const first = tieredList[0];
  await db.collection("ops_incident_hospital_assignments").doc(incidentId).set({
    incidentId, zoneId: OPS_ZONE_CENTER.id, incidentLat: lat, incidentLng: lng, incidentHex,
    requiredServices, candidateHospitalIds: chain, orderedHospitalIds: orderedIds,
    notifyIndex: 0, notifiedHospitalId: first.id, notifiedHospitalName: first.name,
    notifiedHospitalLat: first.lat, notifiedHospitalLng: first.lng,
    notifiedHospitalIds: [first.id], notifiedAt: FieldValue.serverTimestamp(),
    escalateAfterMs: 120000, tier1EndIndex, tier2EndIndex, dispatchStatus: "pending_acceptance",
    assignedAt: FieldValue.serverTimestamp(), reason: first.ring === 0 ? "in_hex" : `hex_ring_${first.ring}`,
    primaryHospitalId: null, primaryHospitalName: null, primaryDistanceKm: null,
  }, { merge: true });

  await _writeOpsDashboardAlert({ incidentId, kind: "hospital_dispatch_notify", title: "Hospital dispatch \u2014 acceptance required", body: `${first.name} (${first.id}) has 120s to accept this incident (hex ring ${first.ring}).`, severity: "info", extra: { hospitalId: first.id, hexRing: first.ring, requiredServices } });
}

async function escalateHospitalDispatchAssignment(assignmentRef, d, escalationReason) {
  const incidentId = assignmentRef.id;
  const ordered = Array.isArray(d.orderedHospitalIds) ? d.orderedHospitalIds.map((x) => String(x)) : [];
  const cur = (d.notifiedHospitalId || "").toString();
  let curIdx = ordered.indexOf(cur);
  if (curIdx < 0) curIdx = 0;
  const nextIdx = curIdx + 1;
  if (nextIdx >= ordered.length) {
    await assignmentRef.set({ dispatchStatus: "exhausted", dispatchExhaustedAt: FieldValue.serverTimestamp(), lastEscalationReason: escalationReason || "timeout" }, { merge: true });
    await _writeOpsDashboardAlert({ incidentId, kind: "hospital_dispatch_exhausted", title: "No hospital accepted dispatch", body: "All eligible hospitals in range were notified; none accepted in time.", severity: "critical", extra: { zoneId: OPS_ZONE_CENTER.id } });
    return;
  }
  const nextId = ordered[nextIdx];
  let nextName = nextId;
  let nextLat = null;
  let nextLng = null;
  try {
    const hs = await db.collection("ops_hospitals").doc(nextId).get();
    if (hs.exists) { const hd = hs.data() || {}; nextName = String(hd.name || nextId); if (typeof hd.lat === "number") nextLat = hd.lat; if (typeof hd.lng === "number") nextLng = hd.lng; }
  } catch (_) {}
  await assignmentRef.set({ notifiedHospitalId: nextId, notifiedHospitalName: nextName, notifiedHospitalLat: nextLat, notifiedHospitalLng: nextLng, notifyIndex: nextIdx, notifiedHospitalIds: FieldValue.arrayUnion(nextId), notifiedAt: FieldValue.serverTimestamp(), dispatchStatus: "pending_acceptance", lastEscalationReason: escalationReason || "timeout" }, { merge: true });
  await _writeOpsDashboardAlert({ incidentId, kind: "hospital_dispatch_notify", title: "Hospital dispatch \u2014 next hospital", body: `${nextName} (${nextId}) \u2014 please accept or decline within 60s.`, severity: "info", extra: { hospitalId: nextId, notifyIndex: nextIdx } });
}

exports.acceptHospitalDispatch = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "User must be authenticated.");
  const { incidentId, hospitalId } = request.data;
  if (!incidentId || !hospitalId) throw new HttpsError("invalid-argument", "incidentId and hospitalId required");
  const assignSnap = await db.collection("ops_incident_hospital_assignments").doc(incidentId).get();
  if (!assignSnap.exists) throw new HttpsError("not-found", "Assignment not found");
  const assign = assignSnap.data();
  if (assign.notifiedHospitalId !== hospitalId) throw new HttpsError("permission-denied", "Not the notified hospital");
  await assignSnap.ref.set({ dispatchStatus: "accepted", acceptedHospitalId: hospitalId, acceptedAt: FieldValue.serverTimestamp() }, { merge: true });
  return { success: true };
});

exports.declineHospitalDispatch = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "User must be authenticated.");
  const { incidentId, hospitalId, reason } = request.data;
  if (!incidentId || !hospitalId) throw new HttpsError("invalid-argument", "incidentId and hospitalId required");
  const assignSnap = await db.collection("ops_incident_hospital_assignments").doc(incidentId).get();
  if (!assignSnap.exists) throw new HttpsError("not-found", "Assignment not found");
  const assign = assignSnap.data();
  if (assign.notifiedHospitalId !== hospitalId) throw new HttpsError("permission-denied", "Not the notified hospital");
  await escalateHospitalDispatchAssignment(assignSnap.ref, assign, reason || "declined");
  return { success: true };
});

exports.hospitalDispatchEscalation = onSchedule({ schedule: "every 1 minutes", timeoutSeconds: 120 }, async () => {
  const snaps = await db.collection("ops_incident_hospital_assignments").where("dispatchStatus", "==", "pending_acceptance").get();
  for (const doc of snaps.docs) {
    const d = doc.data();
    const notifiedAt = d.notifiedAt;
    if (!notifiedAt || !notifiedAt.toMillis) continue;
    const elapsed = Date.now() - notifiedAt.toMillis();
    const timeout = d.escalateAfterMs || 120000;
    if (elapsed >= timeout) {
      await escalateHospitalDispatchAssignment(doc.ref, d, "timeout");
    }
  }
});

exports.dispatchSOS = onDocumentCreated("sos_incidents/{id}", async (event) => {
  const incidentId = event.params.id;
  const data = event.data?.data();
  if (!data) return;
  try {
    await dispatchHospitalInHex({ incidentId, incident: data });
    const lat = data.lat;
    const lng = data.lng;
    if (!(typeof lat === "number" && typeof lng === "number")) return;
    const bounds = geohashQueryBounds([lat, lng], ALERT_RADIUS_KM * 1000);
    const promises = bounds.map((b) => db.collection("users").where("dutyStatus", "==", "on_duty").orderBy("geohash").startAt(b[0]).endAt(b[1]).get());
    const snapshots = await Promise.all(promises);
    const fcmTokens = new Set();
    for (const snap of snapshots) {
      for (const doc of snap.docs) {
        const u = doc.data();
        if (u.fcmToken) fcmTokens.add(u.fcmToken);
      }
    }
    if (fcmTokens.size > 0) {
      const tokens = Array.from(fcmTokens).slice(0, 500);
      await admin.messaging().sendEachForMulticast({
        tokens,
        data: { incidentId, type: "sos_dispatch", lat: String(lat), lng: String(lng) },
      });
    }
  } catch (e) {
    console.error("dispatchSOS error:", e);
  }
});

exports.enforceSosCreateLimits = onDocumentCreated("sos_incidents/{id}", async (event) => {
  const uid = event.data?.data()?.userId;
  if (!uid) return;
  const windowMs = 5 * 60 * 1000;
  const countSnap = await db.collection("sos_incidents").where("userId", "==", uid).where("timestamp", ">", new Date(Date.now() - windowMs)).count().get();
  if (countSnap.data().count > 3) {
    await db.collection("sos_incidents").doc(event.params.id).delete();
    console.warn(`Rate-limited SOS from ${uid}`);
  }
});

// Not exported from `functions/index.js` unless you require this module there — the live app's 1h rule is
// `expireStaleSosIncidents` in `index.js` (moves docs to `sos_incidents_archive`). This job only re-tags
// very old *pending* rows in-place after 24h and does not replace that TTL.
exports.autoArchiveStaleSosIncidents = onSchedule({ schedule: "every 15 minutes", timeoutSeconds: 300 }, async () => {
  const staleMs = 24 * 60 * 60 * 1000;
  const snaps = await db.collection("sos_incidents").where("status", "==", "pending").get();
  for (const doc of snaps.docs) {
    const d = doc.data();
    const ts = d.timestamp;
    if (!ts || !ts.toMillis) continue;
    if (Date.now() - ts.toMillis() > staleMs) {
      await doc.ref.set({ status: "archived_stale", archivedAt: FieldValue.serverTimestamp() }, { merge: true });
    }
  }
});

const admin = require("firebase-admin");
module.exports = { dispatchHospitalInHex, escalateHospitalDispatchAssignment };
