local source = debug.getinfo(1, "S").source
local script = source:sub(1, 1) == "@" and source:sub(2) or source
local root = script:match("^(.*)[\\/]Scripts[\\/]main%.lua$") or "."
local dll = root .. "/Native/WorkSuitability100.dll"
dll = dll:gsub("\\\\", "/")

local VERSION = "v2.8"
local TARGET_RANK = 100
local SPEED_HOOK = "/Script/Pal.PalIndividualCharacterParameter:GetCraftSpeedByWorkSuitability"

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

local speed_hook_registered = false

local function install_speed_hook()
    if speed_hook_registered then
        return true
    end

    local settings = FindFirstOf("PalGameSetting")
    if not settings or not settings:IsValid() then
        print("[WorkSuitability100 " .. VERSION .. "] PalGameSetting not available for speed hook yet.")
        return false
    end

    local map_ok, work_map = pcall(function()
        return settings.WorkSuitabilityDefineDataMap
    end)
    if not map_ok or work_map == nil then
        print("[WorkSuitability100 " .. VERSION .. "] ERROR: WorkSuitabilityDefineDataMap unavailable for speed hook: " .. tostring(work_map))
        return false
    end

    local function get_speed10(work_suitability)
        local find_ok, value = pcall(function()
            return work_map:Find(work_suitability)
        end)
        if not find_ok or value == nil then
            return nil
        end

        local row_ok, row = pcall(function()
            return value:get()
        end)
        if not row_ok or row == nil then
            return nil
        end

        local speeds = row.CraftSpeeds
        if speeds == nil then
            return nil
        end

        local count_ok, count = pcall(function()
            return speeds:GetArrayNum()
        end)
        if not count_ok or tonumber(count) == nil or tonumber(count) < 11 then
            return nil
        end

        local speed_ok, speed10 = pcall(function()
            return tonumber(speeds[10])
        end)
        if not speed_ok or not speed10 or speed10 <= 0 then
            return nil
        end

        return speed10
    end

    local pre_id, post_id
    local register_ok, register_err = pcall(function()
        pre_id, post_id = RegisterHook(
            SPEED_HOOK,
            function()
                -- The original native function is allowed to execute unchanged.
                -- The post-hook below replaces only its returned speed when rank > 10.
            end,
            function(Context, WorkSuitability, ReturnValue)
                local rank_ok, rank = pcall(function()
                    local value = WorkSuitability and WorkSuitability:get()
                    if type(value) == "number" then
                        return tonumber(Context:GetWorkSuitabilityRank(value))
                    end
                    return nil
                end)

                rank = rank_ok and rank or nil
                if not rank or rank <= 10 or rank > TARGET_RANK then
                    return nil
                end

                local ws_ok, ws = pcall(function()
                    return WorkSuitability and WorkSuitability:get()
                end)
                if not ws_ok or type(ws) ~= "number" then
                    return nil
                end

                local speed10 = get_speed10(ws)
                if not speed10 then
                    print("[WorkSuitability100 " .. VERSION .. "] WARNING: no rank-10 CraftSpeed found for WorkSuitability=" .. tostring(ws))
                    return nil
                end

                local scaled = math.floor((speed10 * rank / 10) + 0.5)
                if scaled < 1 then
                    scaled = 1
                end

                return scaled
            end
        )
    end)

    if not register_ok then
        print("[WorkSuitability100 " .. VERSION .. "] ERROR: failed to register speed hook: " .. tostring(register_err))
        return false
    end

    if not pre_id or not post_id then
        print("[WorkSuitability100 " .. VERSION .. "] ERROR: speed hook registration returned invalid hook IDs.")
        return false
    end

    speed_hook_registered = true
    print("[WorkSuitability100 " .. VERSION .. "] Speed hook registered: " .. SPEED_HOOK)
    print("[WorkSuitability100 " .. VERSION .. "] Rank > 10 speed formula: rank10Speed * rank / 10, capped at rank " .. TARGET_RANK)
    return true
end

ExecuteInGameThread(function()
    local settings = FindFirstOf("PalGameSetting")
    if not settings or not settings:IsValid() then
        print("[WorkSuitability100 " .. VERSION .. "] PalGameSetting not available yet; retrying initialization.")
        ExecuteInGameThread(function()
            local retry_settings = FindFirstOf("PalGameSetting")
            if retry_settings and retry_settings:IsValid() then
                set_rank_cap(retry_settings)
                install_speed_hook()
            else
                print("[WorkSuitability100 " .. VERSION .. "] ERROR: PalGameSetting still unavailable on retry.")
            end
        end)
        return
    end

    set_rank_cap(settings)
    if not install_speed_hook() then
        ExecuteInGameThread(function()
            install_speed_hook()
        end)
    end
end)
