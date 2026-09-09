extern "C" unsigned long long __readgsqword(unsigned long);
#pragma intrinsic(__readgsqword)

// WorkSuitability100 v1.7
// Current-build runtime patcher.
// Resolves the native WorkSuitabilityMaxRank and
// CanUseTargetWorkSuitabilityRankUp entries from UE reflection metadata,
// then patches only the selected functions' level-10 immediates to 100.

using u8 = unsigned char;
using u16 = unsigned short;
using u32 = unsigned int;
using u64 = unsigned long long;
using usize = unsigned long long;
using BOOL = int;
using HANDLE = void*;
using HMODULE = void*;

static HMODULE g_self_module = nullptr;
static bool g_initialized = false;
static bool g_patched = false;

using VirtualProtect_t = BOOL (__stdcall*)(void*, usize, u32, u32*);
using FlushInstructionCache_t = BOOL (__stdcall*)(HANDLE, const void*, usize);
using CreateFileW_t = HANDLE (__stdcall*)(const wchar_t*, u32, u32, void*, u32, u32, HANDLE);
using WriteFile_t = BOOL (__stdcall*)(HANDLE, const void*, u32, u32*, void*);
using CloseHandle_t = BOOL (__stdcall*)(HANDLE);

static VirtualProtect_t pVirtualProtect = nullptr;
static FlushInstructionCache_t pFlushInstructionCache = nullptr;
static CreateFileW_t pCreateFileW = nullptr;
static WriteFile_t pWriteFile = nullptr;
static CloseHandle_t pCloseHandle = nullptr;

static constexpr u32 PAGE_EXECUTE_READWRITE = 0x40u;
static constexpr u32 FILE_APPEND_DATA = 0x00000004u;
static constexpr u32 FILE_SHARE_READ = 0x00000001u;
static constexpr u32 FILE_SHARE_WRITE = 0x00000002u;
static constexpr u32 FILE_SHARE_DELETE = 0x00000004u;
static constexpr u32 OPEN_ALWAYS = 4;
static constexpr u32 CREATE_ALWAYS = 2;
static constexpr u32 FILE_ATTRIBUTE_NORMAL = 0x80u;
static HANDLE const INVALID_HANDLE_VALUE_ = (HANDLE)(~(usize)0);
static HANDLE const CURRENT_PROCESS_ = (HANDLE)(~(usize)0);

static bool ascii_equal(const char* a, const char* b)
{
    if (!a || !b) return false;
    while (*a && *b)
    {
        if (*a != *b) return false;
        ++a; ++b;
    }
    return *a == 0 && *b == 0;
}

static wchar_t wide_lower(wchar_t c)
{
    return (c >= L'A' && c <= L'Z') ? (wchar_t)(c + (L'a' - L'A')) : c;
}

static bool wide_name_equal(const wchar_t* a, u16 a_len_bytes, const wchar_t* b)
{
    if (!a || !b) return false;
    u32 n = a_len_bytes / 2;
    u32 i = 0;
    for (; i < n && b[i]; ++i)
        if (wide_lower(a[i]) != wide_lower(b[i])) return false;
    return i == n && b[i] == 0;
}

static u8* get_peb()
{
    return (u8*)__readgsqword(0x60);
}

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
        u8* base = *(u8**)(entry + 0x30);
        u16 name_len = *(u16*)(entry + 0x58);
        wchar_t* name = *(wchar_t**)(entry + 0x60);
        if (base && name && wide_name_equal(name, name_len, wanted)) return base;
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
    pFlushInstructionCache = (FlushInstructionCache_t)resolve_export(kb, "FlushInstructionCache");
    pCreateFileW = (CreateFileW_t)resolve_export(kb, "CreateFileW");
    pWriteFile = (WriteFile_t)resolve_export(kb, "WriteFile");
    pCloseHandle = (CloseHandle_t)resolve_export(kb, "CloseHandle");
    return pVirtualProtect && pFlushInstructionCache && pCreateFileW && pWriteFile && pCloseHandle;
}

static u32 ascii_len(const char* s)
{
    u32 n = 0;
    while (s && s[n]) ++n;
    return n;
}

static u32 wide_len(const wchar_t* s)
{
    u32 n = 0;
    while (s && s[n]) ++n;
    return n;
}

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
    for (u32 guard = 0; node && node != head && guard < 512; ++guard)
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
    for (u32 i = 0; i < n; ++i) temp[i] = full[i];
    temp[n] = 0;
    for (int pass = 0; pass < 2; ++pass)
    {
        n = wide_len(temp);
        int last = -1;
        for (u32 i = 0; i < n; ++i)
            if (temp[i] == L'\\' || temp[i] == L'/') last = (int)i;
        if (last < 0) return false;
        temp[last] = 0;
    }
    const wchar_t suffix[] = L"\\work_suitability_100.log";
    u32 sn = wide_len(suffix);
    n = wide_len(temp);
    if (n + sn + 1 > 1024) return false;
    for (u32 i = 0; i < n; ++i) g_log_path[i] = temp[i];
    for (u32 i = 0; i < sn; ++i) g_log_path[n + i] = suffix[i];
    g_log_path[n + sn] = 0;
    return true;
}

