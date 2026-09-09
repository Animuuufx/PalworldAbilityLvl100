local VERSION = "v0.6"

local CAN_USE_HOOK = "/Script/Pal.PalUtility:CanUseTargetWorkSuitabilityRankUp"
local ADD_RANK_HOOK = "/Script/Pal.PalIndividualCharacterParameter:SetWorkSuitabilityAddRank"
local STATIC_ITEM_HOOK = "/Script/Pal.PalStaticItemDataBase:CanUseItemToCharacter"
local PROCESSOR_ITEM_HOOK = "/Script/Pal.PalItemUseProcessor:CanUseItemToCharacter"
local SLOT_TARGET_HOOK = "/Script/Pal.PalItemSlot:CanUseItemToCharacter"

local handbook_codes = {
    EmitFlame = true,
    Watering = true,
    Seeding = true,
    GenerateElectricity = true,
    Handcraft = true,
    Collection = true,
    Deforest = true,
    Mining = true,
    ProductMedicine = true,
    Cool = true,
    Transport = true,
    MonsterFarm = true,
}

local suitability_ids = {
    EmitFlame = 1,
    Watering = 2,
    Seeding = 3,
    GenerateElectricity = 4,
    Handcraft = 5,
    Collection = 6,
    Deforest = 7,
    Mining = 8,
    ProductMedicine = 9,
    Cool = 10,
    Transport = 11,
    MonsterFarm = 12,
}

local function unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function()
        if value.get then return value:get() end
        return value
    end)
    return ok and result or nil
end

local function full_name(value)
    local object = unwrap(value)
    if not object then return "<nil>" end
    local ok, name = pcall(function() return object:GetFullName() end)
    return ok and tostring(name) or "<unnamed>"
end

local function handbook_code(value)
    local name = full_name(value)
    return name:match("WorkSuitability_AddTicket_([%w_]+)")
end

local function is_handbook(value)
    return handbook_codes[handbook_code(value)] == true
end

local function try_slot_item(slot)
    slot = unwrap(slot)
    if not slot then return nil end

    local ok, item = pcall(function()
        if slot.TryGetStaticItemData then
            return slot:TryGetStaticItemData()
        end
        return nil
    end)
    if ok and item then
        item = unwrap(item)
        if item then return item end
    end

    local ok_id, item_id = pcall(function()
        if slot.GetItemId then
            return slot:GetItemId()
        end
        return nil
    end)
    if ok_id and item_id then
        local raw = unwrap(item_id)
        if raw then
            local ok_static, static_id = pcall(function() return raw.StaticId end)
            if ok_static and static_id then
                local static_name = tostring(unwrap(static_id))
                if static_name:find("WorkSuitability_AddTicket_", 1, true) then
                    return static_name
                end
            end
            local text = tostring(raw)
            if text:find("WorkSuitability_AddTicket_", 1, true) then
                return text
            end
        end
    end

    return nil
end

local pending_target = {}
local mutation_seen = {}

local function target_key(target, code)
    return full_name(target) .. "|" .. tostring(code or "")
end

local function mark_pending(target, code)
    if target ~= nil and code ~= nil then
        pending_target[target_key(target, code)] = true
    end
end

local function get_work_rank(target, id)
    target = unwrap(target)
    if not target or not id then return nil end

    local getters = {
        "GetWorkSuitabilityAddRank",
        "GetWorkSuitabilityRankWithCharacterRank",
        "GetWorkSuitabilityRank",
    }

    for _, name in ipairs(getters) do
        local ok, value = pcall(function()
            local fn = target[name]
            if type(fn) == "function" then
                return fn(target, id)
            end
            return nil
        end)
        if ok and value ~= nil then
            local n = tonumber(unwrap(value))
            if n ~= nil then return math.floor(n) end
        end
    end

    return nil
end

local setter_fn = nil
local function get_setter()
    if setter_fn ~= nil then return setter_fn end
    local ok, fn = pcall(function()
        return StaticFindObject("/Script/Pal.PalIndividualCharacterParameter:SetWorkSuitabilityAddRank")
    end)
    if ok and fn then
        setter_fn = fn
        return fn
    end
    return nil
end

local function set_work_add_rank(target, id, value)
    target = unwrap(target)
    id = tonumber(id)
    value = tonumber(value)
    if not target or not id or not value then return false end

    value = math.max(0, math.min(100, math.floor(value)))

    local ok, result = pcall(function()
        local fn = get_setter()
        if fn then
            return fn(target, id, value)
        end
        return target:SetWorkSuitabilityAddRank(id, value)
    end)

    if ok then
        print("[WorkSuitabilityUnlock " .. VERSION .. "] Direct add-rank set: id=" .. tostring(id) .. " value=" .. tostring(value) .. " target=" .. full_name(target))
        return true
    end

    print("[WorkSuitabilityUnlock " .. VERSION .. "] Direct add-rank set failed: " .. tostring(result))
    return false
end

