local _, B = ...
B.version = "0.4.2"
B.modules, B.events, B.capabilities = {}, {}, {}
function B:IsSecret(value)
    if type(issecretvalue) == "function" then
        local ok, result = pcall(issecretvalue, value)
        if not ok or result then return true end
    end
    if type(canaccessvalue) == "function" then
        local ok, result = pcall(canaccessvalue, value)
        if not ok or not result then return true end
    end
    return false
end
function B:Plain(value)
    if self:IsSecret(value) then return "<restricted>" end
    local t = type(value)
    if t == "number" or t == "string" or t == "boolean" or t == "nil" then
        return tostring(value)
    end
    return "<" .. t .. ">"
end
function B:Number(value)
    if self:IsSecret(value) then return nil end
    if type(value) ~= "number" then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end
function B:Print(text) DEFAULT_CHAT_FRAME:AddMessage("|cff49c9eaBrutefist:|r " .. text) end
function B:AddModule(name, module) self.modules[name] = module end
function B:On(event, callback)
    if not self.events[event] then
        self.events[event] = {}
        local ok = pcall(self.frame.RegisterEvent, self.frame, event)
        self.capabilities[event] = ok
    end
    table.insert(self.events[event], callback)
end
function B:Dispatch(event, ...)
    if self.modules.Diagnostics then self.modules.Diagnostics:Capture(event, ...) end
    for _, callback in ipairs(self.events[event] or {}) do
        local ok, err = pcall(callback, ...)
        if not ok then
            self.modules.Swing:Reset("Module error, see diagnostics")
            if self.modules.Diagnostics then self.modules.Diagnostics:Log("ERROR " .. self:Plain(err)) end
        end
    end
end
B.frame = CreateFrame("Frame")
B.frame:SetScript("OnEvent", function(_, event, ...) B:Dispatch(event, ...) end)
