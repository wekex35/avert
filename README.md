# Avert

Menu-bar Mac app that soft-blurs your screen when you look away — head pose from AirPods, no camera.

With AirPods in and Motion & Fitness allowed, Avert reads orientation from Apple’s headphone motion API, compares it to a calibrated “facing the screen” pose, and draws click-through overlays on your display(s). It can also nudge you for stillness / sustained tilt, run a guided neck mobility set counted from AirPods motion, and try to reclaim AirPods after a phone-call handoff.

## How it works

| You look… | What happens |
|-----------|----------------|
| Left / right | Soft blur/veil on that side |
| Down | Optional soft dim |
| Up | Optional full cover (sticky until cleared) |
| ⌘⇧B | Manual panic — same full cover on demand |

**Hard requirement:** Without AirPods motion, Avert cannot blur from head pose. Panic hotkey and settings still work.

### Run / export

```bash
open Avert.xcodeproj   # Xcode → Run with AirPods in → Enable → Calibrate
chmod +x scripts/export-app.sh && ./scripts/export-app.sh   # Release .app → dist/
```

Ship checklist: [docs/LAUNCH.md](docs/LAUNCH.md). Privacy: [docs/PRIVACY.md](docs/PRIVACY.md). Version **1.0.0**.

## Requirements

| Item | Notes |
|------|--------|
| macOS | 14 Sonoma or later |
| Headphones | AirPods (or motion-capable Beats) in ear; audio preferably on this Mac |
| Motion & Fitness | Required for tracking |
| Bluetooth | Reclaim after calls |
| Notifications | Neck break / tilt / exercise / recalibrate prompts |
| Login Items | Optional launch at login |

Sandbox entitlements: Bluetooth, audio-input, user-selected files (panic image). No camera — privacy blur is headphone IMU only.

---

## Feature inventory (from code)

### 1. Core privacy blur

| Feature | What it does | Caveats |
|---------|--------------|---------|
| **Look-away side veil** | Past yaw threshold (default **22.5°**), that side soft-blurs/veils; intensity rises as you turn further. Clears near center (~**5°** hysteresis). | Needs AirPods motion + calibration. Overlays ignore mouse clicks. |
| **Calibration** | “Facing the screen” becomes center. Guided: wait for motion → face screen → practice left → right → down → up. Returning users auto-recenter (~1s after motion returns) without forcing the sheet. | First enable opens calibration. Recalibrate from menu / Status. |
| **Look-down dim** | Chin-down past threshold (default **18°**) → soft full-screen dim (~30–80% opacity). | Toggleable; can invert up/down if pitch feels reversed. |
| **Look-up panic cover** | Chin-up past threshold (default **14°**) → full-screen cover (black or custom image). Sticky until ⌘⇧B / Clear — looking down does not clear it. | Toggleable. During calibration practice, look-up shows cover without locking sticky panic. |
| **Manual panic blur** | Same full-screen cover on demand (menu or ⌘⇧B). | Independent of look-up; clears only via toggle/clear. |
| **Panic cover style** | Solid black, or user-chosen image (JPEG/PNG/HEIC/WebP → Application Support). | Falls back to black if no image. Path: `~/Library/Application Support/Avert/panic-cover.jpg`. |
| **Sensitivity** | Yaw **12–40°**, blur intensity **40–100%**, fade **80–500 ms**. | Live via Privacy settings. |

### 2. Neck care / stillness / flex reminders

| Feature | What it does | Caveats |
|---------|--------------|---------|
| **Stillness reminders** | Facing screen + barely moving for interval (default **20 min**; options **2–60**) → notification to take a neck break. | Needs notifications. Only while “facing screen.” ~5s dwell before long timer; **30 min** cooldown. Wellness only. |
| **Sustained tilt reminders** | Head pitch ≥ flex threshold (default **20°**) for flex duration (**15 min** in code, not in UI) → nudge to reset posture. | Same notification + 30 min cooldown. Duration fixed unless changed in defaults. |
| **Status line feedback** | “Neck break suggested” / “Posture reset suggested.” | Clears when monitors reset (disable, recalibrate, etc.). |

### 3. Neck exercises

