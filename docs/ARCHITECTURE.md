# Architecture

- `bin/` — CLI executable that starts the Thor CLI.
- `lib/devto_analytics/` — application code: `api_client`, `collector`, `weekly_collector`, `formatter`, and `cli`.
- `spec/` — RSpec tests.
- `docs/` — documentation and API probe artifacts.

Design notes:
- Keep API calls isolated in `APIClient` so responses can be inspected/recorded.
- `Collector` orchestrates listing articles and calling analytics endpoints per article.
- `Formatter` handles CSV/JSON output responsibilities.

A `fetch` runs two passes over the same article list:

1. `Collector` reads `/api/analytics/totals` — **lifetime** counters — and writes
   `{org}-analytics-{date}.{csv,json}`.
2. `WeeklyCollector` reads `/api/analytics/historical` — **per-day** counters —
   sums them over a fixed window of whole UTC calendar days, and writes
   `{org}-window-{date}.{csv,json}`.

The split exists because the two endpoints answer different questions and fail
differently. Totals are cumulative, so a period can only be inferred by diffing
two daily snapshots — which is sensitive to run timing and misreports a recovered
failed fetch as a traffic spike. The historical endpoint measures the period
directly. `WeeklyCollector` owns its own window arithmetic, progress reporting,
and output writing so `Collector` stays a thin orchestrator over the two passes.

Both passes resume independently from their own JSON file, and both share one
`APIClient` instance so the request pacing/backoff applies across the whole run.
