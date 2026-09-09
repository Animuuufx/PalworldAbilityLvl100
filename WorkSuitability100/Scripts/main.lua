-- WorkSuitability100 v1.7
-- Current Palworld runtime patch loader.
-- The native DLL resolves current UE reflection metadata and patches the
-- rank-10 checks used by work-suitability rank-up handling.

local MOD = "[WorkSuitability100 v1.7]"

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

print(MOD .. " Native rank patcher loaded.\n")
print(MOD .. " Check WorkSuitability100\\work_suitability_100.log for selected native RVAs.\n")
