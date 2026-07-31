# Usage

Copy `.env.example` to `.env` and set `DEVTO_API_KEY` and other variables.

## Ruby Version

This project requires Ruby 3.4+. Use the wrapper scripts to ensure the correct Ruby version:

**PowerShell:**
```powershell
.\run.ps1 <command> [options]
```

**CMD:**
```cmd
run.bat <command> [options]
```

The wrapper scripts automatically select Ruby 3.4, even if your system default is a different version.

## Examples

Run the CLI to fetch analytics and write CSV:

**With wrapper (recommended):**
```powershell
.\run.ps1 fetch --org your_org_slug --since 2025-06-01 --format csv --out-dir data
```

**Direct (only if Ruby 3.4+ is your system default):**
```
ruby ./bin/devto-analytics fetch --org your_org_slug --since 2025-06-01 --format csv --out-dir data
```

List articles for the organization:

```powershell
.\run.ps1 list-articles --org your_org_slug
```

Visualize analytics in a web dashboard:

```powershell
.\run.ps1 visualize
```

Rake tasks:

```
rake devto:collect[your_org_slug,2025-06-01]
rake devto:dry_run[your_org_slug,2025-06-01]
```

## Output

Outputs are written under `data/YYYY-MM-DD/` by default. Each `fetch` produces two CSVs:

| File | Contents |
| --- | --- |
| `{org}-analytics-YYYY-MM-DD.csv` | **Lifetime** totals per article, from `/api/analytics/totals`. |
| `{org}-window-YYYY-MM-DD.csv` | Activity **inside the last 7 days only**, from `/api/analytics/historical`. |

A `.json` file is written beside each CSV; the window JSON holds the raw per-day
payloads (used for resuming, and for a day-by-day breakdown if you need one).

### The recent-window CSV

Columns: `id, title, url, published_at, window_start, window_end, readers,
read_time_seconds, reactions, comments, follows`.

The window covers **whole UTC calendar days**, ending on the current date and
inclusive of both ends — so `--days 7` run on 2026-07-31 covers
`2026-07-25..2026-07-31`. It does *not* depend on the time of day the run
happens, so two runs on the same date always report the identical period. The
exact range is recorded in the `window_start` / `window_end` columns of every row.

```powershell
.\run.ps1 fetch --days 30      # last 30 calendar days instead of 7
.\run.ps1 fetch --skip-window  # totals only, saves one API call per article
```

Notes:
- The window CSV is written even under `--format json`, since producing it is the
  point of the second pass.
- `readers` is left **blank** (not `0`) when an article's history could not be
  fetched, so a failed request can't be misread as a quiet week.
- This costs one extra API call per article, paced by the same throttle as the
  rest of the run. Expect roughly double the wall-clock of a totals-only fetch.

### Why not just diff two daily totals snapshots?

Diffing yesterday's and today's lifetime CSVs looks equivalent but drifts: the
snapshots are taken at whatever time each run happened, so the interval isn't
exactly seven days. Worse, an article whose totals fetch *failed* in the earlier
snapshot records `0`, and its recovery in the next snapshot then reads as a
enormous jump. The window CSV measures the period directly and avoids both.

Be aware that dev.to reports organization page views in coarse buckets (in
practice, steps of ~10), so for low-traffic articles the granularity of
`readers` is limited. `read_time_seconds` is not bucketed this way.

## Resuming a run

`fetch` is safe to re-run against the same day's output. If `data/YYYY-MM-DD/{org}-analytics-YYYY-MM-DD.json` already exists:
- If every article already has a `readers` value, the run stops immediately and reports the file is already complete — no API calls are made.
- Otherwise, only the articles missing `readers` (almost always due to `429`s exhausting their retries — see Troubleshooting) are re-fetched; everything else is left untouched. This is much cheaper than a full re-run and is the recommended way to fill in gaps after a rate-limited run.

This applies to `--format csv` runs (both files are always written); `--format json`-only runs are resumable the same way since the JSON file is what's read back.

The recent-window pass resumes independently, off `{org}-window-YYYY-MM-DD.json`:
articles whose per-day history was already retrieved are reused as-is, and only
the ones that failed are requested again. Re-running a completed `fetch` therefore
makes no API calls at all.

## Troubleshooting

If you see errors about Ruby version requirements:
1. Verify Ruby 3.4+ is installed: `C:\Ruby34-x64\bin\ruby --version`
2. Use the wrapper scripts (`run.ps1` or `run.bat`) instead of calling `ruby` directly
3. If using a Ruby version manager like `uru`, make sure both Ruby versions are registered