static void clear_log()
{
    if (!pCreateFileW || !pCloseHandle || !g_log_path[0]) return;
    HANDLE h = pCreateFileW(g_log_path, FILE_APPEND_DATA,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h && h != INVALID_HANDLE_VALUE_) pCloseHandle(h);
}

static void log_line(const char* msg)
{
    if (!pCreateFileW || !pWriteFile || !pCloseHandle || !g_log_path[0] || !msg) return;
    HANDLE h = pCreateFileW(g_log_path, FILE_APPEND_DATA,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (!h || h == INVALID_HANDLE_VALUE_) return;
    u32 written = 0;
    pWriteFile(h, msg, ascii_len(msg), &written, nullptr);
    pWriteFile(h, "\r\n", 2, &written, nullptr);
    pCloseHandle(h);
}

static void log_rva(const char* prefix, u32 rva, u32 count)
{
    char buf[128];
    u32 p = 0;
    while (prefix[p] && p < 70) { buf[p] = prefix[p]; ++p; }
    const char* label = " RVA=0x";
    for (u32 i = 0; label[i]; ++i) buf[p++] = label[i];
    const char* hex = "0123456789ABCDEF";
    bool started = false;
    for (int i = 7; i >= 0; --i)
    {
        u8 d = (u8)((rva >> (i * 4)) & 0xF);
        if (d || started || i == 0) { buf[p++] = hex[d]; started = true; }
    }
    const char* cprefix = " COUNT=";
    for (u32 i = 0; cprefix[i]; ++i) buf[p++] = cprefix[i];
    char digs[16]; u32 dn = 0, x = count;
    do { digs[dn++] = (char)('0' + (x % 10)); x /= 10; } while (x && dn < 16);
    while (dn) buf[p++] = digs[--dn];
    buf[p] = 0;
    log_line(buf);
}

static bool mem_equal(const void* a, const void* b, usize n)
{
    const u8* x = (const u8*)a;
    const u8* y = (const u8*)b;
    for (usize i = 0; i < n; ++i) if (x[i] != y[i]) return false;
    return true;
}

static void mem_copy(void* dst, const void* src, usize n)
{
    u8* d = (u8*)dst;
    const u8* s = (const u8*)src;
    for (usize i = 0; i < n; ++i) d[i] = s[i];
}

struct Candidate
{
    u8* fn;
    u32 rva;
    u32 count;
};

static bool is_text_rva(u32 rva, u32 text_rva, u32 text_size)
{
    return rva >= text_rva && rva < text_rva + text_size;
}

static bool get_text_range(u8* base, u32& text_rva, u32& text_size, u32& image_size)
{
    if (!base || *(u16*)base != 0x5A4D) return false;
    u32 pe_off = *(u32*)(base + 0x3C);
    u8* nt = base + pe_off;
    if (*(u32*)nt != 0x00004550) return false;
    u16 section_count = *(u16*)(nt + 6);
    u16 opt_size = *(u16*)(nt + 20);
    u8* opt = nt + 24;
    image_size = *(u32*)(opt + 56);
    u8* sec = nt + 24 + opt_size;
    for (u16 i = 0; i < section_count; ++i)
    {
        u8* s = sec + i * 40;
        char name[9];
        for (u32 j = 0; j < 8; ++j) name[j] = (char)s[j];
        name[8] = 0;
        if (name[0] == '.' && name[1] == 't' && name[2] == 'e' && name[3] == 'x' && name[4] == 't')
        {
            text_rva = *(u32*)(s + 12);
            text_size = *(u32*)(s + 16);
            return text_size != 0 && image_size != 0;
        }
    }
    return false;
}

static u8* find_ascii_string(u8* base, u32 image, const char* wanted, u32& out_rva)
{
    u32 n = ascii_len(wanted);
    if (!base || !wanted || n < 2 || image < n) return nullptr;
    for (u32 r = 0; r + n + 1 <= image; ++r)
    {
        const char* p = (const char*)(base + r);
        bool ok = true;
        for (u32 i = 0; i < n; ++i)
        {
            if (p[i] != wanted[i]) { ok = false; break; }
        }
        if (ok && p[n] == 0)
        {
            out_rva = r;
            return (u8*)p;
        }
    }
    return nullptr;
}

static Candidate* add_candidate(Candidate* list, u32& count, u32 cap, u8* fn, u32 text_rva, u32 text_size, u8* image_base)
{
    if (!fn) return nullptr;
    u32 rva = (u32)(fn - image_base);
    if (!is_text_rva(rva, text_rva, text_size)) return nullptr;
    for (u32 i = 0; i < count; ++i)
    {
        if (list[i].fn == fn)
        {
            ++list[i].count;
            return &list[i];
        }
    }
    if (count >= cap) return nullptr;
    list[count].fn = fn;
    list[count].rva = rva;
    list[count].count = 1;
    ++count;
    return &list[count - 1];
}

static u32 collect_candidates(u8* base, u32 image, u32 text_rva, u32 text_size, const char* name, Candidate* list, u32 cap)
{
    u32 name_rva = 0;
    u8* name_ptr = find_ascii_string(base, image, name, name_rva);
    if (!name_ptr) return 0;
    u32 count = 0;
    u64 want = (u64)(usize)name_ptr;
    for (u32 r = 0x1000; r + 16 <= image; r += 8)
    {
        u64 a = *(u64*)(base + r);
        u64 b = *(u64*)(base + r + 8);
        u8* fn = nullptr;
        if (a == want) fn = (u8*)(usize)b;
        else if (b == want) fn = (u8*)(usize)a;
        if (fn) add_candidate(list, count, cap, fn, text_rva, text_size, base);
    }
    return count;
}

static Candidate* best_candidate(Candidate* list, u32 count)
{
    Candidate* best = nullptr;
    for (u32 i = 0; i < count; ++i)
        if (!best || list[i].count > best->count) best = &list[i];
    return best;
}

static bool writable_patch(u8* address, const u8* bytes, usize n)
{
    u32 old_protect = 0;
    if (!pVirtualProtect(address, n, PAGE_EXECUTE_READWRITE, &old_protect)) return false;
    mem_copy(address, bytes, n);
    pFlushInstructionCache(CURRENT_PROCESS_, address, n);
    u32 ignored = 0;
    pVirtualProtect(address, n, old_protect, &ignored);
    return true;
}

static bool patch_byte(u8* address, u8 expected, u8 value)
{
    if (!address || *address != expected) return false;
    return writable_patch(address, &value, 1) && *address == value;
}

static u32 patch_mov_eax_10(u8* fn, u32 scan)
{
    if (!fn) return 0;
    for (u32 i = 0; i + 5 <= scan; ++i)
    {
        if (fn[i] == 0xB8 && fn[i+1] == 0x0A && fn[i+2] == 0x00 && fn[i+3] == 0x00 && fn[i+4] == 0x00)
        {
            if (patch_byte(fn + i + 1, 0x0A, 0x64)) return 1;
        }
    }
    return 0;
}

static bool short_jcc(u8 b)
{
    return b >= 0x70 && b <= 0x7F;
}

static bool long_jcc(const u8* p)
{
    return p[0] == 0x0F && p[1] >= 0x80 && p[1] <= 0x8F;
}

static u32 patch_compare_10(u8* fn, u32 scan)
{
    if (!fn) return 0;
    u32 patched = 0;
    for (u32 i = 0; i + 4 < scan; ++i)
    {
        if (fn[i] != 0x83) continue;
        u8 modrm = fn[i + 1];
        if (((modrm >> 3) & 7) != 7) continue;
        if (fn[i + 2] != 0x0A) continue;
        bool branch = short_jcc(fn[i + 3]) || long_jcc(fn + i + 3);
        if (!branch) continue;
        if (patch_byte(fn + i + 2, 0x0A, 0x64)) ++patched;
    }
    return patched;
}

static u32 patch_named_function(u8* base, u32 image, u32 text_rva, u32 text_size, const char* name, bool compare_mode)
{
    Candidate candidates[128] = {};
    u32 count = collect_candidates(base, image, text_rva, text_size, name, candidates, 128);
    Candidate* best = best_candidate(candidates, count);
    if (!best) return 0;
    log_rva(name, best->rva, best->count);
    if (compare_mode) return patch_compare_10(best->fn, 512);
    return patch_mov_eax_10(best->fn, 192);
}

static u32 patch_related_rank_checks(u8* base, u32 image, u32 text_rva, u32 text_size)
{
    const char* names[] = {
        "GetWorkSuitabilityRank",
        "GetWorkSuitabilityRankWithCharacterRank",
        "HasWorkSuitabilityRank"
    };
    u32 total = 0;
    for (u32 i = 0; i < 3; ++i)
    {
        Candidate candidates[128] = {};
        u32 count = collect_candidates(base, image, text_rva, text_size, names[i], candidates, 128);
        Candidate* best = best_candidate(candidates, count);
        if (!best) continue;
        log_rva(names[i], best->rva, best->count);
        total += patch_compare_10(best->fn, 512);
    }
    return total;
}

static bool apply_current(u8* base, u32 image)
{
    u32 text_rva = 0, text_size = 0, parsed_image = 0;
    if (!get_text_range(base, text_rva, text_size, parsed_image))
    {
        log_line("[WorkSuitability100 v1.7] ERROR: could not locate .text.");
        return false;
    }
    if (parsed_image < image) image = parsed_image;

    // The current analysis shows these metadata names are present and have
    // multiple native entries. Select the most frequently referenced entry.
    u32 max_patch = patch_named_function(base, image, text_rva, text_size, "WorkSuitabilityMaxRank", false);
    u32 use_patch = patch_named_function(base, image, text_rva, text_size, "CanUseTargetWorkSuitabilityRankUp", true);
    u32 related = 0;
    if (max_patch == 0 && use_patch == 0)
        related = patch_related_rank_checks(base, image, text_rva, text_size);

    u32 total = max_patch + use_patch + related;
    if (total)
    {
        log_line("[WorkSuitability100 v1.7] PATCHED: current rank ceiling checks now accept 100.");
        return true;
    }

    log_line("[WorkSuitability100 v1.7] ERROR: located current native functions but found no patchable level-10 checks.");
    return false;
}

static bool apply_legacy(u8* exe, u32 size)
{
    static const u8 a0[] = {0x44,0x8B,0x88,0x54,0x0F,0x00,0x00};
    static const u8 a1[] = {0x41,0xB9,0x64,0x00,0x00,0x00,0x90};
    static const u8 b0[] = {0x8B,0x88,0x54,0x0F,0x00,0x00};
    static const u8 b1[] = {0xB9,0x64,0x00,0x00,0x00,0x90};
    static const u8 c0[] = {0x3B,0xB8,0x54,0x0F,0x00,0x00};
    static const u8 c1[] = {0x83,0xFF,0x64,0x90,0x90,0x90};
    static const u8 d0[] = {0x39,0x83,0x54,0x0F,0x00,0x00,0x0F,0x8C,0x80,0x00,0x00,0x00};
    static const u8 d1[] = {0x83,0xF8,0x64,0x90,0x90,0x90,0x0F,0x8F,0x80,0x00,0x00,0x00};
    const u8* pats0[] = {a0,b0,c0,d0};
    const u8* pats1[] = {a1,b1,c1,d1};
    const u32 lens[] = {7,6,6,12};
    u8* found[4] = {};
    for (u32 which = 0; which < 4; ++which)
    {
        for (u32 r = 0x1000; r + lens[which] <= size; ++r)
        {
            if (mem_equal(exe + r, pats0[which], lens[which])) { found[which] = exe + r; break; }
        }
        if (!found[which]) return false;
    }
    for (u32 i = 0; i < 4; ++i)
        if (!writable_patch(found[i], pats1[i], lens[i])) return false;
    return true;
}

static bool apply_patch()
{
    u8* exe = get_exe_base();
    if (!exe)
    {
        log_line("[WorkSuitability100 v1.7] ERROR: executable base is unavailable.");
        return false;
    }
    u32 image = 0, text_rva = 0, text_size = 0;
    if (!get_text_range(exe, text_rva, text_size, image))
    {
        log_line("[WorkSuitability100 v1.7] ERROR: invalid Palworld PE image.");
        return false;
    }
    if (apply_current(exe, image)) return true;
    if (apply_legacy(exe, image))
    {
        log_line("[WorkSuitability100 v1.7] Legacy compatibility patches applied.");
        return true;
    }
    return false;
}

extern "C" __declspec(dllexport) int luaopen_WorkSuitability100(void*)
{
    if (g_initialized) return 0;
    g_initialized = true;
    if (!resolve_winapi()) return 0;
    if (!build_log_path()) return 0;
    clear_log();
    log_line("[WorkSuitability100 v1.7] Loaded through Lua package.loadlib.");
    g_patched = apply_patch();
    if (g_patched) log_line("[WorkSuitability100 v1.7] Initialization successful.");
    else log_line("[WorkSuitability100 v1.7] Initialization failed.");
    return 0;
}

extern "C" __declspec(dllexport) int WorkSuitability100Apply(void*)
{
    if (!g_initialized) luaopen_WorkSuitability100(nullptr);
    else if (!g_patched) g_patched = apply_patch();
    return 0;
}

extern "C" BOOL __stdcall DllMain(void* module, u32 reason, void*)
{
    if (reason == 1) g_self_module = module;
    return 1;
}
