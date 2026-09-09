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

def in_text(rva,ss):
    return any(n=='.text' and va<=rva<va+rs for n,va,rs,rp,vs,ch in ss)

def findall(d,p):
    s=0
    while True:
        i=d.find(p,s)
        if i<0:return
        yield i; s=i+1

def main():
    d=Path(sys.argv[1]).read_bytes(); ss=sections(d); pe=u32(d,0x3c); base=struct.unpack_from('<Q',d,pe+24+24)[0]
    names=[b'GetCraftSpeedByWorkSuitability',b'CanUseTargetWorkSuitabilityRankUp',b'WorkSuitabilityMaxRank',b'GetWorkSuitabilityRank',b'GetWorkSuitabilityRankWithCharacterRank',b'HasWorkSuitabilityRank',b'GetCraftSpeed_WorkSuitability']
    md=Cs(CS_ARCH_X86,CS_MODE_64)
    md.detail=True
    print('NATIVE_LOOKUP_EXACT:')
    seen=set()
    candidates={}
    for name in names:
        for fo in findall(d,name):
            r=fo_to_rva(fo,ss)
            if r is None: continue
            ptr=struct.pack('<Q',base+r)
            for sec,va,rs,rp,vs,ch in ss:
                for pfo in findall(d[rp:rp+rs],ptr):
                    at=rp+pfo
                    # UE native lookup entries are expected to be {NamePtr, FunctionPtr}.
                    # Accept only the immediate +8 or -8 neighbor, rather than a broad window.
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
                        seen.add(key); candidates[native]=True
                        tag=' reversed' if reversed_pair else ''
                        print(f'{name.decode()} string_rva=0x{r:X} pair_rva=0x{fo_to_rva(pair,ss):X} native_rva=0x{native:X}{tag}')
    print('NATIVE_FUNCTION_DISASM:')
    for r in sorted(candidates):
        fo=rva_to_fo(r,ss)
        if fo is None: continue
        code=d[fo:fo+192]
        ins=list(md.disasm(code,base+r))
        print(f'FUNCTION RVA=0x{r:X} FILE=0x{fo:X}')
        for i in ins[:24]:
            print(f'  +0x{i.address-(base+r):03X}: {i.mnemonic} {i.op_str}')
        # Highlight instructions using immediate 10 or 100 and direct returns/jumps.
        hits=[]
        for i in ins[:64]:
            if i.mnemonic in ('cmp','mov','lea','add','sub','test','and','or','call','jmp','je','jne','jg','jge','jl','jle','ja','jae','jb','jbe','ret'):
                if '0xa' in i.op_str.lower() or '0x64' in i.op_str.lower() or i.mnemonic=='ret': hits.append(f'+0x{i.address-(base+r):03X}: {i.mnemonic} {i.op_str}')
        for h in hits: print('  HIT '+h)
    print('END_NATIVE_ANALYSIS')

if __name__=='__main__': main()
