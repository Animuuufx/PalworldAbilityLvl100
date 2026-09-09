import struct
import sys
from pathlib import Path
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

EXE = Path(sys.argv[1])
d = EXE.read_bytes()
pe = struct.unpack_from('<I', d, 0x3C)[0]
base = struct.unpack_from('<Q', d, pe + 24 + 24)[0]
nsecs = struct.unpack_from('<H', d, pe + 6)[0]
opt = struct.unpack_from('<H', d, pe + 20)[0]
sec = pe + 24 + opt
sections = []
for i in range(nsecs):
    o = sec + i * 40
    name = d[o:o+8].rstrip(b'\0').decode('ascii', 'replace')
    va = struct.unpack_from('<I', d, o + 12)[0]
    rs = struct.unpack_from('<I', d, o + 16)[0]
    rp = struct.unpack_from('<I', d, o + 20)[0]
    sections.append((name, va, rs, rp))

def rva_to_fo(rva):
    for _, va, rs, rp in sections:
        if va <= rva < va + rs:
            return rp + (rva - va)
    return None

def in_text(rva):
    return any(n == '.text' and va <= rva < va + rs for n, va, rs, _ in sections)

def read_ascii(addr):
    if addr < 0 or addr >= len(d):
        return ''
    end = d.find(b'\0', addr, min(len(d), addr + 256))
    if end < 0:
        end = min(len(d), addr + 256)
    try:
        return d[addr:end].decode('ascii', 'replace')
    except Exception:
        return ''

md = Cs(CS_ARCH_X86, CS_MODE_64)
md.detail = True

def disasm(rva, size=256):
    fo = rva_to_fo(rva)
    if fo is None:
        return []
    return list(md.disasm(d[fo:fo+size], base+rva))

def fmt(rva, text):
    return f'0x{rva:X}: {text}'

def rel_target(insn):
    if insn.mnemonic != 'call' or not insn.bytes or insn.bytes[0] != 0xE8:
        return None
    rel = struct.unpack_from('<i', bytes(insn.bytes), 1)[0]
    return insn.address + insn.size + rel - base

name = b'GetCraftSpeedByWorkSuitability'
occ = []
start = 0
while True:
    i = d.find(name, start)
    if i < 0:
        break
    occ.append(i)
    start = i + 1

print(f'EXE_SIZE={len(d)}')
print(f'IMAGE_BASE=0x{base:X}')
print(f'GETCRAFT_NAME_OCCURRENCES={len(occ)}')

# Find text pointers in the image that reference the reflected name.
cands = {}
for i in occ:
    addr = i
    q = struct.pack('<Q', base + addr)
    pos = 0
    while True:
        p = d.find(q, pos)
        if p < 0:
            break
        rva = p
        fo_field = rva + 8
        if fo_field + 8 <= len(d):
            ptr = struct.unpack_from('<Q', d, fo_field)[0]
            fn_rva = ptr - base
            if 0 <= fn_rva < len(d) and in_text(fn_rva):
                cands.setdefault(fn_rva, 0)
                cands[fn_rva] += 1
        pos = p + 1

print('REFLECTION_FN_CANDIDATES:')
for rva, hits in sorted(cands.items(), key=lambda x: (-x[1], x[0])):
    print(f'  0x{rva:X} hits={hits}')
    for ins in disasm(rva, 384):
        rr = ins.address - base
        s = ins.op_str.lower()
        if ins.mnemonic == 'ret' or ins.mnemonic == 'call' or any(k in s for k in ('[rcx +', '[rdx +', '[rax +', '[r8 +')) or ins.mnemonic in {'cmp','test','mov','movzx','movsxd','lea','imul','add','sub','shl','shr','sar','idiv','cdq','cmovg','cmovge','cmovl','cmovle','jg','jge','jl','jle','ja','jb','je','jne'}:
            print(f'    {fmt(rr, ins.mnemonic + " " + ins.op_str)}')

# Reverse references: enumerate direct calls to each candidate and nearby instructions.
print('DIRECT_CALLERS:')
callers = {}
for cand in cands:
    target_abs = base + cand
    needle = struct.pack('<i', 0)  # placeholder to avoid endian helpers below
    for rva in range(0x1000, len(d) - 5):
        fo = rva_to_fo(rva)
        if fo is None or d[fo] != 0xE8:
            continue
        rel = struct.unpack_from('<i', d, fo + 1)[0]
        dest = (base + rva + 5 + rel) - base
        if dest == cand:
            callers.setdefault(rva, []).append(cand)

for rva, targets in sorted(callers.items()):
    print(f'  CALLER=0x{rva:X} -> {", ".join(f"0x{x:X}" for x in targets)}')
    fn = max(0x1000, rva - 96)
    for ins in disasm(fn, 224):
        rr = ins.address - base
        if rr > rva + 96:
            break
        if rr >= rva - 64:
            print(f'    {fmt(rr, ins.mnemonic + " " + ins.op_str)}')

# Search for likely CraftSpeed table consumers by looking for the reflected field name,
# then pointer-adjacent code and direct functions that reference the string's address.
for field in [b'CraftSpeeds', b'WorkSuitabilityDefineDataMap', b'WorkSuitabilityMaxRank']:
    occf = []
    p = 0
    while True:
        p = d.find(field, p)
        if p < 0:
            break
        occf.append(p)
        p += 1
    print(f'FIELD {field.decode()} OCCURRENCES={len(occf)}')
    for p in occf[:20]:
        print(f'  fileoff=0x{p:X} rva=0x{p:X}')

print('END_NATIVE_SPEED_ANALYSIS')
