# Additional pre-release review

Date: 2026-10-24. Source: `da37699` plus local backlog changes.

Method: Impeccable context and native source review, Nielsen usability heuristics, and inspection of the committed synthetic screenshots. This is an existing native macOS SwiftUI utility, not a web surface. No browser detector applies. No interface changes were made. Live keyboard, VoiceOver, contrast measurement, clean-machine installation, and accordion animation were not tested in this review.

The main user task is to glance at current quota or estimated cost and know whether action is needed. Preserve the compact panel, native menus, real app icons, tool detection and separate quota/cost units. Additional settings should not crowd the main panel.

## Major findings

### 1. Protect preferences from lost updates

Heuristic 5: error prevention. `main.swift` launches detached preference processes. `bin/ai-usage` reads and rewrites the entire config without locking or an atomic update; some CLI branches bypass `save_configuration` entirely. Rapid changes can overwrite each other, and invalid JSON silently falls back to an empty configuration. This is a source-supported risk, not a reproduced concurrent UI failure.

Recommendation: serialize read-modify-write operations, lock across CLI processes, atomically replace the file, report malformed configuration without overwriting it, and roll back optimistic budget changes when saving fails. Verify simultaneous updates preserve both settings and failures preserve the original file.

### 2. Separate billing periods from calendar months

Heuristics 2 and 4: real-world match and consistency. `Usage.total(.month)` adds Cursor billing-period costs to other tools' calendar-month costs. The hero compares this sum against a calendar-based allowance. The README and tooltip disclose this, but the prominent total still mixes different intervals. A monthly tool budget also uses this same `month` field.

Recommendation: aggregate only matching calendar ranges; present Cursor plan/billing usage separately with explicit start/end dates. Verify month boundaries, billing resets and local time zones. Keep today's model details explicitly labeled when Week or Month is selected, or make those details follow the selected range.

### 3. Distinguish fresh, stale and partial data in the menu bar

Heuristic 1: visibility of system status. The panel warns about partial costs when its hero exists. The compact bar sums successful sources and shows a generic warning, but does not name that amount as partial. `MenuBarContent` receives only cached usage, not `store.failure` or its age, so a failed refresh can leave old values looking current. If every cost source fails, the hero disappears.

Recommendation: keep the last successful value per source, its collection time, and a separate status. Make partial/stale values explicit in the tooltip and accessible label; use a compact status marker in the bar. Distinguish zero cost from unavailable cost. Test one failed source, all failed sources, sleep/resume and stale cache.

### 4. Make failures actionable and stop the initial loading state

Heuristics 9 and 10: recovery and help. Source errors and header failures are single-line raw strings. Expanding an errored tool does not expose the full error or recovery instructions. When no usable cache exists and collection fails, the content still renders a progress indicator because `usage` is nil.

Recommendation: use distinct loading, empty and failed states. Show a short explanation and Retry; offer relevant actions such as opening the provider or explaining a missing collector. Put full technical details behind an explicit copy action, excluding tokens and session contents. Leave the panel compact in the success state.

## Minor findings

### 5. Mark notifications delivered only after successful scheduling

Heuristics 1 and 5. Alert thresholds are recorded in UserDefaults before permission is granted or scheduling succeeds. A denied permission or scheduling error can suppress that threshold for the remainder of its period. Permission is requested during Store initialization and again in `notify`.

Recommendation: request permission when alerts are enabled, expose denied status with an action to open system settings, and record deduplication after successful scheduling. Check callbacks and prevent duplicate concurrent sends. Provide a test notification.

### 6. Handle OpenCode database variants independently

Heuristic 6: recognition rather than recall. `opencode_titles` queries `session` and `session_v2` within one try block. A missing table aborts all results; the path also ignores XDG_DATA_HOME despite detection honoring it.

Reproduced using a temporary SQLite database containing only `session_v2`: a valid `demo-id`/`Demo title` row returned `{}`. No real OpenCode database was read or modified for this reproduction.

Recommendation: discover available tables, preserve results when another table is absent, honor the configured data directory, and close the connection on every path. Use synthetic fixtures for each supported schema.

### 7. Keep one-decimal formatting without making small costs look free

Heuristics 2 and 4. Current formatting can display a nonzero cost below $0.05 as `$0`. The menu-bar formatter forces Brazilian separators while the panel forces US currency formatting, independent of the chosen language. Compact quota percentages truncate while the panel rounds.

Recommendation: preserve the requested maximum of one decimal, but display a localized `< $0.1` for small positive values and `$0` only for actual zero. Use a consistent locale and deliberate percent-rounding policy. This does not change the underlying cost calculation.

### 8. Validate accessible operation before adding more UI

Heuristics 7 and 8. The bar has a useful accessible label and quota bars expose values. However, the source uses very small fixed fonts, always animates refresh/expansion, and does not reference Reduce Motion. Accordion buttons do not explicitly expose expanded state. These are test targets; this review does not establish actual VoiceOver or contrast failures.

Recommendation: verify keyboard-only operation, meaningful names and expanded state with VoiceOver, readable long tool names and multiple quota buckets, Increase Contrast and Reduce Motion. Preserve a compact default; reveal additional details progressively. Avoid importing mobile touch-target rules into this macOS review.

## Scope and priorities

Existing installation, CI, licensing, packaging, privacy and accordion tasks remain applicable; do not duplicate them. Signature/notarization and Homebrew preparation are distribution work, not proof of usage accuracy.

Top three priorities: protect preference writes; align reporting periods; expose partial/stale data clearly. Next, fix initial failure recovery. Finish with visual polish after these behavior changes.

Questions skipped: product, target platform and requested analysis scope are already established in the conversation. No permission or product choice is needed to deliver this review.
