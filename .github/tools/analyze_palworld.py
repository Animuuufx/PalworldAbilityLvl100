import sys, struct
from pathlib import Path
from capstone import Cs, CS_ARCH_X86, CS_MODE_64, x86_const

def u16(d,o): return struct.unpack_from('<H',d,o)[0]
def u32(d,o): return struct.unpack_from('<I',d,o)[0]
def u64(d,o): return struct.unpack_from('<Q',d,o)[0]
def parse_sections(d):
    pe=u32(d,0x3c); assert d[pe:pe+4]==b'PE\0\0'
    c=pe+4; n=u16(d,c+2); os=u16(d,c+16); so=c+20+os; out=[]
    for i in range(n):
        o=so+i*40; out.append((d[o:o+8].rstrip(b'\0').decode('ascii','replace'),u32(d,o+12),u32(d,o+16),u32(d,o+20),u32(d,o+8),u32(d,o+36)))
    return pe,out

def image_base(d,pe):
    o=pe+24; assert u16(d,o)==0x20b; return struct.unpack_from('<Q',d,o+24)[0]
def findall(d,p):
    s=0
    while True:
        i=d.find(p,s)
        if i<0:return
        yield i; s=i+1
def fo_to_rva(fo,secs):
    for n,va,rs,rp,vs,ch in secs:
        if rp<=fo<rp+rs:return va+(fo-rp)
    return None
def rva_to_file(rva,secs):
    for n,va,rs,rp,vs,ch in secs:
        if va<=rva<va+rs:return rp+(rva-va)
    return None
def hx(b): return ' '.join(f'{x:02X}' for x in b)

def refs_to_rva(d,secs,base,target_rva,only_text=False):
    md=Cs(CS_ARCH_X86,CS_MODE_64); md.detail=True; out=[]
    wanted=[s for s in secs if (not only_text or (s[5]&0x20000000))]
    for sn,va,rs,rp,vs,ch in wanted:
        for ins in md.disasm(d[rp:rp+rs],base+va):
            for op in ins.operands:
                if op.type==3 and op.mem.base==x86_const.X86_REG_RIP:
                    target=ins.address+ins.size+op.mem.disp-base
                    if target==target_rva: out.append((ins.address-base,ins.mnemonic,ins.op_str))
    return out

def pointer_xrefs(d,secs,base,target_rva):
    p=struct.pack('<Q',base+target_rva); out=[]
    for sn,va,rs,rp,vs,ch in secs:
        for off in findall(d[rp:rp+rs],p): out.append((va+off,sn))
    return out

def text_rva(rva,secs):
    for n,va,rs,rp,vs,ch in secs:
        if n=='.text' and va<=rva<va+rs:return True
    return False

def metadata_pointer_candidates(d,secs,base,ptr_rva,window=0x180):
    fo=rva_to_file(ptr_rva,secs)
    if fo is None:return []
    lo=max(0,fo-window); hi=min(len(d),fo+window)
    out=[]
    for off in range(lo,hi-7,8):
        v=u64(d,off)
        if v<base: continue
        r=v-base
        if text_rva(r,secs): out.append((fo_to_rva(off,secs),r))
    return out

def nearby_bytes(d,secs,rva,n=192):
    fo=rva_to_file(rva,secs)
    return hx(d[max(0,fo-n):min(len(d),fo+n)]) if fo is not None else ''

