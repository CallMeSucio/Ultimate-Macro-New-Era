class Discord
{
    static baseURL := "https://discord.com/api/v10/"
    static ComponentsV2Flag := 32768
    static ColorInfo := 0x5865F2
    static ColorSuccess := 0x55C477
    static ColorWarning := 0xE8A24A
    static ColorDanger := 0xF06B7A
    static ColorNeutral := 0x657084
    static ColorPurple := 0xA970FF
    static LastStatus := 0
    static LastResponseText := ""
    static LastError := ""

    static EscapeJson(value)
    {
        value := String(value)
        value := StrReplace(value, "\r\n", "`n")
        value := StrReplace(value, "\n", "`n")
        value := StrReplace(value, "\t", "`t")
        value := StrReplace(value, "\", "\\")
        value := StrReplace(value, '"', '\"')
        value := StrReplace(value, "`r", "")
        value := StrReplace(value, "`n", "\n")
        value := StrReplace(value, "`t", "\t")
        return value
    }

    static SendEmbed(message, color := 0x5865F2, content := "", pBitmap := 0, channel := "", replyID := 0)
    {
        if (content != "")
            message := content "`n`n" message
        if pBitmap
            return this.SendScreenshot(pBitmap, message, color, channel, replyID)
        return this.SendCard(message, color, , channel, replyID)
    }

    static SendCard(message, color := 0x5865F2, buttons := "", channel := "", replyID := 0)
    {
        children := [Map("type", 10, "content", this.TruncateText(message, 3900))]
        buttonRow := this.BuildButtonRow(buttons)
        if (Type(buttonRow) = "Map") {
            children.Push(Map("type", 14, "divider", JSON.true, "spacing", 1))
            children.Push(buttonRow)
        }

        payload := this.BuildComponentsPayload(children, color, replyID)
        return this.SendMessageAPI(payload, "application/json", channel)
    }

    static SendConnectionNotice(prefix := "!", channel := "", gatewayEnabled := false)
    {
        commandHint := prefix "help"
        if gatewayEnabled
            commandHint .= " or /help"
        message := "**Connected to Discord**`n"
            . "The personal bot is online and ready for commands.`n`n"
            . "Try " commandHint " to see what is available.`n`n"
            . "If it does not reply, enable Message Content Intent under Developer Portal > Bot and check View Channel, Send Messages and Read Message History."
        buttons := [
            Map("label", "Bot not responding?", "url", "https://support-dev.discord.com/hc/en-us/articles/4404772028055-Message-Content-Privileged-Intent-FAQ"),
            Map("label", "Open Developer Portal", "url", "https://discord.com/developers/applications")
        ]
        if gatewayEnabled
            buttons.Push(Map("label", "Health check", "custom_id", "bot:health"))
        return this.SendCard(message, this.ColorSuccess, buttons, channel)
    }

    static BuildButtonRow(buttons)
    {
        if !IsObject(buttons)
            return []

        row := []
        for button in buttons {
            if !IsObject(button) || !button.Has("label")
                continue

            payload := Map("type", 2, "label", SubStr(String(button["label"]), 1, 80))
            if button.Has("url") {
                payload["style"] := 5
                payload["url"] := String(button["url"])
            } else if button.Has("custom_id") {
                payload["style"] := button.Has("style") ? Integer(button["style"]) : 2
                payload["custom_id"] := String(button["custom_id"])
            } else {
                continue
            }
            row.Push(payload)
            if row.Length >= 5
                break
        }

        return row.Length ? Map("type", 1, "components", row) : []
    }

    static BuildStringSelectRow(customID, options, placeholder := "Choose an option")
    {
        if !IsObject(options)
            return []

        normalized := []
        for option in options {
            if !IsObject(option) || !option.Has("label") || !option.Has("value")
                continue
            normalized.Push(Map(
                "label", this.TruncateText(String(option["label"]), 100),
                "value", this.TruncateText(String(option["value"]), 100)
            ))
            if normalized.Length >= 25
                break
        }

        if !normalized.Length
            return []

        select := Map(
            "type", 3,
            "custom_id", this.TruncateText(String(customID), 100),
            "placeholder", this.TruncateText(String(placeholder), 150),
            "min_values", 1,
            "max_values", 1,
            "options", normalized
        )
        return Map("type", 1, "components", [select])
    }

    static BuildComponentsPayload(children, color := 0x5865F2, replyID := 0)
    {
        colorValue := IsNumber(color) ? Integer(color) : this.ColorInfo
        payload := Map(
            "flags", this.ComponentsV2Flag,
            "allowed_mentions", Map("parse", []),
            "components", [Map("type", 17, "accent_color", colorValue, "components", children)]
        )

        replyID := this.ResolveReplyID(replyID)
        if (replyID != 0)
            payload["message_reference"] := Map("message_id", String(replyID), "fail_if_not_exists", JSON.false)

        return JSON.stringify(payload, 0, "")
    }

    static SendComponents(children, color := 0x5865F2, channel := "", replyID := 0)
    {
        payload := this.BuildComponentsPayload(children, color, replyID)
        return this.SendMessageAPI(payload, "application/json", channel)
    }

    static ResolveReplyID(replyID := 0)
    {
        if (replyID != 0)
            return replyID
        global BotActiveInteraction
        if IsObject(BotActiveInteraction)
            return 0
        global BotActiveReplyID
        return IsSet(BotActiveReplyID) ? BotActiveReplyID : 0
    }

    static TruncateText(value, maxChars := 3900)
    {
        value := String(value)
        return StrLen(value) <= maxChars ? value : SubStr(value, 1, maxChars - 3) "..."
    }

    static IsValidSnowflake(value)
    {
        return RegExMatch(Trim(String(value)), "^\d{15,22}$")
    }

    static SendScreenshot(pBitmap := 0, description := "", color := 12434877, channel := "", replyID := 0)
    {
        colorValue := IsNumber(color) ? Integer(color) : this.ColorInfo
        children := [Map("type", 10, "content", this.TruncateText(description != "" ? description : "Screenshot", 3900))]
        fields := []

        if pBitmap {
            children.Push(Map(
                "type", 12,
                "items", [Map(
                    "media", Map("url", "attachment://screenshot.png"),
                    "description", "Screenshot from Ultimate Macro"
                )]
            ))
        }

        payload_json := this.BuildComponentsPayload(children, colorValue, replyID)
        fields.Push(Map("name", "payload_json", "content-type", "application/json", "content", payload_json))

        if pBitmap
            fields.Push(Map("name", "files[0]", "filename", "screenshot.png", "content-type", "image/png", "pBitmap", pBitmap))

        this.CreateFormData(&postdata, &contentType, fields)
        return this.SendMessageAPI(postdata, contentType, channel)
    }

    static SendImage(pBitmap, imgname := "image.png", replyID := 0)
    {
        children := [Map(
            "type", 12,
            "items", [Map("media", Map("url", "attachment://" imgname), "description", "Image from Ultimate Macro")]
        )]
        params := [Map(
            "name", "payload_json",
            "content-type", "application/json",
            "content", this.BuildComponentsPayload(children, this.ColorInfo, replyID)
        )]
        params.Push(Map("name", "files[0]", "filename", imgname, "content-type", "image/png", "pBitmap", pBitmap))
        this.CreateFormData(&postdata, &contentType, params)
        return this.SendMessageAPI(postdata, contentType)
    }

    static SendMessageAPI(postdata, contentType := "application/json", channel := "", url := "")
    {
        global ChannelID
        global BotActiveInteraction, BotInteractionReplied

        interactionRequest := false
        requestMethod := "POST"

        if !url {
            if IsObject(BotActiveInteraction) && BotActiveInteraction.Has("application_id")
                && BotActiveInteraction.Has("token") {
                interactionRequest := true
                url := this.baseURL "webhooks/" BotActiveInteraction["application_id"] "/" BotActiveInteraction["token"]
                if !BotInteractionReplied {
                    requestMethod := "PATCH"
                    url .= "/messages/@original"
                    BotInteractionReplied := true
                }
            } else {
                if (!channel && ChannelID)
                    channel := ChannelID
                url := this.baseURL "channels/" channel "/messages"
            }
        }

        return this.Request(requestMethod, url, postdata, contentType, 3, !interactionRequest)
    }

    static GetCommands(channel)
    {
        global UserID, BotPrefix, command_buffer
        messages := this.GetRecentMessages(channel)

        for msg in messages {
            if !msg.Has("author") || msg["author"]["id"] != UserID
                continue

            content := Trim(msg["content"])
            prefix := SubStr(content, 1, 1)
            if (prefix != "!" && prefix != BotPrefix)
                continue
            if (IsSet(BotSeenCommandIDs) && BotSeenCommandIDs.Has(msg["id"]))
                continue

            attachmentURL := ""
            if msg.Has("attachments") {
                attachments := msg["attachments"]
                if (Type(attachments) = "Array" && attachments.Length > 0) {
                    firstAttachment := attachments[1]
                    if (IsObject(firstAttachment) && firstAttachment.Has("url"))
                        attachmentURL := String(firstAttachment["url"])
                }
            }

            command_buffer.Push({
                content: content,
                id: msg["id"],
                url: attachmentURL,
                user_id: msg["author"]["id"]
            })
            if IsSet(BotSeenCommandIDs) {
                BotSeenCommandIDs[msg["id"]] := A_TickCount
                if (BotSeenCommandIDs.Count > 500) {
                    for seenID, seenTick in BotSeenCommandIDs {
                        BotSeenCommandIDs.Delete(seenID)
                        break
                    }
                }
            }
        }
    }

    static GetChannel(channelid)
    {
        return this.Request("GET", this.baseURL "channels/" channelid)
    }

    static GetMember(guild_id, user_id)
    {
        return this.Request("GET", this.baseURL "guilds/" guild_id "/members/" user_id)
    }

    static GetRecentMessages(channel)
    {
        static lastmsg := Map()

        if !lastmsg.Has(channel) {
            try
                firstMessages := JSON.parse(this.GetMessageAPI("?limit=1", channel))
            catch
                return []

            if (Type(firstMessages) = "Array" && firstMessages.Length > 0)
                lastmsg[channel] := firstMessages[1]["id"]
            return []
        }

        try
            messages := JSON.parse(this.GetMessageAPI("?after=" lastmsg[channel] "&limit=100", channel))
        catch
            return []

        if (Type(messages) = "Array" && messages.Length > 0)
            lastmsg[channel] := messages[1]["id"]

        return messages
    }

    static GetMessageAPI(params := "", channel := "")
    {
        global ChannelID
        if !channel
            channel := ChannelID
        return this.Request("GET", this.baseURL "channels/" channel "/messages" params)
    }

    static Request(method, url, body?, contentType := "", maxAttempts := 3, useBotToken := true)
    {
        global BotToken
        lastResponse := ""
        this.LastStatus := 0
        this.LastResponseText := ""
        this.LastError := ""

        loop maxAttempts {
            try {
                wr := ComObject("WinHttp.WinHttpRequest.5.1")
                wr.Option[9] := 2720
                wr.Open(method, url, false)
                wr.SetRequestHeader("User-Agent", "DiscordBot (AHK, " A_AhkVersion ")")
                if (useBotToken && BotToken != "")
                    wr.SetRequestHeader("Authorization", "Bot " BotToken)
                if (contentType != "")
                    wr.SetRequestHeader("Content-Type", contentType)
                wr.SetTimeouts(5000, 5000, 15000, 15000)

                if IsSet(body)
                    wr.Send(body)
                else
                    wr.Send()

                status := wr.Status
                lastResponse := wr.ResponseText
                this.LastStatus := status
                this.LastResponseText := lastResponse

                if (status = 429) {
                    if (A_Index = maxAttempts)
                        return lastResponse
                    Sleep(this.GetRetryDelayMs(wr, lastResponse))
                    continue
                }

                if (status >= 500 && status <= 599) {
                    if (A_Index = maxAttempts)
                        return lastResponse
                    Sleep(Min(5000, 750 * A_Index))
                    continue
                }

                return lastResponse
            } catch Error as err {
                this.LastError := err.Message
                if (A_Index = maxAttempts)
                    return lastResponse
                Sleep(Min(5000, 750 * A_Index))
            }
        }

        return lastResponse
    }

    static GetRetryDelayMs(wr, responseText := "")
    {
        seconds := 0

        try {
            header := Trim(wr.GetResponseHeader("Retry-After"))
            if IsNumber(header)
                seconds := Number(header)
        }

        if (seconds <= 0) {
            try {
                parsed := JSON.parse(responseText)
                if parsed.Has("retry_after") && IsNumber(parsed["retry_after"])
                    seconds := Number(parsed["retry_after"])
            }
        }

        if (seconds <= 0) {
            try {
                header := Trim(wr.GetResponseHeader("X-RateLimit-Reset-After"))
                if IsNumber(header)
                    seconds := Number(header)
            }
        }

        if (seconds <= 0)
            seconds := 1

        return Min(30000, Max(500, Ceil(seconds * 1000) + 150))
    }

    static SaveProtectedToken(settingsPath, token)
    {
        token := String(token)
        if (token = "") {
            try IniDelete(settingsPath, "Token", "TokenProtected")
            try IniDelete(settingsPath, "Token", "BotToken")
            return
        }

        input := Buffer(StrPut(token, "UTF-8"), 0)
        size := StrPut(token, input, "UTF-8") - 1
        inputBlob := Buffer(A_PtrSize = 8 ? 16 : 8, 0)
        outputBlob := Buffer(A_PtrSize = 8 ? 16 : 8, 0)
        NumPut("UInt", size, inputBlob, 0)
        NumPut("Ptr", input.Ptr, inputBlob, A_PtrSize)

        if !DllCall("Crypt32\CryptProtectData", "Ptr", inputBlob.Ptr, "Ptr", 0, "Ptr", 0, "Ptr", 0,
            "Ptr", 0, "UInt", 0x1, "Ptr", outputBlob.Ptr)
            throw Error("Windows could not protect the Discord bot token.")

        protectedSize := NumGet(outputBlob, 0, "UInt")
        protectedPtr := NumGet(outputBlob, A_PtrSize, "Ptr")
        try IniWrite(this.Base64EncodeBuffer(protectedPtr, protectedSize), settingsPath, "Token", "TokenProtected")
        finally DllCall("Kernel32\LocalFree", "Ptr", protectedPtr)
        try IniDelete(settingsPath, "Token", "BotToken")
    }

    static LoadProtectedToken(settingsPath)
    {
        encoded := IniRead(settingsPath, "Token", "TokenProtected", "")
        if (encoded = "") {
            legacy := IniRead(settingsPath, "Token", "BotToken", "")
            if (legacy != "") {
                this.SaveProtectedToken(settingsPath, legacy)
                return legacy
            }
            return ""
        }

        try encrypted := this.Base64Decode(encoded)
        catch
            return ""

        inputBlob := Buffer(A_PtrSize = 8 ? 16 : 8, 0)
        outputBlob := Buffer(A_PtrSize = 8 ? 16 : 8, 0)
        NumPut("UInt", encrypted.Size, inputBlob, 0)
        NumPut("Ptr", encrypted.Ptr, inputBlob, A_PtrSize)
        if !DllCall("Crypt32\CryptUnprotectData", "Ptr", inputBlob.Ptr, "Ptr", 0, "Ptr", 0, "Ptr", 0,
            "Ptr", 0, "UInt", 0x1, "Ptr", outputBlob.Ptr)
            return ""

        plainSize := NumGet(outputBlob, 0, "UInt")
        plainPtr := NumGet(outputBlob, A_PtrSize, "Ptr")
        try return StrGet(plainPtr, plainSize, "UTF-8")
        finally DllCall("Kernel32\LocalFree", "Ptr", plainPtr)
    }

    static Base64EncodeBuffer(pointer, size)
    {
        chars := 0
        DllCall("Crypt32\CryptBinaryToStringW", "Ptr", pointer, "UInt", size, "UInt", 0x40000001,
            "Ptr", 0, "UIntP", &chars)
        output := Buffer(chars * 2)
        if !DllCall("Crypt32\CryptBinaryToStringW", "Ptr", pointer, "UInt", size, "UInt", 0x40000001,
            "Ptr", output.Ptr, "UIntP", &chars)
            throw Error("Could not protect the Discord bot token.")
        return StrGet(output, "UTF-16")
    }

    static Base64Decode(value)
    {
        size := 0
        if !DllCall("Crypt32\CryptStringToBinaryW", "Str", value, "UInt", 0, "UInt", 1, "Ptr", 0,
            "UIntP", &size, "Ptr", 0, "Ptr", 0)
            throw Error("The protected Discord bot token could not be decoded.")
        decodedBytes := Buffer(size)
        if !DllCall("Crypt32\CryptStringToBinaryW", "Str", value, "UInt", 0, "UInt", 1,
            "Ptr", decodedBytes.Ptr, "UIntP", &size, "Ptr", 0, "Ptr", 0)
            throw Error("The protected Discord bot token could not be decoded.")
        return decodedBytes
    }

    static CreateFormData(&retData, &contentType, fields)
    {
        static chars := "0|1|2|3|4|5|6|7|8|9|a|b|c|d|e|f|g|h|i|j|k|l|m|n|o|p|q|r|s|t|u|v|w|x|y|z"

        chars := Sort(chars, "D| Random")
        boundary := SubStr(StrReplace(chars, "|"), 1, 12)
        hData := DllCall("GlobalAlloc", "UInt", 0x2, "UPtr", 0, "Ptr")
        if !hData
            throw Error("Unable to allocate multipart buffer")

        pStream := 0
        if DllCall("ole32\CreateStreamOnHGlobal", "Ptr", hData, "Int", 0, "PtrP", &pStream, "UInt") {
            DllCall("GlobalFree", "Ptr", hData, "Ptr")
            throw Error("Unable to create multipart stream")
        }

        pData := 0
        try {
            for field in fields
            {
                str :=
                (
                    '
                    
                    ------------------------------' boundary '
                    Content-Disposition: form-data; name="' field["name"] '"' (field.Has("filename") ? ('; filename="' field["filename"] '"') : "") '
                    Content-Type: ' field["content-type"] '
                    
                    ' (field.Has("content") ? (field["content"] "`r`n") : "")
                )

                utf8 := Buffer(length := StrPut(str, "UTF-8") - 1)
                StrPut(str, utf8, length, "UTF-8")
                DllCall("shlwapi\IStream_Write", "Ptr", pStream, "Ptr", utf8.Ptr, "UInt", length, "UInt")

                if field.Has("pBitmap")
                {
                    pFileStream := 0
                    try {
                        pFileStream := Gdip_SaveBitmapToStream(field["pBitmap"])
                        if !pFileStream
                            throw Error("Unable to encode screenshot")
                        DllCall("shlwapi\IStream_Size", "Ptr", pFileStream, "UInt64P", &size := 0, "UInt")
                        DllCall("shlwapi\IStream_Reset", "Ptr", pFileStream, "UInt")
                        DllCall("shlwapi\IStream_Copy", "Ptr", pFileStream, "Ptr", pStream, "UInt", size, "UInt")
                    } finally {
                        if pFileStream
                            ObjRelease(pFileStream)
                    }
                }

                if field.Has("file")
                {
                    pFileStream := 0
                    try {
                        DllCall("shlwapi\SHCreateStreamOnFileEx", "WStr", field["file"], "Int", 0, "UInt", 0x80, "Int", 0, "Ptr", 0, "PtrP", &pFileStream)
                        if !pFileStream
                            throw Error("Unable to open multipart file")
                        DllCall("shlwapi\IStream_Size", "Ptr", pFileStream, "UInt64P", &size := 0, "UInt")
                        DllCall("shlwapi\IStream_Copy", "Ptr", pFileStream, "Ptr", pStream, "UInt", size, "UInt")
                    } finally {
                        if pFileStream
                            ObjRelease(pFileStream)
                    }
                }
            }

            str := "`r`n------------------------------" boundary "--`r`n"
            utf8 := Buffer(length := StrPut(str, "UTF-8") - 1)
            StrPut(str, utf8, length, "UTF-8")
            DllCall("shlwapi\IStream_Write", "Ptr", pStream, "Ptr", utf8.Ptr, "UInt", length, "UInt")

            pData := DllCall("GlobalLock", "Ptr", hData, "Ptr")
            if !pData
                throw Error("Unable to lock multipart buffer")

            size := DllCall("GlobalSize", "Ptr", hData, "UPtr")
            retData := ComObjArray(0x11, size)
            pvData := NumGet(ComObjValue(retData), 8 + A_PtrSize, "Ptr")
            DllCall("RtlMoveMemory", "Ptr", pvData, "Ptr", pData, "UPtr", size)
        } finally {
            if pData
                DllCall("GlobalUnlock", "Ptr", hData)
            if pStream
                ObjRelease(pStream)
            DllCall("GlobalFree", "Ptr", hData, "Ptr")
        }

        contentType := "multipart/form-data; boundary=----------------------------" boundary
    }
}
