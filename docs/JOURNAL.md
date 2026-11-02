# Project journal

## 2026-11-02 — optional QUIC REALITY HTTP/3 source support

Added optional per-profile `h3` ALPN with legacy default, safe import/export/config round trips and mode-specific exact core hash checks. Local candidate Xray core source `d39241a662de9400b58e33abc85d6e30765550f9` Darwin arm64 SHA-256 `6dea1ca35335cef454913bf7a33937bb1a8a10d54724c76b1751ef46fe465025`; the legacy b7 core remains in a distinct install slot. Synthetic app tests passed; no installed application, profile, privileged helper, tunnel or server was changed by this source update. For rollback choose the existing legacy app and b7 core or revert the scoped source commit; verify actual runtime before action. Local core artifact manifest: `/private/tmp/xray-h3-build-20261102/MANIFEST.txt` (temporary, preserve while needed). No traffic-similarity or production-safety claim.
