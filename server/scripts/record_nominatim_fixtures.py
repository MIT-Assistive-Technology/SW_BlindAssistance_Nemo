"""Save real Nominatim responses for tests/test_geocode.py (BE-2).

Run from server/ after setting USER_AGENT in .env:

    python scripts/record_nominatim_fixtures.py                    # addresses not saved yet
    python scripts/record_nominatim_fixtures.py --force            # re-record everything
    python scripts/record_nominatim_fixtures.py --only mit-stata   # just one address

It sends the exact query geocode() sends, one request per address and at most one per second
(Nominatim's usage policy), and writes tests/fixtures/nominatim/<id>.json. Commit those files:
the tests replay them and never call Nominatim themselves. The summary at the end shows what
each address resolved to, so you can fix an address in addresses.json before committing.
"""

import argparse
import importlib
import json
import os
import sys
from datetime import UTC, datetime
from pathlib import Path

import httpx

SERVER = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER))  # so `app` imports when run as a plain script
resolver = importlib.import_module("app.resolver")

FIXTURES = SERVER / "tests" / "fixtures" / "nominatim"
NEAR_M = 300  # keep in sync with tests/test_geocode.py


def load_dotenv(path: Path) -> None:
    """Minimal .env reader so this script needs no extra dependency. Real env vars win."""
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip("\"'"))


def describe(entry: dict, response: list[dict]) -> str:
    """One line on what geocode() makes of this response, flagging what the tests will reject."""
    parsed = resolver.parse_address(entry["address"])
    try:
        point = resolver.point_from_results(response, parsed)
    except resolver.GeocodeNotFound as exc:
        status = "ok" if entry.get("expect") == "not_found" else "PROBLEM"
        return f"{status}: not found ({exc})"
    if entry.get("expect") == "not_found":
        return f"PROBLEM: expected not found, got {point.category}/{point.type}"

    problems = []
    if point.precision != "house":
        problems.append("only the street matched")
    if "near" in entry:
        meters = resolver._meters_between((point.lat, point.lon), tuple(entry["near"]))
        if meters >= NEAR_M:
            problems.append(f"{meters:.0f} m from 'near'")
    status = "PROBLEM: " + ", ".join(problems) if problems else "ok"
    doors = len(point.entrances)
    return (
        f"{status} ({point.category}/{point.type}, {point.osm_ref}, "
        f"{point.lat:.5f},{point.lon:.5f}, {doors} usable door{'s' * (doors != 1)})"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--force", action="store_true", help="re-record saved addresses too")
    parser.add_argument("--only", nargs="+", metavar="ID", help="record only these ids")
    args = parser.parse_args()

    load_dotenv(SERVER / ".env")
    user_agent = os.environ.get("USER_AGENT", "")
    if not user_agent.strip():
        print("Set USER_AGENT in server/.env first (copy .env.example to .env).")
        return 1
    if "team contact" in user_agent:
        print("Note: USER_AGENT still has the placeholder contact from .env.example.")

    manifest = json.loads((FIXTURES / "addresses.json").read_text(encoding="utf-8"))["addresses"]
    unknown = set(args.only or []) - {e["id"] for e in manifest}
    if unknown:
        print(f"Unknown id(s): {', '.join(sorted(unknown))}")
        return 1

    base_url = os.environ.get("NOMINATIM_URL", resolver.DEFAULT_NOMINATIM_URL).rstrip("/")
    failures = 0
    with httpx.Client() as client:
        for entry in manifest:
            if args.only and entry["id"] not in args.only:
                continue
            path = FIXTURES / f"{entry['id']}.json"
            if path.exists() and not args.force:
                print(f"{entry['id']}: already saved (use --force to re-record)")
                continue

            params = resolver.nominatim_params(resolver.parse_address(entry["address"]))
            try:
                response = resolver.nominatim_search(params, client)  # rate-limited to 1/s
            except resolver.UpstreamUnavailable as exc:
                print(f"{entry['id']}: FAILED, nothing saved ({exc})")
                failures += 1
                continue

            record = {
                "id": entry["id"],
                "address": entry["address"],
                "recorded_at": datetime.now(UTC).isoformat(timespec="seconds"),
                "url": f"{base_url}/search",
                "params": params,
                "response": response,
            }
            text = json.dumps(record, indent=2, ensure_ascii=False) + "\n"
            path.write_text(text, encoding="utf-8")
            print(f"{entry['id']}: {describe(entry, response)}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
