#!/usr/bin/env python3
"""Spawn hermes chat --cli -s <skill> and submit a short kickoff once.

Avoids Hermes paste-collapse (≥5 lines or ≥2000 chars → [Pasted text #N]).
Uses raw TTY relay so Enter stays inside Hermes, not the outer shell.
"""
from __future__ import annotations

import os
import pty
import select
import sys
import termios
import time
import tty


# Keep under paste_collapse thresholds (5 lines / 2000 chars)
DEFAULT_KICKOFF = (
    "Inicie o onboarding agora. Skill hermes-client-onboarding. "
    "Pre-flight silencioso e abra a Phase 1 (voce fala primeiro)."
)


def main() -> int:
    skill = os.environ.get("HERMES_ONBOARD_SKILL", "hermes-client-onboarding")
    kickoff = os.environ.get("HERMES_ONBOARD_KICKOFF", DEFAULT_KICKOFF).strip()
    # Collapse accidental newlines so we never trip paste_collapse by lines
    kickoff = " ".join(kickoff.split())
    if len(kickoff) > 400:
        kickoff = kickoff[:397] + "..."

    argv = ["hermes", "chat", "--cli", "-s", skill]
    if len(sys.argv) > 1:
        argv.extend(sys.argv[1:])

    pid, master = pty.fork()
    if pid == 0:
        os.environ.pop("HERMES_TUI_QUERY", None)  # avoid confusing classic CLI
        os.execvp(argv[0], argv)

    stdin_fd = sys.stdin.fileno()
    stdout_fd = sys.stdout.fileno()
    old_tty = None
    if sys.stdin.isatty():
        old_tty = termios.tcgetattr(stdin_fd)
        tty.setraw(stdin_fd)

    sent = False
    buf = b""
    start = time.time()
    # Wait for skill activation line, else inject after a few seconds
    try:
        while True:
            r, _, _ = select.select([master, stdin_fd], [], [], 0.15)
            now = time.time()

            if master in r:
                try:
                    data = os.read(master, 8192)
                except OSError:
                    data = b""
                if not data:
                    break
                os.write(stdout_fd, data)
                buf += data
                if len(buf) > 30000:
                    buf = buf[-12000:]

            if stdin_fd in r:
                try:
                    data = os.read(stdin_fd, 8192)
                except OSError:
                    data = b""
                if data:
                    os.write(master, data)

            if not sent:
                lower = buf.lower()
                activated = b"activated skills" in lower or b"hermes-client-onboarding" in lower
                timed = now >= start + 3.5
                if (activated and now >= start + 1.2) or timed:
                    time.sleep(0.25)
                    # Type as normal keys + CR (not a giant paste burst)
                    payload = (kickoff + "\r").encode("utf-8", errors="replace")
                    os.write(master, payload)
                    sent = True

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
        if old_tty is not None:
            try:
                termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_tty)
            except termios.error:
                pass
        try:
            os.close(master)
        except OSError:
            pass

    try:
        _, status = os.waitpid(pid, 0)
        if os.WIFEXITED(status):
            return os.WEXITSTATUS(status)
    except ChildProcessError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
