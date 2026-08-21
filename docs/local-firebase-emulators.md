# Firebase local emulators

This workflow is for debug builds only. `USE_FIREBASE_EMULATORS=true` routes Auth, Firestore, Functions, and Storage to the local Emulator Suite. Without this flag, the app keeps its existing Firebase behavior. Release builds never use the emulator endpoints.

## Physical Android device

1. Connect one authorized phone by USB.
2. Run `powershell -ExecutionPolicy Bypass -File .\tools\start_local_debug.ps1`.
3. In another terminal, run `flutter run --dart-define=USE_FIREBASE_EMULATORS=true`.
4. Open `http://127.0.0.1:4000` for the Emulator Suite UI.

The script runs `adb reverse` for Auth `9099`, Firestore `8080`, Functions `5001`, and Storage `9199`. The in-app orange banner and `[LOCAL_FIREBASE_EMULATORS]` logs confirm local mode.

## Seed and test date

With emulators running, execute `powershell -ExecutionPolicy Bypass -File .\tools\seed_local_emulator.ps1`. It refuses to run unless the local Auth and Firestore endpoints are explicitly set, and creates `player@proxiplay.local` with password `LocalPass123!` plus `games/local-active-game`.

To simulate a date, stop the emulators, run `$env:EMULATOR_TEST_DATE = '2026-09-01'`, then start them again with the script. Set `2026-09-02` and restart for J+1. The variable is read only by the Functions Emulator; production ignores it.

Remote Config and FCM have no local emulator in this stack and are disabled in local emulator mode. Functions suppress outbound SMTP and FCM sends while retaining local Firestore notification records.
