"""
Finds calls to local-style functions that are NEVER DEFINED in their file.

This is the bug that shipped on 2026-09-12: a span removal deleted a function's
definition and left both of its call sites behind. Lua reads an undefined name
as a nil global, and safe_call/pcall swallow the resulting error, so nothing is
visible in any log -- the behaviour simply stops happening, silently.

Complements hoistcheck.py, which only finds calls that appear BEFORE a
definition that does exist.
"""
import re, sys, os, glob

LUA_KEYWORDS = {
    'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function',
    'goto', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return',
    'then', 'true', 'until', 'while',
}

KNOWN = {
    # lua stdlib
    'print', 'pairs', 'ipairs', 'type', 'tostring', 'tonumber', 'pcall',
    'xpcall', 'require', 'select', 'error', 'assert', 'setmetatable',
    'getmetatable', 'rawget', 'rawset', 'rawequal', 'next', 'unpack',
    'collectgarbage', 'load', 'loadstring', 'loadfile', 'dofile',
    # UE4SS globals
    'RegisterHook', 'RegisterKeyBind', 'FindFirstOf', 'FindAllOf',
    'StaticFindObject', 'StaticConstructObject', 'ExecuteInGameThread',
    'ExecuteInGameThreadWithDelay', 'LoopAsync', 'NotifyOnNewObject',
    'IsInGameThread', 'CreateInvalidObject', 'RegisterInitGameStatePreHook',
    'RegisterInitGameStatePostHook', 'RegisterProcessConsoleExecHook',
}


def strip_comments(src):
    out, i, n = [], 0, len(src)
    while i < n:
        m = re.match(r'--\[(=*)\[', src[i:])
        if m:
            eq = m.group(1)
            end = src.find(']' + eq + ']', i)
            end = n if end == -1 else end + len(eq) + 2
            out.append(re.sub(r'[^\n]', ' ', src[i:end]))
            i = end
            continue
        if src.startswith('--', i):
            end = src.find('\n', i)
            end = n if end == -1 else end
            out.append(' ' * (end - i))
            i = end
            continue
        if src[i] in '"\'':
            q = src[i]
            j = i + 1
            while j < n and src[j] != q:
                j += 2 if src[j] == chr(92) else 1
            out.append(' ' * (min(j, n - 1) - i + 1))
            i = min(j, n - 1) + 1
            continue
        out.append(src[i])
        i += 1
    return ''.join(out)


problems = 0
for path in sorted(glob.glob(os.path.join(sys.argv[1], '*.lua'))):
    text = strip_comments(open(path, encoding='utf-8').read())
    lines = text.split('\n')

    bound = set(KNOWN)
    for pat in (r'local\s+function\s+([A-Za-z_]\w*)',
                r'function\s+([A-Za-z_]\w*)\s*\(',
                r'^\s*([A-Za-z_]\w*)\s*=\s*function',
                r'local\s+([A-Za-z_]\w*)\s*=',
                r'local\s+([A-Za-z_]\w*)\s*$',
                r'local\s+([A-Za-z_]\w*)\s*,',
                r'local\s+\w+\s*,\s*([A-Za-z_]\w*)',
                r'function\s+[A-Za-z_]\w*[.:]([A-Za-z_]\w*)',
                r'for\s+([A-Za-z_]\w*)',
                r'function\s*\(([^)]*)\)'):
        for m in re.finditer(pat, text, re.M):
            for g in m.groups():
                for piece in re.split(r'[,\s]+', g or ''):
                    if piece:
                        bound.add(piece)

    for i, line in enumerate(lines, 1):
        for m in re.finditer(r'(?<![\w.:])([a-z_][\w]*)\s*\(', line):
            name = m.group(1)
            if name in bound or name in LUA_KEYWORDS:
                continue
            print("%s:%d  calls '%s' which is NEVER DEFINED in this file"
                  % (os.path.basename(path), i, name))
            problems += 1

print("\nCLEAN - every called local resolves." if problems == 0
      else "\n%d undefined call(s)." % problems)