def main():
    if len(sys.argv)!=2: raise SystemExit('usage: analyze_palworld.py Palworld-Win64-Shipping.exe')
    d=Path(sys.argv[1]).read_bytes(); pe,secs=parse_sections(d); base=image_base(d,pe)
    print(f'FILE_SIZE={len(d)}'); print(f'IMAGE_BASE=0x{base:X}')
    for s in secs: print(f'SECTION {s[0]} RVA=0x{s[1]:X} RAW=0x{s[3]:X} RSZ=0x{s[2]:X}')
    print('TARGETS:')
    names=[b'GetCraftSpeedByWorkSuitability',b'CanUseTargetWorkSuitabilityRankUp',b'WorkSuitabilityMaxRank',b'GetWorkSuitabilityRank',b'GetWorkSuitabilityRankWithCharacterRank',b'HasWorkSuitabilityRank',b'GetCraftSpeed_WorkSuitability']
    target_rvas=[]
    for name in names:
        hits=list(findall(d,name)); rvas=[]
        for fo in hits:
            r=fo_to_rva(fo,secs)
            if r is not None:rvas.append(r)
        print(f'  {name.decode()}: '+(', '.join(f'FILE=0x{fo:X}/RVA=0x{fo_to_rva(fo,secs):X}' for fo in hits[:32]) or 'NOT_FOUND'))
        for r in rvas[:32]: target_rvas.append((name.decode(),r))
    print('STRING_XREFS_ALL_SECTIONS:')
    for name,r in target_rvas:
        refs=refs_to_rva(d,secs,base,r,False)
        if refs: print(f'  {name} RVA=0x{r:X}: '+', '.join(f'0x{x:X} {m} {o}' for x,m,o in refs[:64]))
    print('STRING_XREFS_TEXT_ONLY:')
    for name,r in target_rvas:
        refs=refs_to_rva(d,secs,base,r,True)
        if refs:
            print(f'  {name} RVA=0x{r:X}: '+', '.join(f'0x{x:X} {m} {o}' for x,m,o in refs[:64]))
            for x,m,o in refs[:16]: print(f'    NEAR 0x{x:X}: {nearby_bytes(d,secs,x)}')
    print('STRING_POINTER_XREFS:')
    for name,r in target_rvas:
        hits=pointer_xrefs(d,secs,base,r)
        if hits: print(f'  {name} RVA=0x{r:X}: '+', '.join(f'0x{x:X}({s})' for x,s in hits[:128]))
    print('METADATA_NATIVE_POINTER_CANDIDATES:')
    seen=set()
    for name,r in target_rvas:
        for ptr_rva,sec in pointer_xrefs(d,secs,base,r):
            for at,fn in metadata_pointer_candidates(d,secs,base,ptr_rva):
                key=(name,ptr_rva,at,fn)
                if key in seen: continue
                seen.add(key)
                print(f'  {name} nameptr=0x{ptr_rva:X} candidate_ptr=0x{at:X} native=0x{fn:X}')
    print('RANK_IMMEDIATE_CONTEXT:')
    pats=[b'\x83\xF8\x0A',b'\x83\xF9\x0A',b'\x83\xFA\x0A',b'\x83\xFB\x0A',b'\x83\xFF\x0A',b'\x41\x83\xF8\x0A',b'\x41\x83\xF9\x0A',b'\x41\x83\xFA\x0A']
    for p in pats:
        hits=[]
        for sn,va,rs,rp,vs,ch in secs:
            if not (ch&0x20): continue
            for off in findall(d[rp:rp+rs],p): hits.append(va+off)
        print(f'  {hx(p)}: '+', '.join(f'0x{x:X}' for x in hits[:80]))
        for x in hits[:12]: print(f'    NEAR 0x{x:X}: {nearby_bytes(d,secs,x,96)}')
    print('RANK_100_IMMEDIATE_CONTEXT:')
    pats=[b'\x83\xF8\x64',b'\x83\xF9\x64',b'\x83\xFA\x64',b'\x83\xFB\x64',b'\x83\xFF\x64',b'\xB8\x64\x00\x00\x00',b'\xB9\x64\x00\x00\x00',b'\xBA\x64\x00\x00\x00',b'\xBF\x64\x00\x00\x00']
    for p in pats:
        hits=[]
        for sn,va,rs,rp,vs,ch in secs:
            if not (ch&0x20): continue
            for off in findall(d[rp:rp+rs],p): hits.append(va+off)
        if hits:
            print(f'  {hx(p)}: '+', '.join(f'0x{x:X}' for x in hits[:80]))
            for x in hits[:12]: print(f'    NEAR 0x{x:X}: {nearby_bytes(d,secs,x,96)}')

if __name__=='__main__': main()
