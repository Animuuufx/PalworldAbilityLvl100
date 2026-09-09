import struct, sys
from pathlib import Path
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

EXE = Path(sys.argv[1])
d = EXE.read_bytes()
pe = struct.unpack_from('<I', d, 0x3C)[0]
base = struct.unpack_from('<Q', d, pe + 24 + 24)[0]
n = struct.unpack_from('<H', d, pe + 6)[0]
opt = struct.unpack_from('<H', d, pe + 20)[0]
sec = pe + 24 + opt
sections=[]
for i in range(n):
    o=sec+i*40
    name=d[o:o+8].rstrip(b'\0').decode('ascii','replace')
    sections.append((name,struct.unpack_from('<I',d,o+12)[0],struct.unpack_from('<I',d,o+16)[0],struct.unpack_from('<I',d,o+20)[0]))

def rva_to_fo(rva):
    for _,va,rs,rp in sections:
        if va <= rva < va+rs: return rp+(rva-va)
    return None

def in_text(rva):
    return any(name=='.text' and va<=rva<va+rs for name,va,rs,rp in sections)

md=Cs(CS_ARCH_X86,CS_MODE_64); md.detail=True

def insns(rva,limit=1024):
    fo=rva_to_fo(rva)
    if fo is None:return []
    return list(md.disasm(d[fo:fo+limit],base+rva))

def target_from_call(i):
    if i.mnemonic!='call' or not i.bytes or i.bytes[0]!=0xE8:return None
    rel=struct.unpack_from('<i',bytes(i.bytes),1)[0]
    t=i.address+5+rel-base
    return t if in_text(t) else None

seeds=[0x295B4D0,0x295B500,0x29622C0,0x2962350]
seen=set()
print(f'EXE_SHA_TARGET_SIZE={len(d)} IMAGE_BASE=0x{base:X}')
print('SEED_ANALYSIS:')
for rva in seeds:
    print(f'\nSEED RVA=0x{rva:X}')
    ii=insns(rva,1024)
    for i in ii:
        if i.mnemonic=='call': print(f'  +0x{i.address-(base+rva):03X}: call {i.op_str}')
        if i.mnemonic in {'cmp','mov','movsxd','movzx','lea','imul','add','sub','test','ret','jmp','je','jne','jg','jge','jl','jle','ja','jae','jb','jbe','cmovg','cmovge','cmovl','cmovle'}:
            if any(x in i.op_str.lower() for x in ['[rcx +','[rdx +','[r8 +','[rax +','0xa']) or i.mnemonic in {'ret','cmp','test','call'}:
                print(f'  +0x{i.address-(base+rva):03X}: {i.mnemonic} {i.op_str}')
        t=target_from_call(i)
        if t is not None: seen.add(t)

print('\nCALLED_TARGETS:')
for rva in sorted(seen): print(f'  0x{rva:X}')

print('\nCALLED_TARGET_DETAILS:')
for rva in sorted(seen):
    ii=insns(rva,512)
    if not ii: continue
    print(f'\nTARGET RVA=0x{rva:X}')
    for i in ii:
        s=i.op_str.lower()
        if i.mnemonic in {'cmp','test','mov','movsxd','movzx','lea','imul','add','sub','call','ret','jmp','je','jne','jg','jge','jl','jle','ja','jae','jb','jbe','cmovg','cmovge','cmovl','cmovle'} or '0xa' in s or '[rcx +' in s or '[rdx +' in s or '[r8 +' in s:
            print(f'  +0x{i.address-(base+rva):03X}: {i.mnemonic} {i.op_str}')
print('\nEND_SPEED_TARGET_ANALYSIS')
