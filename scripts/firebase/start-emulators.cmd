@echo off
setlocal

cd /d "%~dp0..\.."
firebase.cmd emulators:start --project demo-proxiplay --only auth,firestore,functions
