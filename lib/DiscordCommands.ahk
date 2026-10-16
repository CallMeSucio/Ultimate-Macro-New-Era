ProcessCommands(*) {
    global command_buffer, UserID, RunningStrategy, ChannelID, BotPrefix, ver, AutorunStartTime, StateFile
    global BotActiveReplyID, BotActiveInteraction, BotInteractionReplied
    global BotConnectionNoticeSent, BotConnectionNoticeNextTry, GatewayEnabled

    try {
        if (!BotConnectionNoticeSent && A_TickCount >= BotConnectionNoticeNextTry) {
            Discord.SendConnectionNotice(BotPrefix, ChannelID, GatewayEnabled)
            if (Discord.LastStatus = 200 || Discord.LastStatus = 201 || Discord.LastStatus = 204) {
                BotConnectionNoticeSent := true
            } else {
                BotConnectionNoticeNextTry := A_TickCount + 60000
            }
        }

        DiscordGatewayReadCommands()
        Discord.GetCommands(ChannelID)

        for command in command_buffer {
            BotActiveReplyID := command.id
            BotActiveInteraction := (IsObject(command) && HasProp(command, "interaction")) ? command.interaction : 0
            BotInteractionReplied := false
            rawContent := Trim(command.content)
            commandPrefix := SubStr(rawContent, 1, 1)
            if (commandPrefix != "!" && commandPrefix != BotPrefix)
                continue

            commandText := StrLower(Trim(SubStr(rawContent, 2)))
            if !RegExMatch(commandText, "^[a-z]+(?:\s+.*)?$")
                continue
            content := RegExReplace(commandText, "\s+.*$")
            argument := Trim(SubStr(commandText, StrLen(content) + 1))
            if String(command.user_id) != String(UserID)
                continue
            if !BotCommandAllowed(content, argument)
                continue
            remoteResult := ReviewHandleRemote136(content, RunningStrategy, StateFile, SettingsFile)
            if remoteResult != "" {
                Discord.SendEmbed(remoteResult, Discord.ColorInfo)
                continue
            }

            if (content = "help" || content = "helpm") {
                Discord.SendEmbed(BuildBotHelpMessage(), Discord.ColorInfo)
            }
            else if (content = "ping") {
                Discord.SendEmbed("Pong! Ultimate Macro TDS bot is online.")
            }
            else if (content = "version") {
                Discord.SendEmbed("Ultimate Macro TDS v" ver)
            }
            else if (content = "current") {
                strategyPath := IniRead(StateFile, "State", "Strategy", "")
                if (strategyPath != "")
                    SplitPath(strategyPath, &currentStrategyName)
                else
                    currentStrategyName := "None selected"

                currentStatus := RunningStrategy ? "Working" : "Stopped"
                currentRuntime := RunningStrategy ? FormatRuntime(AutorunStartTime) : "Not running"
                Discord.SendEmbed(
                    "**Macro:** " currentStatus "`n"
                    . "**Strategy:** " currentStrategyName "`n"
                    . "**Runtime:** " currentRuntime
                )
            }
            else if (content = "stats") {
                savedCoins := IniRead(StateFile, "State", "Coins", 0)
                savedGems := IniRead(StateFile, "State", "Gems", 0)
                savedExp := IniRead(StateFile, "State", "EXP", 0)
                totalTriumphs := Integer(IniRead(StateFile, "State", "TotalTriumphs", 0))
                totalLosses := Integer(IniRead(StateFile, "State", "TotalLosses", 0))
                winrate := MatchWinrate(totalTriumphs, totalLosses)

                Discord.SendEmbed(
                    "**Stats**`n"
                    . "**Wins:** " totalTriumphs " | **Losses:** " totalLosses " | **Win rate:** " winrate "%`n"
                    . "**Coins:** " savedCoins " | **Gems:** " savedGems " | **EXP:** " savedExp
                )
            }
            else if (content = "health") {
                Discord.SendEmbed(BuildBotHealthMessage(), Discord.ColorInfo)
            }
            else if (content = "exportlogs") {
                ExportLogsToDiscord()
            }
            else if (content = "strat") {
                if (argument = "")
                    ListBotStrategies()
                else
                    SelectBotStrategy(argument)
            }
            else if (content = "screenshot") {
                pBitmap := CaptureRobloxClientBitmap()
                if (!pBitmap) {
                    Discord.SendEmbed("Roblox is not running, so there is nothing to capture.")
                } else {
                    Discord.SendScreenshot(pBitmap, "Requested Screenshot")
                    Gdip_DisposeImage(pBitmap)
                }
            }
            else if (content = "status") {
                status := "stopped"
                if (RunningStrategy)
                    status := "working"

                savedCoins := IniRead(StateFile, "State", "Coins", 0)
                savedGems := IniRead(StateFile, "State", "Gems", 0)
                savedExp := IniRead(StateFile, "State", "EXP", 0)

                totalTriumphs := Integer(IniRead(StateFile, "State", "TotalTriumphs", 0))
                totalLosses := Integer(IniRead(StateFile, "State", "TotalLosses", 0))
                totalMatches := totalTriumphs + totalLosses
                winrate := MatchWinrate(totalTriumphs, totalLosses)
                wlRatio := (totalLosses > 0) ? Round(totalTriumphs / totalLosses, 1) : totalTriumphs

                runtime := FormatRuntime(AutorunStartTime)

                autorunStart := IniRead(StateFile, "State", "StartTime", 0)
                coinsPerHour := 0, gemsPerHour := 0, expPerHour := 0
                if (autorunStart > 0) {
                    elapsedMs := A_TickCount - autorunStart
                    elapsedHours := elapsedMs / 3600000
                    if (elapsedHours > 0.001) {
                        coinsPerHour := Round(savedCoins / elapsedHours)
                        gemsPerHour := Round(savedGems / elapsedHours)
                        expPerHour := Round(savedExp / elapsedHours)
                    }
                }

                currentStrategy := IniRead(StateFile, "State", "Strategy", "")

                SplitPath(currentStrategy, &stratName)

                if (RunningStrategy) {
                    statusMsg := "**Macro Status:** Working`n"
                    statusMsg .= "**Runtime:** " runtime "`n`n"
                    statusMsg .= "**Current Strategy:** " stratName "`n`n"
                    statusMsg .= "+" savedCoins " **Coins**`t+" savedGems " **Gems**`t+" savedExp " **EXP**`n"
                    statusMsg .= coinsPerHour " Coins/h`t" gemsPerHour " Gems/h`t" expPerHour " EXP/h`n`n"
                    statusMsg .= "**Total Matches:** " totalMatches "`t**Wins:** " totalTriumphs "`t**Losses:** " totalLosses "`n"
                    statusMsg .= "**Winrate:** " winrate "%`t**W/L Ratio:** " wlRatio
                } else {
                    statusMsg := "**Macro Status:** Stopped"
                }

                currentTime := A_Hour ":" A_Min ":" A_Sec
                statusMsg .= "`n-# Ultimate Macro Bot • " currentTime

                Discord.SendEmbed(statusMsg, Discord.ColorInfo)
            }
            else if (content = "stop") {
                if (RunningStrategy) {
                    Discord.SendEmbed("Stopping the macro.", Discord.ColorSuccess)
                    StopStrategy()
                } else {
                    Discord.SendEmbed("The macro is not running.", Discord.ColorWarning)
                }
            }
            else if (content = "start") {
                problem := QueueStrategyStart()
                if (problem != "") {
                    Discord.SendEmbed("Could not start the macro: " problem, Discord.ColorDanger)
                } else {
                    Discord.SendEmbed("The macro start was queued after validating its strategy and party settings.",
                        Discord.ColorSuccess)
                }
            } else if (content = "private") {
                Discord.SendEmbed("This bot is private. Your Discord account or channel is not authorized.", Discord.ColorWarning)
            } else {
                Discord.SendEmbed(
                    "Unknown command. Use " BotPrefix "help to see the available commands.",
                    Discord.ColorWarning
                )
            }
        }

    } catch Error as err {
        LogToConsole("Discord command error: " err.Message, true)
        try Discord.SendEmbed("I could not finish that command. Check the local runtime log for details.", Discord.ColorDanger)
    }

    BotActiveReplyID := 0
    BotActiveInteraction := 0
    BotInteractionReplied := false
    command_buffer := []
}

