const { onCall, HttpsError } = require("firebase-functions/v2/https");
const crypto = require("crypto");
const textToSpeech = require("@google-cloud/text-to-speech");

/** Lazy client — constructing TextToSpeechClient at module load runs gRPC
 *  credential discovery and can exceed Firebase's 10s deploy-time analysis
 *  timeout ("User code failed to load"). Instantiate on first synthesis only.
 */
let ttsClient;
function getTtsClient() {
  if (!ttsClient) {
    ttsClient = new textToSpeech.TextToSpeechClient();
  }
  return ttsClient;
}

/** Small LRU to cut duplicate billing for repeated prompts. */
const _cache = new Map();
const CACHE_MAX = 200;

function cacheGet(key) {
  const v = _cache.get(key);
  if (!v) return null;
  _cache.delete(key);
  _cache.set(key, v);
  return v;
}

function cacheSet(key, val) {
  _cache.set(key, val);
  while (_cache.size > CACHE_MAX) {
    const first = _cache.keys().next().value;
    _cache.delete(first);
  }
}

/**
 * Google Cloud Text-to-Speech fallback for browsers/devices without a local voice pack.
 * Auth: signed-in users only.
 */
exports.synthesizeSpeech = onCall(
  {
    cors: true,
    memory: "256MiB",
    timeoutSeconds: 30,
    maxInstances: 30,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const text = (request.data && request.data.text) || "";
    const bcp47 = ((request.data && request.data.bcp47) || "en-IN").trim();
    const t = String(text).trim();
    if (!t) {
      throw new HttpsError("invalid-argument", "text required");
    }
    if (t.length > 600) {
      throw new HttpsError("invalid-argument", "text too long");
    }
    const lang = bcp47.replace(/_/g, "-") || "en-IN";
    const cacheKey = crypto
      .createHash("sha256")
      .update(`${lang}|${t}`, "utf8")
      .digest("hex");
    const hit = cacheGet(cacheKey);
    if (hit) {
      return { audioBase64: hit, mime: "audio/mpeg", cached: true };
    }
    try {
      const [resp] = await getTtsClient().synthesizeSpeech({
        input: { text: t },
        voice: {
          languageCode: lang,
          ssmlGender: "FEMALE",
        },
        audioConfig: {
          audioEncoding: "MP3",
          speakingRate: 1.0,
        },
      });
      const buf = resp.audioContent;
      if (!buf || !buf.length) {
        throw new HttpsError("internal", "empty audio");
      }
      const b64 = Buffer.from(buf).toString("base64");
      cacheSet(cacheKey, b64);
      return { audioBase64: b64, mime: "audio/mpeg", cached: false };
    } catch (e) {
      console.error("[synthesizeSpeech]", e);
      throw new HttpsError("internal", e.message || "TTS failed");
    }
  },
);
