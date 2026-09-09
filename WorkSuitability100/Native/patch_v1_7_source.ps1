$ErrorActionPreference = 'Stop'

$path = Join-Path $PSScriptRoot 'WorkSuitability100_v1_7.cpp'
$source = Get-Content -Raw -LiteralPath $path

# v1.7 already resolves the real native implementations. The remaining failure
# was that the patcher only recognized one encoding of `cmp ..., 10` and only
# searched the first 2048 bytes. Replace that scanner with a conservative
# x64 immediate-compare scanner that understands the common 8/32-bit forms.
$comparePattern = '(?s)static u32 patch_compare_10\(u8\* fn, u32 scan\)\s*\{.*?\n\}\s*\n\s*static u32 patch_mov_eax_10'
$compareReplacement = @'
static u32 patch_compare_10(u8* fn, u32 scan)
{
    if (!fn) return 0;
    u32 patched = 0;

    // Patch only immediates equal to 10 in actual x64 CMP instructions.
    // Supported encodings:
    //   83 /7 ib       cmp r/m32, imm8
    //   81 /7 id       cmp r/m32, imm32
    //   3D id          cmp eax, imm32
    // Optional REX prefixes are handled.  We additionally require a nearby
    // conditional consumer (Jcc/SETcc/CMOVcc) so unrelated constants are not
    // modified.
    for (u32 i = 0; i + 8 < scan; ++i)
    {
        u32 p = i;
        if (fn[p] >= 0x40 && fn[p] <= 0x4F) ++p;

        u32 imm = 0;
        u32 imm_size = 0;
        bool is_cmp = false;

        if (fn[p] == 0x83)
        {
            u8 modrm = fn[p + 1];
            if (((modrm >> 3) & 7) == 7 && fn[p + 2] == 0x0A)
            {
                is_cmp = true;
                imm = 10;
                imm_size = 1;
            }
        }
        else if (fn[p] == 0x81)
        {
            u8 modrm = fn[p + 1];
            if (((modrm >> 3) & 7) == 7 &&
                fn[p + 2] == 0x0A && fn[p + 3] == 0x00 &&
                fn[p + 4] == 0x00 && fn[p + 5] == 0x00)
            {
                is_cmp = true;
                imm = 10;
                imm_size = 4;
            }
        }
        else if (fn[p] == 0x3D &&
                 fn[p + 1] == 0x0A && fn[p + 2] == 0x00 &&
                 fn[p + 3] == 0x00 && fn[p + 4] == 0x00)
        {
            is_cmp = true;
            imm = 10;
            imm_size = 4;
        }

        if (!is_cmp || imm != 10 || !imm_size) continue;

        // Look through the short instruction window for a conditional
        // consumer.  This handles small LEA/MOV/test sequences between the
        // comparison and the branch/conditional operation.
        bool conditional = false;
        u32 end = p + 12;
        if (end > scan) end = scan;
        for (u32 j = p + 2; j + 1 < end; ++j)
        {
            if (fn[j] >= 0x70 && fn[j] <= 0x7F) { conditional = true; break; }
            if (fn[j] == 0x0F && fn[j + 1] >= 0x80 && fn[j + 1] <= 0x8F)
            { conditional = true; break; }
            if (fn[j] >= 0x90 && fn[j] <= 0x9F) { conditional = true; break; }
            if (fn[j] == 0x0F && fn[j + 1] >= 0x40 && fn[j + 1] <= 0x4F)
            { conditional = true; break; }
        }
        if (!conditional) continue;

        u8* imm_ptr = fn + p + (fn[p] == 0x3D ? 1 : 2);
        if (imm_size == 1)
        {
            if (imm_ptr[0] == 0x0A && patch_byte(imm_ptr, 0x0A, 0x64)) ++patched;
        }
        else
        {
            if (imm_ptr[0] == 0x0A && imm_ptr[1] == 0x00 &&
                imm_ptr[2] == 0x00 && imm_ptr[3] == 0x00)
            {
                if (patch_byte(imm_ptr, 0x0A, 0x64)) ++patched;
            }
        }
    }
    return patched;
}

static u32 patch_mov_eax_10'@

$updated = [regex]::Replace($source, $comparePattern, $compareReplacement, 1)
if ($updated -eq $source) { throw 'patch_compare_10 replacement did not match source.' }

# The max-rank implementation can also return the literal 10 directly.
$movPattern = '(?s)static u32 patch_mov_eax_10\(u8\* fn, u32 scan\)\s*\{.*?\n\}\s*\n\s*static u32 resolve_and_patch_name'
$movReplacement = @'
static u32 patch_mov_eax_10(u8* fn, u32 scan)
{
    if (!fn) return 0;
    for (u32 i = 0; i + 5 <= scan; ++i)
    {
        // mov eax,10
        if (fn[i] == 0xB8 && fn[i + 1] == 0x0A &&
            fn[i + 2] == 0x00 && fn[i + 3] == 0x00 && fn[i + 4] == 0x00)
        {
            if (patch_byte(fn + i + 1, 0x0A, 0x64)) return 1;
        }
    }
    return 0;
}

static u32 resolve_and_patch_name'@

$updated2 = [regex]::Replace($updated, $movPattern, $movReplacement, 1)
if ($updated2 -eq $updated) { throw 'patch_mov_eax_10 replacement did not match source.' }

# Give the current native implementation enough room for the inlined cap logic.
$updated2 = $updated2 -replace 'patch_compare_10\(impl, 2048\)', 'patch_compare_10(impl, 8192)'
$updated2 = $updated2 -replace 'patch_mov_eax_10\(impl, 512\)', 'patch_mov_eax_10(impl, 8192)'

Set-Content -LiteralPath $path -Value $updated2 -NoNewline -Encoding UTF8
Write-Host 'Patched WorkSuitability100 v1.8 rank-cap scanner.'
