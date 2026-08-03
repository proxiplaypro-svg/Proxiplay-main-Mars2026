@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 command [args...]
  echo Example: %~nx0 node --test test\instant_winners_core.test.js
  exit /b 1
)

cd /d "%~dp0..\..\firebase\functions"
firebase.cmd emulators:exec --project demo-proxiplay --only auth,firestore,functions "%*"
