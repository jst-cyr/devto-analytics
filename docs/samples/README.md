# API Sample Responses (sanitized)

This folder contains small, trimmed and sanitized sample JSON files captured from the Dev.to API to document response shapes.

- `sample_articles_trimmed.json`: a small array of article objects (3 items) with identifying fields and sanitized user/organization data.
- `sample_analytics_totals_trimmed.json`: a small totals response showing the keys used by the collector.
- `sample_analytics_historical_trimmed.json`: example historical data for a few dates.

These files are safe to commit and useful as fixtures for tests and documentation. The original full captures are preserved (if present) in `docs/` and `data/` but should be kept out of source control if they contain large or sensitive content.
