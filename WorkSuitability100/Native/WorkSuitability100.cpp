extern "C" unsigned long long __readgsqword(unsigned long);
#pragma intrinsic(__readgsqword)

// WorkSuitability100 v1.4 - rank ceiling + handbook + native work-speed scaling
// Exact target: Palworld Steam v1.0.3.101238
// EXE SHA256: fe3c15064524bae1947852467c4f92bc22469acc033a3d3c8031eab4324e41e8
//
// v1.4 keeps the v1.2 rank + handbook patches and replaces the unsafe
// UE4SS Lua speed hooks from v1.3 with one native detour at Palworld's
// rank -> work-speed lookup. The original lookup already clamps ranks above
// the table length (10); our hook lets it obtain the normal level-10 value
// and then extends that value for real ranks 11..100. No reflected UFunction
// is recursively called from Lua.

using u8 = unsigned char;
using u16 = unsigned short;
using u32 = unsigned int;
using usize = unsigned long long;
using BOOL = int;
using HANDLE = void*;
using HMODULE = void*;

// Tiny CRT-free memcpy because this DLL is linked /nodefaultlib.
extern "C" void* memcpy(void* dst, const void* src, usize n)
{
    volatile u8* d = (volatile u8*)dst;
    const volatile u8* s = (const volatile u8*)src;
    for (usize i = 0; i < n; ++i) d[i] = s[i];
    return dst;
}

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

static constexpr usize EXPECTED_IMAGE_SIZE = 0x09FAD000ull;

// Site A: suitability-rank map builder
// Original: 44 8B 88 54 0F 00 00   mov r9d,dword ptr [rax+0xF54]
// Patched:  41 B9 64 00 00 00 90   mov r9d,100 / nop
static constexpr usize RVA_MAP_MAX_READ = 0x02E6F3CAull;
static const u8 ORIGINAL_MAP[7] = {0x44,0x8B,0x88,0x54,0x0F,0x00,0x00};
static const u8 PATCH_MAP[7]    = {0x41,0xB9,0x64,0x00,0x00,0x00,0x90};

// Site B: scalar character-adjusted rank clamp
// Original: 8B 88 54 0F 00 00      mov ecx,dword ptr [rax+0xF54]
// Patched:  B9 64 00 00 00 90      mov ecx,100 / nop
static constexpr usize RVA_SCALAR_MAX_READ = 0x02F7481Aull;
static const u8 ORIGINAL_SCALAR[6] = {0x8B,0x88,0x54,0x0F,0x00,0x00};
static const u8 PATCH_SCALAR[6]    = {0xB9,0x64,0x00,0x00,0x00,0x90};

// Site C: PalUtility::CanUseTargetWorkSuitabilityRankUp
// Original: 3B B8 54 0F 00 00   cmp edi,dword ptr [rax+0xF54]
//           7D 12               jge reject
// Patched:  83 FF 64 90 90 90   cmp edi,100 / nops
// The original jge remains, so rank 99 is allowed and rank 100 is rejected.
static constexpr usize RVA_HANDBOOK_ELIGIBILITY_MAX = 0x032B26D3ull;
static const u8 ORIGINAL_HANDBOOK_ELIGIBILITY[6] = {0x3B,0xB8,0x54,0x0F,0x00,0x00};
static const u8 PATCH_HANDBOOK_ELIGIBILITY[6]    = {0x83,0xFF,0x64,0x90,0x90,0x90};

// Site D: actual handbook application branch. The game calculates next rank
// (current + 1) in EAX, then rejects if configured max < next rank.
// Original: 39 83 54 0F 00 00   cmp dword ptr [rbx+0xF54],eax
//           0F 8C 80 00 00 00   jl reject
// Patched:  83 F8 64 90 90 90   cmp eax,100 / nops
//           0F 8F 80 00 00 00   jg reject
// This allows next rank <= 100 and rejects 101+.
static constexpr usize RVA_HANDBOOK_USE_MAX = 0x02F7C21Cull;
static const u8 ORIGINAL_HANDBOOK_USE[12] = {0x39,0x83,0x54,0x0F,0x00,0x00,0x0F,0x8C,0x80,0x00,0x00,0x00};
static const u8 PATCH_HANDBOOK_USE[12]    = {0x83,0xF8,0x64,0x90,0x90,0x90,0x0F,0x8F,0x80,0x00,0x00,0x00};


