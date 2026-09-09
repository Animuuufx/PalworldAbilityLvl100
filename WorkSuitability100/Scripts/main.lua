local source = debug.getinfo(1, "S").source
local script = source:sub(1, 1) == "@" and source:sub(2) or source
local root = script:match("^(.*)[\\/]Scripts[\\/]main%.lua$") or "."
local dll = root .. "/Native/WorkSuitability100.dll"
dll = dll:gsub("\\\\", "/")

print("[WorkSuitability100 v2.5] Loading native DLL: " .. dll)

local ok, loader, load_err = pcall(package.loadlib, dll, "luaopen_WorkSuitability100")
if not ok then
    print("[WorkSuitability100 v2.5] ERROR: package.loadlib threw: " .. tostring(loader))
    return
end
if type(loader) ~= "function" then
    print("[WorkSuitability100 v2.5] ERROR: package.loadlib returned no loader: " .. tostring(load_err or loader))
    return
end

local init_ok, init_err = pcall(loader)
if not init_ok then
    print("[WorkSuitability100 v2.5] ERROR: DLL initialization failed: " .. tostring(init_err))
else
    print("[WorkSuitability100 v2.5] Native loader initialized.")
end

local function raise_work_suitability_cap()
    local settings = FindFirstOf("PalGameSetting")
    if not settings or not settings:IsValid() then
        print("[WorkSuitability100 v2.5] PalGameSetting not available yet.")
        return false
    end

    local ok_set, err = pcall(function()
        settings.WorkSuitabilityMaxRank = 100
    end)
    if not ok_set then
        print("[WorkSuitability100 v2.5] ERROR: failed to set WorkSuitabilityMaxRank: " .. tostring(err))
        return false
    end

    local verify_ok, value = pcall(function()
        return settings.WorkSuitabilityMaxRank
    end)
    if verify_ok and tonumber(value) == 100 then
        print("[WorkSuitability100 v2.5] PalGameSetting.WorkSuitabilityMaxRank = 100")
        return true
    end

    print("[WorkSuitability100 v2.5] WARNING: WorkSuitabilityMaxRank write did not verify as 100 (value=" .. tostring(value) .. ")")
    return false
end

ExecuteInGameThread(function()
    if not raise_work_suitability_cap() then
        print("[WorkSuitability100 v2.5] Retrying WorkSuitabilityMaxRank setup after game initialization.")
        ExecuteInGameThread(function()
            raise_work_suitability_cap()
        end)
    end
end)
