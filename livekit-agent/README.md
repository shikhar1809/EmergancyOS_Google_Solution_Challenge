# LiveKit Agents

This folder ships the two LiveKit voice agents that EmergencyOS dispatches
into LiveKit rooms from Cloud Functions. Both agents speak in response to
jobs the server creates — users do not need to discover or address them
manually.

```
livekit-agent/
├── lifeline-agent/   One-shot TTS reader used inside emergency rooms.
└── copilot-agent/    Persistent per-user assistant that explains screens.
```

## How they fit together

```
Flutter client ─────▶ Cloud Functions (functions/)
                         │
                         │ AgentDispatchClient.createDispatch(...)
                         ▼
                    LiveKit Cloud / self-host
                         │
                         ├──▶ lifeline-agent  (agentName: "lifeline")
                         │      Joins the active SOS/hospital room, reads the
                         │      `importantComms` metadata field verbatim,
                         │      then shuts down. Stateless and one-shot.
                         │
                         └──▶ copilot-agent   (agentName: "copilot")
                                Joins a private user room, listens, and
                                explains the current Flutter route using the
                                `copilot_context` data channel. Persistent
                                until the user ends the call.
```

- Cloud Functions mint LiveKit access tokens and trigger dispatch with
  `AgentDispatchClient` using the `agentName` each agent registers.
- Agent names are fixed in `main.ts`:
  - `lifeline-agent/main.ts` → `agentName: 'lifeline'`
  - `copilot-agent/main.ts`  → `agentName: 'copilot'`
  They can be overridden from Cloud Functions via the environment variables
  `LIFELINE_LIVEKIT_AGENT_NAME` / `COPILOT_LIVEKIT_AGENT_NAME`.
- Both agents read LiveKit credentials from `.env.local` at startup. They
  do **not** touch Firebase; all data plumbing happens through LiveKit room
  metadata and data channels.

## lifeline-agent

**Role:** Read critical comms aloud in an emergency room (ambulance dispatch
details, hospital hand-off confirmation, triage update) without any
conversational back-and-forth.

**Pipeline:** OpenAI Realtime model (`voice: 'coral'` by default) with
background noise cancellation. No VAD / STT / turn detection because the
agent never listens — it speaks and exits.

**Input contract:** Job metadata carries the text in one of these keys
(checked in order):

```jsonc
{
  "importantComms": "Cardiac arrest inbound, ETA 4 minutes, AIIMS bay 3",
  // or snake_case / legacy alias:
  "important_comms": "...",
  "text": "..."
}
```

**Lifecycle:**

1. `defineAgent.entry` starts an `AgentSession` with the realtime model.
2. Connects to the room, reads `importantComms`, `waitForPlayout()`.
3. Calls `session.shutdown()`. The job terminates automatically.

**Local dev:**

```bash
cd livekit-agent/lifeline-agent
npm install
cp .env.example .env.local   # Fill LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET
npm run dev
```

`npm run dev` uses `node --env-file=.env.local` + `tsx` so there is no build
step. For production, run the same command under a process manager (pm2,
systemd) on a machine that can reach your LiveKit control plane.

## copilot-agent

**Role:** A persistent voice assistant the user can tap from any screen.
It explains the current Flutter route, walks through features, and guides
users through first-aid protocols (CPR, choking, bleeding, burns, heart
attack, stroke, seizure, allergy, drowning, fracture) when asked. It never
triggers SOS on its own.

**Pipeline:**

| Stage               | Component |
|---------------------|-----------|
| Voice activity det. | Silero VAD (pre-warmed in `prewarm`) |
| STT                 | `deepgram/nova-3:multi` (multilingual) |
| LLM                 | `google/gemini-2.5-flash` |
| TTS                 | `cartesia/sonic-3` |
| Turn detection      | LiveKit `turnDetector.MultilingualModel` |
| Noise cancellation  | `@livekit/noise-cancellation-node` |

**Input contract:** Two sources of context:

1. **Job metadata** — `walkthrough: true|false` toggles the on-boarding
   walkthrough persona.
2. **`copilot_context` data channel** — the Flutter client sends small JSON
   frames whenever the route changes:
   ```jsonc
   {
     "route": "/sos/active",
     "title": "SOS Active",
     "digest": "Ambulance ETA 6 min. Volunteer 320m away.",
     "walkthrough": false
   }
   ```
   The agent merges these into an in-memory page context string that the
   `getAppPageContext` tool exposes to the LLM.

**Tools exposed to the LLM:**

- `getAppPageContext()` — returns the latest route + digest.
- `getMedicalProtocol({ topic })` — looks up a canned protocol (CPR,
  choking, bleeding, burns, heart_attack, stroke, seizure,
  allergic_reaction, drowning, fracture).

Base instructions (in `copilot_agent.ts`) forbid markdown, emojis, and
hallucinated SOS actions — voice safety first.

**Local dev:**

```bash
cd livekit-agent/copilot-agent
npm install
cp .env.example .env.local   # Same three LIVEKIT_* keys as lifeline-agent
npm run dev
```

The agent expects the LLM/STT/TTS credentials to be configured at the
LiveKit project level (LiveKit routes the provider calls server-side). No
`OPENAI_API_KEY` / `GOOGLE_API_KEY` is required in the agent's `.env.local`
in that mode. If you self-host without LiveKit's hosted inference, set the
matching provider API keys via the LiveKit agents plugin conventions.

## Environment

`.env.local` for both agents:

```env
LIVEKIT_URL=wss://your-project.livekit.cloud
LIVEKIT_API_KEY=...
LIVEKIT_API_SECRET=...
```

In production, keep `LIVEKIT_API_SECRET` in a secret manager (Firebase
Secret Manager for Cloud Functions, GCP Secret Manager / AWS SSM for the
agent hosts).

## Deploying

Either agent is a plain long-running Node process. Any platform that can
run `npm run start` works:

- **Bare metal / VM:** `pm2 start npm -- run start` inside each folder.
- **Docker:** a minimal `node:22-alpine` image, `npm ci`, then the same
  start command. Expose no ports — LiveKit initiates the connection
  outward to its control plane.
- **Cloud Run (pull-based):** works because LiveKit agents connect *out*
  to the control plane; set `min-instances=1` so idle instances stay
  warm enough to claim dispatched jobs.

Make sure both agents reach the LiveKit URL configured in Cloud Functions
so that server-side `AgentDispatchClient` calls from `functions/` can route
jobs to them.

## Troubleshooting

- **Agent never joins the room** — check that `agentName` in `main.ts`
  matches the `agentName` Cloud Functions uses when calling
  `AgentDispatchClient.createDispatch`. Mismatched names silently drop
  dispatches.
- **Lifeline stays silent** — confirm `importantComms` is present in the
  job metadata payload you send from Cloud Functions.
- **Copilot has no screen context** — verify the Flutter client is
  publishing data frames on the `copilot_context` topic. The agent only
  listens to that exact topic string.
- **Realtime voice is choppy** — LiveKit noise cancellation is native
  (`@livekit/noise-cancellation-node`); on ARM hosts you may need to
  rebuild the native module or disable it in `inputOptions`.