// Site E: common Pal game-setting lookup used by
// UPalIndividualCharacterParameter::GetCraftSpeedByWorkSuitability and the
// suitability-aware buff path.
// Signature observed in this exact EXE:
//   int32 Lookup(void* GameSetting, uint8 WorkSuitability, int32 Rank)
//
// Inside the original function the work-speed TArray length is compared with
// Rank, and Rank is replaced by (ArrayNum - 1) when it is too large. This is
// the actual reason rank 75/100 still performs like rank 10.
//
// We detour the function, call an executable trampoline containing the exact
// original 14-byte prologue, then extend the already-capped level-10 result:
//   rank 10  = 1.0x
//   rank 11  = 1.5x
//   rank 20  = 6.0x
//   rank 50  = 21.0x
//   rank 75  = 33.5x
//   rank 100 = 46.0x
static bool mem_equal(const void* a, const void* b, usize n);
static void mem_copy(void* d0, const void* s0, usize n);

static constexpr usize RVA_WORK_SPEED_LOOKUP = 0x02F11560ull;
static const u8 ORIGINAL_SPEED_PROLOGUE[14] = {
    0x48,0x89,0x5C,0x24,0x18,       // mov [rsp+18],rbx
    0x48,0x89,0x74,0x24,0x20,       // mov [rsp+20],rsi
    0x55,                            // push rbp
    0x57,                            // push rdi
    0x41,0x54                       // push r12
};

using WorkSpeedLookup_t = int (__fastcall*)(void*, u8, int);
static WorkSpeedLookup_t g_original_work_speed_lookup = nullptr;
static void* g_speed_trampoline = nullptr;
static bool g_speed_hook_installed = false;

static int __fastcall work_speed_lookup_hook(void* gameSetting, u8 workSuitability, int rank)
{
    if (!g_original_work_speed_lookup) return 0;

    int vanilla = g_original_work_speed_lookup(gameSetting, workSuitability, rank);
    if (rank <= 10 || vanilla <= 0) return vanilla;

    if (rank > 100) rank = 100;

    // multiplier = 1 + (rank - 10) * 0.5 = (rank - 8) / 2.
    // Do it with 64-bit integer math so this hot path needs no CRT/floating runtime.
    long long scaled2 = (long long)vanilla * (long long)(rank - 8);
    long long scaled = (scaled2 + 1) / 2;
    if (scaled > 2147480000LL) scaled = 2147480000LL;
    if (scaled < 1) scaled = 1;
    return (int)scaled;
}

static void write_abs_jump(u8* out14, const void* destination)
{
    // jmp qword ptr [rip+0] ; followed by absolute destination
    out14[0]=0xFF; out14[1]=0x25;
    out14[2]=0; out14[3]=0; out14[4]=0; out14[5]=0;
    usize dst=(usize)destination;
    for (u32 i=0;i<8;++i) out14[6+i]=(u8)(dst >> (i*8));
}

static bool install_native_speed_hook(u8* exe)
{
    if (g_speed_hook_installed) return true;
    if (!exe || !pVirtualAlloc || !pVirtualProtect || !pFlushInstructionCache) return false;

    u8* target=exe+RVA_WORK_SPEED_LOOKUP;
    if (!mem_equal(target, ORIGINAL_SPEED_PROLOGUE, 14)) return false;

    u8* tramp=(u8*)pVirtualAlloc(nullptr, 64, MEM_COMMIT|MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!tramp) return false;

    mem_copy(tramp, target, 14);
    write_abs_jump(tramp+14, target+14);
    pFlushInstructionCache(CURRENT_PROCESS_, tramp, 28);

    g_speed_trampoline=tramp;
    g_original_work_speed_lookup=(WorkSpeedLookup_t)tramp;

    u8 jump[14];
    write_abs_jump(jump, (const void*)&work_speed_lookup_hook);
    u32 oldProtect=0;
    if (!pVirtualProtect(target,14,PAGE_EXECUTE_READWRITE,&oldProtect)) return false;
    mem_copy(target,jump,14);
    pFlushInstructionCache(CURRENT_PROCESS_,target,14);
    u32 ignored=0;
    pVirtualProtect(target,14,oldProtect,&ignored);

    g_speed_hook_installed=true;
    return true;
}