BotCommandAllowed(name, argument := "") {
    global BotCommandCooldowns
    key := name "|" argument
    now := A_TickCount
    cooldown := 750
    if (name = "start" || name = "stop")
        cooldown := 5000
    else if (name = "screenshot" || name = "exportlogs")
        cooldown := 2000

    if BotCommandCooldowns.Has(key) && now < BotCommandCooldowns[key]
        return false
    BotCommandCooldowns[key] := now + cooldown
    return true
}

BuildBotHealthMessage() {
    global BotCommandPollMs, BotToken, ChannelID, UserID, GatewayEnabled, RunningStrategy

    apiStatus := "waiting"
    if (Discord.LastStatus >= 200 && Discord.LastStatus < 300)
        apiStatus := "reachable"
    else if (Discord.LastStatus > 0)
        apiStatus := "error " Discord.LastStatus

    gatewayStatus := DiscordGatewayHealthSummary()
    macroStatus := RunningStrategy ? "working" : "stopped"
    return "**Bot health**`n"
        . "API: " apiStatus "`n"
        . "Prefix polling: every " BotCommandPollMs " ms`n"
        . "Message Content Intent: required for prefix commands`n"
        . "Native slash commands: " (GatewayEnabled ? gatewayStatus : "off") "`n"
        . "Macro: " macroStatus
}

