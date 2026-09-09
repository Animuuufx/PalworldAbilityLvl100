-- WorkSuitability100 v1.6
-- Current Palworld compatibility loader.
-- The native DLL handles the current rank-100 compatibility check and
-- retains the legacy byte-patch fallback for older supported binaries.

local MOD = "[WorkSuitability100 v1.6]"

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

print(MOD .. " Native compatibility initializer loaded.\n")
print(MOD .. " Check WorkSuitability100\\work_suitability_100.log for the detected mode.\n")
