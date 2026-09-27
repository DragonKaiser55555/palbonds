#!/usr/bin/env python3
"""Strip Lua comments for the SHIPPED package.

Dragón, 2026-09-23: "why would a player who has no intention to even work in
the mod need to have files with the story of experiments and comments? isn't
that meant for github only?" — they do not. `mod/` keeps every comment (that
is the development source, and it is on GitHub); the package players download
carries only code.

Usage:  python tools/strip-comments.py <source dir> <output dir>

What it does, and what it deliberately does NOT do:
  * removes `--` line comments and `--[[ long ]]` / `--[==[ ]==]` comments;
  * removes the blank lines a comment leaves behind, and trailing whitespace;
  * NEVER touches anything inside a string, including "--" in a message, the
    long-bracket strings the settings file is written from, and escapes;
  * changes no code, no names and no order, so the shipped file is the same
    program with the commentary removed.

Line numbers move, which matters when a player quotes one from a crash. That
is covered by committing the stripped tree: the shipped file of any released
version is reproducible from git.
"""
import os
import sys


def strip_lua(src: str) -> str:
    out = []
    i, n = 0, len(src)
    while i < n:
        ch = src[i]

        # --- short string ------------------------------------------------
        if ch in ("'", '"'):
            quote = ch
            out.append(ch)
            i += 1
            while i < n:
                c = src[i]
                out.append(c)
                if c == "\\" and i + 1 < n:      # escape: copy the pair whole
                    out.append(src[i + 1])
                    i += 2
                    continue
                i += 1
                if c == quote:
                    break
            continue

        # --- long string [[ ]] / [=[ ]=] ---------------------------------
        if ch == "[":
            j = i + 1
            eq = 0
            while j < n and src[j] == "=":
                eq += 1
                j += 1
            if j < n and src[j] == "[":
                close = "]" + "=" * eq + "]"
                k = src.find(close, j + 1)
                k = n if k < 0 else k + len(close)
                out.append(src[i:k])
                i = k
                continue

        # --- comment ------------------------------------------------------
        if ch == "-" and src.startswith("--", i):
            j = i + 2
            eq = 0
            if j < n and src[j] == "[":
                k = j + 1
                while k < n and src[k] == "=":
                    eq += 1
                    k += 1
                if k < n and src[k] == "[":          # long comment
                    close = "]" + "=" * eq + "]"
                    e = src.find(close, k + 1)
                    i = n if e < 0 else e + len(close)
                    continue
            e = src.find("\n", i)                     # line comment
            i = n if e < 0 else e
            continue

        out.append(ch)
        i += 1

    # tidy: drop trailing whitespace and the empty lines comments left behind
    lines = "".join(out).split("\n")
    kept, blank_run = [], 0
    for line in lines:
        line = line.rstrip()
        if line == "":
            blank_run += 1
            if blank_run > 1 or not kept:
                continue
            kept.append("")
        else:
            blank_run = 0
            kept.append(line)
    while kept and kept[-1] == "":
        kept.pop()
    return "\n".join(kept) + "\n"


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src_dir, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    total_in = total_out = 0
    for name in sorted(os.listdir(src_dir)):
        if not name.endswith(".lua"):
            continue
        src = open(os.path.join(src_dir, name), encoding="utf-8").read()
        stripped = strip_lua(src)
        with open(os.path.join(out_dir, name), "w", encoding="utf-8", newline="\n") as f:
            f.write(stripped)
        a, b = src.count("\n"), stripped.count("\n")
        total_in += a
        total_out += b
        print("%-16s %5d -> %4d lines (-%d%%)" % (name, a, b, round(100 * (a - b) / a) if a else 0))
    print("%-16s %5d -> %4d lines" % ("TOTAL", total_in, total_out))


if __name__ == "__main__":
    main()
