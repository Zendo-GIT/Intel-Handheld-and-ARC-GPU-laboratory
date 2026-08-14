# Changelog

## 1.0.0 — 2026-08-14

- Added the verified six-byte unsupported-GPU dialog suppression patch for
  Steam build 12158144.
- Added 100% internal-scale and HDR-off graphics corruption protection.
- Added Intel Vulkan pipeline-cache header validation without rebuilding or
  prefetching the cache.
- Added a controlled direct Steam launch with temporary AppID context.
- Added chapter-progress-only automatic presentation recovery plus
  `Ctrl+Alt+F11` manual recovery. Checkpoints and in-game hangs cannot trigger
  the automatic path.
- Removed rejected asset-I/O and hung-window auto-resets, forced 2.14 GB cache
  prefetch, priority/throttling changes and RTSS/overlay isolation after
  long-session testing.
- Added reversible Steam Play integration using a locally compiled wrapper and
  a separately verified game payload, with an exact-path runtime handoff for
  Windows Game Bar and ClawTweaks recognition.
