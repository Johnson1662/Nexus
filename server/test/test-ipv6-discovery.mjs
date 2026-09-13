import assert from "node:assert/strict";
import { collectHostIpsForTest } from "../dist/server.mjs";

console.log("=== Testing Host IP Discovery (IPv4 + IPv6) ===");

const ips = collectHostIpsForTest("test-host-id");

assert(Array.isArray(ips), "collectHostIps returns an array");
assert(ips.length >= 1, "at least the HOST: sentinel is present");
assert.equal(ips[ips.length - 1], "HOST:test-host-id", "HOST: sentinel is appended last");

const addresses = ips.filter((entry) => !entry.startsWith("HOST:"));
for (const address of addresses) {
  assert(!address.startsWith("127."), `loopback must be excluded: ${address}`);
  assert(!address.startsWith("169.254."), `IPv4 link-local must be excluded: ${address}`);
  assert(!/^fe80/i.test(address), `IPv6 link-local must be excluded: ${address}`);
  assert(address !== "::1", "IPv6 loopback must be excluded");
  assert(!address.includes("%"), "IPv6 zone index must be stripped");
  assert(/^[0-9a-fA-F:.]+$/.test(address), `address must be a bare IP literal: ${address}`);
}

// Ranking: LAN IPv4 first, then global IPv6, then ULA IPv6, then other IPv4.
const rank = (address) => {
  if (!address.includes(":")) {
    return /^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(address) ? 0 : 3;
  }
  return /^f[cd]/i.test(address) ? 2 : 1;
};
const ranks = addresses.map(rank);
const sorted = [...ranks].sort((a, b) => a - b);
assert.deepEqual(ranks, sorted, "addresses must be ordered by quality rank");

console.log(`Discovered ${addresses.length} usable address(es):`, addresses);
console.log("ALL IP DISCOVERY TESTS PASSED!");
