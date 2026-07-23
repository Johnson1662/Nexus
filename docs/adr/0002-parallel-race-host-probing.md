# Parallel Race Host Probing Strategy

We decided to probe multiple candidate host IPs simultaneously using HTTP `/probe` requests with a tight timeout, connecting to whichever responds first. This eliminates fallback latency across changing networks (LAN, hotspot, Tailscale, Relay).
