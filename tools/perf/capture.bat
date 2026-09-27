@echo off
REM ===========================================================================
REM  PalBonds frame-time capture  --  RIGHT-CLICK - "Run as administrator"
REM ===========================================================================
REM  PresentMon cannot start a trace session without elevation ("access denied"),
REM  which is why this exists as a .bat instead of being run from the assistant's
REM  shell.
REM
REM  Records 7 minutes, so the timing does not have to be exact: start it, load
REM  in, fly the route, and say roughly when the flying started and stopped --
REM  the analysis is trimmed to that window with
REM    node tools/perf/analyze-presentmon.js --range <from> <to> <csv>
REM
REM  Usage:  capture.bat [name]        (default name: today + "-flying")
REM ===========================================================================

setlocal

set "PRESENTMON=C:\Users\Dragon\Proyectos\_tools\PresentMon\PresentMon-2.5.1-x64.exe"
set "OUTDIR=C:\Users\Dragon\Proyectos\32-PalBonds\perf-captures"

set "NAME=%~1"
if "%NAME%"=="" set "NAME=2026-09-27_runJ-119-flying"

net session >nul 2>&1
if errorlevel 1 (
  echo.
  echo   NOT RUNNING AS ADMINISTRATOR.
  echo   Close this, right-click capture.bat and choose "Run as administrator".
  echo.
  pause
  exit /b 1
)

if not exist "%PRESENTMON%" (
  echo   PresentMon not found at:
  echo   %PRESENTMON%
  pause
  exit /b 1
)

echo.
echo   Recording Palworld frame times for 7 minutes into:
echo   %OUTDIR%\%NAME%.csv
echo.
echo   Load in, get airborne, and fly the route. It stops on its own.
echo.

"%PRESENTMON%" --process_name Palworld-Win64-Shipping.exe ^
  --output_file "%OUTDIR%\%NAME%.csv" ^
  --timed 420 --terminate_after_timed --stop_existing_session

echo.
echo   Done. Tell the assistant roughly when the flying started and stopped.
echo.
pause