ExportLogsToDiscord() {
    global LogLines
    exportPath := ""
    try {
        exportPath := RuntimeLogExportBundle()
        if (exportPath = "")
            throw Error("The diagnostic log bundle could not be created.")

        payload := Discord.BuildComponentsPayload([
            Map("type", 10, "content", "Diagnostics bundle attached. Sensitive values were redacted locally before upload.")
        ], Discord.ColorNeutral)
        Discord.CreateFormData(&postdata, &contentType, [
            Map("name", "payload_json", "content-type", "application/json", "content", payload),
            Map("name", "files[0]", "filename", "UltimateMacro-logs.txt", "content-type", "text/plain", "file",
                exportPath)
        ])
        Discord.SendMessageAPI(postdata, contentType)
    } catch Error as err {
        Discord.SendEmbed("Could not export diagnostics: " err.Message)
    } finally {
        if (exportPath != "" && FileExist(exportPath))
            try FileDelete(exportPath)
    }
}

BuildBotHelpMessage() {
    global BotPrefix, GatewayEnabled

    tick := Chr(96)
    text := "**Commands**`n"
    text .= tick BotPrefix "help" tick "  this list`n"
    text .= tick BotPrefix "status" tick "  macro status`n"
    text .= tick BotPrefix "current" tick "  active strategy`n"
    text .= tick BotPrefix "stats" tick "  saved resources`n"
    text .= tick BotPrefix "screenshot" tick "  capture Roblox`n"
    text .= tick BotPrefix "start" tick " / " tick BotPrefix "stop" tick "  macro control`n"
    text .= tick BotPrefix "strat" tick "  choose a strategy`n"
    text .= tick BotPrefix "health" tick "  bot connection`n"
    text .= tick BotPrefix "ping" tick " / " tick BotPrefix "version" tick "  quick checks`n"
    text .= tick BotPrefix "exportlogs" tick "  redacted diagnostics`n"
    text .= tick BotPrefix "stopaftergame" tick " / " tick BotPrefix "cancelstop" tick "  next-match control`n"
    text .= tick BotPrefix "summary" tick " / " tick BotPrefix "rewards" tick " / " tick BotPrefix "recent" tick "  match history`n"
    text .= tick BotPrefix "performance" tick " / " tick BotPrefix "placements" tick " / " tick BotPrefix "alerts" tick "  QA tools"
    if GatewayEnabled
        text .= "`n`n" tick "/strat" tick " opens the strategy menu."
    return text
}

