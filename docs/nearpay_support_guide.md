# NearPay Support Guide

## 1) Reproduce The Issue (Step-By-Step)
- Confirm NFC is enabled on the device.
- Open the app and navigate to the payment flow.
- Attempt the NearPay payment.
- Note the exact time the failure happens and what the user did just before it.

## 2) Capture Android Logs (ADB)
```bash
adb logcat -s "NearPay:V" "ReaderCore:V" "flutter:V" "*:S" > nearpay_log.txt
```

## 3) Capture Dart-Layer Logs (Flutter DevTools)
- Run the app in debug mode.
- Open Flutter DevTools.
- Go to the Logging or Console view.
- Filter for `NearPay` and export the logs.

## 4) What To Send To NearPay Support
- Device model.
- Android version.
- NFC status (enabled/disabled).
- Environment used (SANDBOX or PRODUCTION).
- `applicationId` (package name).
- The captured log file (`nearpay_log.txt`) and the in-app log file.

## 5) Log File Location (Device File Manager)
- Path: `Internal Storage → Android → data → <applicationId> → files → logs`
- File name format: `nearpay_YYYYMMDD.log`

لاسترجاع سجل الأحداث من جهاز العميل:
افتح تطبيق مدير الملفات على الجهاز
اذهب إلى: الذاكرة الداخلية ← Android ← data ← [اسم التطبيق] ← files ← logs
أرسل ملف nearpay_YYYYMMDD.log لفريق الدعم الفني
