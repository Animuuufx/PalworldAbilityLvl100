#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <unordered_set>
#include <algorithm>

using u8 = uint8_t;
using u16 = uint16_t;
using u32 = uint32_t;
using u64 = uint64_t;

static constexpr u32 kRankCap = 100;
static HMODULE g_self = nullptr;
static bool g_initialized = false;
static bool g_patched = false;
static std::wstring g_logPath;

struct Range { u8* begin{}; u32 size{}; u32 rva{}; };
struct Candidate { u8* fn{}; u32 rva{}; u32 hits{}; };
struct PatchStats { u32 changed{}; u32 already{}; };

static void log_line(const std::string& s)
{
    if (g_logPath.empty()) return;
    FILE* f = nullptr;
    _wfopen_s(&f, g_logPath.c_str(), L"ab");
    if (!f) return;
    fwrite(s.data(), 1, s.size(), f);
    fwrite("\r\n", 1, 2, f);
    fclose(f);
}

static bool get_ranges(u8* base, Range& text, u32& image)
{
    if (!base || *reinterpret_cast<u16*>(base) != 0x5A4D) return false;
    u8* nt = base + *reinterpret_cast<u32*>(base + 0x3C);
    if (*reinterpret_cast<u32*>(nt) != 0x00004550) return false;
    u16 n = *reinterpret_cast<u16*>(nt + 6);
    u16 opt = *reinterpret_cast<u16*>(nt + 20);
    u8* oh = nt + 24;
    image = *reinterpret_cast<u32*>(oh + 56);
    u8* sec = oh + opt;
    for (u16 i = 0; i < n; i++) {
        u8* s = sec + i * 40;
        char name[9]{}; memcpy(name, s, 8);
        u32 va = *reinterpret_cast<u32*>(s + 12);
        u32 sz = *reinterpret_cast<u32*>(s + 16);
        if (!strcmp(name, ".text") && sz) {
            text = {base + va, sz, va};
            return true;
        }
    }
    return false;
}

static u8* ascii_string(u8* base, u32 image, const char* name, u32& rva)
{
    size_t n = strlen(name);
    for (u32 i = 0; i + n < image; i++) {
        if (!memcmp(base + i, name, n)) { rva = i; return base + i; }
    }
    return nullptr;
}

static bool in_text(u8* p, const Range& text)
{ return p >= text.begin && p < text.begin + text.size; }

static void add_candidate(std::vector<Candidate>& out, u8* fn, u8* base, const Range& text)
{
    if (!in_text(fn, text)) return;
    u32 rva = (u32)(fn - base);
    for (auto& c : out) if (c.rva == rva) { c.hits++; return; }
    out.push_back({fn, rva, 1});
}

static std::vector<Candidate> collect_candidates(u8* base, u32 image, const Range& text, const char* name)
{
    std::vector<Candidate> out;
    u32 nr = 0;
    u8* np = ascii_string(base, image, name, nr);
    if (!np) return out;
    u64 want = (u64)np;
    for (u32 r = 0x1000; r + 16 <= image; r += 8) {
        u64 a = *reinterpret_cast<u64*>(base + r);
        u64 b = *reinterpret_cast<u64*>(base + r + 8);
        if (a == want) add_candidate(out, (u8*)b, base, text);
        if (b == want) add_candidate(out, (u8*)a, base, text);
    }
    std::sort(out.begin(), out.end(), [](auto& a, auto& b) { return a.hits > b.hits; });
    return out;
}

static u8* resolve_lazy(u8* fn, const Range& text, u8* base)
{
    for (u32 i = 0; i < 96 && i + 7 < text.size; i++) {
        u8* p = fn + i;
        if (p[0] == 0x48 && p[1] == 0x8B && p[2] == 0x05) {
            int32_t d = *reinterpret_cast<int32_t*>(p + 3);
            u8** slot = reinterpret_cast<u8**>(p + 7 + d);
            if (slot && in_text(*slot, text)) return *slot;
        }
    }
    return fn;
}

static bool patch_byte(u8* at, u8 oldv, u8 newv, const char* why, const Range& text, u8* base, PatchStats& st)
{
    if (!at || !in_text(at, text)) return false;
    if (*at == newv) { st.already++; return true; }
    if (*at != oldv) return false;
    DWORD oldp = 0;
    if (!VirtualProtect(at, 1, PAGE_EXECUTE_READWRITE, &oldp)) return false;
    *at = newv;
    DWORD tmp = 0;
    VirtualProtect(at, 1, oldp, &tmp);
    FlushInstructionCache(GetCurrentProcess(), at, 1);
    char buf[256];
    sprintf_s(buf, "[WorkSuitability100 v2.4] PATCH %s RVA=0x%X %02X->%02X", why, (u32)(at - base), oldv, newv);
    log_line(buf);
    st.changed++;
    return true;
}

