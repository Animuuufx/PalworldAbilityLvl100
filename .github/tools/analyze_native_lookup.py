import sys, struct
from pathlib import Path
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

def u16(d,o): return struct.unpack_from('<H',d,o)[0]
def u32(d,o): return struct.unpack_from('<I',d,o)[0]
def u64(d,o): return struct.unpack_from('<Q',d,o)[0]

def sections(d):
    pe=u32(d,0x3c); n=u16(d,pe+6); opt=u16(d,pe+20); so=pe+24+opt; out=[]
    for i in range(n):
        o=so+i*40; out.append((d[o:o+8].rstrip(b'\0').decode('ascii','replace'),u32(d,o+12),u32(d,o+16),u32(d,o+20),u32(d,o+8),u32(d,o+36)))
    return out

def fo_to_rva(fo,ss):
    for n,va,rs,rp,vs,ch in ss:
        if rp<=fo<rp+rs:return va+(fo-rp)

def rva_to_fo(rva,ss):
    for n,va,rs,rp,vs,ch in ss:
        if va<=rva<va+rs:return rp+(rva-va)

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
    print('NATIVE_LOOKUP_PAIRS:')
    seen=set()
    for name in names:
        for fo in findall(d,name):
            r=fo_to_rva(fo,ss)
            if r is None: continue
            ptr=struct.pack('<Q',base+r)
            for sec,va,rs,rp,vs,ch in ss:
                for pfo in findall(d[rp:rp+rs],ptr):
                    at=rp+pfo
                    # Check +/- 0x80 around each pointer xref for pairs where one qword
                    # equals the target string address and the neighboring qword is .text.
                    lo=max(0,at-0x100); hi=min(len(d)-16,at+0x100)
                    for q in range(lo,hi+1,8):
                        a=u64(d,q); b=u64(d,q+8)
                        ar=a-base if a>=base else -1; br=b-base if b>=base else -1
                        if ar==r and in_text(br,ss):
                            key=(name,fo_to_rva(q,ss),br)
                            if key not in seen:
                                seen.add(key); print(f'{name.decode()} string_rva=0x{r:X} pair_rva=0x{fo_to_rva(q,ss):X} native_rva=0x{br:X}')
                        if br==r and in_text(ar,ss):
                            key=(name,fo_to_rva(q,ss),ar)
                            if key not in seen:
                                seen.add(key); print(f'{name.decode()} string_rva=0x{r:X} pair_rva=0x{fo_to_rva(q,ss):X} native_rva=0x{ar:X} reversed')
    print('NATIVE_PROLOGUES:')
    md=Cs(CS_ARCH_X86,CS_MODE_64)
    # Disassemble every discovered native candidate again from the pair output is awkward;
    # repeat the scan and print first 8 instructions for each unique candidate.
    candidates=set()
    for name in names:
        for fo in findall(d,name):
            r=fo_to_rva(fo,ss)
            if r is None: continue
            ptr=struct.pack('<Q',base+r)
            for sec,va,rs,rp,vs,ch in ss:
                for pfo in findall(d[rp:rp+rs],ptr):
                    at=rp+pfo; lo=max(0,at-0x100); hi=min(len(d)-16,at+0x100)
                    for q in range(lo,hi+1,8):
                        a=u64(d,q); b=u64(d,q+8)
                        ar=a-base if a>=base else -1; br=b-base if b>=base else -1
                        if ar==r and in_text(br,ss): candidates.add(br)
                        if br==r and in_text(ar,ss): candidates.add(ar)
    for r in sorted(candidates):
        fo=rva_to_fo(r,ss); code=d[fo:fo+32]
        ins=list(md.disasm(code,base+r))
        text=' | '.join(f'{i.mnemonic} {i.op_str}' for i in ins[:6])
        print(f'  RVA=0x{r:X}: {text}')

if __name__=='__main__': main()
