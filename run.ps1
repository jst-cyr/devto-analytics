# Wrapper script to run devto-analytics with Ruby 3.4
# Switches to Ruby 3.4 using uru (if available) or PATH modification

# Check if uru is available
if (Get-Command uru -ErrorAction SilentlyContinue) {
    Write-Host "Switching to Ruby 3.4 with uru..." -ForegroundColor Green
    uru 3.4
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to switch to Ruby 3.4. Make sure uru is set up correctly." -ForegroundColor Red
        exit 1
    }
} else {
    # No uru found, modify PATH to prioritize Ruby 3.4
    Write-Host "Using Ruby 3.4 via PATH modification..." -ForegroundColor Green
    $env:PATH = "C:\Ruby34-x64\bin;$env:PATH"
}

# Verify Ruby version
$rubyVersion = ruby --version
Write-Host "Using Ruby: $rubyVersion" -ForegroundColor Cyan

# Pass all arguments to the devto-analytics command
Write-Host "Running: bundle exec ruby .\bin\devto-analytics $args" -ForegroundColor Cyan
bundle exec ruby .\bin\devto-analytics @args
