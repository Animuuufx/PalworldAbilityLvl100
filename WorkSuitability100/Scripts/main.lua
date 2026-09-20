local source = debug.getinfo(1, "S").source
local script = source:sub(1, 1) == "@" and source:sub(2) or source
local root = script:match("^(.*)[\\/]Scripts[\\/]main%.lua$") or "."
local dll = (root .. "/Native/WorkSuitability100.dll"):gsub("\\\\", "/")

local VERSION = "v4.2.1"
local TARGET_RANK = 100

-- Rank 30 remains around 100x rank-10 throughput.
-- Rank 100 reaches 100,000x so end-game work is effectively instant
-- without pushing returned int32 craft-speed values near overflow.
local MAX_CRAFT_SPEED = 1000000000
local MAX_RESOURCE_RATE = 10000000
local MAX_COLLECTION_YIELD_FACTOR = 500.0
local MAX_PROGRESS_AMOUNT = 100000000.0
local RECENT_CRAFT_SCALE_SECONDS = 0.75
local MULTITYPE_PROGRESS_HOOK = "/Script/Pal.PalWorkProgressMultiType:AddProgressForWorkType"

local CRAFT_HOOKS = {
    {
        -- A large part of the live work system (including newer production
        -- buildings) asks the actor component for work speed instead of
        -- calling UPalIndividualCharacterParameter directly.
        path = "/Script/Pal.PalCharacterParameterComponent:GetCraftSpeed_WorkSuitability",
        label = "Component:GetCraftSpeed_WorkSuitability",
        explicit_suitability = true,
    },
    {
        path = "/Script/Pal.PalIndividualCharacterParameter:GetCraftSpeedByWorkSuitability",
        label = "GetCraftSpeedByWorkSuitability",
        explicit_suitability = true,
    },
    {
        path = "/Script/Pal.PalIndividualCharacterParameter:GetCraftSpeed_withBuff_WorkSuitability",
        label = "GetCraftSpeed_withBuff_WorkSuitability",
        explicit_suitability = true,
    },
    {
        path = "/Script/Pal.PalIndividualCharacterParameter:GetCraftSpeed",
        label = "GetCraftSpeed",
        explicit_suitability = false,
    },
    {
        path = "/Script/Pal.PalIndividualCharacterParameter:GetCraftSpeed_withBuff",
        label = "GetCraftSpeed_withBuff",
        explicit_suitability = false,
    },
}

local RESOURCE_HOOKS = {
    {
        path = "/Script/Pal.PalGameSetting:GetMiningDamageRate",
        label = "MiningDamageRate",
        source = "Mining",
        field = "DamageRate",
    },
    {
        path = "/Script/Pal.PalGameSetting:GetDeforestDamageRate",
        label = "DeforestDamageRate",
        source = "Deforest",
        field = "DamageRate",
    },
    {
        path = "/Script/Pal.PalGameSetting:GetCollectionDropNumRate",
        label = "CollectionDropNumRate",
        source = "Collection",
        field = "DropNumRate",
        yield_hook = true,
    },
}

local settings = nil
local registered = {}
local craft_stack = {}
local logged_scale = {}
local recent_craft_scale = {}

local function unwrap(value)
    if value == nil then return nil end

    local ok, result = pcall(function()
        if value.get then return value:get() end
        if value.Get then return value:Get() end
        return value
    end)

    if ok then return result end
    return value
end

local function to_number(value)
    value = unwrap(value)
    if value == nil then return nil end

    local direct = tonumber(value)
    if direct ~= nil then return direct end

    local ok, text_value = pcall(function() return tostring(value) end)
    if ok then return tonumber(text_value) end
    return nil
end

local function is_valid(value)
    value = unwrap(value)
    if value == nil then return false end

    local ok, valid = pcall(function()
        if value.IsValid then return value:IsValid() end
        return true
    end)

    return ok and valid ~= false
end

local function turbo_factor(rank)
    rank = tonumber(rank)
    if not rank or rank <= 10 then return 1.0 end

    rank = math.min(TARGET_RANK, math.max(10, rank))

    -- 10 -> 1x
    -- 20 -> 10x
    -- 30 -> 100x
    if rank <= 30 then
        return 10 ^ ((rank - 10) / 10)
    end

    -- Continue smoothly from 100x at rank 30 to 100,000x at rank 100.
    return 100 * (10 ^ (3 * (rank - 30) / 70))
