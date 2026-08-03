#!/usr/bin/env python3
"""Fallback: spawn hermes chat --cli and inject a short kickoff via PTY.

Prefer tmux path in start-onboarding.sh — this can freeze prompt_toolkit
on some terminals. Kept for hosts without tmux.
"""
from __future__ import annotations

import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time
import tty


DEFAULT_KICKOFF = (
    "Inicie o onboarding agora. Skill hermes-client-onboarding. "
    "Pre-flight silencioso e Phase 1 (voce fala primeiro)."
)


def _set_winsize(fd: int) -> None:
    try:
        import shutil

        cols, rows = shutil.get_terminal_size(fallback=(120, 40))
        packed = struct.pack("HHHH", rows, cols, 0, 0)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, packed)
    except Exception:
        pass


def main() -> int:
    skill = os.environ.get("HERMES_ONBOARD_SKILL", "hermes-client-onboarding")
    kickoff = os.environ.get("HERMES_ONBOARD_KICKOFF", DEFAULT_KICKOFF).strip()
    kickoff = " ".join(kickoff.split())
    if len(kickoff) > 400:
        kickoff = kickoff[:397] + "..."

    argv = ["hermes", "chat", "--cli", "-s", skill]
    if len(sys.argv) > 1:
        argv.extend(sys.argv[1:])

    pid, master = pty.fork()
    if pid == 0:
        os.environ.pop("HERMES_TUI_QUERY", None)
        os.execvp(argv[0], argv)

    _set_winsize(master)

    def _on_winch(_sig: int, _frame: object) -> None:
        _set_winsize(master)
        try:
            os.kill(pid, signal.SIGWINCH)
        except ProcessLookupError:
            pass

    try:
        signal.signal(signal.SIGWINCH, _on_winch)
    except Exception:
        pass

    stdin_fd = sys.stdin.fileno()
    stdout_fd = sys.stdout.fileno()
    old_tty = None
    if sys.stdin.isatty():
        old_tty = termios.tcgetattr(stdin_fd)
        tty.setraw(stdin_fd)

    sent = False
    buf = b""
    start = time.time()
    try:
        while True:
            r, _, _ = select.select([master, stdin_fd], [], [], 0.12)
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
                ready = (
                    b"activated skills" in lower
                    or b"welcome to hermes" in lower
                    or b"type your message" in lower
                )
                if (ready and now >= start + 1.0) or now >= start + 4.0:
                    time.sleep(0.35)
                    os.write(master, (kickoff + "\r").encode("utf-8", errors="replace"))
                    sent = True

            wpid, status = os.waitpid(pid, os.WNOHANG)
            if wpid == pid:
                return os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1
    except KeyboardInterrupt:
        try:
            os.kill(pid, signal.SIGINT)
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