static bool mem_equal(const void* a, const void* b, usize n)
{
    const u8* x = (const u8*)a;
    const u8* y = (const u8*)b;
    for (usize i = 0; i < n; ++i) if (x[i] != y[i]) return false;
    return true;
}

static void mem_copy(void* d0, const void* s0, usize n)
{
    u8* d = (u8*)d0;
    const u8* s = (const u8*)s0;
    for (usize i = 0; i < n; ++i) d[i] = s[i];
}

static bool ascii_equal(const char* a, const char* b)
{
    if (!a || !b) return false;
    while (*a && *b) { if (*a != *b) return false; ++a; ++b; }
    return *a == 0 && *b == 0;
}

static wchar_t wide_lower(wchar_t c)
{
    if (c >= L'A' && c <= L'Z') return (wchar_t)(c + (L'a' - L'A'));
    return c;
}

static bool wide_name_equal(const wchar_t* a, u16 a_len_bytes, const wchar_t* b)
{
    if (!a || !b) return false;
    u32 n = a_len_bytes / 2;
    u32 i = 0;
    for (; i < n && b[i]; ++i) if (wide_lower(a[i]) != wide_lower(b[i])) return false;
    return i == n && b[i] == 0;
}

static u8* get_peb() { return (u8*)__readgsqword(0x60); }
static u8* get_exe_base()
{
    u8* peb = get_peb();
    return peb ? *(u8**)(peb + 0x10) : nullptr;
}

static u8* find_loaded_module(const wchar_t* wanted)
{
    u8* peb = get_peb();
    if (!peb) return nullptr;
    u8* ldr = *(u8**)(peb + 0x18);
    if (!ldr) return nullptr;
    u8* head = ldr + 0x20;
    u8* node = *(u8**)head;
    for (u32 guard = 0; node && node != head && guard < 512; ++guard)
    {
        u8* entry = node - 0x10;
        u8* dll_base = *(u8**)(entry + 0x30);
        u16 name_len = *(u16*)(entry + 0x58);
        wchar_t* name_buf = *(wchar_t**)(entry + 0x60);
        if (dll_base && name_buf && wide_name_equal(name_buf, name_len, wanted)) return dll_base;
        node = *(u8**)node;
    }
    return nullptr;
}

static void* resolve_export(u8* module, const char* wanted)
{
    if (!module || !wanted || *(u16*)module != 0x5A4D) return nullptr;
    u32 pe_off = *(u32*)(module + 0x3C);
    u8* nt = module + pe_off;
    if (*(u32*)nt != 0x00004550) return nullptr;
    u8* opt = nt + 24;
    u32 export_rva = *(u32*)(opt + 112);
    u32 export_size = *(u32*)(opt + 116);
    if (!export_rva || !export_size) return nullptr;
    u8* exp = module + export_rva;
    u32 count = *(u32*)(exp + 0x18);
    u32* funcs = (u32*)(module + *(u32*)(exp + 0x1C));
    u32* names = (u32*)(module + *(u32*)(exp + 0x20));
    u16* ords = (u16*)(module + *(u32*)(exp + 0x24));
    for (u32 i = 0; i < count; ++i)
    {
        const char* name = (const char*)(module + names[i]);
        if (!ascii_equal(name, wanted)) continue;
        u32 fn_rva = funcs[ords[i]];
        if (fn_rva >= export_rva && fn_rva < export_rva + export_size) return nullptr;
        return module + fn_rva;
    }
    return nullptr;
}

