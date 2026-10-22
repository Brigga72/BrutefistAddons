local _, B = ...
local S = {state = "Waiting for native swing", count = 0, rejected = 0}
B:AddModule("Swing", S)
function S:Reset(reason)
    self.start, self.duration = nil, nil
    self.state = reason or "Waiting for native swing"
end
function S:Accept(duration, hand)
    local h = B:Number(hand)
    local d = B:Number(duration)
    if not h or not d or d <= 0 then
        self.rejected = self.rejected + 1
        self:Reset("Swing data unavailable")
        return
    end
    local main = Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.MainHand or 0
    if h ~= main then return end
    self.count = self.count + 1
    self.start, self.duration = GetTime(), d
    self.state = "Native event, estimated countdown"
end
function S:Sample(now)
    if not self.start then return nil, nil, self.state end
    local left = math.max(0, self.duration - (now - self.start))
    if left == 0 then return 0, self.duration, "Waiting for next native swing" end
    return left, self.duration, self.state
end
function S:Init()
    B:On("PLAYER_SWING", function(d, h) self:Accept(d, h) end)
    B:On("UNIT_ATTACK_SPEED", function(unit)
        if not B:IsSecret(unit) and unit == "player" then
            self:Reset("Speed changed, awaiting native swing")
        end
    end)
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_LEAVING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_EQUIPMENT_CHANGED", "WEAPON_SLOT_CHANGED"}) do
        B:On(event, function() self:Reset() end)
    end
    -- Discard uncertain timing around casts rather than infer a spell-specific reset.
    for _, event in ipairs({"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START"}) do
        B:On(event, function(unit)
            if not B:IsSecret(unit) and unit == "player" then self:Reset("Casting, awaiting native swing") end
        end)
    end
    if not B.capabilities.PLAYER_SWING then self:Reset("PLAYER_SWING unsupported") end
end
