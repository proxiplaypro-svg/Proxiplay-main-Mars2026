@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 command [args...]
  echo Example: %~nx0 node --test test\instant_winners_core.test.js
  exit /b 1
)

cd /d "%~dp0..\.."
set "EMU_CMD=%*"
(
  echo SMTP_HOST=localhost
  echo SMTP_PORT=587
  echo SMTP_SECURE=false
  echo SMTP_USER=demo-user
  echo SMTP_PASS=demo-pass
  echo SMTP_FROM_EMAIL=demo@proxiplay.local
  echo SMTP_FROM_NAME=Proxiplay Demo
  echo SMTP_REPLY_TO=
) > firebase\functions\.env.local
firebase.cmd emulators:exec --project demo-proxiplay --only auth,firestore,functions "cmd /S /C ""cd /D firebase\\functions && %EMU_CMD%"""
