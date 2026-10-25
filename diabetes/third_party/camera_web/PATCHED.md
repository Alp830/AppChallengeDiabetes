# Patched camera_web 0.3.5+3

Copied from pub.dev `camera_web` 0.3.5+3 (BSD licence, see `LICENSE`), with
one change in `lib/src/camera_web.dart`, marked `PATCHED (diabetes app)`.

**Bug:** `availableCameras()` opens every video input to read its facing mode
and has no per-device error handling. One camera that is listed but can't
start fails the whole call. OBS Virtual Camera does this whenever OBS isn't
streaming (`NotReadableError: Could not start video source`), so the app showed
"Can't open the camera" on a machine with a working webcam.

**Fix:** a device that fails with `notReadable`, `abort`, `overconstrained` or
`notFound` is skipped. Permission errors still throw.

Upstream 0.3.5+6 (2026-09-08) still has the bug. When a release fixes it,
remove `dependency_overrides` from `pubspec.yaml` and delete this folder.
