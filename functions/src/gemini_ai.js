const { onCall } = require("firebase-functions/v2/https");
const { HttpsError } = require("firebase-functions/v2/https");
const { GoogleGenAI } = require("@google/genai");
const { AI_SAFETY_PREAMBLE, withSafetyForRole } = require("./ai_safety");

const apiKey = process.env.GEMINI_API_KEY;
const ai = new GoogleGenAI({ apiKey });

function lifelineSystemPrompt(scenario) {
  const s = scenario || "General Emergency";
  return (
    AI_SAFETY_PREAMBLE +
    "\n\n" +
    `## ROLE: LIFELINE FIRST-AID COPILOT\n` +
    `Scenario: ${s}\n` +
    `Rules: output exactly 3-5 numbered steps in plain text. Be safe and concrete. If life-threatening, include "Call 112 now" as a step.`
  );
}

exports.analyzeTriageImage = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "User must be authenticated.");
  const { base64str, mimeType, prompt } = request.data;
  if (!base64str || !prompt) throw new HttpsError("invalid-argument", "Missing image or prompt");
  try {
    const safePrompt = withSafetyForRole("triage", prompt);
    const response = await ai.models.generateContent({
      model: "gemini-2.5-flash",
      contents: [safePrompt, { inlineData: { data: base64str, mimeType: mimeType || "image/jpeg" } }]
    });
    return { result: response.text() };
  } catch (e) {
    console.error("Gemini Error:", e);
    throw new HttpsError("internal", "Failed to run AI triage.");
  }
});

exports.lifelineChat = onCall(
  { cors: true, memory: "512MiB", timeoutSeconds: 60, invoker: "public" },
  async (request) => {
    const { scenario, message } = request.data || {};
    if (!message) throw new HttpsError("invalid-argument", "message is required");
    try {
      const response = await ai.models.generateContent({
        model: "gemini-2.5-flash",
        contents: [
          { role: "user", parts: [{ text: lifelineSystemPrompt(scenario) }] },
          { role: "user", parts: [{ text: message }] },
        ],
      });
      return { reply: response.text() };
    } catch (e) {
      console.error("Lifeline chat error:", e);
      throw new HttpsError("internal", "AI unavailable.");
    }
  }
);

exports.analyzeIncidentVideo = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "User must be authenticated.");
  const { incidentId, base64str, mimeType } = request.data;
  if (!incidentId || !base64str) throw new HttpsError("invalid-argument", "Missing incidentId or video frame");
  try {
    const response = await ai.models.generateContent({
      model: "gemini-2.5-flash",
      contents: [
        withSafetyForRole(
          "vision",
          `Analyze this emergency scene image for incident ${incidentId}. Describe hazards, victim count, and recommended response. Be concise.`,
        ),
        { inlineData: { data: base64str, mimeType: mimeType || "image/jpeg" } }
      ]
    });
    return { analysis: response.text() };
  } catch (e) {
    console.error("Video analysis error:", e);
    throw new HttpsError("internal", "Failed to analyze video frame.");
  }
});

exports.analyzeIncidentVoiceNote = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "User must be authenticated.");
  const { incidentId, audioBase64 } = request.data;
  if (!incidentId || !audioBase64) throw new HttpsError("invalid-argument", "Missing incidentId or audio");
  try {
    const response = await ai.models.generateContent({
      model: "gemini-2.5-flash",
      contents: [
        withSafetyForRole(
          "vision",
          `Transcribe and analyze this emergency voice note for incident ${incidentId}. Extract key medical details.`,
        ),
        { inlineData: { data: audioBase64, mimeType: "audio/webm" } }
      ]
    });
    return { analysis: response.text() };
  } catch (e) {
    console.error("Voice note analysis error:", e);
    throw new HttpsError("internal", "Failed to analyze voice note.");
  }
});

function buildSituationBriefPrompt(incident, activity, hospital, volunteers) {
  const task = `Generate a concise situation brief for emergency responders.
Incident: ${incident.type || "Unknown"} at ${incident.lat}, ${incident.lng}
Status: ${incident.status || "active"}
Hospital: ${hospital || "pending"}
Volunteers: ${(volunteers || []).length} assigned
Recent activity: ${(activity || []).slice(0, 10).map(a => a.text || "").join("; ")}
Output: 3-5 bullet points max. Focus on actionable intelligence.`;
  return withSafetyForRole("brief", task);
}

exports.generateSituationBriefForIncident = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "User must be authenticated.");
  const { incidentId } = request.data;
  if (!incidentId) throw new HttpsError("invalid-argument", "incidentId required");
  try {
    const admin = require("firebase-admin");
    const db = admin.firestore();
    const incSnap = await db.collection("sos_incidents").doc(incidentId).get();
    if (!incSnap.exists) throw new HttpsError("not-found", "Incident not found");
    const incident = incSnap.data();
    const actSnap = await db.collection("sos_incidents").doc(incidentId).collection("victim_activity").orderBy("createdAt", "desc").limit(20).get();
    const activity = actSnap.docs.map(d => d.data());
    const response = await ai.models.generateContent({
      model: "gemini-2.5-flash",
      contents: [buildSituationBriefPrompt(incident, activity)]
    });
    await db.collection("sos_incidents").doc(incidentId).set({
      situationBrief: response.text(),
      situationBriefAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { brief: response.text() };
  } catch (e) {
    console.error("Situation brief error:", e);
    throw new HttpsError("internal", "Failed to generate brief.");
  }
});

exports.refreshSituationBriefsScheduled = require("firebase-functions/v2/scheduler").onSchedule(
  { schedule: "every 5 minutes", timeoutSeconds: 300, memory: "512MiB" },
  async () => {
    const admin = require("firebase-admin");
    const db = admin.firestore();
    const now = Date.now();
    const staleMs = 10 * 60 * 1000;
    const snaps = await db.collection("sos_incidents")
      .where("status", "in", ["pending", "dispatched", "accepted"])
      .get();
    for (const doc of snaps.docs) {
      const d = doc.data();
      const briefAt = d.situationBriefAt;
      const briefMs = briefAt && typeof briefAt.toMillis === "function" ? briefAt.toMillis() : null;
      if (!briefMs || (now - briefMs) > staleMs) {
        try {
          const response = await ai.models.generateContent({
            model: "gemini-2.5-flash",
            contents: [buildSituationBriefPrompt(d, [])]
          });
          await doc.ref.set({
            situationBrief: response.text(),
            situationBriefAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        } catch (e) {
          console.warn(`Brief refresh failed for ${doc.id}:`, e);
        }
      }
    }
  }
);
