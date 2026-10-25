"""Build the pilot entrance bundles (the MVP deliverable, plan sections 2 and 8).

Run from server/:

    python scripts/build_bundles.py                          # every site in pilot_sites.json
    python scripts/build_bundles.py --only mit-stata         # one site (repeatable)
    python scripts/build_bundles.py --offline                # saved responses only, no network
    python scripts/build_bundles.py --refresh                # re-fetch Overpass, ignore the cache

Each site runs the ladder (geocode -> find_building -> read_entrances -> facade_fallback ->
path checks), is validated against app/models.ResolveResult, and is written to
bundles/<id>.json. A step that fails is reported with its name and the other sites keep going.
Exit code 1 if any site did not produce a bundle.

Overpass responses are cached in tests/fixtures/overpass/. A live run saves them there; commit
them (small, ODbL) so --offline rebuilds the same bundles. Nominatim responses come from
tests/fixtures/nominatim/ offline (record new ones with scripts/record_nominatim_fixtures.py).
data_version.osm is the Overpass data timestamp unless --osm-version is given.
"""

import argparse
import functools
import os
import sys
from datetime import UTC, datetime
from pathlib import Path

import httpx

SERVER = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER))  # so `app` imports when run as a plain script

from record_nominatim_fixtures import load_dotenv  # scripts/, next to this file

from app import bundle, doors, overpass, resolver
from app.models import DataVersion

SITES = SERVER / "pilot_sites.json"
BUNDLES = SERVER / "bundles"
FIXTURES = SERVER / "tests" / "fixtures" / "nominatim"
OVERPASS_FIXTURES = SERVER / "tests" / "fixtures" / "overpass"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--only", action="append", metavar="ID", help="build just this site")
    parser.add_argument("--offline", action="store_true", help="no network: saved responses")
    parser.add_argument("--refresh", action="store_true", help="re-fetch every Overpass query")
    parser.add_argument("--sites", type=Path, default=SITES)
    parser.add_argument("--out", type=Path, default=BUNDLES)
    parser.add_argument(
        "--osm-version",
        help="date of the OSM data used, for data_version.osm (default: the Overpass "
        "timestamp, else today, UTC)",
    )
    args = parser.parse_args(argv)
    if args.offline and args.refresh:
        parser.error("--refresh needs the network; drop --offline")

    sites = bundle.load_sites(args.sites)
    if args.only:
        unknown = sorted(set(args.only) - {s.id for s in sites})
        if unknown:
            parser.error(f"unknown site id: {', '.join(unknown)}")
        sites = [s for s in sites if s.id in args.only]

    if args.offline:
        client = bundle.replay_client(FIXTURES)
        doors.CLIENT = overpass.Client(cache_dir=OVERPASS_FIXTURES, offline=True)
        os.environ.setdefault("USER_AGENT", "MIT-AT-CarToCurb/offline")
        # Nothing leaves the machine, so Nominatim's 1 request/s policy doesn't apply.
        resolver._nominatim_limiter = resolver.RateLimiter(0)
    else:
        load_dotenv(SERVER / ".env")
        client = httpx.Client()
        max_age = 0 if args.refresh else overpass.CACHE_MAX_AGE_S
        doors.CLIENT = overpass.Client(cache_dir=OVERPASS_FIXTURES, max_age_s=max_age)

    stages = bundle.Stages(geocode=functools.partial(resolver.geocode, client=client))
    today = datetime.now(UTC).date().isoformat()
    version = DataVersion(osm=args.osm_version or today, model=bundle.MODEL_VERSION)
    failures = 0
    with client:
        for site in sites:
            report = bundle.run_site(site, stages, version)
            if report.ok:
                result = report.bundle
                stamp = doors.area_for(result.building).osm_date  # cached: no extra query
                if not args.osm_version and stamp != "unknown":
                    osm = version.model_copy(update={"osm": stamp})
                    result = result.model_copy(update={"data_version": osm})
                path = bundle.write_bundle(result, site.id, args.out)
                print(f"{site.id} [{site.label or site.name or '-'}]: {report.describe()} -> {path.relative_to(SERVER)}")
            else:
                failures += 1
                print(f"{site.id} [{site.label or site.name or '-'}]: {report.describe()}")
    print(f"\n{len(sites) - failures} of {len(sites)} bundles built.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
