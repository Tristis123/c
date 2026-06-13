@echo off
python shutdown_server.py
if %errorlevel% neq 0 (
    echo.
    echo Python not found. Please install Python from https://python.org
    pause
)
