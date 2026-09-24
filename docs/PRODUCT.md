# Product

## One-liner

Avert blurs the side of your Mac screen when you look away, using AirPods head tracking.

## Problem

On a plane, café, or open office, people beside you can read your screen. Existing tools are static (privacy filters), camera-based (battery, awkward), or require you to remember to dim.

Looking away is the natural signal that privacy matters *right now*.

## Inspiration

Public discussion around a dual-facing / privacy-oriented iPhone concept (“iPhone Duo”). Avert takes the *software* half of that idea and ships it on Mac first, where system overlays are allowed.

## Primary user

Someone who:

- Uses a MacBook in public or semi-public spaces
- Already wears AirPods Pro / Max / recent AirPods with head tracking
- Wants privacy without a physical filter or camera watching them

## Core loop

```
Wear AirPods → Open Avert → Calibrate facing screen → Work normally
         ↓
   Look left/right past threshold
         ↓
   Matching screen side soft-blurs
         ↓
   Look back → blur clears
```

## V1 scope (must ship)

- Menu bar app (always available, minimal chrome)
- Enable / disable toggle
- One-tap calibration (“I’m looking at the screen”)
- Directional side blur driven by yaw relative to calibrated pose
- Status: AirPods connected / motion available / tracking active
- Sensible defaults for blur strength and yaw threshold
- App Store–safe public APIs only

## V1 non-goals

- Camera / Vision face tracking (later optional)
- Pitch-based posture coaching (different product)
- Reading or modifying other apps’ content
- iOS system-wide overlay
- Multi-display advanced layouts beyond “cover the active display”
- Accounts, cloud, analytics suites

## Success criteria (V1)

- From cold start + AirPods in ears: calibrate and see side blur within ~60 seconds
- Blur feels intentional, not seizure-inducing (smooth fade, hysteresis)
- Works without Accessibility or Screen Recording permissions
- Clear copy when AirPods aren’t connected or motion isn’t available

## Pricing (open)

Document only — not locked:

- Free trial / freemium vs one-time purchase vs subscription
- Decide after first usable binary exists

## Brand notes

- Name: **Avert**
- Tone: quiet utility, not security theater
- Avoid claiming “military-grade” or absolute privacy; this is shoulder-surf reduction
