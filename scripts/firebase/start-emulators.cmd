@echo off
setlocal

cd /d "%~dp0..\.."
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
firebase.cmd emulators:start --project demo-proxiplay --only auth,firestore,functions
