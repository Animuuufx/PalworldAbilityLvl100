local source = debug.getinfo(1, "S").source
local script = source:sub(1, 1) == "@" and source:sub(2) or source
local root = script:match("^(.*)[\\/]Scripts[\\/]main%.lua$") or "."
local dll = root .. "/../Native/WorkSuitability100.dll"

dll = dll:gsub("\\\\", "/")

local ok, loader = pcall(package.loadlib, dll, "luaopen_WorkSuitability100")
if not ok then
    print("[WorkSuitability100 v2.0] ERROR: package.loadlib failed: " .. tostring(loader))
    return
end

local loaded, err = pcall(loader)
if not loaded then
    print("[WorkSuitability100 v2.0] ERROR: DLL initialization failed: " .. tostring(err))
else
    print("[WorkSuitability100 v2.0] Loader initialized.")
end
