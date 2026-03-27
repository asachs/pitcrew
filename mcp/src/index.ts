#!/usr/bin/env node
/**
 * Pitcrew MCP Server
 *
 * Exposes bay management (git worktrees) and beads integration (task tracking)
 * as MCP tools for the GitHub Copilot CLI crew chief.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve, basename } from "node:path";
import { homedir } from "node:os";

const BAYS_DIR = process.env.PITCREW_BAYS || resolve(homedir(), "bays");
const BD = process.env.PITCREW_BD || "bd";

// ── Helpers ──────────────────────────────────────────────────────

function run(cmd: string, cwd?: string): string {
  try {
    return execSync(cmd, {
      cwd,
      encoding: "utf-8",
      timeout: 30_000,
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
  } catch (e: any) {
    throw new Error(`Command failed: ${cmd}\n${e.stderr || e.message}`);
  }
}

function bayPath(beadId: string): string {
  return resolve(BAYS_DIR, `pit-${beadId}`);
}

// ── Server ──────────────────────────────────────────────────────

const server = new McpServer({
  name: "pitcrew",
  version: "0.1.0",
});

// ── Bay Management Tools ────────────────────────────────────────

server.tool(
  "create_bay",
  "Create an isolated git worktree (bay) for a pit call",
  {
    repo_path: z.string().describe("Absolute path to the git repository"),
    bead_id: z.string().describe("Bead ID (e.g., pitcrew-a3f2)"),
  },
  async ({ repo_path, bead_id }) => {
    const bay = bayPath(bead_id);
    const branch = `pit/${bead_id}`;
    run(`git worktree add "${bay}" -b "${branch}"`, repo_path);
    // Apply CRLF fix (lesson from first pit stop)
    run(`git config core.autocrlf false`, bay);
    return { content: [{ type: "text", text: `Bay created at ${bay} on branch ${branch}` }] };
  }
);

server.tool(
  "list_bays",
  "List all active git worktree bays",
  {
    repo_path: z.string().describe("Absolute path to the git repository"),
  },
  async ({ repo_path }) => {
    const output = run("git worktree list --porcelain", repo_path);
    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "release_bay",
  "Merge a bay back to the current branch and clean up",
  {
    repo_path: z.string().describe("Absolute path to the git repository"),
    bead_id: z.string().describe("Bead ID to release"),
  },
  async ({ repo_path, bead_id }) => {
    const bay = bayPath(bead_id);
    const branch = `pit/${bead_id}`;

    // Verify bay has commits
    run(`git log ${branch} --oneline -1`, repo_path);

    // Run .pitcrew-verify if it exists
    const verifyScript = resolve(repo_path, ".pitcrew-verify");
    if (existsSync(verifyScript)) {
      try {
        run(`bash "${verifyScript}"`, bay);
      } catch (e: any) {
        return {
          content: [{
            type: "text",
            text: `🔴 Verification failed in bay ${bead_id}:\n${e.message}`,
          }],
        };
      }
    }

    // Merge
    try {
      const mergeResult = run(`git merge "${branch}" --no-edit`, repo_path);
      // Clean up
      run(`git worktree remove "${bay}"`, repo_path);
      run(`git branch -d "${branch}"`, repo_path);
      return {
        content: [{
          type: "text",
          text: `🟢 Released ${bead_id}: ${mergeResult}`,
        }],
      };
    } catch (e: any) {
      const msg = e.message || "";
      if (msg.includes("CONFLICT")) {
        return {
          content: [{
            type: "text",
            text: `🟡 Merge conflict in ${bead_id}. Crew chief must resolve:\n${msg}`,
          }],
        };
      }
      return {
        content: [{
          type: "text",
          text: `🔴 Merge failed for ${bead_id}:\n${msg}`,
        }],
      };
    }
  }
);

server.tool(
  "cleanup_bays",
  "Remove all pit worktrees and branches",
  {
    repo_path: z.string().describe("Absolute path to the git repository"),
  },
  async ({ repo_path }) => {
    const worktrees = run("git worktree list --porcelain", repo_path);
    const bays = worktrees
      .split("\n")
      .filter((l) => l.startsWith("worktree ") && l.includes("/pit-"))
      .map((l) => l.replace("worktree ", ""));

    let cleaned = 0;
    for (const bay of bays) {
      const id = basename(bay).replace("pit-", "");
      try {
        run(`git worktree remove "${bay}"`, repo_path);
        run(`git branch -D "pit/${id}"`, repo_path);
        cleaned++;
      } catch { /* ignore cleanup errors */ }
    }
    return { content: [{ type: "text", text: `Cleaned ${cleaned} bays` }] };
  }
);