static bool resolve_winapi()
{
    u8* kb = find_loaded_module(L"KERNELBASE.DLL");
    if (!kb) kb = find_loaded_module(L"KERNEL32.DLL");
    if (!kb) return false;
    pVirtualProtect = (VirtualProtect_t)resolve_export(kb, "VirtualProtect");
    pVirtualAlloc = (VirtualAlloc_t)resolve_export(kb, "VirtualAlloc");
    pFlushInstructionCache = (FlushInstructionCache_t)resolve_export(kb, "FlushInstructionCache");
    pCreateFileW = (CreateFileW_t)resolve_export(kb, "CreateFileW");
    pWriteFile = (WriteFile_t)resolve_export(kb, "WriteFile");
    pCloseHandle = (CloseHandle_t)resolve_export(kb, "CloseHandle");
    return pVirtualProtect && pVirtualAlloc && pFlushInstructionCache && pCreateFileW && pWriteFile && pCloseHandle;
}

static u32 wide_len(const wchar_t* s) { u32 n=0; while (s && s[n]) ++n; return n; }
static u32 ascii_len(const char* s) { u32 n=0; while (s && s[n]) ++n; return n; }

static wchar_t g_log_path[1024] = {};
static bool build_log_path()
{
    u8* peb = get_peb();
    if (!peb || !g_self_module) return false;
    u8* ldr = *(u8**)(peb + 0x18);
    if (!ldr) return false;
    u8* head = ldr + 0x20;
    u8* node = *(u8**)head;
    const wchar_t* full = nullptr;
    u16 full_len_bytes = 0;
    for (u32 guard=0; node && node != head && guard<512; ++guard)
    {
        u8* entry = node - 0x10;
        if (*(void**)(entry + 0x30) == g_self_module)
        {
            full_len_bytes = *(u16*)(entry + 0x48);
            full = *(wchar_t**)(entry + 0x50);
            break;
        }
        node = *(u8**)node;
    }
    if (!full || !full_len_bytes) return false;
    u32 n = full_len_bytes / 2;
    if (n >= 1023) return false;
    wchar_t temp[1024];
    for (u32 i=0;i<n;++i) temp[i]=full[i];
    temp[n]=0;
    for (int pass=0; pass<2; ++pass)
    {
        n=wide_len(temp); int last=-1;
        for (u32 i=0;i<n;++i) if (temp[i]==L'\\' || temp[i]==L'/') last=(int)i;
        if (last<0) return false;
        temp[last]=0;
    }
    n=wide_len(temp);
    const wchar_t suffix[] = L"\\work_suitability_100.log";
    u32 sn=wide_len(suffix);
    if (n+sn+1 > 1024) return false;
    for (u32 i=0;i<n;++i) g_log_path[i]=temp[i];
    for (u32 i=0;i<sn;++i) g_log_path[n+i]=suffix[i];
    g_log_path[n+sn]=0;
    return true;
}

