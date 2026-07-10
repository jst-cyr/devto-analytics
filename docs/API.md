# API Mapping & Probe Plan

This document will capture the endpoints we probe and example responses from the Dev.to / Forem API.

Planned probe requests (run during implementation after setting `DEVTO_API_KEY`):

- `GET /api/articles?username=puppet&per_page=100` — list articles for org/user `puppet`.
- `GET /api/articles/{id}` — inspect article canonical fields (url, title, published_at).
- `GET /api/analytics/totals?article_id={id}` — retrieve aggregate metrics for `id`.
- `GET /api/analytics/historical?start=2025-06-01&article_id={id}` — retrieve daily metrics since date.

Save sample JSON responses here once available.

Captured responses (saved in `docs/`):

- `sample_articles.json` — first page (up to 100) of articles returned by `GET /api/articles?username=puppet&per_page=100`.
	- Top-level: JSON array of article objects.
	- Common fields observed (per article):
		- `id` (Integer)
		- `title` (String)
		- `url` (String) and `canonical_url` (String)
		- `path` (String) — relative path under `/organization/slug/...`
		- `published_at` / `published_timestamp` (ISO 8601 String)
		- `comments_count` (Integer)
		- `public_reactions_count` / `positive_reactions_count` (Integer)
		- `tag_list` / `tags` (Array/String)
		- `user` (object) and `organization` (object)

- `sample_analytics_totals_3042001.json` — raw response from `GET /api/analytics/totals?article_id=3042001`.
	- Observed shape (body parsed as JSON):
		- `comments`: { `total`: Integer }
		- `follows`: { `total`: Integer }
		- `reactions`: { `total`: Integer, `like`: Integer, `readinglist`: Integer, `unicorn`: Integer }
		- `page_views`: { `total`: Integer, `average_read_time_in_seconds`: Integer, `total_read_time_in_seconds`: Integer }

- `sample_analytics_historical_3042001.json` — raw response from `GET /api/analytics/historical?start=2025-06-01&article_id=3042001`.
	- Observed shape (body parsed as JSON): a mapping of ISO dates (YYYY-MM-DD) to daily metrics objects. Each daily metrics object contains the same nested keys as totals, e.g.:
		- `comments`: { `total`: Integer }
		- `follows`: { `total`: Integer }
		- `reactions`: { `total`: Integer, `like`: Integer, `readinglist`: Integer, `unicorn`: Integer }
		- `page_views`: { `total`: Integer, `average_read_time_in_seconds`: Integer, `total_read_time_in_seconds`: Integer }

Notes and mapping to requested output fields:
- Article URL: use `url` or `canonical_url` from `sample_articles.json`.
- Date posted: use `published_at` or `published_timestamp` from article metadata.
- All-time Readers: `page_views.total` in `analytics/totals` (not present in article metadata). Requires analytics access.
- All-time Reactions: can be read from `positive_reactions_count` in article metadata (public reactions) or `reactions.total` in `analytics/totals` (analytics may split types).
- All-time Comments: `comments_count` in article metadata or `comments.total` from `analytics/totals`.

Authentication notes:
- Listing articles is available with the provided API key and returns public metadata.
- Analytics endpoints (`/api/analytics/totals` and `/api/analytics/historical`) scope per-article results to an "owner": by default, the API key's own user. Requesting `article_id` alone for an article authored by someone else returns `422 {"error":"You can't view this article's stats"}`, with `readers` coming back blank.
- Passing `organization_id` alongside `article_id` switches the owner to the organization, which authorizes analytics for *any* article published under that org — not just ones authored by the API key's user — as long as the key belongs to an org member (`GET /api/organizations/{slug}` resolves the numeric id). The collector resolves and passes this automatically.

Next steps:
- Analytics access is available; the collector queries `/api/analytics/totals` (with `organization_id`) for each article and produces the consolidated CSV with the requested columns, including readers for org members' posts.

