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

Behaviour of `/api/analytics/historical` (observed 2026-07-31, org `puppet`):
- `start` is inclusive, and the response runs from `start` through *today* — there
  is no `end` parameter, so a bounded window has to be trimmed client-side
  (`WeeklyCollector#within_window`).
- Days with no activity are still present, with zeroed metrics. An absent date is
  therefore not the same as a zero, and a `{"error": ...}` body must not be summed
  as zero — it means the request was refused (see authentication notes below).
- It obeys the same `organization_id` ownership scoping as `/totals`.
- Summing `page_views.total` over a 7-day window across all 62 org articles gave
  212, matching the diff of the 2026-07-24 and 2026-07-31 lifetime snapshots
  (`+212` for pre-existing articles) — the two endpoints agree in aggregate.
  Per-article they agreed on 58 of 60; the 2 that differed by 10 are explained by
  the snapshots being taken at different times of day, which is precisely why the
  window CSV uses this endpoint rather than a snapshot diff.
- **Page views are reported in coarse buckets.** Across all 27 consecutive weekly
  snapshot pairs collected so far, 92.5% of per-article deltas are exact multiples
  of 10 (129 landed on exactly `+10` versus 17 on `+11`/`+12`/`+13` combined), and
  single-day historical values for low-traffic articles come back as `0` or `10`.
  Treat small `page_views` differences as noise. `total_read_time_in_seconds` does
  not appear to be bucketed and is the finer-grained engagement signal.

Notes and mapping to requested output fields:
- Article URL: use `url` or `canonical_url` from `sample_articles.json`.
- Date posted: use `published_at` or `published_timestamp` from article metadata.
- All-time Readers: `page_views.total` in `analytics/totals` (not present in article metadata). Requires analytics access.
- All-time Reactions: can be read from `positive_reactions_count` in article metadata (public reactions) or `reactions.total` in `analytics/totals` (analytics may split types).
- All-time Comments: `comments_count` in article metadata or `comments.total` from `analytics/totals`.

Authentication notes:
- Listing articles is available with the provided API key and returns public metadata.
- Analytics endpoints (`/api/analytics/totals` and `/api/analytics/historical`) scope per-article results to an "owner": by default, the API key's own user. Requesting `article_id` alone for an article authored by someone else returns `422 {"error":"You can't view this article's stats"}`, with `readers` coming back blank.
- Passing `organization_id` alongside `article_id` switches the owner to the organization, which authorizes analytics for *any* article published under that org — not just ones authored by the API key's user — as long as the key belongs to an org member (`GET /api/organizations/{slug}` resolves the numeric id).
- **Organization-scoped requests throttle noticeably harder than user-scoped ones.** Confirmed empirically (2026-07-17): firing 4 user-scoped + 4 org-scoped requests concurrently for the *same owned article*, repeated across 3 rounds (24 requests total), user-scoped succeeded 7/12 (58%) while org-scoped succeeded only 2/12 (17%) — despite Rack::Attack's throttle rules (`config/initializers/rack_attack.rb`) not discriminating on `organization_id` at all. The org-scoped `AnalyticsService` path is evidently more expensive server-side. Because of this, the collector only passes `organization_id` for articles it doesn't already own (see `DEVTO_USERNAME` below); it always uses the cheaper, plain `article_id`-only request for the API key's own articles.
- `GET /api/users/me` (the natural way to determine "who is this API key" programmatically) returns `401` with this auth scheme — it appears to require OAuth rather than an `api-key` header. That's why ownership is determined via `DEVTO_USERNAME` (user-supplied) rather than resolved automatically.

Next steps:
- Analytics access is available; the collector queries `/api/analytics/totals` for each article — with `organization_id` only when needed — and produces the consolidated CSV with the requested columns, including readers for org members' posts.
- A second pass queries `/api/analytics/historical` for each article and writes a
  recent-window CSV (`{org}-window-{date}.csv`) covering the last 7 calendar days.
  See `docs/USAGE.md` for the output columns and window semantics.

Rate limiting notes:
- Forem throttles API reads to ~3 requests/second per key (`Rack::Attack`, see `config/initializers/rack_attack.rb` in the Forem source) and returns `429` with a `Retry-After` header when exceeded.
- `APIClient` paces requests below that rate (`MIN_REQUEST_INTERVAL`, default 0.5s) to avoid triggering 429s in the first place, and on a 429 sleeps for at least the `Retry-After` duration when the server provides one (never less than our own growing backoff — see `DEFAULT_INITIAL_BACKOFF`, doubling each attempt) up to `DEFAULT_MAX_RETRIES` (default 6) otherwise.
- All three are tunable via `DEVTO_MIN_REQUEST_INTERVAL`, `DEVTO_INITIAL_BACKOFF`, and `DEVTO_MAX_RETRIES` — raise `DEVTO_MAX_RETRIES` if a run still comes back with blank `readers` columns after exhausting retries.
- Setting `DEVTO_USERNAME` (see above) is the single biggest lever for reducing 429s, since it avoids the more heavily-throttled `organization_id` path for the majority of articles (your own).

