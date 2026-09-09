extern "C" unsigned long long __readgsqword(unsigned long);
#pragma intrinsic(__readgsqword)

// WorkSuitability100 v1.5
// Compatibility update: removes the hard dependency on the old Palworld image
// size and absolute RVAs. Patch sites are located by instruction signatures.
// The release EXE currently published with this repo is the compatibility target.

using u8 = unsigned char;
using u16 = unsigned short;
using u32 = unsigned int;
using usize = unsigned long long;
using BOOL = int;
using HANDLE = void*;
using HMODULE = void*;

static HMODULE g_self_module = nullptr;
static bool g_initialized = false;
static bool g_patched = false;

using VirtualProtect_t = BOOL (__stdcall*)(void*, usize, u32, u32*);
using VirtualAlloc_t = void* (__stdcall*)(void*, usize, u32, u32);
using FlushInstructionCache_t = BOOL (__stdcall*)(HANDLE, const void*, usize);
using CreateFileW_t = HANDLE (__stdcall*)(const wchar_t*, u32, u32, void*, u32, u32, HANDLE);
using WriteFile_t = BOOL (__stdcall*)(HANDLE, const void*, u32, u32*, void*);
using CloseHandle_t = BOOL (__stdcall*)(HANDLE);

static VirtualProtect_t pVirtualProtect = nullptr;
static VirtualAlloc_t pVirtualAlloc = nullptr;
static FlushInstructionCache_t pFlushInstructionCache = nullptr;
static CreateFileW_t pCreateFileW = nullptr;
static WriteFile_t pWriteFile = nullptr;
static CloseHandle_t pCloseHandle = nullptr;

static constexpr u32 PAGE_EXECUTE_READWRITE = 0x40u;
static constexpr u32 MEM_COMMIT = 0x00001000u;
static constexpr u32 MEM_RESERVE = 0x00002000u;
static constexpr u32 FILE_APPEND_DATA = 0x00000004u;
static constexpr u32 FILE_SHARE_READ = 0x00000001u;
static constexpr u32 FILE_SHARE_WRITE = 0x00000002u;
static constexpr u32 FILE_SHARE_DELETE = 0x00000004u;
static constexpr u32 OPEN_ALWAYS = 4;
static constexpr u32 CREATE_ALWAYS = 2;
static constexpr u32 FILE_ATTRIBUTE_NORMAL = 0x80;
static HANDLE const INVALID_HANDLE_VALUE_ = (HANDLE)(~(usize)0);
static HANDLE const CURRENT_PROCESS_ = (HANDLE)(~(usize)0);

static bool mem_equal(const void* a, const void* b, usize n)
{
    const u8* x=(const u8*)a;
    const u8* y=(const u8*)b;
    for (usize i=0;i<n;++i) if (x[i]!=y[i]) return false;
    return true;
}

static void mem_copy(void* d0, const void* s0, usize n)
{
    u8* d=(u8*)d0;
    const u8* s=(const u8*)s0;
    for (usize i=0;i<n;++i) d[i]=s[i];
}

static bool ascii_equal(const char* a,const char* b)
{
    if (!a || !b) return false;
    while (*a && *b) { if (*a!=*b) return false; ++a; ++b; }
    return *a==0 && *b==0;
}

static wchar_t wide_lower(wchar_t c)
{
    if (c>=L'A' && c<=L'Z') return (wchar_t)(c+(L'a'-L'A'));
    return c;
}

static bool wide_name_equal(const wchar_t* a,u16 a_len_bytes,const wchar_t* b)
{
    if (!a || !b) return false;
    u32 n=a_len_bytes/2;
    u32 i=0;
    for (;i<n && b[i];++i) if (wide_lower(a[i])!=wide_lower(b[i])) return false;
    return i==n && b[i]==0;
}

static u8* get_peb() { return (u8*)__readgsqword(0x60); }
static u8* get_exe_base()
{
    u8* peb=get_peb();
    return peb ? *(u8**)(peb+0x10) : nullptr;
}

