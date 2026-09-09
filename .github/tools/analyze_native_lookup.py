import sys, struct
from pathlib import Path
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

def u16(d,o): return struct.unpack_from('<H',d,o)[0]
def u32(d,o): return struct.unpack_from('<I',d,o)[0]
def u64(d,o): return struct.unpack_from('<Q',d,o)[0]

def sections(d):
    pe=u32(d,0x3c); n=u16(d,pe+6); opt=u16(d,pe+20); so=pe+24+opt; out=[]
    for i in range(n):
        o=so+i*40
        out.append((d[o:o+8].rstrip(b'\0').decode('ascii','replace'),u32(d,o+12),u32(d,o+16),u32(d,o+20),u32(d,o+8),u32(d,o+36)))
    return out

def fo_to_rva(fo,ss):
    for n,va,rs,rp,vs,ch in ss:
        if rp<=fo<rp+rs:return va+(fo-rp)
    return None

def rva_to_fo(rva,ss):
    for n,va,rs,rp,vs,ch in ss:
        if va<=rva<va+rs:return rp+(rva-va)
    return None

def in_text(rva,ss): return any(n=='.text' and va<=rva<va+rs for n,va,rs,rp,vs,ch in ss)

def findall(d,p):
    s=0
    while True:
        i=d.find(p,s)
        if i<0:return
        yield i; s=i+1

def native_candidates(d,ss,base,names):
    seen=set(); candidates={}
    for name in names:
        for fo in findall(d,name):
            r=fo_to_rva(fo,ss)
            if r is None: continue
            ptr=struct.pack('<Q',base+r)
            for sec,va,rs,rp,vs,ch in ss:
                for pfo in findall(d[rp:rp+rs],ptr):
                    at=rp+pfo
                    for q in (at-8,at):
                        if q<0 or q+16>len(d): continue
                        a=u64(d,q); b=u64(d,q+8)
                        ar=a-base if a>=base else -1; br=b-base if b>=base else -1
                        native=None; pair=None; reversed_pair=False
                        if ar==r and in_text(br,ss): native=br; pair=q
                        elif br==r and in_text(ar,ss): native=ar; pair=q; reversed_pair=True
                        if native is None: continue
                        key=(name,native,pair)
                        if key in seen: continue
                        seen.add(key); candidates.setdefault(name.decode(),[]).append(native)
                        tag=' reversed' if reversed_pair else ''
                        print(f'{name.decode()} string_rva=0x{r:X} pair_rva=0x{fo_to_rva(pair,ss):X} native_rva=0x{native:X}{tag}')
    return candidates

def disasm_function(d,ss,base,rva,limit=2048):
    fo=rva_to_fo(rva,ss)
    if fo is None: return
    md=Cs(CS_ARCH_X86,CS_MODE_64); md.detail=True
    ins=list(md.disasm(d[fo:fo+limit],base+rva))
    print(f'FOCUS_FUNCTION RVA=0x{rva:X} FILE=0x{fo:X}')
    for i in ins:
        rel=i.address-(base+rva)
        op=i.op_str.lower()
        text=f'+0x{rel:03X}: {i.mnemonic} {i.op_str}'.rstrip()
        if i.mnemonic in ('cmp','mov','lea','add','sub','imul','idiv','div','test','and','or','xor','shl','shr','sar','call','jmp','je','jne','jg','jge','jl','jle','ja','jae','jb','jbe','seta','setae','setb','setbe','sete','setne','cmovg','cmovge','cmovl','cmovle','cmova','cmovae','cmovb','cmovbe','cmove','cmovne','ret') or '0xa' in op:
            print('  '+text)
    for i in ins:
        if '0xa' not in i.op_str.lower(): continue
        rel=i.address-(base+rva)
        start=max(0,rel-24); end=min(len(d)-fo,rel+40)
        b=d[fo+start:fo+end]
        print('  IMM10_BYTES +0x%03X: %s' % (rel,b.hex(' ')))
    print('END_FOCUS_FUNCTION')

def main():
    d=Path(sys.argv[1]).read_bytes(); ss=sections(d); pe=u32(d,0x3c); base=struct.unpack_from('<Q',d,pe+24+24)[0]
    names=[b'GetCraftSpeedByWorkSuitability',b'CanUseTargetWorkSuitabilityRankUp',b'WorkSuitabilityMaxRank',b'GetWorkSuitabilityRank',b'GetWorkSuitabilityRankWithCharacterRank',b'HasWorkSuitabilityRank',b'GetCraftSpeed_WorkSuitability']
    md=Cs(CS_ARCH_X86,CS_MODE_64); md.detail=True
    print('NATIVE_LOOKUP_EXACT:')
    candidates=native_candidates(d,ss,base,names)
    print('NATIVE_FUNCTION_DISASM:')
    all_native=sorted({r for vals in candidates.values() for r in vals})
    for r in all_native:
        fo=rva_to_fo(r,ss)
        if fo is None: continue
        ins=list(md.disasm(d[fo:fo+256],base+r))
        print(f'FUNCTION RVA=0x{r:X} FILE=0x{fo:X}')
        for i in ins[:32]: print(f'  +0x{i.address-(base+r):03X}: {i.mnemonic} {i.op_str}')
        for i in ins[:96]:
            if '0xa' in i.op_str.lower() or '0x64' in i.op_str.lower(): print(f'  HIT +0x{i.address-(base+r):03X}: {i.mnemonic} {i.op_str}')
    print('FOCUSED_CURRENT_WORKSUITABILITY:')
    focus=[0x2BB12C0,0x2BB6850,0x2B75390,0x2B740A0,0x28DE8E0,0x295CF70,0x295D190,0x295D1C0,0x29621E0,0x2962250,0x2962290]
    for r in focus: disasm_function(d,ss,base,r)
    print('SPEED_TARGETS:')
    speed_focus=[r for r in all_native if r in candidates.get('GetCraftSpeedByWorkSuitability',[]) or r in candidates.get('GetCraftSpeed_WorkSuitability',[])]
    for r in sorted(set(speed_focus)): disasm_function(d,ss,base,r,4096)
    print('END_NATIVE_ANALYSIS')

if __name__=='__main__': main()
