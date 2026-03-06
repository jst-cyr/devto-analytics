@echo off
REM Wrapper script to run devto-analytics with Ruby 3.4
REM Switches to Ruby 3.4 using uru (if available) or PATH modification

REM Check if uru is available
where uru >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo Switching to Ruby 3.4 with uru...
    call uru 3.4
    if ERRORLEVEL 1 (
        echo Failed to switch to Ruby 3.4. Make sure uru is set up correctly.
        exit /b 1
    )
) else (
    REM No uru found, modify PATH to prioritize Ruby 3.4
    echo Using Ruby 3.4 via PATH modification...
    set PATH=C:\Ruby34-x64\bin;%PATH%
)

REM Verify Ruby version
ruby --version

echo Running: bundle exec ruby .\bin\devto-analytics %*
bundle exec ruby .\bin\devto-analytics %*
