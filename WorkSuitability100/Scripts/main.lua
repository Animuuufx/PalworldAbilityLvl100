local source = debug.getinfo(1, "S").source
local script = source:sub(1, 1) == "@" and source:sub(2) or source
local root = script:match("^(.*)[\\/]Scripts[\\/]main%.lua$") or "."
local dll = root .. "/Native/WorkSuitability100.dll"
dll = dll:gsub("\\\\", "/")

local VERSION = "v2.7"
local TARGET_RANK = 100

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
else
    print("[WorkSuitability100 " .. VERSION .. "] Native loader initialized.")
end

local function set_rank_cap(settings)
    local ok_set, err = pcall(function()
        settings.WorkSuitabilityMaxRank = TARGET_RANK
    end)
    if not ok_set then
        print("[WorkSuitability100 " .. VERSION .. "] ERROR: failed to set WorkSuitabilityMaxRank: " .. tostring(err))
        return false
    end

    local verify_ok, value = pcall(function()
        return settings.WorkSuitabilityMaxRank
    end)
    if verify_ok and tonumber(value) == TARGET_RANK then
        print("[WorkSuitability100 " .. VERSION .. "] WorkSuitabilityMaxRank = " .. TARGET_RANK)
        return true
    end

    print("[WorkSuitability100 " .. VERSION .. "] WARNING: WorkSuitabilityMaxRank write did not verify as " .. TARGET_RANK .. " (value=" .. tostring(value) .. ")")
    return false
end

local function extend_speed_table(row, label)
    local speeds = row.CraftSpeeds
    if speeds == nil then
        print("[WorkSuitability100 " .. VERSION .. "] WARNING: " .. label .. " has no CraftSpeeds array.")
        return false
    end

    local count_ok, count = pcall(function()
        return speeds:GetArrayNum()
    end)
    if not count_ok then
        print("[WorkSuitability100 " .. VERSION .. "] WARNING: could not read CraftSpeeds size for " .. label .. ".")
        return false
    end

    count = tonumber(count) or 0
    if count <= 0 then
        print("[WorkSuitability100 " .. VERSION .. "] WARNING: " .. label .. " CraftSpeeds is empty.")
        return false
    end

    local speed10 = tonumber(speeds[math.min(10, count - 1)]) or 0
    if speed10 <= 0 then
        print("[WorkSuitability100 " .. VERSION .. "] WARNING: " .. label .. " has invalid rank-10 speed=" .. tostring(speed10) .. ".")
        return false
    end

    print("[WorkSuitability100 " .. VERSION .. "] " .. label .. " CraftSpeeds entries=" .. count .. ", rank10=" .. tostring(speed10))

    -- UE4SS TArray supports indexed reads/writes, but __newindex cannot grow
    -- the array beyond Num. Only write existing entries here; growth is handled
    -- separately below when the array has spare capacity.
    if count >= TARGET_RANK + 1 then
        print("[WorkSuitability100 " .. VERSION .. "] " .. label .. " CraftSpeeds already has " .. count .. " entries.")
        return true
    end

    local max_ok, max_count = pcall(function()
        return speeds:GetArrayMax()
    end)
    max_count = max_ok and (tonumber(max_count) or 0) or 0

    if max_count < TARGET_RANK + 1 then
        print("[WorkSuitability100 " .. VERSION .. "] WARNING: " .. label .. " CraftSpeeds capacity=" .. max_count .. " cannot be grown through Lua indexing.")
        return false
    end

    for rank = count, TARGET_RANK do
        local speed = math.floor((speed10 * rank / 10) + 0.5)
        local ok_write, write_err = pcall(function()
            speeds[rank] = speed
        end)
        if not ok_write then
            print("[WorkSuitability100 " .. VERSION .. "] ERROR: failed writing " .. label .. " rank " .. rank .. ": " .. tostring(write_err))
            return false
        end
    end

    print("[WorkSuitability100 " .. VERSION .. "] " .. label .. " CraftSpeeds extended to rank " .. TARGET_RANK)
    return true
end

local function extend_work_suitability_speeds()
    local settings = FindFirstOf("PalGameSetting")
    if not settings or not settings:IsValid() then
        print("[WorkSuitability100 " .. VERSION .. "] PalGameSetting not available yet.")
        return false
    end

    set_rank_cap(settings)

    local map_ok, work_map = pcall(function()
        return settings.WorkSuitabilityDefineDataMap
    end)
    if not map_ok or work_map == nil then
        print("[WorkSuitability100 " .. VERSION .. "] ERROR: WorkSuitabilityDefineDataMap is unavailable: " .. tostring(work_map))
        return false
    end

    local map_count_ok, map_count = pcall(function()
        return #work_map
    end)
    if map_count_ok then
        print("[WorkSuitability100 " .. VERSION .. "] WorkSuitabilityDefineDataMap entries=" .. tostring(map_count))
    end

    local touched = 0
    local failed = 0

    local foreach_ok, foreach_err = pcall(function()
        work_map:ForEach(function(key, value)
            local row_ok, row_or_err = pcall(function()
                return value:get()
            end)
            if not row_ok or row_or_err == nil then
                failed = failed + 1
                print("[WorkSuitability100 " .. VERSION .. "] WARNING: failed to read WorkSuitabilityDefineDataMap row: " .. tostring(row_or_err))
                return false
            end

            local row = row_or_err
            local label = "WorkSuitability"
            local key_ok, key_name = pcall(function()
                local k = key:get()
                if k and k.ToString then
                    return k:ToString()
                end
                return tostring(k)
            end)
            if key_ok and key_name and key_name ~= "" then
                label = key_name
            end

            local row_success = extend_speed_table(row, label)
            if row_success then
                local set_ok, set_err = pcall(function()
                    value:set(row)
                end)
                if not set_ok then
                    failed = failed + 1
                    print("[WorkSuitability100 " .. VERSION .. "] ERROR: failed to write updated " .. label .. " row: " .. tostring(set_err))
                    return false
                end
                touched = touched + 1
            else
                failed = failed + 1
            end

            return false
        end)
    end)

    if not foreach_ok then
        print("[WorkSuitability100 " .. VERSION .. "] ERROR: WorkSuitabilityDefineDataMap iteration failed: " .. tostring(foreach_err))
        return false
    end

    print("[WorkSuitability100 " .. VERSION .. "] Speed-table initialization complete. rows_updated=" .. touched .. " rows_failed=" .. failed)
    return touched > 0 and failed == 0
end

ExecuteInGameThread(function()
    local ok_setup = extend_work_suitability_speeds()
    if not ok_setup then
        print("[WorkSuitability100 " .. VERSION .. "] Retrying speed-table setup after game initialization.")
        ExecuteInGameThread(function()
            extend_work_suitability_speeds()
        end)
    end
end)
