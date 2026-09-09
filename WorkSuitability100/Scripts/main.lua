local source = debug.getinfo(1, "S").source
local script = source:sub(1, 1) == "@" and source:sub(2) or source
local root = script:match("^(.*)[\\/]Scripts[\\/]main%.lua$") or "."
local dll = root .. "/Native/WorkSuitability100.dll"
dll = dll:gsub("\\\\", "/")

local VERSION = "v3.0"
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

    local register_ok, pre_id, post_id = pcall(function()
        local pre, post = RegisterHook(
            SPEED_HOOK,
            function(Context, WorkSuitability)
                -- Intentionally empty. The native function must execute normally.
            end,
            function(Context, WorkSuitability)
                local rank_ok, rank = pcall(function()
                    local value = WorkSuitability and WorkSuitability:get()
                    if type(value) ~= "number" then
                        return nil
                    end
                    return tonumber(Context:GetWorkSuitabilityRank(value))
                end)

                rank = rank_ok and rank or nil
                if not rank or rank <= 10 or rank > TARGET_RANK then
                    return nil
                end

                -- Rank 30 = 20x, with rank 10 = 1x.
                -- Linear growth: factor = 1 + (rank - 10) * 0.95
                local factor = 1.0 + ((rank - 10) * 0.95)
                local original_ok, original = pcall(function()
                    return ReturnValue
                end)
                original = original_ok and tonumber(original) or nil

                -- Get the vanilla rank-10 speed from the settings table when available.
                -- This is deliberately kept independent of TArray growth.
                local speed10 = nil
                local find_ok, value = pcall(function()
                    local work_map = settings.WorkSuitabilityDefineDataMap
                    if not work_map then
                        return nil
                    end
                    return work_map:Find(WorkSuitability:get())
                end)
                if find_ok and value ~= nil then
                    local row_ok, row = pcall(function() return value:get() end)
                    if row_ok and row ~= nil and row.CraftSpeeds ~= nil then
                        local count_ok, count = pcall(function() return row.CraftSpeeds:GetArrayNum() end)
                        if count_ok and tonumber(count) and tonumber(count) >= 11 then
                            local speed_ok, candidate = pcall(function() return tonumber(row.CraftSpeeds[10]) end)
                            if speed_ok and candidate and candidate > 0 then
                                speed10 = candidate
                            end
                        end
                    end
                end

                -- If the table lookup is unavailable, use the native return as the baseline.
                -- At rank 10 vanilla returns the rank-10 speed, so this still scales correctly.
                if not speed10 then
                    speed10 = original
                end

                if not speed10 or speed10 <= 0 then
                    print("[WorkSuitability100 " .. VERSION .. "] WARNING: unable to determine speed baseline for WorkSuitability=" .. tostring(WorkSuitability:get()) .. " rank=" .. tostring(rank))
                    return nil
                end

                local scaled = math.floor((speed10 * factor) + 0.5)
                if scaled < 1 then
                    scaled = 1
                end

                print("[WorkSuitability100 " .. VERSION .. "] SPEED override: WorkSuitability=" .. tostring(WorkSuitability:get()) .. " rank=" .. tostring(rank) .. " baseline=" .. tostring(speed10) .. " factor=" .. string.format("%.2f", factor) .. " result=" .. tostring(scaled))
                return scaled
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
    print("[WorkSuitability100 " .. VERSION .. "] Speed scaling: rank 10 = 1x, rank 30 = 20x, rank 100 = 86.5x")
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
