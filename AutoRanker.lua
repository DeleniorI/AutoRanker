-- AutoRanker for WoW 1.12.1
-- Updates lower-rank spells on action bars to the highest rank you know.
-- Manual command: /arank
-- Debug command: /arank debug
-- Dump command: /arank dump

local AR = {}

AR.debug = false
AR.pending = false
AR.elapsed = 0
AR.delay = 1.0

local tooltip = CreateFrame("GameTooltip", "AutoRankerTooltip", nil, "GameTooltipTemplate")
tooltip:SetOwner(UIParent, "ANCHOR_NONE")

local frame = CreateFrame("Frame")

local function AR_Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffAutoRanker:|r " .. msg)
    end
end

local function AR_Debug(msg)
    if AR.debug then
        AR_Print(msg)
    end
end

local function AR_GetText(globalName)
    local obj = getglobal(globalName)
    if obj then
        return obj:GetText()
    end
    return nil
end

local function AR_GetRankNumber(rankText)
    if not rankText then
        return 0
    end

    local _, _, rank = string.find(rankText, "Rank (%d+)")
    if rank then
        return tonumber(rank)
    end

    _, _, rank = string.find(rankText, "(%d+)")
    if rank then
        return tonumber(rank)
    end

    return 0
end

local function AR_IsCursorClear()
    if CursorHasItem and CursorHasItem() then
        return false
    end

    if CursorHasSpell and CursorHasSpell() then
        return false
    end

    if CursorHasMacro and CursorHasMacro() then
        return false
    end

    return true
end

local function AR_GetActionNameAndRank(slot)
    tooltip:ClearLines()
    tooltip:SetAction(slot)

    local left1 = AR_GetText("AutoRankerTooltipTextLeft1")
    local left2 = AR_GetText("AutoRankerTooltipTextLeft2")
    local left3 = AR_GetText("AutoRankerTooltipTextLeft3")

    local right1 = AR_GetText("AutoRankerTooltipTextRight1")
    local right2 = AR_GetText("AutoRankerTooltipTextRight2")
    local right3 = AR_GetText("AutoRankerTooltipTextRight3")

    local spellName = left1
    local rankText = nil

    -- Vanilla often puts spell rank here:
    -- Frostbolt               Rank 1
    if right1 and AR_GetRankNumber(right1) > 0 then
        rankText = right1
    elseif right2 and AR_GetRankNumber(right2) > 0 then
        rankText = right2
    elseif right3 and AR_GetRankNumber(right3) > 0 then
        rankText = right3

    -- Some clients/addons may put rank on left lines.
    elseif left2 and AR_GetRankNumber(left2) > 0 then
        rankText = left2
    elseif left3 and AR_GetRankNumber(left3) > 0 then
        rankText = left3
    end

    return spellName, rankText, left1, left2, left3, right1, right2, right3
end

local function AR_BuildHighestSpellTable()
    local highest = {}

    local i = 1
    while true do
        local name, rankText = GetSpellName(i, BOOKTYPE_SPELL)

        if not name then
            break
        end

        local rankNumber = AR_GetRankNumber(rankText)

        if rankNumber > 0 then
            if not highest[name] or rankNumber > highest[name].rankNumber then
                highest[name] = {
                    spellIndex = i,
                    rankText = rankText,
                    rankNumber = rankNumber
                }
            end
        end

        i = i + 1
    end

    return highest
end

local function AR_IsProbablyMacro(slot)
    if GetActionText and GetActionText(slot) then
        return true
    end

    return false
end

local function AR_UpdateBars()
    local updated = 0

    if not AR_IsCursorClear() then
        AR_Print("Cursor is not empty. Clear your cursor and try /arank again.")
        return
    end

    local highest = AR_BuildHighestSpellTable()

    for slot = 1, 120 do
        if HasAction(slot) and not AR_IsProbablyMacro(slot) then
            local actionName, actionRankText = AR_GetActionNameAndRank(slot)

            if actionName and highest[actionName] then
                local currentRank = AR_GetRankNumber(actionRankText)
                local best = highest[actionName]

                AR_Debug(
                    "Slot " ..
                    slot ..
                    ": " ..
                    actionName ..
                    " current=" ..
                    currentRank ..
                    " best=" ..
                    best.rankNumber
                )

                if currentRank > 0 and best.rankNumber > currentRank then
                    ClearCursor()
                    PickupSpell(best.spellIndex, BOOKTYPE_SPELL)
                    PlaceAction(slot)
                    ClearCursor()

                    updated = updated + 1

                    AR_Print(
                        "Updated slot " ..
                        slot ..
                        ": " ..
                        actionName ..
                        " " ..
                        actionRankText ..
                        " -> " ..
                        best.rankText
                    )
                end
            end
        end
    end

    if updated == 0 then
        AR_Print("No outdated spell ranks found.")
    else
        AR_Print("Done. Updated " .. updated .. " action slot(s).")
    end
end

local function AR_DumpBars()
    AR_Print("Dumping action bar spell tooltip data...")

    for slot = 1, 120 do
        if HasAction(slot) then
            local actionName, actionRankText, left1, left2, left3, right1, right2, right3 = AR_GetActionNameAndRank(slot)

            if actionName then
                AR_Print(
                    "Slot " ..
                    slot ..
                    " | name=" ..
                    tostring(actionName) ..
                    " | rank=" ..
                    tostring(actionRankText) ..
                    " | L1=" ..
                    tostring(left1) ..
                    " | L2=" ..
                    tostring(left2) ..
                    " | R1=" ..
                    tostring(right1) ..
                    " | R2=" ..
                    tostring(right2)
                )
            end
        end
    end

    AR_Print("Dump finished.")
end

local function AR_ScheduleUpdate()
    AR.pending = true
    AR.elapsed = 0

    frame:SetScript("OnUpdate", function()
        AR.elapsed = AR.elapsed + arg1

        if AR.elapsed >= AR.delay then
            AR.pending = false
            frame:SetScript("OnUpdate", nil)
            AR_UpdateBars()
        end
    end)
end

local function AR_ShowHelp()
    AR_Print("Commands:")
    AR_Print("/arank - update spell ranks on action bars")
    AR_Print("/arank debug - toggle debug mode")
    AR_Print("/arank dump - print detected action bar spell data")
end

SLASH_AUTORANKER1 = "/arank"
SlashCmdList["AUTORANKER"] = function(msg)
    if msg == "debug" then
        AR.debug = not AR.debug

        if AR.debug then
            AR_Print("Debug mode ON.")
        else
            AR_Print("Debug mode OFF.")
        end

        return
    end

    if msg == "dump" then
        AR_DumpBars()
        return
    end

    if msg == "help" then
        AR_ShowHelp()
        return
    end

    AR_Print("Scanning ranks...")
    AR_UpdateBars()
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("LEARNED_SPELL_IN_TAB")

frame:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" then
        AR_Print("Loaded. Type /arank to update spell ranks.")
    elseif event == "LEARNED_SPELL_IN_TAB" then
        AR_Debug("Learned spell event detected. Scheduling update.")
        AR_ScheduleUpdate()
    end
end)