# Architecture

- `bin/` — CLI executable that starts the Thor CLI.
- `lib/devto_analytics/` — application code: `api_client`, `collector`, `formatter`, and `cli`.
- `spec/` — RSpec tests.
- `docs/` — documentation and API probe artifacts.

Design notes:
- Keep API calls isolated in `APIClient` so responses can be inspected/recorded.
- `Collector` orchestrates listing articles and calling analytics endpoints per article.
- `Formatter` handles CSV/JSON output responsibilities.
