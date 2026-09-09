import sys, struct
from pathlib import Path
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

# Speed-path analysis for the current Palworld executable.
# Triggered by repository changes so CI can refresh speed_analysis.txt.
EXE = Path(sys.argv[1])
d = EXE.read_bytes()

def u16(o): return struct.unpack_from('<H', d, o)[0]
def u32(o): return struct.unpack_from('<I', d, o)[0]
def u64(o): return struct.unpack_from('<Q', d, o)[0]

def sections():
    pe = u32(0x3c); n = u16(pe + 6); opt = u16(pe + 20); so = pe + 24 + opt
    out=[]
    for i in range(n):
        o = so + i*40
        name = d[o:o+8].rstrip(b'\0').decode('ascii','replace')
        out.append((name, u32(o+12), u32(o+16), u32(o+20)))
    return out

ss = sections()
pe = u32(0x3c)
base = struct.unpack_from('<Q', d, pe + 24 + 24)[0]

def rva_to_fo(rva):
    for n,va,rs,rp in ss:
        if va <= rva < va + rs:
            return rp + (rva-va)
    return None

def fo_to_rva(fo):
    for n,va,rs,rp in ss:
        if rp <= fo < rp + rs:
            return va + (fo-rp)
    return None

def findall(pat):
    s=0
    while True:
        i=d.find(pat,s)
        if i < 0: return
        yield i; s=i+1

def in_text(rva):
    return any(n=='.text' and va <= rva < va+rs for n,va,rs,rp in ss)

def metadata_candidates(name):
    out=[]; seen=set()
    for fo in findall(name):
        r=fo_to_rva(fo)
        if r is None: continue
        ptr=struct.pack('<Q',base+r)
        for sec,va,rs,rp in ss:
            for pfo in findall_in_range(ptr,rp,rp+rs):
                q=pfo-8
                if q < 0: continue
                for q in (q,pfo):
                    if q+16>len(d): continue
                    a=u64(q); b=u64(q+8)
                    if a==base+r and in_text(b-base): native=b-base
                    elif b==base+r and in_text(a-base): native=a-base
                    else: continue
                    key=(native,q)
                    if key not in seen:
                        seen.add(key); out.append(native)
    return sorted(set(out))

def findall_in_range(pat, start, end):
    off=start
    while off < end:
        i=d.find(pat,off,end)
        if i < 0: return
        yield i; off=i+1

def disasm(rva, limit=1024):
    fo=rva_to_fo(rva)
    if fo is None: return []
    md=Cs(CS_ARCH_X86,CS_MODE_64); md.detail=True
    return list(md.disasm(d[fo:fo+limit], base+rva))

def fmt(ins):
    return f'+0x{ins.address-(base+cur):04X}: {ins.mnemonic} {ins.op_str}'.rstrip()

name=b'GetCraftSpeedByWorkSuitability'
cands=metadata_candidates(name)
print(f'FILE_SIZE={len(d)} IMAGE_BASE=0x{base:X}')
print('SPEED_NATIVE_CANDIDATES:')
for r in cands: print(f'  0x{r:X}')

focus=set(cands)|{0x295F2C0,0x295D460,0x295D490,0x295D4C0,0x29619B0,0x2961A30,0x2961BA0,0x2961C40,0x2961C70,0x2961C90,0x2961E10,0x2961EA0,0x2961EC0,0x2961EE0,0x2961FD0,0x2962090,0x29620C0,0x29620F0,0x2962120,0x2962150,0x2962180,0x29621B0,0x29621E0,0x2962250,0x2962290,0x29622C0,0x2962350,0x29623E0,0x2962410,0x2962440,0x29624D0,0x2962580}

md=Cs(CS_ARCH_X86,CS_MODE_64); md.detail=True
for cur in sorted(focus):
    ins=disasm(cur,1536)
    if not ins: continue
    relevant=[]
    for i in ins:
        op=i.op_str.lower(); m=i.mnemonic.lower()
        if m in {'cmp','test','mov','movss','movsd','add','addss','addsd','sub','subss','subsd','mul','imul','mulss','mulsd','div','idiv','divss','divsd','lea','call','jmp','je','jne','jg','jge','jl','jle','ja','jae','jb','jbe','cmovg','cmovge','cmovl','cmovle','cmova','cmovae','cmovb','cmovbe','seta','setae','setb','setbe','sete','setne','cvtsi2ss','cvttss2si','cvtss2sd','cvtsd2ss','roundss','maxss','minss','ret'} or '0xa' in op:
            relevant.append(i)
    if not relevant: continue
    print(f'\nFUNCTION RVA=0x{cur:X} FILE=0x{rva_to_fo(cur):X}')
    for i in relevant[:180]: print('  '+fmt(i))
    for i in relevant:
        op=i.op_str.lower()
        if '0xa' in op:
            rel=i.address-(base+cur); fo=rva_to_fo(cur)+rel
            a=max(0,fo-32); b=min(len(d),fo+64)
            print(f'  IMM10_BYTES +0x{rel:03X}: {d[a:b].hex(" ")}')
print('\nEND_SPEED_ANALYSIS')