end

local function scaled_number(base, rank, cap)
    base = tonumber(base)
    rank = tonumber(rank)
    if not base or base <= 0 or not rank or rank <= 10 then return nil end

    local value = base * turbo_factor(rank)
    if cap and value > cap then value = cap end
    if value < 1 then value = 1 end
    return value
end

local function current_settings()
    if settings and is_valid(settings) then return settings end

    local ok, found = pcall(function() return FindFirstOf("PalGameSetting") end)
    if ok and found and is_valid(found) then
        settings = found
        return settings
    end

    return nil
end

local runtime_ready = false

local function is_runtime_ready()
    if runtime_ready then return true end

    -- CharacterParameterComponent speed functions are also called while a save
    -- is being reconstructed. Do not inspect those partially initialized
    -- objects. Once the local player character exists, normal world work has
    -- started and the component path is safe to scale.
    local ok, player = pcall(function()
        return FindFirstOf("PalPlayerCharacter")
    end)

    if ok and player and is_valid(player) then
        runtime_ready = true
        print("[WorkSuitability100 " .. VERSION .. "] Runtime world ready; component scaling enabled.")
        return true
    end

    return false
end

local function character_parameter_from_context(context)
    local target = unwrap(context)
    if not target then return nil end

    -- UPalCharacterParameterComponent is the path used by a number of actual
    -- work implementations. Resolve it back to the underlying individual
    -- parameter so rank > 10 can be read correctly.
    local ok_get, parameter = pcall(function()
        local fn = target.GetIndividualParameter
        if type(fn) == "function" then
            return fn(target)
        end
        return nil
    end)
    parameter = ok_get and unwrap(parameter) or nil
    if parameter and is_valid(parameter) then
        return parameter
    end

    local ok_prop, property_value = pcall(function()
        return target.IndividualParameter
    end)
    property_value = ok_prop and unwrap(property_value) or nil
    if property_value and is_valid(property_value) then
        return property_value
    end

    return target
end

local function effective_rank(context, suitability)
    local target = character_parameter_from_context(context)
    local ws = to_number(suitability)
    if not target or ws == nil then return nil end

    local getters = {
        "GetWorkSuitabilityRankWithCharacterRank",
        "GetWorkSuitabilityRank",
    }

    for _, method in ipairs(getters) do
        local ok, value = pcall(function()
            local fn = target[method]
            if type(fn) ~= "function" then return nil end
            return fn(target, ws)
        end)

        local rank = ok and to_number(value) or nil
        if rank ~= nil then
            return math.min(TARGET_RANK, math.max(0, math.floor(rank)))
        end
    end

    return nil
end

local function current_suitability(context)
    local target = character_parameter_from_context(context)
    if not target then return nil end

    local ok, value = pcall(function()
        return target:GetCurrentWorkSuitability()
    end)

    if not ok then return nil end
    return to_number(value)
end

local function rank10_craft_speed(suitability)
    local game_settings = current_settings()
    local ws = to_number(suitability)
    if not game_settings or ws == nil then return nil end

    local ok, speed = pcall(function()
        local data_map = game_settings.WorkSuitabilityDefineDataMap
        if not data_map then return nil end

        local row_param = data_map:Find(ws)
        if row_param == nil then return nil end

        local row = unwrap(row_param)
        if not row or not row.CraftSpeeds then return nil end

        return to_number(row.CraftSpeeds[10])
    end)

    if ok then return speed end
    return nil
end

local function object_key(value)
    local object = unwrap(value)
    if not object then return "<nil>" end

    local ok, name = pcall(function() return object:GetFullName() end)
    if ok and name then return tostring(name) end
    return tostring(object)
end

local function recent_key(character_parameter, suitability)
    local normalized = character_parameter_from_context(character_parameter)
    return object_key(normalized) .. "|" .. tostring(to_number(suitability))
end

local function mark_recent_craft_scale(character_parameter, suitability)
    recent_craft_scale[recent_key(character_parameter, suitability)] = os.clock()
end

local function was_recently_craft_scaled(character_parameter, suitability)
    local key = recent_key(character_parameter, suitability)
    local when = recent_craft_scale[key]
    if not when then return false end

    local age = os.clock() - when
    if age < 0 or age > RECENT_CRAFT_SCALE_SECONDS then
        recent_craft_scale[key] = nil
        return false
    end

    return true
end

