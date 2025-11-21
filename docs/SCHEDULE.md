# Scheduling

You can schedule weekly runs using any scheduler. Example GitHub Actions workflow is provided in `.github/workflows/ci.yml` to run CI; consider adding a scheduled workflow that runs `rake devto:collect` weekly and uploads collected files as artifacts.

Example crontab (runs Monday at 03:00 UTC):

```
0 3 * * 1 cd /path/to/repo && bundle install && rake devto:collect[puppet,2025-06-01]
```

When running in CI, store `DEVTO_API_KEY` in secrets and load it as an environment variable for the job.