local function ensure_handbook_rank(target, code)
    local id = suitability_ids[code]
    if not id then return false end

    target = unwrap(target)
    if not target then return false end

    local key = target_key(target, code)
    local current = get_work_rank(target, id)
    if current == nil then current = 0 end

    -- The native setter is a Set operation, not an increment operation.
    -- Keep normal 1..10 handbook progression intact, but once the game reaches
    -- its old ceiling, explicitly write the next rank instead of letting the
    -- legacy eligibility path hold it at 10.
    local next_rank = current + 1
    if next_rank > 100 then next_rank = 100 end

    print("[WorkSuitabilityUnlock " .. VERSION .. "] Ensuring handbook rank: " .. code .. " current=" .. tostring(current) .. " next=" .. tostring(next_rank))
    local ok = set_work_add_rank(target, id, next_rank)
    if ok then
        mutation_seen[key] = true
    end
    return ok
end

print("[WorkSuitabilityUnlock " .. VERSION .. "] Loading.")
print("[WorkSuitabilityUnlock " .. VERSION .. "] Target-selection hooks enabled.")

local slot_pre, slot_post = RegisterHook(SLOT_TARGET_HOOK, function(Context, IndividualParameter)
    local item = try_slot_item(Context)
    local code = handbook_code(item)

    if not code and type(item) == "string" then
        code = item:match("WorkSuitability_AddTicket_([%w_]+)")
    end

    if not handbook_codes[code] then return nil end

    print("[WorkSuitabilityUnlock " .. VERSION .. "] Slot target override: " .. code)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Slot: " .. full_name(Context))
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Target: " .. full_name(IndividualParameter))
    mark_pending(IndividualParameter, code)
    return true
end)

if slot_pre and slot_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Slot target hook registered.")
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] WARNING: slot target hook registration failed.")
end

local static_pre, static_post = RegisterHook(STATIC_ITEM_HOOK, function(Context, IndividualParameter)
    if not is_handbook(Context) then return nil end

    local code = handbook_code(Context)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Item-data target override: " .. code)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Target: " .. full_name(IndividualParameter))
    mark_pending(IndividualParameter, code)
    return true
end)

if static_pre and static_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Static item target hook registered.")
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] WARNING: static item target hook registration failed.")
end

local processor_pre, processor_post = RegisterHook(PROCESSOR_ITEM_HOOK,
    function(Context, IndividualParameter, Item)
        if not is_handbook(Item) then return nil end

        local code = handbook_code(Item)
        local key = target_key(IndividualParameter, code)
        mutation_seen[key] = nil
        mark_pending(IndividualParameter, code)

        print("[WorkSuitabilityUnlock " .. VERSION .. "] Processor target override: " .. code)
        print("[WorkSuitabilityUnlock " .. VERSION .. "] Target: " .. full_name(IndividualParameter))
        return true
    end,
    function(Context, IndividualParameter, Item)
        if not is_handbook(Item) then return nil end

        local code = handbook_code(Item)
        local key = target_key(IndividualParameter, code)

        -- If the normal handbook transaction was rejected after target
        -- selection, perform the real persistent SetWorkSuitabilityAddRank
        -- call ourselves. The native function is still used, so save data,
        -- delegates, and replication remain owned by Palworld.
        if not mutation_seen[key] then
            ensure_handbook_rank(IndividualParameter, code)
        end

        pending_target[key] = nil
        return nil
    end
)

if processor_pre and processor_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Item processor target hook registered.")
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] WARNING: processor target hook registration failed.")
end

local can_use_pre, can_use_post = RegisterHook(CAN_USE_HOOK, function(Context, IndividualParameter, Item)
    if not is_handbook(Item) then return nil end

    local code = handbook_code(Item)
    mark_pending(IndividualParameter, code)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Handbook eligibility override: " .. code)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Target parameter: " .. full_name(IndividualParameter))
    return true
end)

if can_use_pre and can_use_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Rank-up eligibility hook registered.")
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] WARNING: rank-up eligibility hook registration failed.")
end

local add_pre, add_post = RegisterHook(ADD_RANK_HOOK, function(Context, WorkSuitability, AddRank)
    local target = unwrap(Context)
    local suitability = tonumber(unwrap(WorkSuitability))
    local amount = tonumber(unwrap(AddRank))

    print("[WorkSuitabilityUnlock " .. VERSION .. "] SetWorkSuitabilityAddRank called: target=" .. full_name(target) .. " suitability=" .. tostring(suitability) .. " addRank=" .. tostring(amount))

    if not target or not suitability or not amount then return nil end

    -- For the handbook path, SetWorkSuitabilityAddRank receives the value that
    -- will be stored. Once the old 10 cap is reached, advance that value by one.
    local code = nil
    for name, id in pairs(suitability_ids) do
        if id == suitability then code = name break end
    end
    local key = target_key(target, code)
    if code and pending_target[key] then
        local current = get_work_rank(target, suitability)
        if current ~= nil and current >= 10 and amount <= 10 then
            AddRank:Set(math.min(100, current + 1))
            print("[WorkSuitabilityUnlock " .. VERSION .. "] Raised handbook mutation past 10: " .. tostring(current + 1))
        end
        mutation_seen[key] = true
    end

    return nil
end)

if add_pre and add_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Rank mutation hook registered.")
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] WARNING: rank mutation hook registration failed.")
end
