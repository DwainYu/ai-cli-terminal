// ai-cli-terminal — PI title extension
//
// Loaded by the wrapper as `pi -e <this file>`; it is part of this repository,
// not a file dropped into the user's ~/.pi directory.
//
// Contract with the adapter (src/cli/pi.adapter):
//     title = <basename(cwd)> + " · " + PI
// A unit test asserts that CLI_NAME below stays in sync with ACT_ADAPTER_DISPLAY.
//
// Why an extension exists at all (probe, 2026-10-05, pi 1.0.3):
//   * PI sets the terminal title itself to `π - <basename(cwd)>`;
//   * it does so right AFTER the `session_start` event;
//   * no flag or setting disables that write;
//   * extension event contexts do not expose `ctx.ui.setTitle`, so the sequence
//     is written to stdout — exactly what PI's own `setTitle` does internally.
// Because PI's write lands after `session_start`, this extension schedules ONE
// deferred re-emit from that handler. One shot: no daemon, no polling, no
// background process, no `wait`.
//
// Safety: a title failure must never break the TUI, so every write is guarded.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const SEPARATOR = " · ";
const CLI_NAME = "PI"; // must match ACT_ADAPTER_DISPLAY in src/cli/pi.adapter

/** Remove characters that must never appear inside an OSC payload. */
function sanitize(value: string): string {
  return value.replace(/[\x00-\x1f\x7f]/g, "");
}

/** Project name = basename of the current working directory. */
function projectName(): string {
  try {
    const cwd = process.cwd();
    const parts = cwd.split(/[\\/]+/).filter((part) => part.length > 0);
    return parts.length > 0 ? parts[parts.length - 1] : "/";
  } catch {
    return "/";
  }
}

/** Write OSC 0 with "<project> · PI". */
function emitTitle(): void {
  try {
    const title = sanitize(projectName()) + SEPARATOR + CLI_NAME;
    process.stdout.write(`\x1b]0;${title}\x07`);
  } catch {
    /* a title is never worth failing a session over */
  }
}

/** One deferred re-emit, scheduled from session_start (see file header). */
function scheduleReemit(): void {
  try {
    const timer: any = setTimeout(emitTitle, 400);
    if (timer && typeof timer.unref === "function") timer.unref();
  } catch {
    /* ignore */
  }
}

export default function (pi: ExtensionAPI): void {
  const events = [
    "session_start",
    "before_agent_start",
    "agent_start",
    "agent_end",
    "turn_end",
    "message_end",
    "session_info_changed",
  ];

  for (const event of events) {
    try {
      pi.on(event as any, (async () => {
        if (event === "session_start") scheduleReemit();
        emitTitle();
      }) as any);
    } catch {
      // Unknown event name in this pi version: skip it rather than fail load.
    }
  }
}
