# Project status

Updated: 2026-11-04 22:20 — America/Sao_Paulo

## Current work
- Task: AIU-001 `tasks/ai-usage/tasks.json` — add DeepSeek spend as a cost tool.
- Objective: done; collector, Swift cosmetics, docs and tests implemented and validated.
- State: implemented, tested, built, installed locally, committed and pushed to `origin/main`.

## Code and environment
- Branch: `main`; local changes: `bin/ai-usage`, `main.swift`, `tests/test_collector.py`, `README.md`, `docs/REFERENCE.md`, new `tasks/`, `AGENTS.md`, this file.
- Services: menu bar app installed at `~/Applications/AI Usage.app` (relaunched by `./install.sh`); collector copied to `~/.local/bin/ai-usage`.
- Publication: `96c73e0` pushed to `origin/main` on 2026-11-04; no release.

## Validation
- 2026-11-04: `python3 -m unittest discover -s tests -v` — 24 tests OK, including new DeepSeek pricing, folding, fork-prefix, zstd and unpriced-model cases.
- 2026-11-04: `python3 tests/check_swift.py` — old and current payload compatibility OK.
- 2026-11-04: `./install.sh` — collector reports `DeepSeek today $1.05 ok` and the app relaunched.
- 2026-11-04: `AIUsage --snapshot /tmp/ai-usage-deepseek.png Today` — panel shows DeepSeek row with app icon and today's cost.
- Evidence: snapshot at `/tmp/ai-usage-deepseek.png`; commands above.

## Blockers and next step
- Blocker/user action: none.
- Next step: review the diff and commit the change set on `main`.

## Context needed to resume
- DeepSeek spend is priced from `~/.dsh/sessions` logs at published USD rates; peak/off-peak windows are UTC weekdays and Chinese holidays are not modelled, so holiday samples overestimate. See `docs/REFERENCE.md`.
- The collector must stay Python 3.9 stdlib-only because the app runs it with `/usr/bin/python3`; zstd logs fall back to the `zstd` binary.
