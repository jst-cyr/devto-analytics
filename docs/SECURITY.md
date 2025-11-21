# Security

- Never commit real API keys. Use `.env` locally and keep it out of git.
- For CI, add `DEVTO_API_KEY` (and any secrets) to your CI provider's secrets store.
- Limit API key permissions if possible and rotate keys periodically.