ListBotStrategies() {
    global BotStrategyChoices, BotStrategyChoiceTime, StratsDir, RecordingsDir, GatewayEnabled

    choices := []
    seenPaths := Map()
    CollectBotStrategyFiles(choices, seenPaths, StratsDir)
    CollectBotStrategyFiles(choices, seenPaths, RecordingsDir)
    BotStrategyChoices := SortBotStrategyChoices(choices)
    BotStrategyChoiceTime := A_TickCount

    if (BotStrategyChoices.Length = 0) {
        Discord.SendEmbed("No .strat files were found.", Discord.ColorWarning)
        return
    }

    if (GatewayEnabled && DiscordGatewayHealthSummary() = "connected") {
        SendBotStrategyMenus()
        return
    }

    SendBotStrategyTextList()
}

CollectBotStrategyFiles(choices, seenPaths, directory) {
    if !IsSet(directory) || directory = "" || !DirExist(directory)
        return

    loop files, directory "\*.strat", "F" {
        path := A_LoopFileFullPath
        key := StrLower(path)
        if seenPaths.Has(key)
            continue
        seenPaths[key] := true
        choices.Push({ name: A_LoopFileName, path: path })
    }
}

SortBotStrategyChoices(choices) {
    sorted := []
    for item in choices {
        itemKey := StrLower(item.name) "|" StrLower(item.path)
        insertAt := sorted.Length + 1
        for index, existing in sorted {
            existingKey := StrLower(existing.name) "|" StrLower(existing.path)
            if (StrCompare(itemKey, existingKey, false) < 0) {
                insertAt := index
                break
            }
        }
        sorted.InsertAt(insertAt, item)
    }
    return sorted
}

BotStrategyDisplayName(item, index := 0) {
    name := RegExReplace(String(item.name), "(?i)\.strat$", "")
    if (name = "")
        name := "Strategy " index
    return Discord.TruncateText(name, 100)
}

SendBotStrategyMenus() {
    global BotStrategyChoices

    total := BotStrategyChoices.Length
    start := 1
    part := 1
    maxRowsPerMessage := 18
    optionsPerRow := 25
    maxChoicesPerMessage := maxRowsPerMessage * optionsPerRow

    while (start <= total) {
        end := Min(total, start + maxChoicesPerMessage - 1)
        children := BuildBotStrategyMenuChildren(start, end, total, part)
        Discord.SendComponents(children, Discord.ColorPurple)
        start := end + 1
        part += 1
    }
}

BuildBotStrategyMenuChildren(start, end, total, part := 1) {
    global BotStrategyChoices

    heading := "**Strategies**`n"
    if (total > 450)
        heading .= "Part " part " · " start "-" end " of " total
    else if (total > 25)
        heading .= "Select one · " start "-" end " of " total
    else
        heading .= "Select one"

    children := [
        Map("type", 10, "content", heading),
        Map("type", 14, "divider", JSON.true, "spacing", 1)
    ]
    rowStart := start
    while (rowStart <= end) {
        rowEnd := Min(end, rowStart + 24)
        options := []
        optionIndex := rowStart
        while (optionIndex <= rowEnd) {
            item := BotStrategyChoices[optionIndex]
            options.Push(Map(
                "label", BotStrategyDisplayName(item, optionIndex),
                "value", String(optionIndex)
            ))
            optionIndex += 1
        }

        placeholder := "Choose a strategy"
        if (total > 25)
            placeholder .= " (" rowStart "-" rowEnd ")"
        row := Discord.BuildStringSelectRow("bot:strats:" rowStart, options, placeholder)
        if (Type(row) = "Map")
            children.Push(row)
        rowStart := rowEnd + 1
    }
    return children
}