static u8* find_loaded_module(const wchar_t* wanted)
{
    u8* peb=get_peb();
    if (!peb) return nullptr;
    u8* ldr=*(u8**)(peb+0x18);
    if (!ldr) return nullptr;
    u8* head=ldr+0x20;
    u8* node=*(u8**)head;
    for (u32 guard=0;node && node!=head && guard<512;++guard)
    {
        u8* entry=node-0x10;
        u8* dll_base=*(u8**)(entry+0x30);
        u16 name_len=*(u16*)(entry+0x58);
        wchar_t* name_buf=*(wchar_t**)(entry+0x60);
        if (dll_base && name_buf && wide_name_equal(name_buf,name_len,wanted)) return dll_base;
        node=*(u8**)node;
    }
    return nullptr;
}

static void* resolve_export(u8* module,const char* wanted)
{
    if (!module || !wanted || *(u16*)module!=0x5A4D) return nullptr;
    u32 pe_off=*(u32*)(module+0x3C);
    u8* nt=module+pe_off;
    if (*(u32*)nt!=0x00004550) return nullptr;
    u8* opt=nt+24;
    u32 export_rva=*(u32*)(opt+112);
    u32 export_size=*(u32*)(opt+116);
    if (!export_rva || !export_size) return nullptr;
    u8* exp=module+export_rva;
    u32 count=*(u32*)(exp+0x18);
    u32* funcs=(u32*)(module+*(u32*)(exp+0x1C));
    u32* names=(u32*)(module+*(u32*)(exp+0x20));
    u16* ords=(u16*)(module+*(u32*)(exp+0x24));
    for (u32 i=0;i<count;++i)
    {
        const char* name=(const char*)(module+names[i]);
        if (!ascii_equal(name,wanted)) continue;
        u32 fn_rva=funcs[ords[i]];
        if (fn_rva>=export_rva && fn_rva<export_rva+export_size) return nullptr;
        return module+fn_rva;
    }
    return nullptr;
}

static bool resolve_winapi()
{
    u8* kb=find_loaded_module(L"KERNELBASE.DLL");
    if (!kb) kb=find_loaded_module(L"KERNEL32.DLL");
    if (!kb) return false;
    pVirtualProtect=(VirtualProtect_t)resolve_export(kb,"VirtualProtect");
    pVirtualAlloc=(VirtualAlloc_t)resolve_export(kb,"VirtualAlloc");
    pFlushInstructionCache=(FlushInstructionCache_t)resolve_export(kb,"FlushInstructionCache");
    pCreateFileW=(CreateFileW_t)resolve_export(kb,"CreateFileW");
    pWriteFile=(WriteFile_t)resolve_export(kb,"WriteFile");
    pCloseHandle=(CloseHandle_t)resolve_export(kb,"CloseHandle");
    return pVirtualProtect && pVirtualAlloc && pFlushInstructionCache && pCreateFileW && pWriteFile && pCloseHandle;
}

static u32 wide_len(const wchar_t* s) { u32 n=0; while (s && s[n]) ++n; return n; }
static u32 ascii_len(const char* s) { u32 n=0; while (s && s[n]) ++n; return n; }

