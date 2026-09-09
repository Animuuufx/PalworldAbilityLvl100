-- WorkSuitability100 v1.4
-- Inventory-crash fix + native real speed scaling for Palworld Steam v1.0.3.101238.
-- Keeps the rank/handbook ceiling at 100 and moves speed scaling out of UE4SS UFunction hooks.

local MOD = "[WorkSuitability100 v1.4]"

local function get_mod_root()
    local source = debug.getinfo(1, "S").source or ""
    source = source:gsub("^@", "")
    return source:gsub("[/\\][Ss]cripts[/\\]main%.lua$", "")
end

local native_path = get_mod_root() .. "\\Native\\WorkSuitability100.dll"

print(MOD .. " Loaded.\n")

if package == nil or package.loadlib == nil then
    print(MOD .. " ERROR: package.loadlib is unavailable.\n")
    return
end

local init_fn, err = package.loadlib(native_path, "luaopen_WorkSuitability100")
if type(init_fn) ~= "function" then
    print(string.format("%s ERROR loading native DLL: %s\n", MOD, tostring(err)))
    return
end

local ok, call_err = pcall(init_fn)
if not ok then
    print(string.format("%s ERROR calling native initializer: %s\n", MOD, tostring(call_err)))
    return
end

print(MOD .. " Native rank + handbook + work-speed patches loaded.\n")
print(MOD .. " No UE4SS craft-speed UFunction hooks are installed.\n")
print(MOD .. " Check WorkSuitability100\\work_suitability_100.log for PATCHED status.\n")
