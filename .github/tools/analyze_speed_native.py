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
                        native=None; pair=None
                        if ar==r and in_text(br,ss): native=br; pair=q
                        elif br==r and in_text(ar,ss): native=ar; pair=q
                        if native is None: continue
                        key=(name,native,pair)
                        if key in seen: continue
                        seen.add(key); candidates.setdefault(name.decode(),[]).append(native)
                        print(f'{name.decode()} string_rva=0x{r:X} pair_rva=0x{fo_to_rva(pair,ss):X} native_rva=0x{native:X}')
    return candidates

def disasm_function(d,ss,base,rva,limit=1024):
    fo=rva_to_fo(rva,ss)
    if fo is None: return []
    md=Cs(CS_ARCH_X86,CS_MODE_64); md.detail=True
    ins=list(md.disasm(d[fo:fo+limit],base+rva))
    print(f'FOCUS_FUNCTION RVA=0x{rva:X} FILE=0x{fo:X}')
    for i in ins:
        rel=i.address-(base+rva); op=i.op_str.lower()
        if i.mnemonic in ('cmp','mov','lea','add','sub','imul','idiv','div','test','and','or','xor','shl','shr','sar','call','jmp','je','jne','jg','jge','jl','jle','ja','jae','jb','jbe','seta','setae','setb','setbe','sete','setne','cmovg','cmovge','cmovl','cmovle','cmova','cmovae','cmovb','cmovbe','cmove','cmovne','ret') or any(x in op for x in ('0xa','0x64','[rcx +','[rdx +','[rax +','[r8 +')):
            print(f'  +0x{rel:03X}: {i.mnemonic} {i.op_str}')
    print('END_FOCUS_FUNCTION')
    return ins

def main():
    d=Path(sys.argv[1]).read_bytes(); ss=sections(d); pe=u32(d,0x3c); base=struct.unpack_from('<Q',d,pe+24+24)[0]
    print(f'EXE_SIZE={len(d)} IMAGE_BASE=0x{base:X}')
    names=[b'GetCraftSpeedByWorkSuitability',b'CanUseTargetWorkSuitabilityRankUp',b'GetWorkSuitabilityRank',b'GetWorkSuitabilityRankWithCharacterRank',b'HasWorkSuitabilityRank',b'GetCraftSpeed_WorkSuitability']
    print('NATIVE_LOOKUP:')
    candidates=native_candidates(d,ss,base,names)
    print('NATIVE_FUNCTIONS:')
    all_native=sorted({r for vals in candidates.values() for r in vals})
    for r in all_native:
        disasm_function(d,ss,base,r,2048)

    print('SPEED_CALL_GRAPH:')
    speed=set(candidates.get('GetCraftSpeedByWorkSuitability',[]))
    callers=[]
    text_sec=next((x for x in ss if x[0]=='.text'),None)
    if text_sec:
        _,va,rs,rp,_,_=text_sec
        for off in range(rp,rp+rs-5):
            if d[off]!=0xE8: continue
            rel=struct.unpack_from('<i',d,off+1)[0]
            call_rva=va+(off-rp)
            dest_rva=call_rva+5+rel
            if dest_rva in speed:
                callers.append((call_rva,dest_rva))
    for call_rva,dest in callers:
        print(f'DIRECT_CALLER=0x{call_rva:X} TARGET=0x{dest:X}')
        start=max(0,call_rva-0x80)
        start_rva=va+(start-rp)
        disasm_function(d,ss,base,start_rva,384)

    print('FIELD_RVAS:')
    for field in [b'CraftSpeeds',b'WorkSuitabilityDefineDataMap',b'WorkSuitabilityMaxRank']:
        rs=list(findall(d,field)); print(field.decode()+': '+', '.join(f'0x{x:X}' for x in rs))
    print('END_NATIVE_SPEED_ANALYSIS')

if __name__=='__main__': main()
