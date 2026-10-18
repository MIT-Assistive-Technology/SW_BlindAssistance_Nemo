"""Score the pilot entrance bundles against golden ground truth (QA-2 / BE-12).

Run from server/ (or anywhere; the defaults are absolute):

    python scripts/evaluate_bundles.py                    # writes docs/evaluation/latest.md
    python scripts/evaluate_bundles.py --json             # also docs/evaluation/latest.json
    python scripts/evaluate_bundles.py --bundles ../server/bundles --golden ../golden/locations.json \
        --out ../docs/evaluation/latest.md --json out.json

The scoring rules are in app/evaluate.py. Always exits 0 once the report is written: the
verdict is in the report, not the exit code. Prints NOT ENOUGH DATA when fewer than 5 golden
sites are both measured and bundled.
"""

import argparse
import json
import sys
from pathlib import Path

SERVER = Path(__file__).resolve().parents[1]
REPO = SERVER.parent
sys.path.insert(0, str(SERVER))  # so `app` imports when run as a plain script

from app import evaluate


def load_bundles(folder: Path) -> tuple[dict[str, dict], list[str]]:
    """bundle id (file stem) -> bundle dict, plus a note for each unreadable file."""
    bundles, problems = {}, []
    for path in sorted(folder.glob("*.json")) if folder.is_dir() else []:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            problems.append(f"{path.name}: unreadable ({exc})")
            continue
        if not isinstance(data, dict):
            problems.append(f"{path.name}: not a bundle object")
            continue
        bundles[evaluate.bundle_key(path.stem, data)] = data
    return bundles, problems


def _rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPO).as_posix()
    except ValueError:
        return str(path)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--bundles", type=Path, default=SERVER / "bundles")
    parser.add_argument("--golden", type=Path, default=REPO / "golden" / "locations.json")
    parser.add_argument("--sites", type=Path, default=SERVER / "pilot_sites.json")
    parser.add_argument("--out", type=Path, default=REPO / "docs" / "evaluation" / "latest.md")
    parser.add_argument(
        "--json",
        nargs="?",
        const=True,
        default=None,
        metavar="PATH",
        help="also write the full report as JSON (default path: --out with .json)",
    )
    args = parser.parse_args(argv)

    locations = json.loads(args.golden.read_text(encoding="utf-8"))["locations"]
    pilot = []
    if args.sites.is_file():
        pilot = json.loads(args.sites.read_text(encoding="utf-8")).get("sites", [])
    bundles, problems = load_bundles(args.bundles)

    report = evaluate.evaluate(locations, bundles, pilot)
    report["notes"] += problems
    sources = {"bundles": _rel(args.bundles), "golden": _rel(args.golden)}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(evaluate.render_markdown(report, sources), encoding="utf-8")
    print(f"wrote {_rel(args.out)}")
    if args.json is not None:
        json_path = args.out.with_suffix(".json") if args.json is True else Path(args.json)
        json_path.parent.mkdir(parents=True, exist_ok=True)
        json_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {_rel(json_path)}")

    cov = report["coverage"]
    print(
        f"{cov['golden_sites']} golden sites, {len(bundles)} bundles, "
        f"{cov['measured']} measured and scored, {cov['skipped']} skipped."
    )
    if not report["enough_data"]:
        print(
            f"NOT ENOUGH DATA: {cov['measured']} measured site(s); "
            f"need at least {evaluate.MIN_MEASURED_SITES}."
        )
    print(f"M1 verdict: {report['go_no_go']['overall']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
