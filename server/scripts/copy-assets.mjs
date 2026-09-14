import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const serverDir = path.resolve(path.dirname(__filename), "..");

// 1. Ensure output directories exist
const distDir = path.join(serverDir, "dist");
const registryDistDir = path.join(distDir, "registry");
const integrationsDistDir = path.join(distDir, "integrations");
fs.mkdirSync(registryDistDir, { recursive: true });
fs.mkdirSync(integrationsDistDir, { recursive: true });

// 2. Copy agents.json
const registrySrc = path.join(serverDir, "src", "registry", "agents.json");
const registryDst = path.join(registryDistDir, "agents.json");
if (fs.existsSync(registrySrc)) {
  fs.cpSync(registrySrc, registryDst, { dereference: true });
  console.log("[build] copied agents.json to dist/registry/agents.json");
}

// 3. Copy ambient integration assets
const integrationsSrcDir = path.join(serverDir, "assets", "integrations");
if (fs.existsSync(integrationsSrcDir)) {
  for (const file of fs.readdirSync(integrationsSrcDir)) {
    const src = path.join(integrationsSrcDir, file);
    const dst = path.join(integrationsDistDir, file);
    fs.cpSync(src, dst, { dereference: true });
    console.log(`[build] copied ${file} to dist/integrations/${file}`);
  }
}

// 4. Ensure shebang and executable bit on dist/cli.mjs
const cliPath = path.join(distDir, "cli.mjs");
if (fs.existsSync(cliPath)) {
  let content = fs.readFileSync(cliPath, "utf8");
  if (!content.startsWith("#!")) {
    content = "#!/usr/bin/env node\n" + content;
    fs.writeFileSync(cliPath, content, "utf8");
    console.log("[build] prepended shebang to dist/cli.mjs");
  }
  if (process.platform !== "win32") {
    try {
      fs.chmodSync(cliPath, 0o755);
    } catch {}
  }
}