static u8* rel_target(u8* p)
{
    int32_t d = *reinterpret_cast<int32_t*>(p + 1);
    return p + 5 + d;
}

static u32 modrm_len(u8* p, bool addr64)
{
    u8 m = p[0];
    u32 len = 1;
    u8 mod = m >> 6, rm = m & 7;
    if (mod != 3 && addr64 && rm == 4) {
        u8 sib = p[len++];
        u8 baseReg = sib & 7;
        if (mod == 0 && baseReg == 5) len += 4;
    }
    if (mod == 0 && rm == 5) len += 4;
    else if (mod == 1) len += 1;
    else if (mod == 2) len += 4;
    return len;
}

static u32 insn_len(u8* p)
{
    u32 i = 0;
    while (i < 4) {
        u8 b = p[i];
        if (b == 0xF0 || b == 0xF2 || b == 0xF3 || (b >= 0x66 && b <= 0x67) || (b >= 0x40 && b <= 0x4F)) i++;
        else break;
    }
    u8 op = p[i++];
    if (op == 0x0F) {
        u8 o2 = p[i++];
        if (o2 >= 0x80 && o2 <= 0x8F) return i + 4;
        return i + modrm_len(p + i, true);
    }
    if (op == 0xE8 || op == 0xE9) return i + 4;
    if (op == 0xEB || (op >= 0x70 && op <= 0x7F)) return i + 1;
    if (op == 0xC2) return i + 2;
    if (op == 0xC3 || op == 0xCC) return i;
    if (op == 0x68) return i + 4;
    if (op == 0x6A) return i + 1;
    if (op >= 0xB8 && op <= 0xBF) return i + 4;
    if (op == 0x83) return i + modrm_len(p + i, true) + 1;
    if (op == 0x81) return i + modrm_len(p + i, true) + 4;
    if (op == 0x3D) return i + 4;
    if (op == 0x80 || op == 0x82) return i + modrm_len(p + i, true) + 1;
    if (op == 0x84 || op == 0x85 || op == 0x88 || op == 0x89 || op == 0x8A || op == 0x8B || op == 0x8D || op == 0x8F || op == 0x31 || op == 0x33 || op == 0x39 || op == 0x3B || op == 0x01 || op == 0x03 || op == 0x29 || op == 0x2B || op == 0xC7)
    {
        u32 l = i + modrm_len(p + i, true);
        if (op == 0xC7) l += 4;
        return l;
    }
    if (op == 0xC1) return i + modrm_len(p + i, true) + 1;
    if (op == 0xFF) return i + modrm_len(p + i, true);
    if (op == 0x90 || op == 0x55 || op == 0x53 || op == 0x57 || op == 0x56 || op == 0x5D || op == 0x5F || op == 0x5E || op == 0x5B) return i;
    return i;
}

static PatchStats scan_raw_rank_patterns(u8* fn, u8* base, const Range& text, u32 limit, bool max_fn)
{
    PatchStats st{};
    if (!fn || !in_text(fn, text)) return st;
    u32 max = std::min<u32>(limit, (u32)((text.begin + text.size) - fn));
    for (u32 off = 0; off + 8 < max; off++) {
        u8* p = fn + off;
        u32 pref = 0;
        while (pref < 2 && (p[pref] >= 0x40 && p[pref] <= 0x4F)) pref++;
        u8 o = p[pref];

        if (o == 0x83) {
            u8 modrm = p[pref + 1];
            if (((modrm >> 3) & 7) == 7) {
                u32 ml = modrm_len(p + pref + 1, true);
                u32 io = pref + 1 + ml;
                if (io < max && p[io] == 0x0A) {
                    patch_byte(p + io, 0x0A, 0x64, "raw cmp r/m32,10", text, base, st);
                }
            }
        }

        if (o == 0x81) {
            u8 modrm = p[pref + 1];
            if (((modrm >> 3) & 7) == 7) {
                u32 ml = modrm_len(p + pref + 1, true);
                u32 io = pref + 1 + ml;
                if (io + 3 < max && p[io] == 0x0A && p[io+1] == 0 && p[io+2] == 0 && p[io+3] == 0) {
                    patch_byte(p + io, 0x0A, 0x64, "raw cmp r/m32,10", text, base, st);
                }
            }
        }

        if (o == 0x3D && pref + 4 < max && p[pref + 1] == 0x0A && p[pref + 2] == 0 && p[pref + 3] == 0 && p[pref + 4] == 0) {
            patch_byte(p + pref + 1, 0x0A, 0x64, "raw cmp eax,10", text, base, st);
        }

        if (o >= 0xB8 && o <= 0xBF && pref + 4 < max && p[pref + 1] == 0x0A && p[pref + 2] == 0 && p[pref + 3] == 0 && p[pref + 4] == 0) {
            bool nearRet = false;
            for (u32 j = pref + 5; j < pref + 13 && j < max; j++) {
                if (p[j] == 0xC3 || p[j] == 0xC2) { nearRet = true; break; }
            }
            if (max_fn || nearRet) {
                patch_byte(p + pref + 1, 0x0A, 0x64, "raw mov rank max,10", text, base, st);
            }
        }
    }
    return st;
}

