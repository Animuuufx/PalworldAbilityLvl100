local source = debug.getinfo(1, "S").source
local script = source:sub(1, 1) == "@" and source:sub(2) or source
local root = script:match("^(.*)[\\/]Scripts[\\/]main%.lua$") or "."
local dll = root .. "/Native/WorkSuitability100.dll"
dll = dll:gsub("\\\\", "/")

local VERSION = "v3.5"
local TARGET_RANK = 100
local SPEED_HOOK = "/Script/Pal.PalIndividualCharacterParameter:GetCraftSpeedByWorkSuitability"
-- Every rank gets its own speed value. Rank 10 = 1x and rank 30 = 100x.
-- Linear progression: each rank above 10 adds 4.95x.
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

local settings = nil
local speed_hook_registered = false
local speed_table_extended = false

local function set_rank_cap(game_settings)
    local ok_set, err = pcall(function()
        game_settings.WorkSuitabilityMaxRank = TARGET_RANK
    end)
    if not ok_set then
        print("[WorkSuitability100 " .. VERSION .. "] ERROR: failed to set WorkSuitabilityMaxRank: " .. tostring(err))
        return false
    end

    local verify_ok, value = pcall(function()
        return game_settings.WorkSuitabilityMaxRank
    end)
    if verify_ok and tonumber(value) == TARGET_RANK then
        print("[WorkSuitability100 " .. VERSION .. "] WorkSuitabilityMaxRank = " .. TARGET_RANK)
        return true
    end

    print("[WorkSuitability100 " .. VERSION .. "] WARNING: WorkSuitabilityMaxRank write did not verify as " .. TARGET_RANK .. " (value=" .. tostring(value) .. ")")
    return false
end

local function scaled_speed(speed10, rank)
    -- Calculate a unique value for EVERY rank from 11 through 100.
    -- Examples: 11=5.95x, 12=10.9x, 20=50.5x, 30=100x, 47=184.15x, 100=446.5x.
    local factor = 1.0 + ((rank - 10) * SPEED_PER_RANK)
    return math.max(1, math.floor((speed10 * factor) + 0.5)), factor
end

local function extend_speed_table()
    if speed_table_extended then
        return true
    end
    if not settings or not settings:IsValid() then
        return false
    end

    local ok_extend, changed = pcall(function()
        local work_map = settings.WorkSuitabilityDefineDataMap
        if not work_map then
            print("[WorkSuitability100 " .. VERSION .. "] WARNING: WorkSuitabilityDefineDataMap unavailable.")
            return 0
        end

        local changed_rows = 0
        work_map:ForEach(function(key_param, value_param)
            local row_ok, row = pcall(function()
                return value_param:get()
            end)
            if not row_ok or row == nil or row.CraftSpeeds == nil then
                return false
            end

            local count_ok, count = pcall(function()
                return tonumber(row.CraftSpeeds:GetArrayNum())
            end)
            if not count_ok or not count or count < 11 then
                return false
            end

            local base_ok, speed10 = pcall(function()
                return tonumber(row.CraftSpeeds[10])
            end)
            if not base_ok or not speed10 or speed10 <= 0 then
                return false
            end

            -- Explicitly populate EVERY rank, not just selected milestones.
            local wrote = 0
            for rank = 11, TARGET_RANK do
                local result = scaled_speed(speed10, rank)
                row.CraftSpeeds[rank] = result
                wrote = wrote + 1
            end

            local set_ok, set_err = pcall(function()
                value_param:set(row)
            end)
            if not set_ok then
                print("[WorkSuitability100 " .. VERSION .. "] WARNING: failed to commit CraftSpeeds row: " .. tostring(set_err))
                return false
            end

            changed_rows = changed_rows + 1
            print("[WorkSuitability100 " .. VERSION .. "] SPEED TABLE EXTENDED: rank10=" .. tostring(speed10) .. " entries=" .. tostring(wrote) .. " rank11=" .. tostring(row.CraftSpeeds[11]) .. " rank20=" .. tostring(row.CraftSpeeds[20]) .. " rank30=" .. tostring(row.CraftSpeeds[30]) .. " rank47=" .. tostring(row.CraftSpeeds[47]) .. " rank100=" .. tostring(row.CraftSpeeds[100]))
            return false
        end)

        return changed_rows
    end)

    if not ok_extend then
        print("[WorkSuitability100 " .. VERSION .. "] ERROR: speed table extension failed: " .. tostring(changed))
        return false
    end

    if tonumber(changed) and tonumber(changed) > 0 then
        speed_table_extended = true
        print("[WorkSuitability100 " .. VERSION .. "] Every work suitability rank 11-100 now has a distinct CraftSpeed value.")
        return true
    end

    print("[WorkSuitability100 " .. VERSION .. "] WARNING: no CraftSpeeds rows were extended.")
    return false
