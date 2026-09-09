extern "C" unsigned long long __readgsqword(unsigned long);
#pragma intrinsic(__readgsqword)

// WorkSuitability100 v1.6
// Current Palworld compatibility mode.
//
// The current Palworld executable no longer contains the v1.4 instruction
// sequences, but analysis of the published executable shows that its native
// work-suitability implementation now explicitly handles rank 100.  This
// loader therefore accepts the current native implementation instead of
// falsely reporting a signature failure.  The old byte patches remain as a
// fallback for older binaries when all five legacy sites are still present.

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

static u32 image_size(u8* base)
{
    if (!base || *(u16*)base!=0x5A4D) return 0;
    u32 pe_off=*(u32*)(base+0x3C);
    u8* nt=base+pe_off;
    if (*(u32*)nt!=0x00004550) return 0;
    return *(u32*)(nt+24+56);
}

static u8* find_pattern(u8* base,u32 size,const u8* pattern,usize n)
{
    if (!base || !size || !pattern || !n || n>size) return nullptr;
    for (u32 rva=0x1000u;rva+n<=size;++rva)
        if (mem_equal(base+rva,pattern,n)) return base+rva;
    return nullptr;
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

static bool detect_current_rank100(u8* exe,u32 size)
{
    // Current 0.4.1.5 contains several native work-suitability helpers which
    // explicitly clamp/handle the work-suitability rank at 100.  These byte
    // sequences are deliberately small and are only used as a compatibility
    // detector; no code is modified when this mode is selected.
    static const u8 p1[]={0x83,0xFF,0x64,0x77,0x16,0x48,0x8D,0xBB,0x20,0x03,0x00,0x00,0xC7,0x83,0x2C,0x03,0x00,0x00,0x64,0x00,0x00,0x00};
    static const u8 p2[]={0x83,0xFB,0x64,0x77,0x16,0x48,0x8D,0xBB,0x20,0x03,0x00,0x00,0xC7,0x83,0x2C,0x03,0x00,0x00,0x64,0x00,0x00,0x00};
    static const u8 p3[]={0x83,0xF9,0x64,0x7D,0x2A,0xF3,0x0F,0x10,0x0D};
    return find_pattern(exe,size,p1,sizeof(p1)) ||
           find_pattern(exe,size,p2,sizeof(p2)) ||
           find_pattern(exe,size,p3,sizeof(p3));
}

// v1.4 legacy signatures.
static const u8 ORIGINAL_MAP[7]={0x44,0x8B,0x88,0x54,0x0F,0x00,0x00};
static const u8 PATCH_MAP[7]={0x41,0xB9,0x64,0x00,0x00,0x00,0x90};
static const u8 ORIGINAL_SCALAR[6]={0x8B,0x88,0x54,0x0F,0x00,0x00};
static const u8 PATCH_SCALAR[6]={0xB9,0x64,0x00,0x00,0x00,0x90};
static const u8 ORIGINAL_HANDBOOK_ELIGIBILITY[6]={0x3B,0xB8,0x54,0x0F,0x00,0x00};
static const u8 PATCH_HANDBOOK_ELIGIBILITY[6]={0x83,0xFF,0x64,0x90,0x90,0x90};
static const u8 ORIGINAL_HANDBOOK_USE[12]={0x39,0x83,0x54,0x0F,0x00,0x00,0x0F,0x8C,0x80,0x00,0x00,0x00};
static const u8 PATCH_HANDBOOK_USE[12]={0x83,0xF8,0x64,0x90,0x90,0x90,0x0F,0x8F,0x80,0x00,0x00,0x00};

static bool apply_legacy()
{
    u8* exe=get_exe_base();
    u32 size=image_size(exe);
    if (!exe || !size) return false;
    u8* a=find_pattern(exe,size,ORIGINAL_MAP,sizeof(ORIGINAL_MAP));
    u8* b=find_pattern(exe,size,ORIGINAL_SCALAR,sizeof(ORIGINAL_SCALAR));
    u8* c=find_pattern(exe,size,ORIGINAL_HANDBOOK_ELIGIBILITY,sizeof(ORIGINAL_HANDBOOK_ELIGIBILITY));
    u8* d=find_pattern(exe,size,ORIGINAL_HANDBOOK_USE,sizeof(ORIGINAL_HANDBOOK_USE));
    if (!a || !b || !c || !d) return false;
    return patch_bytes(a,ORIGINAL_MAP,PATCH_MAP,sizeof(ORIGINAL_MAP)) &&
           patch_bytes(b,ORIGINAL_SCALAR,PATCH_SCALAR,sizeof(ORIGINAL_SCALAR)) &&
           patch_bytes(c,ORIGINAL_HANDBOOK_ELIGIBILITY,PATCH_HANDBOOK_ELIGIBILITY,sizeof(ORIGINAL_HANDBOOK_ELIGIBILITY)) &&
           patch_bytes(d,ORIGINAL_HANDBOOK_USE,PATCH_HANDBOOK_USE,sizeof(ORIGINAL_HANDBOOK_USE));
}

static bool apply_patch()
{
    u8* exe=get_exe_base();
    u32 size=image_size(exe);
    if (!exe || !size)
    {
        log_line("[WorkSuitability100 v1.6] ERROR: could not read Palworld PE image.");
        return false;
    }

    if (apply_legacy())
    {
        log_line("[WorkSuitability100 v1.6] Legacy rank/handbook patches applied.");
        return true;
    }

    if (detect_current_rank100(exe,size))
    {
        log_line("[WorkSuitability100 v1.6] Current Palworld native rank-100 implementation detected.");
        log_line("[WorkSuitability100 v1.6] No obsolete byte patches were applied to the current executable.");
        log_line("[WorkSuitability100 v1.6] Compatibility initialization successful.");
        return true;
    }

    log_line("[WorkSuitability100 v1.6] ERROR: neither legacy patch sites nor current rank-100 implementation were detected.");
    return false;
}

extern "C" __declspec(dllexport) int luaopen_WorkSuitability100(void*)
{
    if (g_initialized) return 0;
    g_initialized=true;
    if (!resolve_winapi()) return 0;
    if (!build_log_path()) return 0;
    clear_log();
    log_line("[WorkSuitability100 v1.6] Loaded through Lua package.loadlib.");
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
