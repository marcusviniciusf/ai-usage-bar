# Project status

Updated: 2026-11-05 14:27 — America/Sao_Paulo

## Current work
- Tasks: P0 showcase done — AIU-002 (release), AIU-005 (cask), AIU-006 (CI), AIU-007 (README), AIU-008 (metadata). Next: AIU-003 (session row truncation), then AIU-009/AIU-010.
- Objective: turn the repo into a distributable showcase; P1 UI polish is the remaining visible gap.
- State: implemented, tested, released and pushed.

## Code and environment
- Branch: `main`, clean; this snapshot commit follows `1776165` (docs showcase).
- Release: tag `v1.0.0` (`50dd212`), universal zip + release notes published.
- Cask: `marcusviniciusf/homebrew-tap` → `Casks/ai-usage.rb` (version 1.0.0, sha256 `3c25a1e3…`).
- Services: dev app at `~/Applications/AI Usage.app` (built by `./build.sh`); the cask copy was installed, verified and removed to avoid two menu bar instances.
- Publication: `main` and the tag are pushed; CI runs on every push.

## Validation
- 2026-11-05: `python3 -m unittest discover -s tests` — 24 tests OK.
- 2026-11-05: `python3 tests/check_swift.py` with `PATH=/usr/bin:/bin` (no rtk) — old and current payloads OK.
- 2026-11-05: CI run [42074309943](https://github.com/marcusviniciusf/ai-usage-bar/actions/runs/42074309943) — success on `1776165` (tests, wire check, universal build).
- 2026-11-05: release asset re-downloaded; sha256 matches the cask (`3c25a1e3b8c6882861b04325aa53dcd64851375c16055710d6333879ae7acfd4`).
- 2026-11-05: `brew audit --cask` clean; `brew install --cask marcusviniciusf/tap/ai-usage` installed and the app rendered a snapshot.
- 2026-11-05: demo screenshots and GIF regenerated with DeepSeek and checked; README image/doc links verified.
- Evidence: GitHub release, CI run, cask tap, `docs/images/ai-usage-demo.gif`.

## Blockers and next step
- Blocker/user action: upload `docs/images/ai-usage-social.png` in GitHub → Settings → Social preview (no API for it); optional Apple Developer ID if notarization is ever wanted.
- Next step: implement AIU-003 (session row truncation and verbose cost label), then AIU-009/AIU-010.

## Context needed to resume
- Collectors ship inside the app bundle; `~/.local/bin/ai-usage` is only a dev fallback.
- Release flow and commands live in `AGENTS.md`; app is ad-hoc signed, so manual downloads need "Open Anyway".
- DeepSeek pricing: published USD rates, peak 01:00–04:00 and 06:00–10:00 UTC on weekdays; Chinese holidays not modelled.