local function log_scale_once(label, suitability, rank, base, result)
    local key = tostring(label) .. "|" .. tostring(suitability) .. "|" .. tostring(rank)
    if logged_scale[key] then return end
    logged_scale[key] = true

    print(
        "[WorkSuitability100 " .. VERSION .. "] " ..
        tostring(label) ..
        " active: suitability=" .. tostring(suitability) ..
        " rank=" .. tostring(rank) ..
        " base=" .. tostring(base) ..
        " factor=" .. string.format("%.2f", turbo_factor(rank)) ..
        " result=" .. tostring(result)
    )
end

local function craft_pre(label)
    table.insert(craft_stack, {
        label = label,
        scaled_child = false,
    })
end

local function finish_craft_frame()
    local frame = table.remove(craft_stack)
    local parent = craft_stack[#craft_stack]
    return frame, parent
end

local function scale_craft_result(context, suitability, return_value, label)
    local frame, parent = finish_craft_frame()

    -- The component path is hit during save reconstruction, before its
    -- IndividualParameter is safe to dereference. Ignore it until the local
    -- player exists; this prevents load-save crashes while keeping the live
    -- work hook available once gameplay begins.
    if tostring(label):sub(1, 10) == "Component:" and not is_runtime_ready() then
        return nil
    end

    -- If a nested craft-speed function already produced the turbo value,
    -- leave the outer function alone. This is important for newer buildings
    -- that combine multiple suitability-speed calls (Ancient Furnace, etc.).
    if frame and frame.scaled_child then
        if parent then parent.scaled_child = true end
        return nil
    end

    local ws = to_number(suitability)
    if ws == nil then
        ws = current_suitability(context)
    end
    if ws == nil then return nil end

    local rank = effective_rank(context, ws)
    if not rank or rank <= 10 then return nil end

    local native = to_number(return_value)
    local rank10 = rank10_craft_speed(ws)

    -- Prefer the native value when it is sane because it can already include
    -- Pal/passive/base-camp modifiers. Fall back to the rank-10 table when the
    -- native path returns zero because the original table ends at rank 10.
    local base = native
    if not base or base <= 0 then base = rank10 end
    if not base or base <= 0 then return nil end

    -- If the native value is clearly an outlier compared with the rank-10
    -- table, use the stable rank-10 baseline instead.
    if rank10 and rank10 > 0 and base > (rank10 * 64) then
        base = rank10
    end

    local result = scaled_number(base, rank, MAX_CRAFT_SPEED)
    if not result then return nil end
    result = math.floor(result + 0.5)

    if parent then parent.scaled_child = true end
    mark_recent_craft_scale(context, ws)
    log_scale_once(label, ws, rank, base, result)
    return result
end

local function register_craft_hook(def)
    if registered[def.path] then return true end

    local ok, pre_id, post_id = pcall(function()
        if def.explicit_suitability then
            return RegisterHook(
                def.path,
                function(Context, WorkSuitability)
                    craft_pre(def.label)
                    return nil
                end,
                function(Context, WorkSuitability, ReturnValue)
                    local ok_scale, result = pcall(
                        scale_craft_result,
                        Context,
                        WorkSuitability,
                        ReturnValue,
                        def.label
                    )
                    if ok_scale then return result end

                    -- Always unwind the stack if the callback failed before
                    -- scale_craft_result could remove its frame.
                    if craft_stack[#craft_stack] and craft_stack[#craft_stack].label == def.label then
                        table.remove(craft_stack)
                    end

                    print("[WorkSuitability100 " .. VERSION .. "] ERROR: " .. def.label .. " callback failed: " .. tostring(result))
                    return nil
                end
            )
        end

        return RegisterHook(
            def.path,
            function(Context)
                craft_pre(def.label)
                return nil
            end,
            function(Context, ReturnValue)
                local ok_scale, result = pcall(
                    scale_craft_result,
                    Context,
                    nil,
                    ReturnValue,
                    def.label
                )
                if ok_scale then return result end

                if craft_stack[#craft_stack] and craft_stack[#craft_stack].label == def.label then
                    table.remove(craft_stack)
                end

                print("[WorkSuitability100 " .. VERSION .. "] ERROR: " .. def.label .. " callback failed: " .. tostring(result))
                return nil
            end
        )
    end)

    if not ok or not pre_id or not post_id then
        print("[WorkSuitability100 " .. VERSION .. "] WARNING: hook unavailable: " .. def.path .. " (" .. tostring(pre_id) .. ")")
        return false
    end

    registered[def.path] = { pre = pre_id, post = post_id }
    print("[WorkSuitability100 " .. VERSION .. "] Hook registered: " .. def.label)
    return true
end

local function rank10_resource_value(source, field)
    local game_settings = current_settings()
    if not game_settings then return nil end

    local ok, value = pcall(function()
        local container = nil
        local array = nil

        if source == "Mining" then
            container = game_settings.WorkSuitabilityDefineData_Mining
            array = container and container.MiningDefineData
        elseif source == "Deforest" then
            container = game_settings.WorkSuitabilityDefineData_Deforest
            array = container and container.DeforestDefineData
        elseif source == "Collection" then
            container = game_settings.WorkSuitabilityDefineData_Collection
            array = container and container.CollectionDefineData
        end

        if not array then return nil end

        local entry = unwrap(array[10])
        if not entry then return nil end
        return to_number(entry[field])
    end)

    if ok then return value end
    return nil
end

local function register_resource_hook(def)
    if registered[def.path] then return true end

    local ok, pre_id, post_id = pcall(function()
        return RegisterHook(
            def.path,
            function(Context, Rank)
                return nil
            end,
            function(Context, Rank, ReturnValue)
                local ok_scale, result = pcall(function()
                    local rank = to_number(Rank)
                    if not rank or rank <= 10 then return nil end
                    rank = math.min(TARGET_RANK, math.max(0, math.floor(rank)))

                    local base = rank10_resource_value(def.source, def.field)
                    if not base or base <= 0 then
                        base = to_number(ReturnValue)
                    end
                    if not base or base <= 0 then return nil end

                    local factor = turbo_factor(rank)
                    if def.yield_hook then
                        -- Gathering speed is handled by the craft-speed hooks.
                        -- Limit item-quantity multiplication so rank 100 does
                        -- not try to spawn absurd numbers of loose items.
                        factor = math.min(factor, MAX_COLLECTION_YIELD_FACTOR)
                    end

                    local scaled = base * factor
                    if scaled > MAX_RESOURCE_RATE then scaled = MAX_RESOURCE_RATE end
                    if scaled < 1 then scaled = 1 end

                    log_scale_once(def.label, def.source, rank, base, scaled)
                    return scaled
                end)

                if ok_scale then return result end
                print("[WorkSuitability100 " .. VERSION .. "] ERROR: " .. def.label .. " callback failed: " .. tostring(result))
                return nil
            end
        )
    end)

    if not ok or not pre_id or not post_id then
        print("[WorkSuitability100 " .. VERSION .. "] WARNING: hook unavailable: " .. def.path .. " (" .. tostring(pre_id) .. ")")
        return false
    end

    registered[def.path] = { pre = pre_id, post = post_id }
    print("[WorkSuitability100 " .. VERSION .. "] Hook registered: " .. def.label)
    return true
end

local function max_assigned_rank_for_work(context, suitability)
    local work = unwrap(context)
    local ws = to_number(suitability)
    if not work or ws == nil then return nil, false, 0 end

    local best_rank = nil
    local recently_scaled = false
    local matched_workers = 0

    local ok, err = pcall(function()
        local rep = work.AssignRepInfoArray
        local items = rep and rep.Items
        if not items then return end

        items:ForEach(function(_, entry_param)
            local entry = unwrap(entry_param)
            local assign = entry and unwrap(entry.WorkAssign) or nil
            if not assign or not is_valid(assign) then return false end

            local assign_ws = nil
            pcall(function()
                assign_ws = to_number(assign:GetWorkSuitability())
            end)

            if assign_ws ~= nil and assign_ws ~= ws then
                return false
            end

            local character_parameter = nil
            pcall(function()
                character_parameter = assign:GetAssignedIndividualParameter()
            end)

            if not character_parameter or not is_valid(character_parameter) then
                return false
            end

            local rank = effective_rank(character_parameter, ws)
            if not rank then return false end

            matched_workers = matched_workers + 1
            if not best_rank or rank > best_rank then
                best_rank = rank
            end

            if was_recently_craft_scaled(character_parameter, ws) then
                recently_scaled = true
            end

            return false
        end)
    end)

    if not ok then
        print("[WorkSuitability100 " .. VERSION .. "] WARNING: multi-type assigned-worker scan failed: " .. tostring(err))
    end

    return best_rank, recently_scaled, matched_workers
end

local function register_multitype_progress_hook()
    if registered[MULTITYPE_PROGRESS_HOOK] then return true end

    local ok, pre_id, post_id = pcall(function()
        return RegisterHook(
            MULTITYPE_PROGRESS_HOOK,
            function(Context, WorkSuitability, Amount)
                local ok_scale, err = pcall(function()
                    local ws = to_number(WorkSuitability)
                    local amount = to_number(Amount)
                    if ws == nil or not amount or amount <= 0 then return end

                    local rank, recently_scaled, workers =
                        max_assigned_rank_for_work(Context, ws)

                    if not rank or rank <= 10 then return end

                    -- The standard craft-speed hooks are preferred. If one of
                    -- the assigned workers was just turbo-scaled there, this
                    -- progress call is already carrying the boosted speed.
                    if recently_scaled then
                        log_scale_once(
                            "MultiTypeProgress(native-speed-path)",
                            ws,
                            rank,
                            amount,
                            amount
                        )
                        return
                    end

                    local result = amount * turbo_factor(rank)
                    if result > MAX_PROGRESS_AMOUNT then
                        result = MAX_PROGRESS_AMOUNT
                    end

                    Amount:Set(result)
                    log_scale_once(
                        "MultiTypeProgress(fallback workers=" .. tostring(workers) .. ")",
                        ws,
                        rank,
                        amount,
                        result
                    )
                end)

                if not ok_scale then
                    print("[WorkSuitability100 " .. VERSION .. "] ERROR: multi-type progress callback failed: " .. tostring(err))
                end
                return nil
            end,
            function(Context, WorkSuitability, Amount)
                return nil
            end
        )
    end)

    if not ok or not pre_id or not post_id then
        print("[WorkSuitability100 " .. VERSION .. "] WARNING: hook unavailable: " .. MULTITYPE_PROGRESS_HOOK .. " (" .. tostring(pre_id) .. ")")
        return false
    end

    registered[MULTITYPE_PROGRESS_HOOK] = { pre = pre_id, post = post_id }
    print("[WorkSuitability100 " .. VERSION .. "] Hook registered: MultiTypeProgress")
    return true
end

local function set_rank_cap()
    local game_settings = current_settings()
    if not game_settings then
        print("[WorkSuitability100 " .. VERSION .. "] PalGameSetting unavailable.")
        return false
    end

    local ok, err = pcall(function()
        game_settings.WorkSuitabilityMaxRank = TARGET_RANK
    end)

    if not ok then
        print("[WorkSuitability100 " .. VERSION .. "] ERROR: rank-cap write failed: " .. tostring(err))
        return false
    end

    local verify = to_number(game_settings.WorkSuitabilityMaxRank)
    print("[WorkSuitability100 " .. VERSION .. "] WorkSuitabilityMaxRank = " .. tostring(verify))
    return verify == TARGET_RANK
end

local function install_runtime_scaling()
    set_rank_cap()

    local craft_count = 0
    for _, def in ipairs(CRAFT_HOOKS) do
        if register_craft_hook(def) then craft_count = craft_count + 1 end
    end

    local resource_count = 0
    for _, def in ipairs(RESOURCE_HOOKS) do
        if register_resource_hook(def) then resource_count = resource_count + 1 end
    end

    local multitype_ok = register_multitype_progress_hook()

    print(
        "[WorkSuitability100 " .. VERSION .. "] Runtime scaling ready: craft hooks=" ..
        tostring(craft_count) .. "/" .. tostring(#CRAFT_HOOKS) ..
        " resource hooks=" .. tostring(resource_count) .. "/" .. tostring(#RESOURCE_HOOKS) ..
        " multitype=" .. tostring(multitype_ok)
    )
    print("[WorkSuitability100 " .. VERSION .. "] Scale targets: rank20=10x rank30=100x rank100=100000x.")
end

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
print("[WorkSuitability100 " .. VERSION .. "] Native rank-cap loader initialized.")

ExecuteInGameThread(function()
    install_runtime_scaling()
end)

-- Some UFunctions may not exist in memory at the first mod-load callback.
-- Retry once after startup. Already registered hooks are skipped.
if type(ExecuteWithDelay) == "function" then
    ExecuteWithDelay(5000, function()
        ExecuteInGameThread(function()
            install_runtime_scaling()
        end)
    end)
end