static bool cap_consumer(u8* at, u32 remaining)
{
    u32 n = 0;
    u8* p = at;
    while (n < 32 && n < remaining) {
        u32 l = insn_len(p);
        if (!l || l > 32) return false;
        u8 op = p[0];
        if ((op >= 0x70 && op <= 0x7F) || (op == 0x0F && ((p[1] >= 0x80 && p[1] <= 0x8F) || (p[1] >= 0x40 && p[1] <= 0x4F)))) return true;
        if (op == 0xC3 || op == 0xC2) break;
        p += l;
        n += l;
    }
    return false;
}

static PatchStats scan_function(u8* fn, u8* base, const Range& text, u32 limit, bool max_fn, int depth, std::unordered_set<u32>& visited)
{
    PatchStats st{};
    if (!fn || !in_text(fn, text) || depth > 4) return st;
    u32 start = (u32)(fn - base);
    if (!visited.insert(start).second) return st;

    // Do not stop after the first patch. A single native path can contain
    // multiple independent rank clamps (max-rank return, upgrade gate,
    // result normalization, etc.).
    auto raw = scan_raw_rank_patterns(fn, base, text, std::min<u32>(limit, 8192), max_fn);
    st.changed += raw.changed;
    st.already += raw.already;

    u8* p = fn;
    u32 off = 0;
    while (off + 8 < limit && p + 8 < text.begin + text.size) {
        u32 l = insn_len(p);
        if (!l || l > 32 || off + l > limit) break;
        u8 op = p[0];
        u32 pref = (p[0] >= 0x40 && p[0] <= 0x4F) ? 1 : 0;
        u8 o = p[pref];
        u32 immOff = 0;
        bool cmp10 = false;
        if (o == 0x83 && ((p[pref + 1] >> 3) & 7) == 7) {
            u32 ml = modrm_len(p + pref + 1, true);
            immOff = pref + 1 + ml;
            cmp10 = p[immOff] == 0x0A;
        } else if (o == 0x81 && ((p[pref + 1] >> 3) & 7) == 7) {
            u32 ml = modrm_len(p + pref + 1, true);
            immOff = pref + 1 + ml;
            cmp10 = p[immOff] == 0x0A && p[immOff+1] == 0 && p[immOff+2] == 0 && p[immOff+3] == 0;
        } else if (o == 0x3D) {
            immOff = pref + 1;
            cmp10 = p[immOff] == 0x0A && p[immOff+1] == 0 && p[immOff+2] == 0 && p[immOff+3] == 0;
        }
        if (cmp10 && cap_consumer(p + l, text.begin + text.size - (p + l))) {
            patch_byte(p + immOff, 0x0A, 0x64, "decoded rank cap compare", text, base, st);
        }
        if (o >= 0xB8 && o <= 0xBF && p[pref + 1] == 0x0A && p[pref + 2] == 0 && p[pref + 3] == 0 && p[pref + 4] == 0) {
            if (max_fn || cap_consumer(p + l, text.begin + text.size - (p + l))) {
                patch_byte(p + pref + 1, 0x0A, 0x64, "decoded rank max immediate", text, base, st);
            }
        }
        if (op == 0xE8) {
            u8* t = rel_target(p);
            auto sub = scan_function(t, base, text, 2048, false, depth + 1, visited);
            st.changed += sub.changed; st.already += sub.already;
        }
        if (op == 0xE9 || op == 0xEB) {
            u8* t = (op == 0xE9) ? rel_target(p) : p + 2 + (int8_t)p[1];
            if (in_text(t, text)) {
                auto sub = scan_function(t, base, text, 2048, max_fn, depth + 1, visited);
                st.changed += sub.changed; st.already += sub.already;
            }
        }
        if (op == 0xC3 || op == 0xC2) break;
        off += l;
        p += l;
    }
    return st;
}

