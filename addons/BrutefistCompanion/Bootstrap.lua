local addon, B = ...
B:On("ADDON_LOADED", function(name)
    if name ~= addon then return end
    BrutefistCompanionDB = BrutefistCompanionDB or {}
    B.db = BrutefistCompanionDB
    local defaults = {x = 0, y = -170, scale = 1, visible = true, locked = true, warning = 0.3}
    for k, v in pairs(defaults) do if B.db[k] == nil then B.db[k] = v end end
    B.modules.Swing:Init(); B.modules.Diagnostics:Init(); B.modules.HUD:Init()
    B:Print("v" .. B.version .. " ready. /bcc for commands; /bcc diag for API report.")
end)
SLASH_BRUTEFISTCOMPANION1 = "/bcc"
SlashCmdList.BRUTEFISTCOMPANION = function(input)
    local cmd, arg = input:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    local d = B.modules.Diagnostics
    if cmd == "warning" then
        local n = tonumber(arg)
        if not n or n ~= n or n < 0.05 or n > 1 then
            B:Print("Use /bcc warning 0.05 through 1 (seconds)."); return
        end
        B.db.warning = n
        B:Print(string.format("Swing warning: %.2f seconds before the estimated swing.", n)); return
    end
    if cmd == "diag" then d:Show(); return end
    if cmd == "record" then
        d.recording = arg ~= "off"
        B:Print("Event recording " .. (d.recording and "on (200 lines max)." or "off.")); return
    end
    if cmd == "clear" then d.lines = {}; d.total = 0; B:Print("History cleared."); return end
    if cmd == "demo" then
        if InCombatLockdown() then B:Print("Demo is available outside combat."); return end
        B.demoStart = GetTime(); B.demoUntil = B.demoStart + 15
        B:Print("15 second simulated demo."); return
    end
    if cmd == "lock" or cmd == "unlock" or cmd == "show" or cmd == "hide" or cmd == "reset" or cmd == "scale" then
        if InCombatLockdown() then B:Print("Change HUD settings after combat."); return end
        if cmd == "lock" then B.db.locked = true
        elseif cmd == "unlock" then B.db.locked = false
        elseif cmd == "show" then B.db.visible = true
        elseif cmd == "hide" then B.db.visible = false
        elseif cmd == "reset" then B.db.x = 0; B.db.y = -170; B.db.scale = 1; B.db.visible = true
        elseif cmd == "scale" then
            local n = tonumber(arg)
            if not n or n < 0.5 or n > 2 then B:Print("Use /bcc scale 0.5 through 2."); return end
            B.db.scale = n
        end
        B.modules.HUD:Place(); return
    end
    B:Print("/bcc unlock, lock, show, hide, reset, scale 1.2, demo, record on/off, clear, diag, warning 0.3")
end
