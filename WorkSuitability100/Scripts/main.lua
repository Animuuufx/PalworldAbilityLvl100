local source = debug.getinfo(1, "S").source
local script = source:sub(1, 1) == "@" and source:sub(2) or source
local root = script:match("^(.*)[\\/]Scripts[\\/]main%.lua$") or "."
local dll = (root .. "/Native/WorkSuitability100.dll"):gsub("\\\\", "/")

local VERSION = "v3.7"
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
    return math.max(1, math.floor((base * factor) + 0.5)), factor
end

local function extend_array(arr, label, field)
    if not arr then
        print("[WorkSuitability100 " .. VERSION .. "] WARNING: " .. label .. " unavailable.")
        return false
    end

    local ok_base, base = pcall(function()
        if field == "DropNumRate" or field == "DamageRate" then
            return tonumber(arr[10][field])
        end
        return tonumber(arr[10])
    end)
    if not ok_base or not base or base <= 0 then
        print("[WorkSuitability100 " .. VERSION .. "] WARNING: " .. label .. " has no valid rank-10 value.")
        return false
    end

    local wrote = 0
    for rank = 11, TARGET_RANK do
        local value = scaled(base, rank)
        local ok_write, err = pcall(function()
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
        if not ok_write then
            print("[WorkSuitability100 " .. VERSION .. "] WARNING: " .. label .. " rank " .. tostring(rank) .. " write failed: " .. tostring(err))
            return false
        end
        wrote = wrote + 1
    end

    local verify_ok, count = pcall(function()
        return tonumber(arr:GetArrayNum())
    end)
    local v47_ok, v47 = pcall(function()
        if field == "DamageRate" or field == "DropNumRate" then
            return tonumber(arr[47][field])
        end
        return tonumber(arr[47])
    end)
    local v100_ok, v100 = pcall(function()
        if field == "DamageRate" or field == "DropNumRate" then
            return tonumber(arr[100][field])
        end
        return tonumber(arr[100])
    end)

    print("[WorkSuitability100 " .. VERSION .. "] " .. label .. " rank10=" .. tostring(base) .. " entries_written=" .. tostring(wrote) .. " array_count=" .. tostring(verify_ok and count or "?") .. " rank47=" .. tostring(v47_ok and v47 or "?") .. " rank100=" .. tostring(v100_ok and v100 or "?"))
    return true
end

local function patch_work_speed(settings)
    local changed = 0

    -- Generic work-speed table. This covers the normal work suitabilities:
    -- Kindling, Watering, Planting, Electricity, Handiwork, Cooling,
    -- Medicine, Transporting, Farming and other entries represented by
    -- WorkSuitabilityDefineDataMap. Animation playback rate is untouched.
    local generic_ok = pcall(function()
        local data = settings.WorkSuitabilityDefineDataMap
        if not data then return end
        data:ForEach(function(key_param, value_param)
            local row_ok, row = pcall(function() return value_param:get() end)
            if row_ok and row and row.CraftSpeeds then
                if extend_array(row.CraftSpeeds, "CraftSpeeds") then
                    changed = changed + 1
                end
            end
            return false
        end)
    end)
    if not generic_ok then
        print("[WorkSuitability " .. VERSION .. "] WARNING: generic work-speed table scan failed.")
    end

    -- Collection/Gathering has an additional rank table controlling the
    -- amount obtained from collection work. Scale that independently while
    -- leaving animation speed alone.
    local collection_ok, collection_err = pcall(function()
        local collection = settings.WorkSuitabilityDefineData_Collection
        if not collection then
            print("[WorkSuitability100 " .. VERSION .. "] WARNING: WorkSuitabilityDefineData_Collection unavailable.")
            return
        end

        if collection.CommonDefineData and collection.CommonDefineData.CraftSpeeds then
            if extend_array(collection.CommonDefineData.CraftSpeeds, "Collection CraftSpeeds") then
                changed = changed + 1
            end
        end

        if collection.CollectionDefineData then
            if extend_array(collection.CollectionDefineData, "Collection DropNumRate", "DropNumRate") then
                changed = changed + 1
            end
        else
            print("[WorkSuitability100 " .. VERSION .. "] WARNING: CollectionDefineData unavailable.")
        end
    end)
    if not collection_ok then
        print("[WorkSuitability100 " .. VERSION .. "] WARNING: Collection patch failed: " .. tostring(collection_err))
    end

    -- Lumbering/Deforest has its own rank data. DamageRate is the actual
    -- amount of tree/resource work performed per work action; changing this
    -- leaves the work animation playback rate untouched.
    local deforest_ok, deforest_err = pcall(function()
        local deforest = settings.WorkSuitabilityDefineData_Deforest
        if not deforest then
            print("[WorkSuitability100 " .. VERSION .. "] WARNING: WorkSuitabilityDefineData_Deforest unavailable.")
            return
        end

        if deforest.CommonDefineData and deforest.CommonDefineData.CraftSpeeds then
            if extend_array(deforest.CommonDefineData.CraftSpeeds, "Deforest CraftSpeeds") then
                changed = changed + 1
            end
        end

        if deforest.DeforestDefineData then
            if extend_array(deforest.DeforestDefineData, "Deforest DamageRate", "DamageRate") then
                changed = changed + 1
            end
        else
            print("[WorkSuitability100 " .. VERSION .. "] WARNING: DeforestDefineData unavailable.")
        end
    end)
    if not deforest_ok then
        print("[WorkSuitability100 " .. VERSION .. "] WARNING: Lumbering/Deforest patch failed: " .. tostring(deforest_err))
    end

    -- Mining has the same special resource-damage structure as Lumbering.
    -- Patch both its generic CraftSpeeds and actual mining DamageRate so the
    -- rank affects ore/resource work rather than only the animation layer.
    local mining_ok, mining_err = pcall(function()
        local mining = settings.WorkSuitabilityDefineData_Mining
        if not mining then
            print("[WorkSuitability100 " .. VERSION .. "] WARNING: WorkSuitabilityDefineData_Mining unavailable.")
            return
        end

        if mining.CommonDefineData and mining.CommonDefineData.CraftSpeeds then
            if extend_array(mining.CommonDefineData.CraftSpeeds, "Mining CraftSpeeds") then
                changed = changed + 1
            end
        end

        if mining.MiningDefineData then
            if extend_array(mining.MiningDefineData, "Mining DamageRate", "DamageRate") then
                changed = changed + 1
            end
        else
            print("[WorkSuitability100 " .. VERSION .. "] WARNING: MiningDefineData unavailable.")
        end
    end)
    if not mining_ok then
        print("[WorkSuitability100 " .. VERSION .. "] WARNING: Mining patch failed: " .. tostring(mining_err))
    end

    print("[WorkSuitability100 " .. VERSION .. "] Work-speed tables patched: " .. tostring(changed))
    return changed
end

ExecuteInGameThread(function()
    local settings = FindFirstOf("PalGameSetting")
    if not settings or not settings:IsValid() then
        print("[WorkSuitability100 " .. VERSION .. "] PalGameSetting not available yet; retrying.")
        ExecuteInGameThread(function()
            settings = FindFirstOf("PalGameSetting")
            if not settings or not settings:IsValid() then
                print("[WorkSuitability100 " .. VERSION .. "] ERROR: PalGameSetting unavailable on retry.")
                return
            end
            local ok_cap, err = pcall(function() settings.WorkSuitabilityMaxRank = TARGET_RANK end)
            if not ok_cap then print("[WorkSuitability100 " .. VERSION .. "] ERROR: rank cap write failed: " .. tostring(err)) end
            print("[WorkSuitability100 " .. VERSION .. "] WorkSuitabilityMaxRank = " .. tostring(settings.WorkSuitabilityMaxRank))
            patch_work_speed(settings)
        end)
        return
    end

    local ok_cap, err = pcall(function() settings.WorkSuitabilityMaxRank = TARGET_RANK end)
    if not ok_cap then print("[WorkSuitability100 " .. VERSION .. "] ERROR: rank cap write failed: " .. tostring(err)) end
    print("[WorkSuitability100 " .. VERSION .. "] WorkSuitabilityMaxRank = " .. tostring(settings.WorkSuitabilityMaxRank))
    patch_work_speed(settings)
end)
