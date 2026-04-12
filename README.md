<div align="center">

<img src="logo.png" alt="EmergencyOS Logo" width="120" />

# EmergencyOS

### AI-Powered Emergency Response Platform

**Google Solution Challenge 2026 · Open Track · Rapid Emergency Response**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Platform-FFCA28?logo=firebase)](https://firebase.google.com)
[![Gemini](https://img.shields.io/badge/Gemini_2.5_Flash-AI-4285F4?logo=google)](https://ai.google.dev)
[![LiveKit](https://img.shields.io/badge/LiveKit-WebRTC-0F0?logo=webrtc)](https://livekit.io)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

</div>

---

## Why EmergencyOS?

> *"My mom suffered a heart attack while nobody was home. I called 112 for an ambulance — no tracking, no ETA. It never came. We rushed her ourselves to the nearest hospital, but they couldn't treat her: the on-call specialist wasn't available. We had to shift her again — precious golden-hour minutes burning away. When the doctor finally saw her, he had to waste more time digging through handwritten files just to know her medication history.*
>
> *By God's grace, my mom survived. But that day I witnessed a gap no family should have to fall into — no real-time visibility, no intelligent dispatch, no hospital routing, no medical history at the point of care.*
>
> **That day, EmergencyOS was born.**"
>
> — **Shikhar Shahi**, Builder & Founder

---

## The Problem

Every minute in a medical emergency counts — the first 60 minutes are called the **Golden Hour**. In India and across the developing world, that window is routinely lost to:

| Gap | Impact |
|-----|--------|
| 🚑 No ambulance ETA or tracking | Victims wait blind, family panics |
| 🏥 Wrong hospital routing | No bed, wrong specialty, forced re-transfer |
| 📋 No patient history at bedside | Doctors repeat diagnostics from scratch |
| 📵 Offline victims can't call for help | SMS-only path abandoned |
| 👨‍⚕️ No bystander guidance | Untrained witnesses freeze or worsen outcomes |
| 🤝 Volunteers exist but are unreachable | Trained responders nearby go unalerted |

EmergencyOS is a full-stack operating system for emergency response that closes every one of these gaps.

---

## What EmergencyOS Does

EmergencyOS connects **six roles** — victim, citizen volunteer, EMS fleet operator, hospital, ops admin, and emergency contact — into one real-time command mesh powered by Gemini AI, Google Maps, LiveKit WebRTC, and Firebase.

```
Victim taps SOS
      │
      ▼
Cloud Function (dispatchSOS)
  ├─ Hex-grid hospital selection (Gemini scores + distance + specialty + beds)
  ├─ FCM Layer 1: Geo-alert all volunteers within 20 km
  ├─ FCM Layer 2: Topic broadcast to all subscribed devices
  ├─ FCM Layer 3: All-user fallback multicast
  └─ SMS GeoSMS relay (Twilio) — offline phones still trigger dispatch
      │
      ▼
Volunteers race to scene → LIFELINE AI guides CPR, bleeding, burns by voice
EMS Fleet accepts assignment → real-time tracking on victim's screen
Hospital accepts 2-minute dispatch window → or auto-escalates to next bed
Ops Admin watches hex-grid command center → Gemini scene brief every 5 min
Emergency Contact receives SMS updates (ETA, volunteer accepted, status)
```

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       CLIENT LAYER                              │
│  ┌──────────────────┐ ┌──────────────────┐ ┌────────────────┐  │
│  │  EmergencyOS App │ │  Admin Ops       │ │  Fleet Panel   │  │
│  │  (Flutter)       │ │  Console (Web)   │ │  (Web)         │  │
│  │  Android/iOS/Web │ │  /ops-dashboard  │ │  /fleet        │  │
│  └────────┬─────────┘ └────────┬─────────┘ └───────┬────────┘  │
└───────────┼─────────────────────┼────────────────────┼──────────┘
            │                     │                    │
┌───────────▼─────────────────────▼────────────────────▼──────────┐
│                    FIREBASE BACKEND                              │
│  ┌──────────────┐  ┌─────────────────────────────────────────┐  │
│  │ Firebase     │  │         Cloud Firestore                 │  │
│  │ Auth         │  │  sos_incidents · ops_hospitals          │  │
│  │ (Google,     │  │  leaderboard · users · volunteers       │  │
│  │  Email, Anon)│  │  ptt_channels · ops_fleet_units         │  │
│  └──────────────┘  │  ops_incident_hospital_assignments      │  │
│  ┌──────────────┐  │  livekit_bridges · livekit_copilot     │  │
│  │ FCM (3-layer)│  └─────────────────────────────────────────┘  │
│  │ Firebase     │  ┌──────────────┐ ┌──────────────────────┐   │
│  │ Storage      │  │ App Check    │ │ Crashlytics          │   │
│  │ App Check    │  │ (reCAPTCHA   │ │ Performance          │   │
│  │ Crashlytics  │  │  v3 / Play   │ │ Monitoring           │   │
│  └──────────────┘  │  Integrity)  │ └──────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
            │
┌───────────▼────────────────────────────────────────────────────┐
│                  CLOUD FUNCTIONS (Node.js v2)                  │
│  dispatchSOS · dispatchHospitalInHex · lifelineChat           │
│  analyzeTriageImage · generateSituationBriefForIncident        │
│  acceptHospitalDispatch · declineHospitalDispatch              │
│  acceptAmbulanceDispatch · hospitalDispatchEscalation          │
│  getLivekitToken · ensureEmergencyBridge · ensureCopilotAgent  │
│  parseSmsGateway · onIncidentUpdate · expireStaleSosIncidents  │
│  updateLeaderboardOnIncidentChange · onExternalIncidentTrigger │
└──────┬──────────────────────┬────────────────────────┬─────────┘
       │                      │                        │
┌──────▼──────┐   ┌───────────▼──────────┐   ┌────────▼────────┐
│ Gemini 2.5  │   │  LiveKit WebRTC      │   │  Twilio SMS     │
│ Flash API   │   │  ┌────────────────┐  │   │  Gateway        │
│ · Triage    │   │  │emergency_bridge│  │   │  · Victim ETA   │
│   vision    │   │  │  _{incidentId} │  │   │  · Contact SMS  │
│ · LIFELINE  │   │  ├────────────────┤  │   │  · Offline SOS  │
│   chat      │   │  │copilot_{uid}   │  │   │    (GeoSMS)     │
│ · Scene     │   │  ├────────────────┤  │   └─────────────────┘
│   brief     │   │  │commsop_...     │  │
│ · Analytics │   │  │commsem_...     │  │   ┌─────────────────┐
│   AI        │   │  │comms_command   │  │   │ Google Maps     │
└─────────────┘   │  └────────────────┘  │   │ Platform        │
                  │  LifelineAgent (TS)  │   │ · Directions    │
                  │  CopilotAgent (TS)   │   │ · Places        │
                  │  OpenAI Realtime     │   │ · Geocoding     │
                  └────────────────────── ┘   └─────────────────┘
```

---

## Features

### 🆘 1. One-Tap SOS Emergency Dispatch

The core of EmergencyOS. A single tap triggers a multi-layered dispatch chain:

- **GPS location** captured immediately
- **Voice capture** to describe the emergency on low-connectivity networks
- **AI triage intake** suggests emergency type and required services
- **3-layer FCM push** alerts nearby volunteers simultaneously:
  - Layer 1: Geo-targeted multicast to volunteers within 20 km
  - Layer 2: FCM topic broadcast to all `sos_alerts` subscribers
  - Layer 3: All-user token fallback (no alert is ever silently dropped)
- **Anti-abuse rate limiting** — fail-open design (real emergencies are never blocked)
- **SOS active locked screen** shows real-time ambulance ETA, tracking, and volunteer status

### 🤖 2. LIFELINE — AI First-Aid Co-Pilot

LIFELINE is an on-device and cloud AI guide for bystanders at an emergency scene:

- **Chat mode**: Powered by Gemini 2.5 Flash via Cloud Function — guides CPR, bleeding control, burns, shocks, strokes, seizures, allergic reactions, drowning, fractures
- **Voice mode**: LiveKit WebRTC + OpenAI Realtime API (`coral` voice) with background noise cancellation
- **Triage camera**: Gemini vision AI analyzes scene photos — returns incident type guess, victim condition, blood visible, hazard summary, confidence level
- **Training arena**: 19-level first-aid curriculum with gamification (XP, levels, leaderboard)
- **Emergency mode toggle**: Switches from training to live emergency guidance
- **Offline fallback**: Local knowledge base serves guidance when cloud is unreachable
- **Multilingual**: Responds in the user's selected language (12 Indian languages supported)

### 🗺️ 3. Real-Time Emergency Map

- Live incident map with **custom hex-grid zone markers** (flat-top axial coordinates, Lucknow ops center anchor)
- Volunteer, EMS fleet, and hospital locations in real-time
- **Nearest AED locator** with walk-time estimate
- **Hazard zones** overlay (fires, floods, accidents)
- Offline map pack for areas with poor connectivity
- Google Maps + flutter_map dual rendering with WebGL fallback

### 🏥 4. Intelligent Hospital Dispatch System

The most technically sophisticated module — zero human operator required:

1. On SOS creation, Cloud Function computes **hex-grid distance** from incident to all hospitals within 60 km
2. Hospitals are scored by: hex ring distance + bed availability + specialty match + haversine km
3. **Three dispatch tiers**: same hex (Tier 1) → rings 1–5 (Tier 2) → specialists beyond (Tier 3)
4. Top hospital gets a **2-minute acceptance window** — decline or timeout escalates to next
5. **Specialty bonus scoring**: cardiac hospitals preferred for heart attacks, trauma for RTA, burns for fires
6. Accepted hospital triggers **ambulance fleet assignment** to the nearest available unit
7. Ambulance operator gets a **3-minute response window** — escalates across hospital network if ignored
8. All status changes (ETA, acceptance, en-route) push to victim via Firestore real-time + Twilio SMS
9. **Ops dashboard alert feed** for every step: hospital notified, declined, exhausted, no beds

### 👨‍🚒 5. Volunteer Response Network

- Volunteers register availability with real-time GPS presence broadcasting
- Geo-radius alert for all available volunteers within 20 km of incident
- **Consignment screen** shows incident type, location, distance, victim name
- Accepts/declines SOS assignments with one tap
- On-scene volunteers submit **scene reports** (photos, video, victim count, hazards) that feed into Gemini situation brief
- **On-scene check-in** marks volunteer physically present
- **Post-incident feedback** drives XP, lives-saved counter, and leaderboard rank
- **Elite volunteer tier**: Lifeline Level 10+ or 5 lives + 1000 XP → earns live voice channel access in emergency bridge
- **PTT channel**: Push-to-talk voice mesh for all responders on an incident

### 🚑 6. EMS Fleet Operations Panel

Dedicated web panel (`/fleet`) for ambulance operators:

- Incoming assignment queue with incident details, hospital name, ETA input
- **Accept/decline** with 3-minute deadline — auto-expires with escalation
- Real-time navigation link opens Google Maps turn-by-turn
- **Fleet comms bridge**: Two dedicated LiveKit rooms per incident:
  - `commsop_{id}` — Operation channel (hospital ↔ EMS coordination)
  - `commsem_{id}` — Emergency channel (victim ↔ EMS voice)
- Fleet unit heartbeat and availability status
- `ops_fleet_units` collection tracks stationed hospital, vehicle type, call sign

### 🏥 7. Hospital Bridge & Live Ops

- Hospital staff receives dispatch notification (FCM push + Ops Alert)
- **2-minute accept/decline** window via hospital dashboard
- Hospital page shows: incident type, distance, required services vs capacity, bed count
- **Live ops screen** gives hospital staff the full incident picture: victim details, EMS status, scene photos, Gemini situation brief
- **Medical record upload**: pre-authorized hospital docs surface allergies, blood type, medications for incoming patient — zero time wasted at admission
- **Comms bridge screen**: LiveKit Discord-style voice channels per incident
- Hospital can accept/decline dispatch via `acceptHospitalDispatch` / `declineHospitalDispatch` Cloud Functions

### 🎛️ 8. Admin Ops Command Center

Full situational awareness for emergency operations administrators:

- **Real-time hex-grid map**: All incidents plotted on axial hex overlay — color-coded by severity, zoom-dependent detail
- **Incident command panel**: Focus any incident, see dispatch chain, hospital assignment, fleet status, volunteer roster
- **Admin analytics dashboard**: Response time histogram, incident type breakdown, volunteer XP trends, zone heatmaps (fl_chart)
- **Fleet management screen**: All units, availability TTL watch, stationed hospital, call sign assignment
- **Volunteer management**: XP, level, lives saved, profile verification
- **System observatory**: Live health check — Firestore, LiveKit, Twilio, Gemini API key status
- **Impact dashboard**: Platform-level outcomes — lives helped, incidents resolved, average response time
- **Ops dispatch note**: Admin can annotate any active incident for EMS and hospital briefings
- **Master comms net**: `comms_command_net` LiveKit room — command-level voice on all incidents

### 🗣️ 9. LIFELINE COPILOT — Voice AI Assistant

A persistent per-user voice assistant powered by LiveKit + OpenAI Realtime:

- Listens on `copilot_{uid}` LiveKit room — always on when user is in the app
- Knows full medical protocols: CPR, choking, bleeding, burns, heart attack, stroke, seizure, anaphylaxis, drowning, fractures
- Tool: `getAppPageContext` — tells copilot what screen the user is on
- Tool: `getMedicalProtocol` — look up any protocol by name
- Tool: `requestEmergencySos` — Copilot can request SOS trigger (user must confirm in-app)
- Background noise cancellation via `@livekit/noise-cancellation-node`
- Voice walkthrough mode for new users — hands-free app navigation coaching

### 📡 10. SMS Offline Emergency Gateway

For users with no app or internet (2G/USSD phones):

- User sends a **GeoSMS** text to the gateway number (powered by Twilio webhook)
- `parseSmsGateway` Cloud Function validates Twilio signature (anti-spoofing)
- Parses coordinates, emergency type, victim count from GeoSMS URL format
- Creates a Firestore incident → triggers full dispatch chain (hospital, volunteers, FCM)
- If incident ID included → **merges SMS update onto existing in-app SOS** (parallel relay)
- **Two-way SMS**: victim receives acknowledgment; ETA and status updates sent back automatically via `onIncidentUpdate`

### 👨‍👩‍👧 11. Family Tracker

- Share a **live tracking link** with family (`/family-tracker/{id}?t={token}`)
- No app required — opens in browser, shows victim's live location + ETA updates
- Emergency contact receives automatic SMS updates: volunteer accepted, ETA, medical status
- Emergency contact can **join the voice bridge** via WebRTC after identity verification

### 🏅 12. Volunteer Leaderboard & Gamification

- XP awarded per incident response, scene report, on-scene check-in, CPR training completion
- Leaderboard aggregated server-side by `updateLeaderboardOnIncidentChange` Cloud Function on incident archive
- Public profile: display name + avatar synced from Firebase Auth
- Training levels 1–19 in LIFELINE arena — each level unlocks new first-aid modules
- **Elite tier**: Level 10+ earns `volunteer_elite` LiveKit grant — priority voice in emergency bridge

### 📴 13. Full Offline Support

- Firestore persistence enabled (50 MB cache)
- `OfflineCacheService` pre-caches critical incident data
- `OfflineKnowledgeService` serves 19-level first-aid curriculum without internet
- `OfflineMapPackService` downloads map tiles for low-connectivity zones
- `OfflineSosStatusService` queues SOS submissions for delivery when signal returns
- Voice TTS reads guidance aloud when screen is unreadable

### 🌐 14. Multi-Language Support (12 Indian Languages)

App UI, LIFELINE responses, and TTS voice guidance available in:
English · हिन्दी · தமிழ் · తెలుగు · ಕನ್ನಡ · മലയാളം · বাংলা · मराठी · ગુજરાતી · ਪੰਜਾਬੀ · ଓଡ଼ିଆ · اردو

Gemini responds in the user's language when `replyLocale` is passed. TTS uses BCP-47 locale code for native speech synthesis.

### 🎯 15. Emergency Drill Mode

- Full simulation of SOS, volunteer response, dispatch chain — without impacting real incidents
- Drill UI banner distinguishes practice from live operations
- Drill route mirrors live routes (`/drill/dashboard`, `/drill/sos-intake`, `/drill/lifeline`)
- Used for community preparedness training

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Mobile / Web App** | Flutter 3.x (Dart), go_router v17, Riverpod 3 |
| **UI** | Material 3, flutter_animate, Lottie, shimmer, fl_chart |
| **Maps** | google_maps_flutter, flutter_map, geolocator, geocoding, flutter_polyline_points |
| **AI** | Gemini 2.5 Flash (triage vision, LIFELINE chat, scene brief, ops analytics) |
| **Voice AI** | LiveKit Agents (TypeScript), OpenAI Realtime API, @livekit/noise-cancellation-node |
| **WebRTC** | livekit_client (Flutter), livekit-server-sdk (Node.js) |
| **Backend** | Firebase Cloud Functions v2 (Node.js 18), 3,358 lines of production logic |
| **Database** | Cloud Firestore (real-time, offline persistence, 50 MB cache) |
| **Auth** | Firebase Auth (Google Sign-In, Email/Password, Anonymous, reCAPTCHA v3) |
| **Push** | Firebase Cloud Messaging (3-layer geo + topic + all-user dispatch) |
| **Storage** | Firebase Storage (scene photos, triage images, incident video) |
| **SMS** | Twilio (inbound GeoSMS webhook, outbound ETA & contact alerts) |
| **State Management** | flutter_riverpod, riverpod_annotation |
| **Localization** | flutter_localizations, intl (12 Indian languages) |
| **Security** | Firebase App Check (Play Integrity + DeviceCheck + reCAPTCHA v3) |
| **Monitoring** | Firebase Crashlytics, Firebase Performance |
| **Platforms** | Android, iOS, Web (3 hosted targets), Linux, Windows, macOS |

---

## Cloud Functions Reference

| Function | Trigger | Purpose |
|----------|---------|---------|
| `dispatchSOS` | Firestore onCreate `sos_incidents/{id}` | 3-layer FCM dispatch + hospital hex routing |
| `dispatchHospitalInHex` | Called by dispatchSOS | Score & order hospitals by hex ring + specialty |
| `hospitalDispatchEscalation` | Scheduled every 1 min | Auto-escalate if hospital doesn't accept in 2 min |
| `acceptHospitalDispatch` | Callable | Hospital accepts — triggers ambulance fleet notify |
| `declineHospitalDispatch` | Callable | Hospital declines — escalates to next hospital |
| `onHospitalAssignmentAcceptedDispatchAmbulance` | Firestore onUpdate | Notify nearest fleet units when hospital accepts |
| `acceptAmbulanceDispatch` | Callable | Operator accepts — sets EMS en-route, updates victim |
| `ambulanceDispatchEscalation` | Scheduled every 1 min | No operator? Escalate to next fleet unit / hospital |
| `expireStaleFleetPendingAssignments` | Scheduled every 1 min | Mark 3-min expired fleet assignments |
| `lifelineChat` | Callable | Gemini 2.5 Flash LIFELINE AI (chat/analytics/training modes) |
| `analyzeTriageImage` | Callable | Gemini vision triage from camera photo |
| `analyzeIncidentVideo` | Callable | Gemini video scene analysis (accepted volunteers only) |
| `generateSituationBriefForIncident` | Callable | Gemini scene brief from volunteer report + video + photos |
| `refreshSituationBriefsScheduled` | Scheduled every 5 min | Keep active incident briefs fresh |
| `getLivekitToken` | Callable | Mint WebRTC join token for emergency bridge (5 roles) |
| `getCopilotLivekitToken` | Callable | Mint copilot room token (per-user) |
| `ensureEmergencyBridge` | Callable | Dispatch Lifeline voice agent into incident room |
| `ensureCopilotAgent` | Callable | Dispatch Copilot voice agent (rate-limited, 2-min) |
| `dispatchLifelineComms` | Callable | Speak important comms text in emergency room |
| `ensureCommsBridgeRooms` | Callable | Create operation + emergency LiveKit rooms per incident |
| `getCommsBridgeLivekitToken` | Callable | Token for hospital/EMS comms bridge (3 channels) |
| `parseSmsGateway` | HTTP (Twilio webhook) | Parse GeoSMS → create/merge incident |
| `onIncidentUpdate` | Firestore onUpdate | SMS ETA updates back to victim phone |
| `notifyEmergencyContactOnUpdate` | Firestore onUpdate | SMS updates to emergency contact (rate-limited 2 min) |
| `updateLeaderboardOnIncidentChange` | Firestore onCreate `sos_incidents_archive/{id}` | Server-side leaderboard aggregation |
| `expireStaleSosIncidents` | Scheduled every 5 min | Hard 1h TTL → archive + delete active incidents |
| `expireStaleHospitalConsignments` | Scheduled every 5 min | Close hospital assignments after 1h |
| `enforceSosCreateLimits` | Firestore onCreate | Rate-limit flag (fail-open — never blocks real emergencies) |
| `onExternalIncidentTrigger` | HTTP (partner webhook) | Third-party incident/AED/readiness event ingestion |
| `refreshHospitalDispatchOnDispatchHints` | Firestore onUpdate | Re-dispatch if AI updates `dispatchHints` |
| `redispatchOnRequiredServicesChange` | Firestore onUpdate | Re-dispatch when required services change |
| `getOpsSystemHealth` | Callable | Integration health check (Firestore, LiveKit, SMS) |
| `opsSupportUserDigest` | Callable | Masked user lookup for ops support |
| `opsSupportForceSignOut` | Callable | Force sign-out a user (security) |

---

## Firestore Collections

```
sos_incidents/             Active emergencies (1h TTL then archived)
sos_incidents_archive/     Closed incidents (leaderboard trigger source)
ops_hospitals/             Hospital registry (lat, lng, beds, services, hex)
ops_incident_hospital_assignments/  Dispatch chain state per incident
ops_fleet_units/           Ambulance units (availability heartbeat 90s TTL)
ops_fleet_assignments/{callSign}/pending/  Per-operator dispatch queue
users/                     User profiles, medical history, FCM tokens
volunteers/                Volunteer presence with lat/lng for geo-query
leaderboard/               Pre-computed volunteer rankings
ptt_channels/{id}/messages/  Push-to-talk voice transcripts
livekit_bridges/           Emergency bridge dispatch records
livekit_copilot_dispatches/ Copilot agent rate-limit records
ops_dashboard_alerts/      Real-time ops feed (hospital dispatch events)
ops_health_metrics/        System counters (dispatch success/error rates)
sos_dispatch_limits/       Per-user geo-dispatch rate-limit state
sos_create_limits/         Per-user SOS creation rate-limit state
aeds/                      AED defibrillator locations (webhook-upsertable)
preparedness_events/       Community readiness event log
webhook_events/            Third-party trigger audit log
```

---

## App Variants (Three Hosted Targets)

| Variant | Entry Point | Hosted At | Primary Users |
|---------|-------------|-----------|---------------|
| **Main** | `main.dart` → `AppVariant.main` | `build/web-main` | Citizens, volunteers, patients |
| **Admin** | `main_admin.dart` → `AppVariant.admin` | `build/web-admin` | Operations command staff |
| **Fleet** | `main_fleet.dart` → `AppVariant.fleet` | `build/web-fleet` | Ambulance operators |

Each variant boots the same Flutter app with `buildRouter(variant)` applying role-specific routing guards, entry screens, and navigation shells.

---

## LiveKit Voice Rooms

| Room Name | Purpose | Participants |
|-----------|---------|-------------|
| `emergency_bridge_{incidentId}` | Victim ↔ Lifeline AI ↔ Volunteers ↔ EMS | victim, accepted_volunteer, volunteer_elite, ems_fleet, emergency_desk, emergency_contact |
| `copilot_{uid}` | Per-user persistent voice assistant | copilot_user_{uid}, Copilot AI agent |
| `commsop_{incidentId}` | Operation coordination voice | Hospital staff, EMS operator |
| `commsem_{incidentId}` | Emergency voice channel | Hospital emergency desk, EMS |
| `comms_command_net` | Master command voice net | Admin master console only |

Token TTL: 6 hours for emergency bridge, 12 hours for comms bridge.

---

## Local Setup

### Prerequisites
- Flutter SDK `^3.11.3`
- Node.js 18+
- Firebase CLI
- A Firebase project with Firestore, Auth, FCM, Storage, App Check enabled

### 1. Clone & Install

```bash
git clone https://github.com/shikhar1809/EmergencyOS_Google_Solution_Challenge.git
cd EmergencyOS_Google_Solution_Challenge
flutter pub get
```

### 2. Firebase Configuration

```bash
# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Configure your Firebase project
flutterfire configure
```

### 3. Cloud Functions Setup

```bash
cd functions
npm install

# Copy environment template
cp .env.example .env
# Edit .env with your keys:
# GEMINI_API_KEY=...
# LIVEKIT_URL=wss://your-project.livekit.cloud
# LIVEKIT_API_KEY=...
# TWILIO_ACCOUNT_SID=...  (optional)
# TWILIO_AUTH_TOKEN=...   (optional)
# TWILIO_PHONE_NUMBER=... (optional)

# Set LiveKit secret in Firebase Secret Manager
firebase functions:secrets:set LIVEKIT_API_SECRET

# Deploy functions
firebase deploy --only functions
```

### 4. LiveKit Agents Setup

**Lifeline voice agent** (reads important comms):
```bash
cd livekit-agent/lifeline-agent
npm install
cp .env.example .env.local
# Edit with LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET, OPENAI_API_KEY
npm run dev
```

**Copilot voice agent** (persistent AI assistant):
```bash
cd livekit-agent/copilot-agent
npm install
cp .env.example .env.local
npm run dev
```

### 5. Run the App

```bash
# Main app (citizens/volunteers)
flutter run -t lib/main.dart

# Admin console
flutter run -t lib/main_admin.dart

# Fleet operator panel
flutter run -t lib/main_fleet.dart
```

### 6. Firebase Hosting Deploy

```bash
# Build all three targets
flutter build web --release --dart-define RECAPTCHA_SITE_KEY=your_key
# (repeat with --target lib/main_admin.dart --output build/web-admin etc.)

firebase deploy --only hosting
```

---

## Environment Variables Reference

### Cloud Functions (`functions/.env`)

| Variable | Required | Description |
|----------|----------|-------------|
| `GEMINI_API_KEY` | Yes | Google Generative AI key for LIFELINE + triage |
| `LIVEKIT_URL` | Yes* | `wss://your-project.livekit.cloud` |
| `LIVEKIT_HTTP_URL` | Yes* | `https://your-project.livekit.cloud` (use if no wss URL) |
| `LIVEKIT_API_KEY` | Yes | LiveKit API key (Firebase parameter or env) |
| `LIVEKIT_API_SECRET` | Yes | LiveKit API secret (Firebase Secret Manager) |
| `LIFELINE_LIVEKIT_AGENT_NAME` | No | Default: `lifeline` |
| `COPILOT_LIVEKIT_AGENT_NAME` | No | Default: `copilot` |
| `TWILIO_ACCOUNT_SID` | Optional | SMS gateway (offline SOS relay) |
| `TWILIO_AUTH_TOKEN` | Optional | Twilio auth |
| `TWILIO_PHONE_NUMBER` | Optional | Sender number for outbound SMS |
| `WEBHOOK_SHARED_SECRET` | Optional | Shared secret for third-party incident webhook |

### LiveKit Agents (`.env.local`)

| Variable | Description |
|----------|-------------|
| `LIVEKIT_URL` | WebSocket URL |
| `LIVEKIT_API_KEY` | API key |
| `LIVEKIT_API_SECRET` | API secret |
| `OPENAI_API_KEY` | For Realtime voice model |

---

## Key Design Decisions

### Why hex-grid dispatch (not simple radius)?
Hex grids provide **uniform neighbor distance** in all 6 directions — no nearest-corner bias. The flat-top axial coordinate system allows precise `ring-0` (same cell) → `ring-5` (5 steps out) escalation with consistent km spacing, matching how real cities are zoned.

### Why 3-layer FCM instead of 1?
Layer 1 (geo-multicast) may fail if volunteers aren't subscribed to the topic or their token is stale. Layer 2 (topic) guarantees all subscribers get it. Layer 3 (all-users) is the safety net for unsubscribed devices. Each layer runs **independently** — one failure never silences another. This is the core reliability guarantee.

### Why fail-open on SOS rate limiting?
Real emergencies cannot be missed for the sake of preventing spam. Rate-limit violations are flagged (`rateLimitFlagged: true`) but **never block the incident**. Dispatch still fires. Ops can review flagged incidents.

### Why three separate web hosting targets?
Admin and fleet panels have different root routes, auth guards, navigation logic, and even Firebase project options. Separate compilations allow independent deployments, isolated cache headers, and role-based access at the CDN level.

### Why LiveKit over proprietary WebRTC?
LiveKit provides an open, self-hostable WebRTC SFU with agent dispatch APIs — critical for an emergency platform that must not depend on a single commercial provider's availability during disasters. The `AgentDispatchClient` allows us to push AI voice agents into rooms programmatically from Cloud Functions.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. All contributions welcome — especially:
- Additional language translations (`lib/core/l10n/`)
- New LIFELINE training levels (`lib/features/ai_assist/domain/lifeline_training_levels.dart`)
- Hospital and AED database integrations
- OSRM / offline routing improvements

---

## License

MIT — See [LICENSE](LICENSE)

---

## Acknowledgements

Built with ❤️ for the **Google Solution Challenge 2026** under the **Rapid Emergency Response** theme (Open Track).

Powered by Google Cloud, Firebase, Gemini AI, Google Maps Platform, LiveKit, and OpenAI.

---

<div align="center">

**Built by Shikhar Shahi**

*For every family that deserves a faster, smarter emergency response.*

</div>
