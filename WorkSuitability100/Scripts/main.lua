local source = debug.getinfo(1, "S").source
local script = source:sub(1, 1) == "@" and source:sub(2) or source
local root = script:match("^(.*)[\\/]Scripts[\\/]main%.lua$") or "."
local dll = root .. "/Native/WorkSuitability100.dll"
dll = dll:gsub("\\\\", "/")

print("[WorkSuitability100 v2.2] Loading native DLL: " .. dll)

local ok, loader, load_err = pcall(package.loadlib, dll, "luaopen_WorkSuitability100")
if not ok then
    print("[WorkSuitability100 v2.2] ERROR: package.loadlib threw: " .. tostring(loader))
    return
end
if type(loader) ~= "function" then
    print("[WorkSuitability100 v2.2] ERROR: package.loadlib returned no loader: " .. tostring(load_err or loader))
    return
end

local init_ok, init_err = pcall(loader)
if not init_ok then
    print("[WorkSuitability100 v2.2] ERROR: DLL initialization failed: " .. tostring(init_err))
else
    print("[WorkSuitability100 v2.2] Native loader initialized.")
end
