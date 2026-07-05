#!/usr/bin/env python3
"""Minimal PTY fixture: renders bracketed paste on a fake prompt line."""

import os
import sys

BRACKETED_PASTE_MODE = b"\x1b[?2004h"
PROMPT = "> "


def write_prompt() -> None:
    sys.stdout.write("\r\n" + PROMPT)
    sys.stdout.flush()


def render_pasted(data: bytes) -> None:
    text = data.decode("utf-8", errors="replace")
    sys.stdout.write("\r\x1b[K" + PROMPT + text)
    sys.stdout.flush()


def main() -> None:
    sys.stdout.buffer.write(BRACKETED_PASTE_MODE)
    write_prompt()
    buf = b""
    while True:
        try:
            chunk = os.read(0, 4096)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
        while True:
            start = buf.find(b"\x1b[200~")
            if start == -1:
                buf = b""
                break
            end = buf.find(b"\x1b[201~", start)
            if end == -1:
                buf = buf[start:]
                break
            pasted = buf[start + 6 : end]
            render_pasted(pasted)
            buf = buf[end + 6 :]


if __name__ == "__main__":
    main()
