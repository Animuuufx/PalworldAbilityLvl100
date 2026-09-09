import sys, struct
from pathlib import Path
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

def u16(d,o): return struct.unpack_from('<H',d,o)[0]
def u32(d,o): return struct.unpack_from('<I',d,o)[0]
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
def hx(b): return ' '.join(f'{x:02X}' for x in b)
def fo_to_rva(fo,secs):
    for n,va,rs,rp,vs,ch in secs:
        if rp<=fo<rp+rs:return va+(fo-rp)
    return None

def main():
    if len(sys.argv)!=2: raise SystemExit('usage: analyze_palworld.py Palworld-Win64-Shipping.exe')
    d=Path(sys.argv[1]).read_bytes(); pe,secs=parse_sections(d); base=image_base(d,pe)
    print(f'FILE_SIZE={len(d)}'); print(f'IMAGE_BASE=0x{base:X}')
    for s in secs: print(f'SECTION {s[0]} RVA=0x{s[1]:X} RAW=0x{s[3]:X} RSZ=0x{s[2]:X}')
    exe=[s for s in secs if s[5]&0x20000000]
    old={'MAP_ORIGINAL':'44 8B 88 54 0F 00 00','SCALAR_ORIGINAL':'8B 88 54 0F 00 00','HANDBOOK_ELIG_ORIGINAL':'3B B8 54 0F 00 00','HANDBOOK_USE_ORIGINAL':'39 83 54 0F 00 00 0F 8C 80 00 00 00','SPEED_PROLOGUE':'48 89 5C 24 18 48 89 74 24 20 55 57 41 54'}
    print('OLD_SIGNATURES:')
    for n,h in old.items():
        hs=[]; p=bytes.fromhex(h)
        for sn,va,rs,rp,vs,ch in exe:
            for off in findall(d[rp:rp+rs],p): hs.append(va+off)
        print(f'  {n}: '+(', '.join(f'0x{x:X}' for x in hs[:64]) or 'NOT_FOUND'))
    md=Cs(CS_ARCH_X86,CS_MODE_64); md.detail=True
    targets=[b'GetCraftSpeedByWorkSuitability',b'CanUseTargetWorkSuitabilityRankUp']
    target_rvas=[]
    print('TARGET_STRINGS:')
    for t in targets:
        hs=list(findall(d,t))
        print(f'  {t.decode()}: '+(', '.join(f'FILE=0x{x:X} RVA=0x{fo_to_rva(x,secs):X}' for x in hs[:32]) if hs else 'NOT_FOUND'))
        for x in hs: 
            r=fo_to_rva(x,secs)
            if r is not None: target_rvas.append(r)
        wt=t.decode().encode('utf-16le'); hs2=list(findall(d,wt))
        print(f'  UTF16 {t.decode()}: '+(', '.join(f'FILE=0x{x:X} RVA=0x{fo_to_rva(x,secs):X}' for x in hs2[:32]) if hs2 else 'NOT_FOUND'))
        for x in hs2:
            r=fo_to_rva(x,secs)
            if r is not None: target_rvas.append(r)
    target_rvas=set(target_rvas)
    print('TARGET_STRING_XREFS:')
    refs=[]
    for sn,va,rs,rp,vs,ch in exe:
        for ins in md.disasm(d[rp:rp+rs],base+va):
            for operand in ins.operands:
                if operand.type==3 and operand.mem.base==41:
                    target=ins.address+ins.size+operand.mem.disp-base
                    if target in target_rvas:
                        refs.append((ins.address-base,target)); print(f'  RVA=0x{ins.address-base:X} {ins.mnemonic} {ins.op_str} -> RVA=0x{target:X}')
    print('XREF_NEIGHBORHOODS:')
    seen=set()
    for rva,_ in refs:
        start=max(0x1000,rva-0x100)
        if start in seen: continue
        seen.add(start)
        for sn,va,rs,rp,vs,ch in exe:
            if va<=start<va+rs:
                off=rp+(start-va); print(f'  START_RVA=0x{start:X} {sn}: {hx(d[off:off+384])}'); break
    print('RANK_10_PATTERNS:')
    pats=[bytes.fromhex(x) for x in ['83 F8 0A','83 F9 0A','83 FA 0A','83 FB 0A','83 FF 0A','41 83 F8 0A','41 83 F9 0A','41 83 FA 0A','B8 0A 00 00 00','B9 0A 00 00 00','BA 0A 00 00 00','BF 0A 00 00 00']]
    for p in pats:
        hs=[]
        for sn,va,rs,rp,vs,ch in exe:
            for off in findall(d[rp:rp+rs],p): hs.append((va+off,sn))
        print(f'  {hx(p)}: '+(', '.join(f'0x{x:X}({s})' for x,s in hs[:160]) or 'NOT_FOUND'))
if __name__=='__main__': main()
