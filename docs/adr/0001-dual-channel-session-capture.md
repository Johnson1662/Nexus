# Dual-Channel Session Capture Architecture

We decided to capture PC-side active session states using a primary ACP `session/list` API channel supplemented by a file-system watcher fallback. This balances standardized protocol stability with full coverage of external CLI-initiated sessions without hard-coupling to private agent schemas.
