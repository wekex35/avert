# Decisions

Record lasting choices here. Prefer short entries: date, decision, why.

## Locked

### 2026-09-24 — Separate repo from DiskViper

Avert is its own product under `~/Programs/peekguard` (repo folder may still use the old path). DiskViper remains storage intelligence only.

### 2026-09-24 — Product name: Avert

Renamed from PeekGuard. Bundle ID `com.avert.app`. Quiet utility tone; “avert” = look away.

### 2026-09-24 — Native Swift, not Flutter

Menu bar + CoreMotion + AppKit overlays are first-class in Swift. Avoid Flutter bridge cost for V1.

### 2026-09-24 — App Store–safe blur path

V1 uses overlay + `NSVisualEffectView`, not private CG blur APIs and not Screen Recording.

### 2026-09-24 — AirPods motion first; no camera in V1

Matches the viral demo’s “AirPods for head tracking” claim and avoids Camera permission.

### 2026-09-24 — iOS system-wide overlay is out of scope

Third-party apps cannot cover other apps on iOS. Any mobile work is in-app only and later.

### 2026-09-24 — Menu bar agent (`LSUIElement`)

Decision: agent app, no Dock icon.
Why: matches quiet utility tone; always available from the menu bar.

### 2026-09-24 — Cover all displays in Phase 1

Decision: recreate left/right overlays for every `NSScreen`.
Why: cheap with the two-panel approach; better than silent gaps on external monitors.

## Open

| ID | Question | Options | Lean |
|----|----------|---------|------|
| D3 | Spaces | Current Space vs all Spaces | All Spaces (`canJoinAllSpaces`) for now |
| D4 | Monetization | Free / paid / freemium | After working binary |
| D5 | Bundle ID / team | TBD | Owner decides at signing |
| D6 | Yaw→side mapping | Confirm with hardware | Fix during Phase 1 bring-up |

## Log template

```
### YYYY-MM-DD — Title

Decision: …
Why: …
```
