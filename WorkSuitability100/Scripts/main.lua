local source = debug.getinfo(1, "S").source
local script = source:sub(1, 1) == "@" and source:sub(2) or source
local root = script:match("^(.*)[\\/]Scripts[\\/]main%.lua$") or "."
local dll = root .. "/Native/WorkSuitability100.dll"
dll = dll:gsub("\\\\", "/")

local VERSION = "v3.2"
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

local settings = nil
local speed_hook_registered = false

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

    local count_ok, count = pcall(function()
        return row.CraftSpeeds:GetArrayNum()
    end)
    if not count_ok or tonumber(count) == nil or tonumber(count) < 11 then
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
                -- Required native pre-hook. Leave the original function untouched.
            end,
            function(Context, WorkSuitability, ReturnValue)
                print("[WorkSuitability100 " .. VERSION .. "] SPEED HOOK FIRED: wsParam=" .. tostring(WorkSuitability) .. " returnParam=" .. tostring(ReturnValue))

                local ok_calc, scaled = pcall(function()
                    if not Context or not WorkSuitability then
                        print("[WorkSuitability100 " .. VERSION .. "] SPEED HOOK: missing Context or WorkSuitability")
                        return nil
                    end

                    local ws = WorkSuitability:get()
                    local native_speed = nil
                    if ReturnValue then
                        local rv_ok, rv = pcall(function()
                            return tonumber(ReturnValue:get())
                        end)
                        if rv_ok then
                            native_speed = rv
                        end
                    end

                    print("[WorkSuitability100 " .. VERSION .. "] SPEED HOOK ARGS: ws=" .. tostring(ws) .. " native=" .. tostring(native_speed))

                    if type(ws) ~= "number" then
                        print("[WorkSuitability100 " .. VERSION .. "] SPEED HOOK: WorkSuitability:get() was not numeric")
                        return nil
                    end

                    local rank = tonumber(Context:GetWorkSuitabilityRank(ws))
                    print("[WorkSuitability100 " .. VERSION .. "] SPEED HOOK RANK: ws=" .. tostring(ws) .. " rank=" .. tostring(rank))

                    if not rank or rank <= 10 or rank > TARGET_RANK then
                        return nil
                    end

                    local speed10 = get_speed10(ws)
                    if not speed10 then
                        print("[WorkSuitability100 " .. VERSION .. "] WARNING: no rank-10 CraftSpeed found for WorkSuitability=" .. tostring(ws) .. " rank=" .. tostring(rank))
                        return nil
                    end

                    local factor = 1.0 + ((rank - 10) * 0.95)
                    local result = math.floor((speed10 * factor) + 0.5)
                    if result < 1 then
                        result = 1
                    end

                    print("[WorkSuitability100 " .. VERSION .. "] SPEED OVERRIDE: ws=" .. tostring(ws) .. " rank=" .. tostring(rank) .. " vanilla10=" .. tostring(speed10) .. " factor=" .. string.format("%.2f", factor) .. " result=" .. tostring(result))
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
    print("[WorkSuitability100 " .. VERSION .. "] Speed scaling: rank 10 = 1x, rank 30 = 20x, rank 100 = 86.5x")
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