end

local function get_speed10(work_suitability)
    if not settings or not settings:IsValid() then
        return nil
    end

    local find_ok, value = pcall(function()
        local work_map = settings.WorkSuitabilityDefineDataMap
        if not work_map then
            return nil
        end
        return work_map:Find(work_suitability)
    end)
    if not find_ok or value == nil then
        return nil
    end

    local row_ok, row = pcall(function()
        return value:get()
    end)
    if not row_ok or row == nil or row.CraftSpeeds == nil then
        return nil
    end

    local speed_ok, speed10 = pcall(function()
        return tonumber(row.CraftSpeeds[10])
    end)
    if not speed_ok or not speed10 or speed10 <= 0 then
        return nil
    end

    return speed10
end

local function install_speed_hook()
    if speed_hook_registered then
        return true
    end

    if not settings or not settings:IsValid() then
        print("[WorkSuitability100 " .. VERSION .. "] PalGameSetting not available for speed hook yet.")
        return false
    end

    local register_ok, pre_id, post_id = pcall(function()
        local pre, post = RegisterHook(
            SPEED_HOOK,
            function(Context, WorkSuitability)
            end,
            function(Context, WorkSuitability, ReturnValue)
                local ok_calc, scaled = pcall(function()
                    if not Context or not WorkSuitability then
                        return nil
                    end

                    local ws = WorkSuitability:get()
                    if type(ws) ~= "number" then
                        return nil
                    end

                    local rank = tonumber(Context:GetWorkSuitabilityRank(ws))
                    if not rank or rank <= 10 or rank > TARGET_RANK then
                        return nil
                    end

                    local speed10 = get_speed10(ws)
                    if not speed10 then
                        return nil
                    end

                    local result, factor = scaled_speed(speed10, rank)
                    print("[WorkSuitability100 " .. VERSION .. "] SPEED OVERRIDE: ws=" .. tostring(ws) .. " rank=" .. tostring(rank) .. " factor=" .. string.format("%.2f", factor) .. " result=" .. tostring(result))
                    return result
                end)

                if ok_calc then
                    return scaled
                end

                print("[WorkSuitability100 " .. VERSION .. "] ERROR: speed callback failed: " .. tostring(scaled))
                return nil
            end
        )
        return true, pre, post
    end)

    if not register_ok then
        print("[WorkSuitability100 " .. VERSION .. "] ERROR: failed to register speed hook: " .. tostring(pre_id))
        return false
    end

    if not pre_id or not post_id then
        print("[WorkSuitability100 " .. VERSION .. "] ERROR: speed hook registration returned invalid hook IDs.")
        return false
    end

    speed_hook_registered = true
    print("[WorkSuitability100 " .. VERSION .. "] Speed hook registered: " .. SPEED_HOOK)
    print("[WorkSuitability100 " .. VERSION .. "] EVERY-RANK scaling: 10=1x, 11=5.95x, 12=10.9x, 20=50.5x, 30=100x, 47=184.15x, 100=446.5x")
    return true
end

ExecuteInGameThread(function()
    settings = FindFirstOf("PalGameSetting")
    if not settings or not settings:IsValid() then
        print("[WorkSuitability100 " .. VERSION .. "] PalGameSetting not available yet; retrying initialization.")
        ExecuteInGameThread(function()
            settings = FindFirstOf("PalGameSetting")
            if settings and settings:IsValid() then
                set_rank_cap(settings)
                extend_speed_table()
                install_speed_hook()
            else
                print("[WorkSuitability100 " .. VERSION .. "] ERROR: PalGameSetting still unavailable on retry.")
            end
        end)
        return
    end

    set_rank_cap(settings)
    extend_speed_table()
    if not install_speed_hook() then
        ExecuteInGameThread(function()
            extend_speed_table()
            install_speed_hook()
        end)
    end
end)
