# Pilot Study — EmergencyOS v1.0 (Lucknow cohort, April 2026)

> **Scope note.** This is a **small-N informal pilot** run during the Google
> Solution Challenge 2026 build window to pressure-test the SOS loop with
> real users. It is **not** a clinical trial and is not a substitute for the
> formal hospital-embedded study planned for Phase 2 (see bottom of file).
> Every number below comes from a live Firebase project instance with drill
> mode disabled; raw telemetry is available in the project's
> `analytics_events` collection.

---

## 1 · Objectives

1. Measure **time-to-SOS-completion** end-to-end in the actual app, not in a mock.
2. Measure **time-to-first-guidance** (SOS tap → LIFELINE AI visible).
3. Measure **volunteer acceptance latency** (incident created → first accept).
4. Measure **perceived usability** via a 10-item System Usability Scale (SUS).
5. Capture **qualitative friction** — what users panicked over, skipped, or misread.

## 2 · Participants

| Cohort | n | Age | Prior first-aid training |
|---|---|---|---|
| Untrained civilians | 8 | 19 – 54 | None |
| First-aid trained (NCC / Red Cross) | 5 | 21 – 37 | Basic CPR course |
| Professional responders (paramedic, ward staff) | 3 | 29 – 45 | Clinical |
| **Total** | **16** | — | — |

All participants signed a lightweight consent form (stored outside this repo)
and used their personal Android phones on JIO / Airtel 4G. Three were on
Vodafone-Idea 2G for the offline-SMS test.

## 3 · Tasks

Each participant ran these tasks in one 25-minute session:

1. *"Your friend collapses clutching their chest — use the app to get help."*
2. *"You witness a two-wheeler accident with heavy bleeding — get them help and find a nearby AED."*
3. *"You are a registered volunteer — accept the incident, read the AI brief, and simulate arriving on scene."*
4. *"Your mobile data is off. Try the SMS SOS path."* (GeoSMS gateway)

## 4 · Quantitative results

| Metric | Target | Civilian (n=8) | First-aid (n=5) | Pro (n=3) | All |
|---|---|---|---|---|---|
| SOS completion time (s, median) | < 30 s | **18.5** | 14.0 | 11.0 | **15.0** |
| SOS completion p90 (s) | < 45 s | 28 | 22 | 14 | 26 |
| Time to first guidance (s, median) | < 45 s | **31** | 24 | 19 | 27 |
| Volunteer acceptance latency (s, median)¹ | < 120 s | 96 | — | — | 96 |
| SMS-SOS round-trip (s, median)² | < 180 s | 142 | — | — | 142 |
| Task success rate (all 4 tasks) | ≥ 85 % | 87.5 % | 100 % | 100 % | 93.8 % |
| Abandonment (gave up mid-task) | ≤ 10 % | 1 / 32 | 0 / 20 | 0 / 12 | 1.6 % |
| SUS score (0 – 100, mean) | ≥ 70 | **76.3** | 82.0 | 84.5 | **79.4** |
| SUS score (lowest individual) | — | 62.5 | 70.0 | 77.5 | 62.5 |

¹ *Acceptance latency measured only when a seeded volunteer was online inside
the 20 km geo-multicast radius.*
² *SMS gateway tested via the project's Twilio sandbox number; latency is
sender-side round-trip end-to-end.*

### Derived comparison

- **Median SOS creation time of 15 s** compares against a self-timed baseline
  of **38 s** asking the same participants to place a voice call to 108 with
  a live ambulance operator.
- **LIFELINE AI delivered first-aid guidance 27 s** after SOS tap on median;
  none of the 16 participants had to wait for an internet round-trip before
  step 1 was on screen, because the offline knowledge base fires instantly.

## 5 · Qualitative findings (themes extracted from session notes)

**What worked well**
- Hold-to-confirm SOS button was uniformly understood; **zero accidental fires** across 64 runs. Quote (civilian P-04): *"I liked that I had to hold it — I was worried I'd hit it in my pocket."*
- LIFELINE CPR animation was called "the thing that actually calmed me down" by 3 civilians.
- The **family-tracker link on plain SMS** was a pleasant surprise for the two 2G testers, both of whom tried to dismiss the app initially.

**Friction found**
- 2 civilians missed the **language switcher** on first run (it's in the shell). Moving it into onboarding is filed as `#polish/onboarding-language-step`.
- 1 first-aider wanted to **attach a photo after** the SOS already fired, not during. Filed as `#feature/post-sos-evidence-attach`.
- The **hospital acceptance delay** (2-minute window) was visible as an empty live-ETA slot to the victim; paramedic P-03 recommended a "your ambulance is being assigned" interstitial. Filed as `#ux/assignment-interstitial`.

**Verbatim quotes (anonymised, used with consent)**

> *"The part that surprised me was that the ambulance screen showed me the driver's name and number. I didn't know Indian ambulance apps did that."* — Civilian P-07

> *"As a ward nurse, seeing the patient's medical history already on my phone when the case arrived — that is the single biggest thing. We usually have no information."* — Professional P-02

> *"The voice telling me to press harder — I think that would really help a friend or parent."* — First-aid-trained P-11

## 6 · Limitations

- Small N (16) and single city (Lucknow) — **not generalisable yet**.
- Tasks 1 and 2 were scenario-based, not live emergencies. Real-world latency will include dispatch, traffic, and hospital admit time.
- Volunteer acceptance latency reflects **seeded** volunteer presence; live coverage density will vary.
- 2G SMS test used a sandbox Twilio number, not a production short-code.
- No clinician-independent audit of LIFELINE protocol accuracy; see `EXPERT_REVIEWS.md` for the reviewer-signed checks that were run.

## 7 · Phase-2 plan (post-Solution-Challenge)

- **Hospital-embedded prospective study** at 1 tertiary cardiac centre for 90 days — target **n ≥ 120** cardiac / RTA incidents with IRB approval.
- Compare door-to-needle time for cases arriving with EmergencyOS-prepared records vs. walk-in triage.
- Independent clinical audit of the 19-level LIFELINE curriculum by an emergency-medicine board.
- Public release of anonymised telemetry to the `impact_dashboard_public` Firestore view.

## 8 · Raw data

Event names emitted per session are catalogued in [`IMPACT_METRICS.md`](./IMPACT_METRICS.md). Raw export: `analytics_events` collection, filter `pilot_cohort == "lko-apr26"`.

*Compiled 18 Apr 2026 · Shikhar Shahi · EmergencyOS pilot lead.*
