local VERSION = "v0.3"

local CAN_USE_HOOK = "/Script/Pal.PalUtility:CanUseTargetWorkSuitabilityRankUp"
local ADD_RANK_HOOK = "/Script/Pal.PalIndividualCharacterParameter:SetWorkSuitabilityAddRank"

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

print("[WorkSuitabilityUnlock " .. VERSION .. "] Loading.")
print("[WorkSuitabilityUnlock " .. VERSION .. "] Eligibility hook: " .. CAN_USE_HOOK)
print("[WorkSuitabilityUnlock " .. VERSION .. "] Rank mutation hook: " .. ADD_RANK_HOOK)

-- The previous versions tried to write WorkSuitability_* directly. Those are
-- not the handbook's persistent add-rank storage. Palworld exposes the actual
-- mutation as SetWorkSuitabilityAddRank(EPalWorkSuitability, int32), and the
-- resulting save data is represented by GotWorkSuitabilityAddRankList.
--
-- Therefore we no longer manufacture reflected properties. We let the native
-- transaction perform the real mutation and only remove the eligibility gate.
local can_use_pre, can_use_post = RegisterHook(CAN_USE_HOOK, function(Context, IndividualParameter, Item)
    local code = handbook_code(Item)
    if not code or not handbook_codes[code] then
        return nil
    end

    print("[WorkSuitabilityUnlock " .. VERSION .. "] Handbook eligibility override: " .. code)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Target parameter: " .. full_name(IndividualParameter))
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Item: " .. full_name(Item))

    -- This function returns bool. Returning true is intentional: the native
    -- handbook code must be allowed to continue into SetWorkSuitabilityAddRank.
    return true
end)

if can_use_pre and can_use_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Eligibility hook registered. PreId=" .. tostring(can_use_pre) .. " PostId=" .. tostring(can_use_post))
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] ERROR: eligibility hook registration failed.")
end

-- Observe the actual persistent mutation. This also gives us a definitive
-- signal that the handbook made it past the eligibility check.
local add_pre, add_post = RegisterHook(ADD_RANK_HOOK, function(Context, WorkSuitability, AddRank)
    local target = unwrap(Context)
    local suitability = unwrap(WorkSuitability)
    local amount = unwrap(AddRank)

    print("[WorkSuitabilityUnlock " .. VERSION .. "] SetWorkSuitabilityAddRank called: target=" .. full_name(target) .. " suitability=" .. tostring(suitability) .. " addRank=" .. tostring(amount))

    -- Do not replace the native mutation. Palworld's own implementation is
    -- responsible for updating the suitability list, delegates, replication,
    -- and save parameter.
    return nil
end)

if add_pre and add_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Rank mutation hook registered. PreId=" .. tostring(add_pre) .. " PostId=" .. tostring(add_post))
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] ERROR: rank mutation hook registration failed.")
end