static PatchStats patch_named(u8* base, u32 image, const Range& text, const char* name, bool max_fn)
{
    PatchStats total{};
    auto cs = collect_candidates(base, image, text, name);
    char b[256];
    sprintf_s(b, "[WorkSuitability100 v2.4] %s candidates=%zu", name, cs.size());
    log_line(b);
    for (size_t i = 0; i < std::min<size_t>(cs.size(), 12); i++) {
        auto c = cs[i];
        u8* impl = resolve_lazy(c.fn, text, base);
        sprintf_s(b, "[WorkSuitability100 v2.4] %s candidate=0x%X impl=0x%X refs=%u", name, c.rva, (u32)(impl - base), c.hits);
        log_line(b);
        std::unordered_set<u32> visited;
        auto st = scan_function(impl, base, text, 8192, max_fn, 0, visited);
        total.changed += st.changed;
        total.already += st.already;
    }
    return total;
}

static bool apply_patch()
{
    u8* base = (u8*)GetModuleHandleW(nullptr);
    if (!base) return false;
    Range text{}; u32 image = 0;
    if (!get_ranges(base, text, image)) {
        log_line("[WorkSuitability100 v2.4] ERROR: PE/.text discovery failed.");
        return false;
    }
    char b[256];
    sprintf_s(b, "[WorkSuitability100 v2.4] module=%p .text RVA=0x%X size=0x%X image=0x%X", base, text.rva, text.size, image);
    log_line(b);
    PatchStats max = patch_named(base, image, text, "WorkSuitabilityMaxRank", true);
    PatchStats gate = patch_named(base, image, text, "CanUseTargetWorkSuitabilityRankUp", false);
    PatchStats rank = patch_named(base, image, text, "GetWorkSuitabilityRank", false);
    PatchStats rank2 = patch_named(base, image, text, "GetWorkSuitabilityRankWithCharacterRank", false);
    PatchStats has = patch_named(base, image, text, "HasWorkSuitabilityRank", false);
    u32 changed = max.changed + gate.changed + rank.changed + rank2.changed + has.changed;
    u32 already = max.already + gate.already + rank.already + rank2.already + has.already;
    sprintf_s(b, "[WorkSuitability100 v2.4] RESULT changed=%u already100=%u", changed, already);
    log_line(b);
    if (changed >= 1 || (max.already >= 1 && gate.already >= 1)) {
        log_line("[WorkSuitability100 v2.4] Compatibility initialization successful.");
        return true;
    }
    log_line("[WorkSuitability100 v2.4] ERROR: relevant rank logic was found but no validated level-10/100 transition was established.");
    return false;
}

static void init_log()
{
    wchar_t mod[MAX_PATH]{};
    GetModuleFileNameW(g_self, mod, MAX_PATH);
    std::wstring p = mod;
    size_t slash = p.find_last_of(L"\\/");
    if (slash != std::wstring::npos) p.resize(slash);
    g_logPath = p + L"\\WorkSuitability100.log";
    FILE* f = nullptr;
    _wfopen_s(&f, g_logPath.c_str(), L"wb");
    if (f) fclose(f);
}

extern "C" __declspec(dllexport) int luaopen_WorkSuitability100(void*)
{
    if (g_initialized) return 0;
    g_initialized = true;
    init_log();
    log_line("[WorkSuitability100 v2.4] Loaded through Lua package.loadlib.");
    g_patched = apply_patch();
    return 0;
}

extern "C" __declspec(dllexport) int WorkSuitability100Apply(void*)
{
    if (!g_initialized) luaopen_WorkSuitability100(nullptr);
    else if (!g_patched) g_patched = apply_patch();
    return 0;
}

BOOL APIENTRY DllMain(HMODULE h, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH) {
        g_self = h;
        DisableThreadLibraryCalls(h);
    }
    return TRUE;
}
