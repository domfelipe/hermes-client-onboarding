#!/usr/bin/env python3
"""Spawn `hermes chat --cli -s <skill>` and inject the kickoff as first user message.

Hermes only runs a model turn after a user message. The TUI startup-query path
races session creation (~4s) and often silently skips. This classic-CLI path
waits for a ready prompt, sends the kickoff once, then hands the TTY to the user.
"""
from __future__ import annotations

import os
import pty
import select
import sys
import time


def main() -> int:
    skill = os.environ.get("HERMES_ONBOARD_SKILL", "hermes-client-onboarding")
    kickoff = os.environ.get(
        "HERMES_ONBOARD_KICKOFF",
        "Inicie AGORA o onboarding de cliente Hermes. Siga a skill "
        "hermes-client-onboarding: pre-flight em silêncio e abra a Phase 1 "
        "com a primeira pergunta. Você fala primeiro. Português brasileiro.",
    )
    if not kickoff.endswith("\n"):
        kickoff += "\n"

    argv = ["hermes", "chat", "--cli", "-s", skill]
    # Extra args after --
    if len(sys.argv) > 1:
        argv.extend(sys.argv[1:])

    pid, master = pty.fork()
    if pid == 0:
        os.execvp(argv[0], argv)

    # Parent: relay I/O; inject kickoff once after session looks ready.
    sent = False
    buf = b""
    start = time.time()
    inject_after = 1.5  # min wait for banner
    deadline = start + 45.0

    try:
        while True:
            timeout = 0.2
            r, _, _ = select.select([master, sys.stdin], [], [], timeout)
            now = time.time()

            if master in r:
                try:
                    data = os.read(master, 8192)
                except OSError:
                    data = b""
                if not data:
                    break
                os.write(sys.stdout.fileno(), data)
                buf += data
                if len(buf) > 20000:
                    buf = buf[-10000:]

            if sys.stdin in r:
                try:
                    data = os.read(sys.stdin.fileno(), 8192)
                except OSError:
                    data = b""
                if not data:
                    # stdin closed — keep agent until it exits
                    pass
                else:
                    os.write(master, data)

            if not sent and now >= start + inject_after:
                lower = buf.lower()
                ready_markers = (
                    b"ready",
                    b"session:",
                    b"try ",
                    b"welcome",
                    b"type your message",
                    b"\n> ",
                    b"\n❯",
                    b"\nprompt",
                )
                looks_ready = any(m in lower for m in ready_markers)
                timed = now >= start + 4.0  # hard fallback inject
                if looks_ready or timed:
                    # Small settle so status line finishes drawing
                    time.sleep(0.35)
                    os.write(master, kickoff.encode("utf-8", errors="replace"))
                    sent = True

            if not sent and now > deadline:
                # Last resort
                os.write(master, kickoff.encode("utf-8", errors="replace"))
                sent = True

            # Reap child
            wpid, status = os.waitpid(pid, os.WNOHANG)
            if wpid == pid:
                if os.WIFEXITED(status):
                    return os.WEXITSTATUS(status)
                return 1
    except KeyboardInterrupt:
        try:
            os.kill(pid, 2)
        except ProcessLookupError:
            pass
        return 130
    finally:
        try:
            os.close(master)
        except OSError:
            pass

    # Blocking wait if loop broke on EOF from master
    try:
        _, status = os.waitpid(pid, 0)
        if os.WIFEXITED(status):
            return os.WEXITSTATUS(status)
    except ChildProcessError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
