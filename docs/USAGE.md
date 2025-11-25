# Usage

Copy `.env.example` to `.env` and set `DEVTO_API_KEY` and other variables.

Examples:

Run the CLI to fetch analytics and write CSV:

```
ruby ./bin/devto-analytics fetch --org your_org_slug --since 2025-06-01 --format csv --out-dir data
```

List articles for the organization:

```
ruby ./bin/devto-analytics list-articles --org your_org_slug
```

Rake tasks:

```
rake devto:collect[your_org_slug,2025-06-01]
rake devto:dry_run[your_org_slug,2025-06-01]
```

Outputs are written under `data/YYYY-MM-DD/` by default.
