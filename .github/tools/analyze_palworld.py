import sys
import struct
from pathlib import Path
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

def u16(data, off): return struct.unpack_from('<H', data, off)[0]
def u32(data, off): return struct.unpack_from('<I', data, off)[0]
def parse_sections(data):
    pe=u32(data,0x3C)
    if data[pe:pe+4]!=b'PE\x00\x00': raise ValueError('Invalid PE')
    coff=pe+4; sections=u16(data,coff+2); opt_size=u16(data,coff+16); sec_off=coff+20+opt_size; out=[]
    for i in range(sections):
        off=sec_off+i*40; name=data[off:off+8].rstrip(b'\x00').decode('ascii','replace'); vs=u32(data,off+8); va=u32(data,off+12); rs=u32(data,off+16); rp=u32(data,off+20); ch=u32(data,off+36); out.append((name,va,vs,rp,rs,ch))
    return pe,out

def image_base(data,pe):
    opt=pe+24
    if u16(data,opt)!=0x20B: raise ValueError('Expected PE32+')
    return struct.unpack_from('<Q',data,opt+24)[0]

def find_all(buf,pat):
    start=0
    while True:
        i=buf.find(pat,start)
        if i<0: return
        yield i; start=i+1

def fmt_bytes(data): return ' '.join(f'{b:02X}' for b in data)
def in_window(rva,center,radius): return center-radius<=rva<=center+radius

def main():
    if len(sys.argv)!=2: raise SystemExit('usage: analyze_palworld.py Palworld-Win64-Shipping.exe')
    data=Path(sys.argv[1]).read_bytes(); pe,sections=parse_sections(data); base=image_base(data,pe)
    print(f'FILE_SIZE={len(data)}'); print(f'IMAGE_BASE=0x{base:X}'); print('SECTIONS:')
    for name,va,vs,rp,rs,ch in sections: print(f'  {name:8} RVA=0x{va:X} VSZ=0x{vs:X} RAW=0x{rp:X} RSZ=0x{rs:X} CH=0x{ch:X}')
    exec_sections=[s for s in sections if s[5]&0x20000000]
    patterns={'MAP_ORIGINAL':bytes.fromhex('44 8B 88 54 0F 00 00'),'SCALAR_ORIGINAL':bytes.fromhex('8B 88 54 0F 00 00'),'HANDBOOK_ELIG_ORIGINAL':bytes.fromhex('3B B8 54 0F 00 00'),'HANDBOOK_USE_ORIGINAL':bytes.fromhex('39 83 54 0F 00 00 0F 8C 80 00 00 00'),'SPEED_PROLOGUE':bytes.fromhex('48 89 5C 24 18 48 89 74 24 20 55 57 41 54'),'MAP_PATCH':bytes.fromhex('41 B9 64 00 00 00 90'),'SCALAR_PATCH':bytes.fromhex('B9 64 00 00 00 90'),'HANDBOOK_ELIG_PATCH':bytes.fromhex('83 FF 64 90 90 90'),'HANDBOOK_USE_PATCH':bytes.fromhex('83 F8 64 90 90 90 0F 8F 80 00 00 00')}
    print('EXACT_PATTERN_SEARCH:')
    for name,pat in patterns.items():
        hits=[]
        for sec_name,va,vs,rp,rs,ch in exec_sections:
            for off in find_all(data[rp:rp+rs],pat): hits.append((va+off,sec_name))
        print(f'  {name}: '+(', '.join(f'RVA=0x{rva:X} ({sec})' for rva,sec in hits[:64]) if hits else 'NOT_FOUND'))
    md=Cs(CS_ARCH_X86,CS_MODE_64); md.detail=True; centers=[0x02E6F3CA,0x02F7481A,0x032B26D3,0x02F7C21C,0x02F11560]; radius=0x120000
    print('NEW_BUILD_IMMEDIATE_10_CANDIDATES:'); total=0; seen=set()
    for sec_name,va,vs,rp,rs,ch in exec_sections:
        sec=data[rp:rp+rs]
        for insn in md.disasm(sec,base+va):
            rva=insn.address-base
            if not any(in_window(rva,c,radius) for c in centers): continue
            if insn.mnemonic.lower() not in ('cmp','mov','movzx','movsxd','sub','add','lea'): continue
            op=insn.op_str.lower().replace('0ah','0xa')
            if '0xa' not in op and ', 10' not in op and '10,' not in op: continue
            key=(rva,bytes(insn.bytes))
            if key in seen: continue
            seen.add(key); total+=1
            if total<=600: print(f'  RVA=0x{rva:X} {sec_name} {insn.mnemonic} {insn.op_str} BYTES={fmt_bytes(insn.bytes)}')
    print(f'  TOTAL_CANDIDATES={total}')
    print('PROLOGUE_NEIGHBORHOODS:')
    for sec_name,va,vs,rp,rs,ch in exec_sections:
        sec=data[rp:rp+rs]
        for off in find_all(sec,bytes.fromhex('48 89 5C 24 18')):
            rva=va+off
            if any(in_window(rva,c,radius) for c in centers): print(f'  RVA=0x{rva:X} {sec_name}: {fmt_bytes(sec[off:off+96])}')
    print('STRING_HINTS:')
    for term in [b'GetCraftSpeedByWorkSuitability',b'CanUseTargetWorkSuitabilityRankUp',b'WorkSuitability','GetCraftSpeedByWorkSuitability'.encode('utf-16le'),'CanUseTargetWorkSuitabilityRankUp'.encode('utf-16le')]:
        hits=list(find_all(data,term)); print(f'  {term!r}: '+(', '.join(f'FILE=0x{x:X}' for x in hits[:32]) if hits else 'NOT_FOUND'))

if __name__=='__main__': main()
