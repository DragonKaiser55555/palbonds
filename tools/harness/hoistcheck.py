"""
Finds Lua locals that are CALLED before they are DEFINED.

Lua locals are not hoisted: a call written above the definition compiles as a
global lookup and is nil at runtime. It throws only when that branch executes,
so it can sit dormant behind a disabled toggle for weeks. This file has been
bitten three times (passes 180, 305, 313).

A name is safe if it has a forward declaration (`local NAME` with no value)
above the first call.
"""
import re, sys, glob, os

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
        out.append(src[i])
        i += 1
    return ''.join(out)

problems = 0
for path in sorted(glob.glob(os.path.join(sys.argv[1], '*.lua'))):
    lines = strip_comments(open(path, encoding='utf-8').read()).split('\n')

    defined = {}      # name -> line of real definition
    forward = {}      # name -> line of bare `local NAME`
    for i, l in enumerate(lines, 1):
        m = re.match(r'\s*local\s+function\s+([A-Za-z_]\w*)', l)
        if m and m.group(1) not in defined:
            defined[m.group(1)] = i
            continue
        m = re.match(r'\s*([A-Za-z_]\w*)\s*=\s*function', l)
        if m and m.group(1) not in defined:
            defined[m.group(1)] = i
            continue
        m = re.match(r'\s*local\s+([A-Za-z_]\w*)\s*=\s*function', l)
        if m and m.group(1) not in defined:
            defined[m.group(1)] = i
            continue
        m = re.match(r'\s*local\s+([A-Za-z_]\w*)\s*$', l)
        if m:
            forward.setdefault(m.group(1), i)
        m = re.match(r'\s*local\s+([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)\s*$', l)
        if m:
            forward.setdefault(m.group(1), i)
            forward.setdefault(m.group(2), i)

    for name, defline in defined.items():
        for i, l in enumerate(lines, 1):
            if i >= defline:
                break
            if re.search(r'(?<![\w.:])' + re.escape(name) + r'\s*\(', l):
                fwd = forward.get(name)
                if fwd is not None and fwd < i:
                    continue
                print("%s:%d  calls '%s' but it is defined at line %d (no forward declaration)"
                      % (os.path.basename(path), i, name, defline))
                problems += 1
                break

print("\nCLEAN - no use-before-definition found." if problems == 0
      else "\n%d problem(s) found." % problems)
