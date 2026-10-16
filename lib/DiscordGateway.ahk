DiscordGatewayInit() {
    DiscordGatewayEnsureDirectories()
    DiscordGatewaySync()
    SetTimer(DiscordGatewayWatchdog, 15000)
}

DiscordGatewayWatchdog(*) {
    DiscordGatewaySync()
}

DiscordGatewayEnsureDirectories() {
    global BotGatewayDir
    if !DirExist(BotGatewayDir)
        DirCreate(BotGatewayDir)
    if !DirExist(BotGatewayDir "\commands")
        DirCreate(BotGatewayDir "\commands")
}

DiscordGatewayWorkerPath() {
    return A_ScriptDir "\discord-gateway\worker.mjs"
}

DiscordGatewayFindNode() {
    candidates := [
        A_ScriptDir "\node\node.exe",
        A_ScriptDir "\nodejs\node.exe",
        EnvGet("LOCALAPPDATA") "\Programs\nodejs\node.exe",
        EnvGet("ProgramFiles") "\nodejs\node.exe"
    ]

    pathValue := EnvGet("PATH")
    for folder in StrSplit(pathValue, ";") {
        folder := RTrim(Trim(folder), "\/")
        if (folder != "")
            candidates.Push(folder "\node.exe")
    }

    for candidate in candidates {
        if FileExist(candidate)
            return candidate
    }
    return ""
}

DiscordGatewaySync() {
    global BotEnabled, BotToken, ChannelID, UserID
    global BotGatewayPID, BotGatewayFingerprint

    if (!BotEnabled || BotToken = ""
        || !Discord.IsValidSnowflake(ChannelID) || !Discord.IsValidSnowflake(UserID)) {
        DiscordGatewayStop()
        return
    }

    worker := DiscordGatewayWorkerPath()
    node := DiscordGatewayFindNode()
    if !FileExist(worker) {
        DiscordGatewayStop()
        DiscordGatewayWriteLocalStatus("error", "The slash-command worker is missing from this build.")
        return
    }
    if (node = "") {
        DiscordGatewayStop()
        DiscordGatewayWriteLocalStatus("error", "Node.js 22 or newer was not found.")
        return
    }

    fingerprint := BotToken "|" ChannelID "|" UserID
    if (BotGatewayPID && ProcessExist(BotGatewayPID) && BotGatewayFingerprint = fingerprint)
        return

    DiscordGatewayStop()
    DiscordGatewayEnsureDirectories()
    DiscordGatewayWriteLocalStatus("starting", "Starting the slash-command worker.")

    previousToken := EnvGet("ULTIMATE_MACRO_DISCORD_TOKEN")
    previousChannel := EnvGet("ULTIMATE_MACRO_DISCORD_CHANNEL_ID")
    previousUser := EnvGet("ULTIMATE_MACRO_DISCORD_USER_ID")
    previousDir := EnvGet("ULTIMATE_MACRO_DISCORD_GATEWAY_DIR")
    try {
        EnvSet("ULTIMATE_MACRO_DISCORD_TOKEN", BotToken)
        EnvSet("ULTIMATE_MACRO_DISCORD_CHANNEL_ID", ChannelID)
        EnvSet("ULTIMATE_MACRO_DISCORD_USER_ID", UserID)
        EnvSet("ULTIMATE_MACRO_DISCORD_GATEWAY_DIR", BotGatewayDir)
        Run('"' node '" "' worker '"', A_ScriptDir, "Hide", &newPID)
        BotGatewayPID := newPID
        BotGatewayFingerprint := fingerprint
        RuntimeLogInfo("discord_gateway_started", "Slash-command gateway worker launched",
            "pid=" BotGatewayPID "; registration_scope=all_servers")
    } catch Error as err {
        BotGatewayPID := 0
        BotGatewayFingerprint := ""
        DiscordGatewayWriteLocalStatus("error", "Could not start the slash-command worker.")
        RuntimeLogWarn("discord_gateway_start_failed", "Could not launch slash-command gateway worker",
            "error=" err.Message)
    } finally {
        EnvSet("ULTIMATE_MACRO_DISCORD_TOKEN", previousToken)
        EnvSet("ULTIMATE_MACRO_DISCORD_CHANNEL_ID", previousChannel)
        EnvSet("ULTIMATE_MACRO_DISCORD_USER_ID", previousUser)
        EnvSet("ULTIMATE_MACRO_DISCORD_GATEWAY_DIR", previousDir)
    }
}

DiscordGatewayStop() {
    global BotGatewayPID, BotGatewayFingerprint
    if (BotGatewayPID && ProcessExist(BotGatewayPID)) {
        try ProcessClose(BotGatewayPID)
    }
    BotGatewayPID := 0
    BotGatewayFingerprint := ""
}

DiscordGatewayReadCommands() {
    global BotGatewayDir, ChannelID, UserID, BotPrefix, command_buffer
    commandDir := BotGatewayDir "\commands"
    if !DirExist(commandDir)
        return

    loop files, commandDir "\*.json", "F" {
        commandPath := A_LoopFileFullPath
        try {
            job := JSON.parse(FileRead(commandPath, "UTF-8"))
            FileDelete(commandPath)
            if !job.Has("interaction") || !job.Has("name")
                continue

            interaction := job["interaction"]
            authorized := job.Has("user_id") && String(job["user_id"]) = String(UserID)
                && job.Has("channel_id") && String(job["channel_id"]) = String(ChannelID)
            name := StrLower(String(job["name"]))
            content := authorized ? BotPrefix name : BotPrefix "private"
            if (authorized && name = "strat" && job.Has("argument") && String(job["argument"]) != "")
                content .= " " String(job["argument"])

            command_buffer.Push({
                content: content,
                id: "slash-" String(job["id"]),
                url: "",
                user_id: job.Has("user_id") ? String(job["user_id"]) : "",
                interaction: interaction,
                source: "gateway"
            })
        } catch Error as err {
            try FileDelete(commandPath)
            RuntimeLogWarn("discord_gateway_command_failed", "Discarded invalid gateway command file",
                "error=" err.Message)
        }
    }
}

DiscordGatewayWriteLocalStatus(state, message := "") {
    global BotGatewayStatusFile
    status := Map(
        "state", state,
        "message", message,
        "guild_count", 0,
        "updated_at", A_NowUTC
    )
    tempPath := BotGatewayStatusFile ".tmp"
    try FileDelete(tempPath)
    try {
        FileAppend(JSON.stringify(status), tempPath, "UTF-8")
        FileMove(tempPath, BotGatewayStatusFile, 1)
    }
}

DiscordGatewayHealthSummary() {
    global BotGatewayStatusFile
    if !FileExist(BotGatewayStatusFile)
        return "not running"
    try {
        status := JSON.parse(FileRead(BotGatewayStatusFile, "UTF-8"))
        if status.Has("state") {
            summary := ""
            switch status["state"] {
                case "ready":
                    summary := "connected"
                case "starting":
                    summary := "starting"
                case "error":
                    summary := "error"
                default:
                    summary := String(status["state"])
            }
            if status.Has("message") && String(status["message"]) != "" && summary != "connected"
                return summary ": " Discord.TruncateText(status["message"], 120)
            return summary
        }
    }
    return "unknown"
}
