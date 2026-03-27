/**
 * Bootstrap — ensures dependencies are installed and TypeScript is compiled,
 * then launches the MCP server.
 *
 * Usage:  node start.js
 *
 * This is the ONLY file users need to run. On first launch it will
 * automatically `npm install` and `npm run build` so no manual setup
 * is required beyond having Node.js (>= 18) installed.
 */

import { existsSync } from "node:fs";
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const log = (msg) => console.error(`[pitcrew-mcp] ${msg}`);

const __filename = fileURLToPath(import.meta.url);
const projectRoot = dirname(__filename);

try {
    const nmPath = resolve(projectRoot, "node_modules");
    if (!existsSync(nmPath)) {
        log("node_modules not found — installing...");
        execSync("npm install --no-fund --no-audit", {
            cwd: projectRoot,
            stdio: ["ignore", "ignore", "inherit"],
        });
        log("Dependencies installed.");
    }

    const distPath = resolve(projectRoot, "dist");
    if (!existsSync(distPath)) {
        log("dist not found — compiling TypeScript...");
        execSync("npm run build", {
            cwd: projectRoot,
            stdio: ["ignore", "ignore", "inherit"],
        });
        log("Build complete.");
    }

    await import("./dist/index.js");
} catch (err) {
    log(`FATAL: ${err.message}`);
    process.exit(1);
}
