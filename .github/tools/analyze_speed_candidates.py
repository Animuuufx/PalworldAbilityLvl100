import sys, struct
from pathlib import Path
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

def u16(d,o): return struct.unpack_from('<H',d,o)[0]
def u32(d,o): return struct.unpack_from('<I',d,o)[0]
def u64(d,o): return struct.unpack_from('<Q',d,o)[0]
def sections(d):
    pe=u32(d,0x3c); n=u16(d,pe+6); opt=u16(d,pe+20); so=pe+24+opt; out=[]
    for i in range(n):
        o=so+i*40; out.append((d[o:o+8].rstrip(b'\0').decode('ascii','replace'),u32(d,o+12),u32(d,o+16),u32(d,o+20)))
    return out
def fo_to_rva(fo,ss):
    for n,va,rs,rp in ss:
        if rp<=fo<rp+rs:return va+(fo-rp)
def rva_to_fo(rva,ss):
    for n,va,rs,rp in ss:
        if va<=rva<va+rs:return rp+(rva-va)
def in_text(rva,ss): return any(n=='.text' and va<=rva<va+rs for n,va,rs,rp in ss)
def findall(d,p):
    s=0
    while True:
        i=d.find(p,s)
        if i<0:return
        yield i; s=i+1

def candidates(d,ss,base,name):
    out=[]; seen=set()
    for fo in findall(d,name):
        r=fo_to_rva(fo,ss)
        if r is None: continue
        ptr=struct.pack('<Q',base+r)
        for n,va,rs,rp in ss:
            for pfo in findall(d[rp:rp+rs],ptr):
                at=rp+pfo
                for q in (at-8,at):
                    if q<0 or q+16>len(d): continue
                    a=u64(d,q); b=u64(d,q+8)
                    ar=a-base if a>=base else -1; br=b-base if b>=base else -1
                    native=None
                    if ar==r and in_text(br,ss): native=br
                    elif br==r and in_text(ar,ss): native=ar
                    if native is not None and native not in seen:
                        seen.add(native); out.append(native)
    return sorted(out)

def disasm(d,ss,base,rva,size):
    fo=rva_to_fo(rva,ss); md=Cs(CS_ARCH_X86,CS_MODE_64); md.detail=True
    ins=list(md.disasm(d[fo:fo+size],base+rva))
    print(f'FUNCTION 0x{rva:X}')
    for i in ins:
        rr=i.address-base
        if i.mnemonic in {'mov','movzx','movsxd','lea','add','sub','imul','idiv','div','cmp','test','and','or','xor','shl','shr','sar','call','jmp','je','jne','jg','jge','jl','jle','ja','jae','jb','jbe','cmovg','cmovge','cmovl','cmovle','setg','setge','setl','setle','ret'} or any(x in i.op_str.lower() for x in ('[rcx +','[rdx +','[rax +','[r8 +','0xa','0x64')):
            print(f'  0x{rr:X}: {i.mnemonic} {i.op_str}')
    print('END_FUNCTION')

def main():
    p=Path(sys.argv[1]); d=p.read_bytes(); ss=sections(d); pe=u32(d,0x3c); base=struct.unpack_from('<Q',d,pe+24+24)[0]
    print(f'EXE_SIZE={len(d)} IMAGE_BASE=0x{base:X}')
    speed=candidates(d,ss,base,b'GetCraftSpeedByWorkSuitability')
    print('SPEED_CANDIDATES='+','.join(f'0x{x:X}' for x in speed))
    for r in speed: disasm(d,ss,base,r,4096)

    text=next(x for x in ss if x[0]=='.text'); _,va,rs,rp=text
    print('DIRECT_CALLERS:')
    for target in speed:
        for off in range(rp,rp+rs-5):
            if d[off]!=0xE8: continue
            rel=struct.unpack_from('<i',d,off+1)[0]
            call_rva=va+(off-rp); dest=call_rva+5+rel
            if dest!=target: continue
            print(f'CALL 0x{call_rva:X} -> 0x{target:X}')
            start=max(va,call_rva-0x120); disasm(d,ss,base,start,0x260)
    print('END_SPEED_ANALYSIS')
if __name__=='__main__': main()