static wchar_t g_log_path[1024]={};
static bool build_log_path()
{
    u8* peb=get_peb();
    if (!peb || !g_self_module) return false;
    u8* ldr=*(u8**)(peb+0x18);
    if (!ldr) return false;
    u8* head=ldr+0x20;
    u8* node=*(u8**)head;
    const wchar_t* full=nullptr;
    u16 full_len_bytes=0;
    for (u32 guard=0;node && node!=head && guard<512;++guard)
    {
        u8* entry=node-0x10;
        if (*(void**)(entry+0x30)==g_self_module)
        {
            full_len_bytes=*(u16*)(entry+0x48);
            full=*(wchar_t**)(entry+0x50);
            break;
        }
        node=*(u8**)node;
    }
    if (!full || !full_len_bytes) return false;
    u32 n=full_len_bytes/2;
    if (n>=1023) return false;
    wchar_t temp[1024];
    for (u32 i=0;i<n;++i) temp[i]=full[i];
    temp[n]=0;
    for (int pass=0;pass<2;++pass)
    {
        n=wide_len(temp); int last=-1;
        for (u32 i=0;i<n;++i) if (temp[i]==L'\\' || temp[i]==L'/') last=(int)i;
        if (last<0) return false;
        temp[last]=0;
    }
    n=wide_len(temp);
    const wchar_t suffix[]=L"\\work_suitability_100.log";
    u32 sn=wide_len(suffix);
    if (n+sn+1>1024) return false;
    for (u32 i=0;i<n;++i) g_log_path[i]=temp[i];
    for (u32 i=0;i<sn;++i) g_log_path[n+i]=suffix[i];
    g_log_path[n+sn]=0;
    return true;
}