static void log_line(const char* msg)
{
    if (!pCreateFileW || !pWriteFile || !pCloseHandle || !g_log_path[0] || !msg) return;
    HANDLE h=pCreateFileW(g_log_path, FILE_APPEND_DATA,
        FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
        nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (!h || h==INVALID_HANDLE_VALUE_) return;
    u32 written=0;
    pWriteFile(h,msg,ascii_len(msg),&written,nullptr);
    pWriteFile(h,"\r\n",2,&written,nullptr);
    pCloseHandle(h);
}

static void clear_log()
{
    if (!pCreateFileW || !pCloseHandle || !g_log_path[0]) return;
    HANDLE h=pCreateFileW(g_log_path, FILE_APPEND_DATA,
        FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
        nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h && h!=INVALID_HANDLE_VALUE_) pCloseHandle(h);
}

static usize get_image_size(u8* base)
{
    if (!base || *(u16*)base != 0x5A4D) return 0;
    u32 pe_off=*(u32*)(base+0x3C);
    u8* nt=base+pe_off;
    if (*(u32*)nt != 0x00004550) return 0;
    return *(u32*)(nt+24+56);
}

static bool patch_bytes(u8* address, const u8* original, const u8* patch, usize n)
{
    if (mem_equal(address, patch, n)) return true;
    if (!mem_equal(address, original, n)) return false;
    u32 oldProtect=0;
    if (!pVirtualProtect(address,n,PAGE_EXECUTE_READWRITE,&oldProtect)) return false;
    mem_copy(address,patch,n);
    pFlushInstructionCache(CURRENT_PROCESS_,address,n);
    u32 ignored=0;
    pVirtualProtect(address,n,oldProtect,&ignored);
    return mem_equal(address,patch,n);
}

static bool apply_patch()
{
    u8* exe=get_exe_base();
    if (!exe || get_image_size(exe)!=EXPECTED_IMAGE_SIZE)
    {
        log_line("[WorkSuitability100 v1.4] ERROR: unexpected Palworld executable image; no patch applied.");
        return false;
    }

    u8* mapSite=exe+RVA_MAP_MAX_READ;
    u8* scalarSite=exe+RVA_SCALAR_MAX_READ;
    u8* eligibilitySite=exe+RVA_HANDBOOK_ELIGIBILITY_MAX;
    u8* handbookUseSite=exe+RVA_HANDBOOK_USE_MAX;
    u8* speedSite=exe+RVA_WORK_SPEED_LOOKUP;

    bool mapRecognized = mem_equal(mapSite,ORIGINAL_MAP,7) || mem_equal(mapSite,PATCH_MAP,7);
    bool scalarRecognized = mem_equal(scalarSite,ORIGINAL_SCALAR,6) || mem_equal(scalarSite,PATCH_SCALAR,6);
    bool eligibilityRecognized = mem_equal(eligibilitySite,ORIGINAL_HANDBOOK_ELIGIBILITY,6) || mem_equal(eligibilitySite,PATCH_HANDBOOK_ELIGIBILITY,6);
    bool handbookUseRecognized = mem_equal(handbookUseSite,ORIGINAL_HANDBOOK_USE,12) || mem_equal(handbookUseSite,PATCH_HANDBOOK_USE,12);
    bool speedRecognized = mem_equal(speedSite,ORIGINAL_SPEED_PROLOGUE,14);
    if (!mapRecognized || !scalarRecognized || !eligibilityRecognized || !handbookUseRecognized || !speedRecognized)
    {
        log_line("[WorkSuitability100 v1.4] ERROR: exact rank/handbook/speed signatures did not match; no patch applied.");
        return false;
    }

    bool a=patch_bytes(mapSite,ORIGINAL_MAP,PATCH_MAP,7);
    bool b=patch_bytes(scalarSite,ORIGINAL_SCALAR,PATCH_SCALAR,6);
    bool c=patch_bytes(eligibilitySite,ORIGINAL_HANDBOOK_ELIGIBILITY,PATCH_HANDBOOK_ELIGIBILITY,6);
    bool d=patch_bytes(handbookUseSite,ORIGINAL_HANDBOOK_USE,PATCH_HANDBOOK_USE,12);
    bool e=install_native_speed_hook(exe);
    if (a && b && c && d && e)
    {
        log_line("[WorkSuitability100 v1.4] PATCHED: work suitability rank ceiling = 100.");
        log_line("[WorkSuitability100 v1.4] PATCHED: handbook eligibility ceiling = 100.");
        log_line("[WorkSuitability100 v1.4] PATCHED: handbook application ceiling = 100.");
        log_line("[WorkSuitability100 v1.4] PATCHED: native work-speed scaling enabled through rank 100.");
        log_line("[WorkSuitability100 v1.4] Inventory-safe: no UE4SS craft-speed UFunction hooks are installed.");
        return true;
    }
    log_line("[WorkSuitability100 v1.4] ERROR: failed to modify one or more rank/handbook/speed paths.");
    return false;
}

extern "C" __declspec(dllexport) int luaopen_WorkSuitability100(void*)
{
    if (g_initialized) return 0;
    g_initialized=true;
    if (!resolve_winapi()) return 0;
    if (!build_log_path()) return 0;
    clear_log();
    log_line("[WorkSuitability100 v1.4] Loaded through Lua package.loadlib.");
    g_patched=apply_patch();
    return 0;
}

extern "C" __declspec(dllexport) int WorkSuitability100Apply(void*)
{
    if (!g_initialized) luaopen_WorkSuitability100(nullptr);
    else if (!g_patched) g_patched=apply_patch();
    return 0;
}

extern "C" BOOL __stdcall DllMain(void* module, u32 reason, void*)
{
    if (reason==1) g_self_module=module;
    return 1;
}
