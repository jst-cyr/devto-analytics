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

Outputs are written under `data/YYYY-MM-DD/` by default.

## Resuming a run

`fetch` is safe to re-run against the same day's output. If `data/YYYY-MM-DD/{org}-analytics-YYYY-MM-DD.json` already exists:
- If every article already has a `readers` value, the run stops immediately and reports the file is already complete — no API calls are made.
- Otherwise, only the articles missing `readers` (almost always due to `429`s exhausting their retries — see Troubleshooting) are re-fetched; everything else is left untouched. This is much cheaper than a full re-run and is the recommended way to fill in gaps after a rate-limited run.

This applies to `--format csv` runs (both files are always written); `--format json`-only runs are resumable the same way since the JSON file is what's read back.

## Troubleshooting

If you see errors about Ruby version requirements:
1. Verify Ruby 3.4+ is installed: `C:\Ruby34-x64\bin\ruby --version`
2. Use the wrapper scripts (`run.ps1` or `run.bat`) instead of calling `ruby` directly
3. If using a Ruby version manager like `uru`, make sure both Ruby versions are registered
