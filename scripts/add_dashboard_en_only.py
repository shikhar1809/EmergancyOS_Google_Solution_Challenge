#!/usr/bin/env python3
"""Append missing phrases to kDashboardL10nByLang['en'] and kDashboardEnglishToKey.

Other locales fall back to English via opsTr when a key is absent.
Run from repo root: python scripts/add_dashboard_en_only.py
"""
from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DART = ROOT / "lib" / "core" / "l10n" / "dashboard_l10n.dart"


def slug(s: str, max_len: int = 40) -> str:
    h = hashlib.sha1(s.encode("utf-8")).hexdigest()[:10]
    base = re.sub(r"[^a-z0-9]+", "_", s.lower())[:max_len].strip("_")
    if not base:
        base = "s"
    return f"{base}_{h}"


def dart_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace("'", "\\'")


def main() -> int:
    text = DART.read_text(encoding="utf-8")

    m = re.search(r"(\n  'en': \{)(.*?)(\n  \},\n  'gu':)", text, re.DOTALL)
    if not m:
        print("Could not locate 'en' block before 'gu'", file=sys.stderr)
        return 1

    en_body = m.group(2)
    existing_keys = set(re.findall(r"'(ops_[^']+)':\s*'", en_body))
    english_by_key: dict[str, str] = {}
    for mm in re.finditer(r"'(ops_[^']+)':\s*'((?:\\'|[^'])*)'", en_body):
        english_by_key[mm.group(1)] = mm.group(2).replace("\\'", "'")

    english_to_key = {v: k for k, v in english_by_key.items()}

    new_phrases = [
        # Management hub & workspace
        "Volunteers",
        "Hospitals",
        "Facility setup",
        "Tap inside {zone} to place the hospital.",
        "Tap inside {zone}.",
        "Could not save location.",
        "Available",
        "No operator signed in",
        "Dispatched / busy",
        "Busy / dispatched",
        "Hospital location",
        "Exact point — saved with onboarding",
        "Type",
        "Status",
        "Incident",
        "Stationed at",
        "Position",
        "Updated",
        "Region",
        "Beds",
        "Services",
        "Get credentials",
        "Credentials…",
        "Tap a fleet marker or pick a unit in the list to manage it.",
        "Tap a hospital marker or pick a row in the list for capacity and onboarding.",
        "Select a category in the left column.",
        "No fleet documents in Firestore for this view.",
        "Responding · {incident}",
        "Standby / available",
        "Registered · no operator signed in",
        "Off duty / unavailable",
        "Approvals and Lookup are open in the main area →",
        "No hospitals in ops_hospitals yet.",
        "Live grid · {detail}",
        "Onboard facility",
        "Hospital doc ID (ops_hospitals)",
        "Display name",
        "City / area",
        "Tap the map at the exact hospital entrance or main drop-off point.",
        "Orange pin shows the saved point. Adjust by tapping elsewhere, or continue.",
        "Continue to credentials",
        "unit",
        "units",
        # Live ops sidebar (master)
        "SOS",
        "Feedback",
        # Analytics dashboard
        "All SOS incidents, hex density, EMS mix, and triage in the main pane.",
        "Dispatch and EMS workflow emphasis — map still shows live pins.",
        "Hotspots, triage severity, and SMS-linked cases.",
        "Volunteer attachment counts and responder lines on the map.",
        "Post-incident ratings and comments from resolved SOS flows.",
        "Analytics is available to Master and Medical console roles.",
        "Community post-incident feedback",
        "Live operations analytics",
        "Ratings and comments from resolved SOS cases",
        "Hex overlay: 48h incident density (blue → orange, tappable) on top; operational coverage tier grid (toggle) matches Live Ops overview.",
        "Cancel hex pick",
        "Select hex cell",
        "Map zoomed to the selected hex. Tap Clear selection in the left rail to reset the view.",
        "Pick a hex, then Confirm to zoom in and inspect.",
        "Fetching environmental data...",
        "AQI: {aqi} ({category})",
        "Hex {key}",
        "Unknown",
        # Hospital live ops / analytics
        "No hospital ID bound — sign in with a facility document ID.",
        "Medical console only",
        "No hospital rows for your scope.",
        "Beds available",
        "Beds total",
        "Trauma / capacity notes",
        "Doctors on duty",
        "Specialists on call",
        "Blood units available (approx.)",
        "Map: online",
        "Map: offline",
        "Update failed.",
        "En route",
        "On scene",
        "Returning",
        "ICU",
        "ENT",
        "Trauma support",
        "Child care",
        "Blood availability",
        "Burn unit",
        "Ventilators",
        "Cardiac cath lab",
        "No hospital data available",
        "Volunteer Management",
        "Approvals: review uploaded certificates. Lookup: find any volunteer by UID or email, moderate, and inspect incidents & submissions.",
        "Next: tap the map at the hospital's exact entrance or ambulance bay, then continue to generate staff credentials.",
        "Tap the map to move the pin, then Save.",
        "Hospital location (edit)",
        "Move the orange pin on the map, then save.",
        "ID",
        "GPS",
        "{available} available / {total} capacity",
        "{zone} · map locked to this area",
        "Hospital {id}",
        "{active} active · {in_zone} in zone",
        "+{count} more",
        "{n48} incidents in cell (48h bin) · {pins} pin(s) located in cell",
        "{count} incidents (48h) in this hex",
        "Cell {key}",
        "{active} active · {in_zone} · zoom {zoom}",
        "Facility {bound}",
        "Fleet on call (EMS)",
    ]

    to_add: list[tuple[str, str]] = []
    for phrase in new_phrases:
        if phrase in english_to_key:
            continue
        k = "ops_" + slug(phrase)
        while k in existing_keys:
            k = k + "x"
        existing_keys.add(k)
        english_to_key[phrase] = k
        to_add.append((k, phrase))

    if not to_add:
        print("All phrases already present.")
        return 0

    lines = [f"    '{k}': '{dart_escape(v)}'," for k, v in to_add]
    new_en_body = en_body + "\n" + "\n".join(lines)

    text = text[: m.start(2)] + new_en_body + text[m.end(2) :]

    m2 = re.search(
        r"(const Map<String, String> kDashboardEnglishToKey = \{)(.*?)(\n\};\n\nextension DashboardL10nContext)",
        text,
        re.DOTALL,
    )
    if not m2:
        print("Could not locate kDashboardEnglishToKey", file=sys.stderr)
        return 1

    rev_lines = [f"  '{dart_escape(v)}': '{k}'," for k, v in to_add]
    new_rev = m2.group(2) + "\n" + "\n".join(rev_lines)
    text = text[: m2.start(2)] + new_rev + text[m2.end(2) :]

    DART.write_text(text, encoding="utf-8", newline="\n")
    print(f"Added {len(to_add)} English-only dashboard strings to {DART}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
