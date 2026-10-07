# API contract

`resolve.example.json` is the agreed shape of `POST /v1/resolve` (see `docs/car-to-curb-plan.md`, section 10). It's the single source of truth for both sides:

- **Server:** `server/app/models.py` must validate it, and `main.py` serves it until the real lookup works.
- **App:** `app/nemo-software/EntranceAPI/EntranceModels.swift` must decode it. A copy lives in `app/nemo-software/Resources/` so `StubEntranceClient` can load it.

To change the contract: edit this file, copy it into the app's `Resources/`, update both models, and run `pytest` in `server/`. `tests/test_contract.py` checks that the models match and the copies are identical.

The coordinates and IDs are placeholders, not real data.
