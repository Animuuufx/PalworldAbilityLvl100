local source = debug.getinfo(1, "S").source
local script = source:sub(1, 1) == "@" and source:sub(2) or source
local root = script:match("^(.*)[\\/]Scripts[\\/]main%.lua$") or "."
local dll = (root .. "/Native/WorkSuitability100.dll"):gsub("\\\\", "/")

local VERSION = "v4.2"

local function log(msg)
    print("[WorkSuitability100 " .. VERSION .. "] " .. tostring(msg))
end

log("Loading native DLL: " .. dll)

local ok, loader, load_err = pcall(package.loadlib, dll, "luaopen_WorkSuitability100")
if not ok then
    log("ERROR: package.loadlib threw: " .. tostring(loader))
    return
end
if type(loader) ~= "function" then
    log("ERROR: package.loadlib returned no loader: " .. tostring(load_err or loader))
    return
end

local init_ok, init_err = pcall(loader)
if not init_ok then
    log("ERROR: DLL initialization failed: " .. tostring(init_err))
    return
end

-- v4.2 performs no PalGameSetting/TArray/TMap mutation from Lua.
-- It also no longer detours the whole GetCraftSpeedByWorkSuitability native function.
-- The DLL redirects only its validated internal rank->speed lookup call.
log("Native rank + crash-safe work-speed lookup patch initialized. Runtime container mutation is disabled.")
