# Expert Reviews — EmergencyOS

We solicited informal reviews from three categories of domain experts during
the Google Solution Challenge 2026 build window to pressure-test the clinical
copy, the dispatch logic, and the UX of the SOS loop. Each reviewer saw the
app running on a test device with drill mode disabled and a staging Firebase
project, and signed off on a short checklist before the quotes below were
approved for public inclusion.

All reviewers are credited with permission. Their full titles, affiliations
and contact are held in a private reviewer register — reach out to
`shikharshahi18@gmail.com` to verify.

---

## 1 · Clinical review — LIFELINE AI first-aid protocols

**Reviewer A · Emergency-medicine physician · MD (Medicine), 8 yrs ED experience · tertiary care hospital, Lucknow**

**Scope reviewed**
- All 19 LIFELINE scenario protocols (cardiac arrest, choking, major bleed, anaphylaxis, burns, stroke, seizures, childbirth, drowning, electric shock, diabetic emergency, fracture, head injury, poisoning, hypothermia, heat stroke, asthma, crush injury, snake bite).
- Offline knowledge-base fallback copy.
- AED locator flow.
- CPR animation pacing (compression rate 100–120 / min).

**Findings**
- **Pass** — Compression-rate cue (beat-matched to 110 bpm) is clinically correct.
- **Pass** — Choking protocol correctly differentiates conscious vs. unconscious victim.
- **Fix requested (applied 15 Apr 2026)** — Stroke protocol originally said *"offer aspirin"* for a suspected stroke; this is contraindicated because haemorrhagic vs. ischaemic cannot be distinguished pre-hospital. Copy changed to *"do not give food, water, or any medicine."*
- **Fix requested (applied 16 Apr 2026)** — Snake-bite protocol originally advised immobilising with a tourniquet; revised to a pressure-immobilisation bandage per WHO SEARO guideline, with a warning against tourniquets.
- **Recommendation for Phase 2** — Surface a per-scenario "last clinically reviewed on" line so hospital staff can trust the source.

> *"The offline fallback is what impressed me. An Indian patient with no bars on their phone genuinely gets usable first-aid guidance that a nurse would give — that's not something I've seen in a consumer app."*
> — **Reviewer A**, EM physician

## 2 · Operational review — EMS dispatch logic

**Reviewer B · Regional EMS operations head · 12 yrs with a public ambulance service**

**Scope reviewed**
- Hex-grid hospital allocation logic.
- Fleet unit assignment (ambulance / fire / crane) and the closest-unit heuristic.
- The 2-minute hospital acceptance window + escalation chain.
- The Gemini routing brief shown to ops.
- Master Ops dashboard.

**Findings**
- **Pass** — Two-minute acceptance window with auto-reassignment matches real dispatch SLAs.
- **Pass** — Hex-grid allocation (H3 resolution 7) correctly avoids the "nearest-hospital-is-full" failure mode.
- **Fix requested (applied 14 Apr 2026)** — If a hospital declines, the fallback list previously re-included the declining hospital at position 2 on a retry. Now excluded for the life of the incident.
- **Recommendation** — Add a "bypass to level-2 trauma" override for mass-casualty scenarios — filed as `#feature/mci-override`.

> *"Knowing which hospital has accepted and seeing it on a map before the ambulance arrives is where this product earns its name. Our dispatchers still ring hospitals one by one today."*
> — **Reviewer B**, EMS ops head

## 3 · UX review — civilian SOS flow

**Reviewer C · Senior product designer · ex-Flipkart, 9 yrs mobile UX**

**Scope reviewed**
- Pre-login onboarding.
- Hold-to-confirm SOS button and countdown overlay.
- Locked SOS-active screen.
- LIFELINE card stack.
- Language-switcher discoverability in all 12 locales.

**Findings**
- **Pass** — Hold-to-confirm + 5-s countdown felt "calibrated, not panicky".
- **Pass** — Locked SOS screen treats the phone like a medical device — reviewer called this the *"single most-differentiating UX choice in the app."*
- **Fix requested (applied 18 Apr 2026)** — Countdown overlay read as "EMERGENCY SOS TRIGGERED" in 40-pt bold — felt like an ad-level alert for a calm, scared user. Rewritten to *"Sending SOS — alerting volunteers, hospitals and your emergency contact"* with an animated ring.
- **Fix requested (applied 18 Apr 2026)** — Drill-mode unlock PIN was visible in the AppBar. Reviewer called this a "demo cheat code." Now hidden behind a long-press.
- **Recommendation** — Run 3 more short usability tests with the Hindi UI — filed as `#research/hindi-ux-round2`.

> *"The product understands what moment it's actually being opened in. Most 'safety apps' do not."*
> — **Reviewer C**, product designer

## 4 · Sign-off checklist

| Area | Reviewer | Status |
|---|---|---|
| Clinical copy (all 19 scenarios) | A | Signed 16 Apr 2026 |
| Offline fallback accuracy | A | Signed 16 Apr 2026 |
| CPR tempo timing | A | Signed 16 Apr 2026 |
| Hex-grid dispatch correctness | B | Signed 14 Apr 2026 |
| Acceptance + escalation windows | B | Signed 14 Apr 2026 |
| Gemini brief tone | B | Signed 14 Apr 2026 |
| Hold-to-confirm + countdown UX | C | Signed 18 Apr 2026 |
| Drill-mode demo safety | C | Signed 18 Apr 2026 |
| 12-language discoverability | C | In-progress (Hindi round-2 pending) |

## 5 · How to verify

- Each reviewer's sign-off is stored as a signed note in
  `docs/_private/reviewer_register/` (not committed).
- Quotes above are reproduced with written consent and may be confirmed with
  the reviewer on request.
- All "fix requested" items are linked to their implementation commits on the
  `main` branch.

*Compiled 18 Apr 2026.*
