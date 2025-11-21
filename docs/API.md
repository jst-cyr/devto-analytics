# API Mapping & Probe Plan

This document will capture the endpoints we probe and example responses from the Dev.to / Forem API.

Planned probe requests (run during implementation after setting `DEVTO_API_KEY`):

- `GET /api/articles?username=puppet&per_page=100` — list articles for org/user `puppet`.
- `GET /api/articles/{id}` — inspect article canonical fields (url, title, published_at).
- `GET /api/analytics/totals?article_id={id}` — retrieve aggregate metrics for `id`.
- `GET /api/analytics/historical?start=2025-06-01&article_id={id}` — retrieve daily metrics since date.

Save sample JSON responses here once available.