static void log_line(const char* msg)
{
    if (!pCreateFileW || !pWriteFile || !pCloseHandle || !g_log_path[0] || !msg) return;
    HANDLE h=pCreateFileW(g_log_path,FILE_APPEND_DATA,
        FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
        nullptr,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
    if (!h || h==INVALID_HANDLE_VALUE_) return;
    u32 written=0;
    pWriteFile(h,msg,ascii_len(msg),&written,nullptr);
    pWriteFile(h,"\r\n",2,&written,nullptr);
    pCloseHandle(h);
}

static void clear_log()
{
    if (!pCreateFileW || !pCloseHandle || !g_log_path[0]) return;
    HANDLE h=pCreateFileW(g_log_path,FILE_APPEND_DATA,
        FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
        nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
    if (h && h!=INVALID_HANDLE_VALUE_) pCloseHandle(h);
}

struct Match { u8* address; u32 count; };

static u32 image_size(u8* base)
{
    if (!base || *(u16*)base!=0x5A4D) return 0;
    u32 pe_off=*(u32*)(base+0x3C);
    u8* nt=base+pe_off;
    if (*(u32*)nt!=0x00004550) return 0;
    return *(u32*)(nt+24+56);
}

static u8* find_pattern_near(u8* base,u32 size,const u8* pattern,usize n,u32 preferred_rva,u32 max_distance,u32* out_count)
{
    if (out_count) *out_count=0;
    if (!base || !size || !pattern || !n || n>size) return nullptr;
    u8* best=nullptr;
    u32 best_dist=0xFFFFFFFFu;
    u32 count=0;
    u32 start=0x1000u;
    if (start>=size) start=0;
    for (u32 rva=start;rva+n<=size;++rva)
    {
        if (!mem_equal(base+rva,pattern,n)) continue;
        ++count;
        u32 dist=(rva>preferred_rva)?(rva-preferred_rva):(preferred_rva-rva);
        if (dist<best_dist) { best_dist=dist; best=base+rva; }
    }
    if (out_count) *out_count=count;
    if (!best) return nullptr;
    if (max_distance && best_dist>max_distance) return nullptr;
    return best;
}

static bool patch_bytes(u8* address,const u8* original,const u8* patch,usize n)
{
    if (mem_equal(address,patch,n)) return true;
    if (!mem_equal(address,original,n)) return false;
    u32 oldProtect=0;
    if (!pVirtualProtect(address,n,PAGE_EXECUTE_READWRITE,&oldProtect)) return false;
    mem_copy(address,patch,n);
    pFlushInstructionCache(CURRENT_PROCESS_,address,n);
    u32 ignored=0;
    pVirtualProtect(address,n,oldProtect,&ignored);
    return mem_equal(address,patch,n);
}

// Original v1.4 byte signatures. The old RVAs are used only as a search hint;
// they are not required to match the new executable.
static const u8 ORIGINAL_MAP[7]={0x44,0x8B,0x88,0x54,0x0F,0x00,0x00};
static const u8 PATCH_MAP[7]={0x41,0xB9,0x64,0x00,0x00,0x00,0x90};
static const u8 ORIGINAL_SCALAR[6]={0x8B,0x88,0x54,0x0F,0x00,0x00};
static const u8 PATCH_SCALAR[6]={0xB9,0x64,0x00,0x00,0x00,0x90};
static const u8 ORIGINAL_HANDBOOK_ELIGIBILITY[6]={0x3B,0xB8,0x54,0x0F,0x00,0x00};
static const u8 PATCH_HANDBOOK_ELIGIBILITY[6]={0x83,0xFF,0x64,0x90,0x90,0x90};
static const u8 ORIGINAL_HANDBOOK_USE[12]={0x39,0x83,0x54,0x0F,0x00,0x00,0x0F,0x8C,0x80,0x00,0x00,0x00};
static const u8 PATCH_HANDBOOK_USE[12]={0x83,0xF8,0x64,0x90,0x90,0x90,0x0F,0x8F,0x80,0x00,0x00,0x00};
static const u8 ORIGINAL_SPEED_PROLOGUE[14]={0x48,0x89,0x5C,0x24,0x18,0x48,0x89,0x74,0x24,0x20,0x55,0x57,0x41,0x54};

using WorkSpeedLookup_t=int (__fastcall*)(void*,u8,int);
static WorkSpeedLookup_t g_original_work_speed_lookup=nullptr;
static bool g_speed_hook_installed=false;

static void write_abs_jump(u8* out14,const void* destination)
{
    out14[0]=0xFF; out14[1]=0x25;
    out14[2]=0; out14[3]=0; out14[4]=0; out14[5]=0;
    usize dst=(usize)destination;
    for (u32 i=0;i<8;++i) out14[6+i]=(u8)(dst>>(i*8));
}

static int __fastcall work_speed_lookup_hook(void* gameSetting,u8 workSuitability,int rank)
{
    if (!g_original_work_speed_lookup) return 0;
    int vanilla=g_original_work_speed_lookup(gameSetting,workSuitability,rank);
    if (rank<=10 || vanilla<=0) return vanilla;
    if (rank>100) rank=100;
    long long scaled2=(long long)vanilla*(long long)(rank-8);
    long long scaled=(scaled2+1)/2;
    if (scaled>2147480000LL) scaled=2147480000LL;
    if (scaled<1) scaled=1;
    return (int)scaled;
}

static bool install_native_speed_hook(u8* target)
{
    if (g_speed_hook_installed) return true;
    if (!target || !pVirtualAlloc || !pVirtualProtect || !pFlushInstructionCache) return false;
    if (!mem_equal(target,ORIGINAL_SPEED_PROLOGUE,14)) return false;

    u8* tramp=(u8*)pVirtualAlloc(nullptr,64,MEM_COMMIT|MEM_RESERVE,PAGE_EXECUTE_READWRITE);
    if (!tramp) return false;
    mem_copy(tramp,target,14);
    write_abs_jump(tramp+14,target+14);
    pFlushInstructionCache(CURRENT_PROCESS_,tramp,28);
    g_original_work_speed_lookup=(WorkSpeedLookup_t)tramp;

    u8 jump[14];
    write_abs_jump(jump,(const void*)&work_speed_lookup_hook);
    u32 oldProtect=0;
    if (!pVirtualProtect(target,14,PAGE_EXECUTE_READWRITE,&oldProtect)) return false;
    mem_copy(target,jump,14);
    pFlushInstructionCache(CURRENT_PROCESS_,target,14);
    u32 ignored=0;
    pVirtualProtect(target,14,oldProtect,&ignored);
    g_speed_hook_installed=true;
    return true;
}

static bool apply_patch()
{
    u8* exe=get_exe_base();
    u32 size=image_size(exe);
    if (!exe || !size)
    {
        log_line("[WorkSuitability100 v1.5] ERROR: could not read Palworld PE image.");
        return false;
    }

    // These are the old RVAs only as a locality hint. A normal game update
    // can move code and still be found safely by its instruction signature.
    const u32 HINT_MAP=0x02E6F3CAu;
    const u32 HINT_SCALAR=0x02F7481Au;
    const u32 HINT_ELIGIBILITY=0x032B26D3u;
    const u32 HINT_HANDBOOK=0x02F7C21Cu;
    const u32 HINT_SPEED=0x02F11560u;
    const u32 MAX_MOVE=0x01000000u;

    u32 cm=0,cs=0,ce=0,ch=0,cv=0;
    u8* mapSite=find_pattern_near(exe,size,ORIGINAL_MAP,7,HINT_MAP,MAX_MOVE,&cm);
    u8* scalarSite=find_pattern_near(exe,size,ORIGINAL_SCALAR,6,HINT_SCALAR,MAX_MOVE,&cs);
    u8* eligSite=find_pattern_near(exe,size,ORIGINAL_HANDBOOK_ELIGIBILITY,6,HINT_ELIGIBILITY,MAX_MOVE,&ce);
    u8* handbookSite=find_pattern_near(exe,size,ORIGINAL_HANDBOOK_USE,12,HINT_HANDBOOK,MAX_MOVE,&ch);
    u8* speedSite=find_pattern_near(exe,size,ORIGINAL_SPEED_PROLOGUE,14,HINT_SPEED,MAX_MOVE,&cv);

    if (!mapSite || !scalarSite || !eligSite || !handbookSite || !speedSite)
    {
        log_line("[WorkSuitability100 v1.5] ERROR: one or more signatures were not found within the compatibility search window.");
        return false;
    }

    log_line("[WorkSuitability100 v1.5] Signature matches found; applying rank/handbook patches.");

    bool a=patch_bytes(mapSite,ORIGINAL_MAP,PATCH_MAP,7);
    bool b=patch_bytes(scalarSite,ORIGINAL_SCALAR,PATCH_SCALAR,6);
    bool c=patch_bytes(eligSite,ORIGINAL_HANDBOOK_ELIGIBILITY,PATCH_HANDBOOK_ELIGIBILITY,6);
    bool d=patch_bytes(handbookSite,ORIGINAL_HANDBOOK_USE,PATCH_HANDBOOK_USE,12);
    bool e=install_native_speed_hook(speedSite);

    if (a && b && c && d && e)
    {
        log_line("[WorkSuitability100 v1.5] PATCHED: work suitability rank ceiling = 100.");
        log_line("[WorkSuitability100 v1.5] PATCHED: handbook eligibility ceiling = 100.");
        log_line("[WorkSuitability100 v1.5] PATCHED: handbook application ceiling = 100.");
        log_line("[WorkSuitability100 v1.5] PATCHED: native work-speed scaling enabled through rank 100.");
        log_line("[WorkSuitability100 v1.5] Compatibility mode: no fixed executable image size or absolute patch RVA required.");
        return true;
    }

    char msg[128];
    (void)msg;
    log_line("[WorkSuitability100 v1.5] ERROR: at least one patch operation failed or was already incompatible.");
    return false;
}

extern "C" __declspec(dllexport) int luaopen_WorkSuitability100(void*)
{
    if (g_initialized) return 0;
    g_initialized=true;
    if (!resolve_winapi()) return 0;
    if (!build_log_path()) return 0;
    clear_log();
    log_line("[WorkSuitability100 v1.5] Loaded through Lua package.loadlib.");
    g_patched=apply_patch();
    return 0;
}

extern "C" __declspec(dllexport) int WorkSuitability100Apply(void*)
{
    if (!g_initialized) luaopen_WorkSuitability100(nullptr);
    else if (!g_patched) g_patched=apply_patch();
    return 0;
}

extern "C" BOOL __stdcall DllMain(void* module,u32 reason,void*)
{
    if (reason==1) g_self_module=module;
    return 1;
}
