"""Summarize a Windows crash dump (crash_*.dmp written by UE4SS) without a debugger.

Prints the exception code, the faulting module+offset, registers, and a heuristic
stack scan: values on the crashing thread's stack that point into loaded modules.

Usage:
    python tools/minidump_summary.py <game>/ParadiseKiller/Binaries/Win64/crash_*.dmp
"""
import struct, sys
d = open(sys.argv[1], 'rb').read()
sig, ver, nstreams, rva = struct.unpack_from('<4sIII', d, 0)
streams = {}
for i in range(nstreams):
    t, size, r = struct.unpack_from('<III', d, rva + 12 * i)
    streams.setdefault(t, (size, r))

def ustr(r):
    n = struct.unpack_from('<I', d, r)[0]
    return d[r + 4:r + 4 + n].decode('utf-16le')

# Modules
mods = []
size, r = streams[4]
n = struct.unpack_from('<I', d, r)[0]
for i in range(n):
    base, msize = struct.unpack_from('<QI', d, r + 4 + 108 * i)
    namerva = struct.unpack_from('<I', d, r + 4 + 108 * i + 20)[0]
    mods.append((base, msize, ustr(namerva).split(chr(92))[-1]))

def where(a):
    for b, s, nm in mods:
        if b <= a < b + s:
            return '%s+0x%X' % (nm, a - b)
    return None

# Exception
size, r = streams[6]
tid = struct.unpack_from('<I', d, r)[0]
code, flags, rec, addr, nparams = struct.unpack_from('<IIQQI', d, r + 8)
params = struct.unpack_from('<15Q', d, r + 8 + 32)[:nparams] if nparams else []
print('thread %d  exception 0x%08X at %s (0x%X)  params %s' % (tid, code, where(addr), addr, [hex(p) for p in params]))
ctxsize, ctxrva = struct.unpack_from('<II', d, r + 8 + 152)
rsp = struct.unpack_from('<Q', d, ctxrva + 0x98)[0]
rip = struct.unpack_from('<Q', d, ctxrva + 0xF8)[0]
regs = ['rax','rcx','rdx','rbx','rsp','rbp','rsi','rdi']
vals = struct.unpack_from('<8Q', d, ctxrva + 0x78)
print('rip', where(rip), ' '.join('%s=%X' % kv for kv in zip(regs, vals)))

# Memory list (type 5 = MemoryListStream, 9 = Memory64ListStream)
mem = []
if 5 in streams:
    size, r = streams[5]
    n = struct.unpack_from('<I', d, r)[0]
    for i in range(n):
        start, dsize, drva = struct.unpack_from('<QII', d, r + 4 + 16 * i)
        mem.append((start, dsize, drva))
if 9 in streams:
    size, r = streams[9]
    n, baserva = struct.unpack_from('<QQ', d, r)
    off = baserva
    for i in range(n):
        start, dsize = struct.unpack_from('<QQ', d, r + 16 + 16 * i)
        mem.append((start, dsize, off)); off += dsize

def readmem(a, n):
    for s, sz, rv in mem:
        if s <= a and a + n <= s + sz:
            return d[rv + a - s: rv + a - s + n]
    return None

print('stack scan (return addresses into modules):')
cnt = 0
for k in range(0, 0x3000, 8):
    b = readmem(rsp + k, 8)
    if b is None: break
    v = struct.unpack('<Q', b)[0]
    w = where(v)
    if w and not w.startswith(('ntdll', 'KERNEL')) or (w and cnt < 3):
        print('  rsp+%04X  %s' % (k, w)); cnt += 1
        if cnt > 45: break