| Feature | What it does | Caveats |
|---------|--------------|---------|
| **3-move set** | Look Down & Up, Tilt Left & Right, Turn Left & Right — **4 reps** each. One rep = center → A → center → B → center (holds ~2.5s center; ~18s most stretches; look-up ~8s). | Not “6×10” (outdated comment). AirPods must stream for auto-counting. |
| **Guided UI** | Sheet with illustrated phases, hold timer, rep progress, Skip / Next / Done. | Privacy veils paused during exercise (panic cover left alone). |
| **Voice coach** | Phase names, 3-2-1 on stretch holds, “Rep N done,” “Set complete.” Soft chimes. | Toggleable; English (`en-US`) TTS. |
| **2-hour reminders** | Repeating local notification; action opens exercise sheet. | Needs notifications. Reminds on timer even if you already exercised (completion is display-only). |
| **Start anytime** | Status “Start exercise” or Neck care → Start exercises. | Best with motion live. |

### 4. AirPods / motion / reclaim

| Feature | What it does | Caveats |
|---------|--------------|---------|
| **Head tracking** | `CMHeadphoneMotionManager` (AirPods / compatible headphone motion). | Motion & Fitness required. One bud at a time (Apple limit). |
| **Call / other-device handoff** | Detects disconnect/unavailable motion; keeps calibration when possible; retries resume. | Status: “On call / other device.” Overlays clear (panic can stay). |
| **Bring AirPods to Mac** | Bluetooth bounce + set AirPods/Beats as default in/out audio, then soft/hard motion resume. | Needs Bluetooth. Best-effort; may still need Bluetooth menu Connect. Also matches some generic BT headphone outputs. |
| **Auto reclaim** | While waiting for motion, periodically reclaims audio if AirPods present; watches Core Audio device changes. | Non-aggressive by default; full BT bounce is user-driven. |
| **Single-ear mode** | Longer disconnect grace (~2.6s vs ~1.2s); shows active ear. | Default on. |
| **Recenter on ear switch** | When streaming bud flips L↔R, auto-recalibrates so the veil doesn’t jump. | Default on; otherwise suggests recalibration. |

### 5. Settings / schedule / login / displays / hotkeys

| Feature | What it does | Caveats |
|---------|--------------|---------|
| **Master Enable** | Protection + tracking on/off. | Default off; remembered. |
| **Schedule** | Always / only active hours / only outside work hours. Pauses overlays outside window → “Paused by schedule.” | Master Enable must still be on. Hour boundaries only (no minutes). |
| **Launch at login** | `SMAppService`. | May fail silently if system blocks login items. |
| **Multi-display** | Veil on all displays or main only; rebuilds when displays change. | Floating, all-Spaces, fullscreen-auxiliary panels. |
| **Panic hotkey** | Global ⌘⇧B toggles panic cover. | Toggleable in General. |
| **Calibration drift prompt** | Settled pose >~**12°** off center for ~**10s** → suggest recalibrate (+ notification). | Toggleable; **15 min** cooldown. |

**UI tabs:** Status · Privacy · Neck care · Schedule · General.

### 6. Menu bar & UI

| Surface | Behavior |
|---------|----------|
| **Menu bar icon** | Avert brand mark. App is accessory (menu-bar only, no Dock icon while running as LSUIElement). |
| **Menu** | Status · Open Avert (⌘O) · Enable (⌘E) · Calibrate (⌘C) · Bring AirPods… (when needed) · Panic blur (⌘⇧B) · Quit (⌘Q). |
| **Main window** | Sidebar with logo (~780×520). Sheets for calibration and exercises. About in General. |
| **Status pane** | Live yaw/pitch/ear, schedule, panic, displays, metrics; Enable / Calibrate / Bring AirPods / Start exercise. |

### 7. Other behavior

- Settings persisted in UserDefaults (enable, thresholds, schedule, etc.)
- Wellness copy: “not a diagnosis”; exercise caution against pain
- Panic image: `~/Library/Application Support/Avert/panic-cover.jpg`

---

## Docs

| Doc | Purpose |
|-----|---------|
| [docs/PRODUCT.md](docs/PRODUCT.md) | Problem, user, scope, non-goals |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Modules, data flow, overlay design |
| [docs/TECH_SPEC.md](docs/TECH_SPEC.md) | APIs, thresholds, calibration, edge cases |
| [docs/APP_STORE.md](docs/APP_STORE.md) | Sandbox, review risks |
| [docs/PRIVACY.md](docs/PRIVACY.md) | On-device privacy statement |
| [docs/LAUNCH.md](docs/LAUNCH.md) | Pre-ship manual checklist |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Build order and later platforms |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Locked product/tech decisions |

## Related (out of scope)

- **DiskViper** — separate product; Avert is not part of it
- **iOS** — head tracking works in-app; system-wide overlay over other apps is not available to third parties (see roadmap)