SendBotStrategyTextList() {
    global BotStrategyChoices, BotPrefix

    total := BotStrategyChoices.Length
    index := 1
    firstMessage := true
    while (index <= total) {
        message := "**Strategies**`n"
        if firstMessage
            message .= "Use " BotPrefix "strat <number> to select one.`n`n"

        while (index <= total) {
            line := index ". " BotStrategyDisplayName(BotStrategyChoices[index], index) "`n"
            if (StrLen(message) + StrLen(line) > 3750 && StrLen(message) > 30)
                break
            message .= line
            index += 1
        }

        Discord.SendEmbed(RTrim(message, "`n"), Discord.ColorPurple)
        firstMessage := false
    }
}

SelectBotStrategy(argument) {
    global BotStrategyChoices, BotStrategyChoiceTime, Strategy1Path, Strategy2Path, RotateStrategies
    global Strategy1Ctrl, Strategy2Ctrl, RotateStrategiesCtrl, SettingsFile, RunningStrategy, StateFile, BotPrefix

    if !RegExMatch(argument, "^\d+$") {
        Discord.SendEmbed("Use a number from the strategy list, for example: " BotPrefix "strat 2", Discord.ColorWarning)
        return
    }

    if (!IsSet(BotStrategyChoices) || !IsObject(BotStrategyChoices)
        || BotStrategyChoices.Length = 0 || !IsSet(BotStrategyChoiceTime)
        || A_TickCount - BotStrategyChoiceTime > 300000) {
        Discord.SendEmbed("The strategy list expired. Run " BotPrefix "strat again.", Discord.ColorWarning)
        ListBotStrategies()
        return
    }

    index := Integer(argument)
    if (index < 1 || index > BotStrategyChoices.Length) {
        Discord.SendEmbed("That strategy number is not in the current list. Run " BotPrefix "strat again.", Discord.ColorWarning
        )
        return
    }

    selected := BotStrategyChoices[index]
    if !FileExist(selected.path) {
        Discord.SendEmbed("That strategy file is no longer available. Run " BotPrefix "strat again.", Discord.ColorWarning)
        return
    }

    Strategy1Path := selected.path
    Strategy2Path := ""
    RotateStrategies := 0
    if IsSet(Strategy1Ctrl)
        Strategy1Ctrl.Value := selected.path
    if IsSet(Strategy2Ctrl)
        Strategy2Ctrl.Value := ""
    if IsSet(RotateStrategiesCtrl)
        RotateStrategiesCtrl.Value := 0
    IniWrite(Strategy1Path, SettingsFile, "Options", "Strategy1")
    IniWrite(Strategy2Path, SettingsFile, "Options", "Strategy2")
    IniWrite(0, SettingsFile, "Options", "RotateStrategies")

    if (RunningStrategy) {
        IniWrite(1, StateFile, "State", "Running")
        IniWrite(selected.path, StateFile, "State", "Strategy")
        Discord.SendEmbed("Selected **" BotStrategyDisplayName(selected, index) "**. Restarting the macro.", Discord.ColorSuccess)
        SafeReload()
    } else {
        problem := QueueStrategyStart()
        if (problem != "")
            Discord.SendEmbed("Could not start **" BotStrategyDisplayName(selected, index) "**: " problem, Discord.ColorDanger)
        else
            Discord.SendEmbed("Selected **" BotStrategyDisplayName(selected, index) "**. Start queued.", Discord.ColorSuccess)
    }
}

MatchWinrate(wins, losses) {
    wins := Integer(wins)
    losses := Integer(losses)
    total := wins + losses
    if (total <= 0)
        return 0

    rate := Round((wins / total) * 100)
    if (rate >= 100 && losses > 0)
        return 99
    if (rate <= 0 && wins > 0)
        return 1
    return rate
}
