$ErrorActionPreference = 'Stop'

$path = Join-Path $PSScriptRoot 'WorkSuitability100_v1_7.cpp'
$source = Get-Content -Raw -LiteralPath $path

$pattern = '(?s)static u32 collect_candidates\(u8\* base, u32 image, u32 text_rva, u32 text_size, const char\* name, Candidate\* list, u32 cap\)\s*\{.*?\n\}\s*\n\s*static Candidate\* best_candidate'

$replacement = @'
static u32 collect_candidates(u8* base, u32 image, u32 text_rva, u32 text_size, const char* name, Candidate* list, u32 cap)
{
    if (!base || !name || !list || cap == 0) return 0;
    u32 total = 0;
    u32 search_from = 0;
    const u32 name_len = ascii_len(name);

    // Match the offline analyzer: inspect every occurrence of the reflected
    // native name, then inspect every byte-aligned QWORD reference to that
    // string and the adjacent QWORD as the native function pointer.
    while (search_from + name_len + 1 <= image)
    {
        u32 name_rva = 0;
        u8* name_ptr = nullptr;
        for (u32 r = search_from; r + name_len + 1 <= image; ++r)
        {
            const char* p = (const char*)(base + r);
            bool ok = true;
            for (u32 i = 0; i < name_len; ++i)
            {
                if (p[i] != name[i]) { ok = false; break; }
            }
            if (ok && p[name_len] == 0)
            {
                name_rva = r;
                name_ptr = (u8*)p;
                break;
            }
        }
        if (!name_ptr) break;
        search_from = name_rva + name_len + 1;

        u64 want = (u64)(usize)name_ptr;
        for (u32 off = 0x1000; off + 8 <= image; ++off)
        {
            u64 value = *(u64*)(base + off);
            if (value != want) continue;

            // The metadata pair can contain the name pointer first or second.
            // Check both adjacent QWORD positions exactly like the analyzer.
            const u32 pair_offsets[2] = { off >= 8 ? off - 8 : off, off };
            for (u32 k = 0; k < 2; ++k)
            {
                u32 pair = pair_offsets[k];
                if (pair + 16 > image) continue;
                u64 a = *(u64*)(base + pair);
                u64 b = *(u64*)(base + pair + 8);
                u8* fn = nullptr;
                if (a == want) fn = (u8*)(usize)b;
                else if (b == want) fn = (u8*)(usize)a;
                if (!fn) continue;
                Candidate* c = add_candidate(list, total, cap, fn, text_rva, text_size, base);
                if (c) c->count += 4;
            }
        }
    }
    return total;
}

static Candidate* best_candidate'@

$updated = [regex]::Replace($source, $pattern, $replacement, 1)
if ($updated -eq $source) { throw 'collect_candidates replacement did not match source.' }
Set-Content -LiteralPath $path -Value $updated -NoNewline -Encoding UTF8
Write-Host 'Patched collect_candidates for exact reflected metadata references.'
