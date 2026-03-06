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

## Troubleshooting

If you see errors about Ruby version requirements:
1. Verify Ruby 3.4+ is installed: `C:\Ruby34-x64\bin\ruby --version`
2. Use the wrapper scripts (`run.ps1` or `run.bat`) instead of calling `ruby` directly
3. If using a Ruby version manager like `uru`, make sure both Ruby versions are registered
