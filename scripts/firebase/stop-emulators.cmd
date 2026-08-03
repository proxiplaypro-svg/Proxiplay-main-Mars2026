@echo off
setlocal

set "HUB_FILE=%TEMP%\hub-demo-proxiplay.json"

if not exist "%HUB_FILE%" (
  echo No emulator hub locator found at "%HUB_FILE%".
  exit /b 1
)

for /f "usebackq delims=" %%I in (`node -e "const fs=require('fs'); const file=process.argv[1]; const data=JSON.parse(fs.readFileSync(file,'utf8')); if(!data.pid){process.exit(2)} process.stdout.write(String(data.pid));" "%HUB_FILE%"`) do set "HUB_PID=%%I"

if not defined HUB_PID (
  echo Unable to resolve the emulator hub PID from "%HUB_FILE%".
  exit /b 1
)

taskkill /PID %HUB_PID% /T
