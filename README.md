# Analytics Dashboard for dev.to
Pulls dev.to analytics from the Forem API for a given organization.

Provides the following data:
- TBD

## Requirements

- Ruby 3.4+
- Bundler

## Ruby Version Management

This project requires Ruby 3.4 or higher. If you have multiple Ruby versions installed, use the provided wrapper scripts to ensure the correct version is used:

**PowerShell:**
```powershell
.\run.ps1 <command> [options]
```

**CMD:**
```cmd
run.bat <command> [options]
```

The wrapper scripts will automatically use Ruby 3.4 (either via `uru` if installed, or by modifying the PATH).

Alternatively, if you have a Ruby version manager like `uru`, you can manually switch to Ruby 3.4:
```powershell
uru 3.4
```

## Quick Start

1. Copy `.env.example` to `.env` and configure your settings
2. Install dependencies: `bundle install`
3. Run commands using the wrapper scripts (see Usage below)

For detailed usage instructions, see [docs/USAGE.md](docs/USAGE.md).
