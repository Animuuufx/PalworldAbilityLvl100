local VERSION = "v0.1"

local HANDBOOK_PREFIX = "WorkSuitability_AddTicket_"
local HOOK = "/Script/Pal.PalUtility:CanUseTargetWorkSuitabilityRankUp"

local handbook_items = {
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

local function safe_full_name(value)
    if value == nil then
        return "<nil>"
    end

    local ok, object = pcall(function()
        return value.get and value:get() or value
    end)
    if not ok or object == nil then
        return "<unreadable>"
    end

    local ok_name, name = pcall(function()
        return object:GetFullName()
    end)
    if ok_name and name then
        return tostring(name)
    end

    return "<unnamed>"
end

local function handbook_code(full_name)
    local code = full_name:match("WorkSuitability_AddTicket_([%w_]+)")
    if not code then
        return nil
    end
    return code
end

print("[WorkSuitabilityUnlock " .. VERSION .. "] Loading.")
print("[WorkSuitabilityUnlock " .. VERSION .. "] Hook target: " .. HOOK)

local pre_id, post_id = RegisterHook(HOOK, function(Context, IndividualParameter, Item)
    local item_name = safe_full_name(Item)
    local code = handbook_code(item_name)

    if not code or not handbook_items[code] then
        return nil
    end

    local individual_name = safe_full_name(IndividualParameter)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Handbook eligibility override: " .. code)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Target parameter: " .. individual_name)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Item: " .. item_name)

    -- The native game rank-up path is left intact. We only remove its
    -- eligibility rejection here so the normal handbook transaction can run.
    -- If the native transaction still refuses to create a missing suitability,
    -- the next revision will hook that mutation path rather than replacing
    -- the whole handbook system.
    return true
end)

if pre_id and post_id then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Hook registered successfully. PreId=" .. tostring(pre_id) .. " PostId=" .. tostring(post_id))
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] ERROR: failed to register handbook eligibility hook.")
end