// ── Beads Integration Tools ─────────────────────────────────────

server.tool(
  "create_pit_call",
  "Create a new pit call (bead) for tracking",
  {
    title: z.string().describe("Task title"),
    description: z.string().describe("Detailed task description"),
    priority: z.number().optional().describe("Priority (0=P0, 1=P1, 2=P2)"),
    files: z.array(z.string()).optional().describe("File paths this task touches"),
  },
  async ({ title, description, priority, files }) => {
    const labels = (files || []).map((f) => `--label "file:${f}"`).join(" ");
    const prio = priority !== undefined ? `-p ${priority}` : "";
    const output = run(
      `${BD} create "${title}" -d "${description.replace(/"/g, '\\"')}" -t task ${prio} ${labels}`
    );
    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "list_pit_calls",
  "List all pit calls with their status",
  {},
  async () => {
    const output = run(`${BD} list`);
    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "claim_pit_call",
  "Claim a pit call (set to in_progress)",
  {
    bead_id: z.string().describe("Bead ID to claim"),
  },
  async ({ bead_id }) => {
    const output = run(`${BD} update ${bead_id} --claim`);
    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "close_pit_call",
  "Close a completed pit call",
  {
    bead_id: z.string().describe("Bead ID to close"),
    message: z.string().describe("Completion message"),
  },
  async ({ bead_id, message }) => {
    const output = run(`${BD} close ${bead_id} -m "${message.replace(/"/g, '\\"')}"`);
    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "timing_screen",
  "Show pit stop status dashboard",
  {
    repo_path: z.string().describe("Absolute path to the git repository"),
  },
  async ({ repo_path }) => {
    const beads = run(`${BD} list`);
    const worktrees = run("git worktree list", repo_path);

    // Load lessons if they exist
    const lessonsPath = resolve(repo_path, ".pitcrew-lessons");
    const lessons = existsSync(lessonsPath)
      ? readFileSync(lessonsPath, "utf-8").split("\n").filter((l: string) => l.startsWith("LESSON:")).length
      : 0;

    return {
      content: [{
        type: "text",
        text: `═══ TIMING SCREEN ═══\n\n${beads}\n\n── Bays ──\n${worktrees}\n\n── Lessons: ${lessons} accumulated`,
      }],
    };
  }
);

server.tool(
  "load_context",
  "Load .pitcrew and .pitcrew-lessons for mechanic prompt injection",
  {
    repo_path: z.string().describe("Absolute path to the git repository"),
  },
  async ({ repo_path }) => {
    const parts: string[] = [];

    const pitcrewPath = resolve(repo_path, ".pitcrew");
    if (existsSync(pitcrewPath)) {
      parts.push("## Project Conventions (.pitcrew)\n\n" + readFileSync(pitcrewPath, "utf-8"));
    }

    const lessonsPath = resolve(repo_path, ".pitcrew-lessons");
    if (existsSync(lessonsPath)) {
      parts.push("## Lessons Learned (.pitcrew-lessons)\n\n" + readFileSync(lessonsPath, "utf-8"));
    }

    return {
      content: [{
        type: "text",
        text: parts.length > 0 ? parts.join("\n\n---\n\n") : "No .pitcrew or .pitcrew-lessons found.",
      }],
    };
  }
);

server.tool(
  "add_lesson",
  "Add a lesson learned from a pit stop to .pitcrew-lessons",
  {
    repo_path: z.string().describe("Absolute path to the git repository"),
    lesson: z.string().describe("What went wrong → what to do instead"),
  },
  async ({ repo_path, lesson }) => {
    const lessonsPath = resolve(repo_path, ".pitcrew-lessons");
    const entry = `\nLESSON: ${lesson}\n`;

    const { appendFileSync } = await import("fs");
    appendFileSync(lessonsPath, entry);

    return { content: [{ type: "text", text: `Added lesson to ${lessonsPath}` }] };
  }
);

// ── Start ───────────────────────────────────────────────────────

const transport = new StdioServerTransport();
await server.connect(transport);
