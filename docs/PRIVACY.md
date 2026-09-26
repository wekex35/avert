# Privacy

**Effective:** 2026-09-24  
**Product:** Avert (`com.avert.app`)

## Summary

Avert is a macOS menu-bar utility that uses **on-device AirPods (headphone) motion** to soft-blur your screen when you look away. It does **not** use a camera, does **not** create an account, and does **not** upload head-pose or screen content to any server.

## Data Avert uses

| Data | Where it stays | Purpose |
|------|----------------|---------|
| AirPods attitude / motion samples | On this Mac only (in memory while running) | Relative look-away / look-down / look-up detection |
| Calibration center (attitude snapshot) | On this Mac (in memory; “calibrated once” flag in UserDefaults) | Define “facing the screen” |
| Settings (thresholds, toggles, schedule) | `UserDefaults` on this Mac | Remember preferences |
| Optional panic cover image | `~/Library/Application Support/Avert/` | Custom full-screen cover |
| Exercise completion timestamp | UserDefaults | Show “last completed” locally |
| Notification permission | System | Neck break / tilt / exercise reminders |

Avert does **not** collect analytics, crash reports to a third party, advertising IDs, or contact information.

## Permissions

- **Motion & Fitness** — required for `CMHeadphoneMotionManager`
- **Bluetooth** — optional reclaim of AirPods audio to this Mac after a phone call
- **Notifications** — optional wellness / exercise reminders
- **User-selected files** — only if you choose a custom panic image
- **Login Item** — only if you enable Launch at login

No Camera, Screen Recording, or Accessibility permissions are required for V1 privacy blur.

## What we claim

Avert is **shoulder-surf reduction**, not absolute privacy. Looking away triggers a veil; determined observers or other sensors are outside scope.

Neck care and guided exercises are **wellness helpers**, not medical advice.

## Contact

Public policy: https://wekex35.github.io/avert/privacy.html  

Questions: open an issue on https://github.com/wekex35/avert/issues
