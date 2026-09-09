local source = debug.getinfo(1, "S").source
local script = source:sub(1, 1) == "@" and source:sub(2) or source
local root = script:match("^(.*)[\\/]Scripts[\\/]main%.lua$") or "."
local dll = (root .. "/Native/WorkSuitability100.dll"):gsub("\\\\", "/")

local VERSION = "v3.8"
local TARGET_RANK = 100
local SPEED_PER_RANK = 4.95

print("[WorkSuitability100 " .. VERSION .. "] Loading native DLL: " .. dll)

local ok, loader, load_err = pcall(package.loadlib, dll, "luaopen_WorkSuitability100")
if not ok then
    print("[WorkSuitability100 " .. VERSION .. "] ERROR: package.loadlib threw: " .. tostring(loader))
    return
end
if type(loader) ~= "function" then
    print("[WorkSuitability100 " .. VERSION .. "] ERROR: package.loadlib returned no loader: " .. tostring(load_err or loader))
    return
end

local init_ok, init_err = pcall(loader)
if not init_ok then
    print("[WorkSuitability100 " .. VERSION .. "] ERROR: DLL initialization failed: " .. tostring(init_err))
    return
end
print("[WorkSuitability100 " .. VERSION .. "] Native loader initialized.")

local function scaled(base, rank)
    local factor = 1.0 + ((rank - 10) * SPEED_PER_RANK)
    return math.max(1, math.floor((base * factor) + 0.5))
end

local function extend_array(arr, label, field)
    if not arr then return false end
    local ok_base, base = pcall(function()
        if field == "DropNumRate" or field == "DamageRate" then
            return tonumber(arr[10][field])
        end
        return tonumber(arr[10])
    end)
    if not ok_base or not base or base <= 0 then return false end

    local wrote = 0
    for rank = 11, TARGET_RANK do
        local value = scaled(base, rank)
        local ok_write = pcall(function()
            if field == "DamageRate" or field == "DropNumRate" then
                local entry = arr[rank]
                if entry ~= nil then
                    entry[field] = value
                    arr[rank] = entry
                else
                    arr[rank] = { [field] = value }
                end
            else
                arr[rank] = value
            end
        end)
        if not ok_write then break end
        wrote = wrote + 1
    end
    print("[WorkSuitability100 " .. VERSION .. "] " .. label .. " rank10=" .. tostring(base) .. " entries_written=" .. tostring(wrote))
    return wrote == 90
end

local function patch_work_speed(settings)
    local changed = 0

    pcall(function()
        local data = settings.WorkSuitabilityDefineDataMap
        if not data then return end
        data:ForEach(function(_, value_param)
            local ok_row, row = pcall(function() return value_param:get() end)
            if ok_row and row and row.CraftSpeeds and extend_array(row.CraftSpeeds, "CraftSpeeds") then
                changed = changed + 1
            end
            return false
        end)
    end)

    local special = {
        {"WorkSuitabilityDefineData_Collection", "Collection", "CollectionDefineData", "DropNumRate"},
        {"WorkSuitabilityDefineData_Deforest", "Deforest", "DeforestDefineData", "DamageRate"},
        {"WorkSuitabilityDefineData_Mining", "Mining", "MiningDefineData", "DamageRate"}
    }

    for _, item in ipairs(special) do
        pcall(function()
            local data = settings[item[1]]
            if not data then return end
            if data.CommonDefineData and data.CommonDefineData.CraftSpeeds then
                if extend_array(data.CommonDefineData.CraftSpeeds, item[2] .. " CraftSpeeds") then changed = changed + 1 end
            end
            if data[item[3]] then
                if extend_array(data[item[3]], item[2] .. " " .. item[4], item[4]) then changed = changed + 1 end
            end
        end)
    end

    print("[WorkSuitability100 " .. VERSION .. "] Work-speed tables patched: " .. tostring(changed))
end

ExecuteInGameThread(function()
    local settings = FindFirstOf("PalGameSetting")
    if not settings or not settings:IsValid() then
        print("[WorkSuitability100 " .. VERSION .. "] ERROR: PalGameSetting unavailable.")
        return
    end

    local ok_cap, err = pcall(function() settings.WorkSuitabilityMaxRank = TARGET_RANK end)
    if not ok_cap then
        print("[WorkSuitability100 " .. VERSION .. "] ERROR: rank cap write failed: " .. tostring(err))
    end
    print("[WorkSuitability100 " .. VERSION .. "] WorkSuitabilityMaxRank = " .. tostring(settings.WorkSuitabilityMaxRank))
    patch_work_speed(settings)
end)
