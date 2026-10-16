OppositeShardMoveKey136(key) {
    key := StrUpper(Trim(String(key)))
    opposite := Map("W", "S", "S", "W", "A", "D", "D", "A")
    return opposite.Has(key) ? opposite[key] : ""
}

ReverseShardMovementRoute136(route) {
    if !IsObject(route) || Type(route) != "Array"
        return []

    reversed := []
    loop route.Length {
        segment := route[route.Length - A_Index + 1]
        if !IsObject(segment) || !HasProp(segment, "key") || !HasProp(segment, "ms")
            return []

        key := OppositeShardMoveKey136(segment.key)
        if (key = "" || !IsNumber(segment.ms))
            return []

        duration := Integer(segment.ms)
        if (duration < 1 || duration > 500)
            return []

        reversed.Push({ key: key, ms: duration })
    }

    return reversed
}

ParseShardCount136(text) {
    if !RegExMatch(Trim(String(text)), "^(\d{1,6}|\d{1,3}(?:,\d{3}){1,2})$", &match)
        return ""
    return Integer(StrReplace(match[1], ",", ""))
}

ShardCountIncreased136(before, after) {
    return IsNumber(before) && IsNumber(after) && Integer(after) > Integer(before)
}

FindVisibleShard136(screenX, screenY, width, height) {
    best := false
    for name in ["ShardA.png", "ShardB.png", "ShardC.png", "ShardD.png"] {
        path := A_ScriptDir "\Resources\Shards\" name
        if !FileExist(path)
            continue

        ; Exclude the HUD counter and hotbar so their shard icon cannot trigger walking.
        match := AdvancedImageSearch(path, 0, Round(height * 0.13), width, Round(height * 0.73), 0.35, 1.25, 0.10)
        if (match.status = "success" && match.score >= 0.82
            && (!best || match.score > best.score)) {
            best := {
                x: match.x, y: match.y,
                w: HasProp(match, "w") ? match.w : 1,
                h: HasProp(match, "h") ? match.h : 1,
                score: match.score, template: name, path: path, kind: "shard"
            }
        }
    }
    return best
}

FindVisibleEventPickup136(screenX, screenY, width, height) {
    shard := FindVisibleShard136(screenX, screenY, width, height)
    if shard
        return shard
    for name in ["LogbookA.png", "LogbookB.png", "LogbookC.png"] {
        path := A_ScriptDir "\Resources\Logbooks\" name
        if !FileExist(path)
            continue
        match := AdvancedImageSearch(path, 0, Round(height * 0.13), width, Round(height * 0.73), 0.35, 1.25, 0.10)
        if match.status = "success" && match.score >= 0.82
            return { x: match.x, y: match.y, w: HasProp(match, "w") ? match.w : 1,
                h: HasProp(match, "h") ? match.h : 1, score: match.score,
                template: name, path: path, kind: "logbook" }
    }
    return false
}

VerifyEventPickupGone136(original, width, height) {
    if !HasProp(original, "path") || !FileExist(original.path)
        return false
    if !GetRobloxScreenClientRect(&screenX, &screenY, &currentW, &currentH)
        || currentW != width || currentH != height
        return false
    searchX := Max(0, original.x - 120)
    searchY := Max(0, original.y - 120)
    loop 2 {
        match := AdvancedImageSearch(original.path, searchX, searchY,
            Min(240, width - searchX), Min(240, height - searchY), 0.35, 1.25, 0.10)
        if match.status = "success" {
            if match.score >= 0.82
                return false
        } else if !InStr(match.message, "image not found") {
            return false
        }
        Sleep(150)
    }
    return true
}

ReadShardCount136(screenX, screenY, width, height) {
    try {
        textResult := ReadGameText136(
            screenX + Round(width * 0.91),
            screenY + Round(height * 0.015),
            Round(width * 0.085),
            Round(height * 0.075),
            { lang: "en-US", scale: 2, grayscale: 1 }
        )
        return ParseShardCount136(textResult.Text)
    } catch Error {
        return ""
    }
}

CaptureShardCameraAnchors136(screenX, screenY, width, height) {
    anchors := []
    regions := [
        { x: Round(width * 0.035), y: Round(height * 0.30), w: Round(width * 0.15), h: Round(height * 0.12) },
        { x: Round(width * 0.815), y: Round(height * 0.30), w: Round(width * 0.15), h: Round(height * 0.12) }
    ]

    for index, region in regions {
        path := A_Temp "\um_shard_anchor_" DllCall("GetCurrentProcessId") "_" index ".png"
        bitmap := Gdip_BitmapFromScreen(
            (screenX + region.x) "|" (screenY + region.y) "|" region.w "|" region.h
        )
        if !bitmap {
            CleanupShardCameraAnchors136(anchors)
            return []
        }

        saveStatus := Gdip_SaveBitmapToFile(bitmap, path, 90)
        Gdip_DisposeImage(bitmap)
        if (saveStatus != 0 || !FileExist(path)) {
            CleanupShardCameraAnchors136(anchors)
            try FileDelete(path)
            return []
        }

        anchors.Push({ path: path, x: region.x, y: region.y, w: region.w, h: region.h })
    }
    return anchors
}

CleanupShardCameraAnchors136(anchors) {
    if !IsObject(anchors)
        return
    for anchor in anchors {
        if (IsObject(anchor) && HasProp(anchor, "path"))
            try FileDelete(anchor.path)
    }
}

VerifyShardCameraAnchors136(anchors) {
    if !IsObject(anchors) || anchors.Length != 2
        return false
    if !GetRobloxScreenClientRect(&screenX, &screenY, &width, &height)
        return false

    for anchor in anchors {
        match := AdvancedImageSearch(anchor.path, Max(0, anchor.x - 8), Max(0, anchor.y - 8),
            anchor.w + 16, anchor.h + 16, 0.95, 1.10, 0.05)
        if (match.status != "success" || match.score < 0.90
            || Abs(match.x - (anchor.x + Round(anchor.w / 2))) > 8
            || Abs(match.y - (anchor.y + Round(anchor.h / 2))) > 8)
            return false
    }
    return true
}

StopAfterShardPickupFailure136(reason) {
    global RunningStrategy, StateFile, canUseAbility, canBeUpgraded
    RuntimeLogWarn("shard_pickup_stopped", "Strategy stopped because shard pickup or return could not be verified",
        "reason=" reason)
    LogToConsole("Shard collection could not be safely verified. Strategy stopped to protect tower placements.", true)
    RunningStrategy := false
    canUseAbility := false
    canBeUpgraded := false
    StopRuntimeTimers()
    try IniWrite(0, StateFile, "State", "Running")
    return false
}

ShardApproachPulse136(match, screenX, screenY, width, height) {
    ; Image-search coordinates are already centers relative to the Roblox client.
    dx := match.x - Round(width * 0.50)
    dy := match.y - Round(height * 0.62)
    if (Abs(dx) <= 18 && Abs(dy) <= 24)
        return false
    direction := Abs(dx) >= Abs(dy) ? (dx > 0 ? "D" : "A") : (dy > 0 ? "S" : "W")
    return { key: direction, ms: Max(60, Min(140, Round(Max(Abs(dx), Abs(dy)) / Max(width, height) * 520))) }
}

ReadStableShardCount136(screenX, screenY, width, height) {
    first := ReadShardCount136(screenX, screenY, width, height)
    Sleep(80)
    second := ReadShardCount136(screenX, screenY, width, height)
    return IsNumber(first) && IsNumber(second) && first = second ? second : ""
}

MoveShardPulse136(key, duration, route) {
    hwnd := GetRobloxHWND()
    if !hwnd || !WinActive("ahk_id " hwnd)
        throw Error("Roblox lost focus during shard collection")
    started := A_TickCount
    held := false
    try {
        SendEvent("{" key " down}")
        held := true
        HyperSleep(duration)
    } finally {
        if held {
            elapsed := Max(1, A_TickCount - started)
            route.Push({ key: key, ms: Min(500, elapsed) })
            SendEvent("{" key " up}")
            if elapsed > 500
                throw Error("Movement pulse exceeded its safety limit")
        }
    }
}

ReturnShardRoute136(route) {
    reversed := ReverseShardMovementRoute136(route)
    if reversed.Length != route.Length
        throw Error("Invalid shard return route")
    for segment in reversed {
        discardedJournal := []
        MoveShardPulse136(segment.key, segment.ms, discardedJournal)
        Sleep(100)
    }
}

SleepWithShardCollection136(duration) {
    global AutoCollectShards, RunningStrategy
    if !AutoCollectShards || duration < 15000 {
        Sleep(duration)
        return RunningStrategy
    }
    deadline := A_TickCount + duration
    while RunningStrategy {
        remaining := deadline - A_TickCount
        if remaining <= 0
            return true
        if remaining >= 15000 && !TryAutoCollectShard136(12000)
            return false
        remaining := deadline - A_TickCount
        if remaining > 0
            Sleep(Min(250, remaining))
    }
    return false
}

TryAutoCollectShard136(budgetMs := 12000) {
    global LegacyMode
    global RunningStrategy, AutoCollectShards, ShardPickupBusy136
    global canUseAbility, canBeUpgraded, needtocheckTowerUI, LastOpenedTowerID, CancelPlacementKey
    static lastScanAt := -5000
    if !RunningStrategy
        return false
    if !AutoCollectShards || ShardPickupBusy136
        return true
    ; Never scan or move for ordinary Survival strategies, even with a stray ON flag.
    if ResolveSolarNight136() = ""
        return true
    if LegacyMode {
        static legacyNoticeShown := false
        if !legacyNoticeShown {
            RuntimeLogWarn("shard_legacy_unsupported", "Shard collection requires the default image-search mode; no movement was sent")
            legacyNoticeShown := true
        }
        return true
    }
    if A_TickCount - lastScanAt < 4000
        return true
    lastScanAt := A_TickCount
    collectionDeadline := A_TickCount + Max(0, Min(12000, budgetMs))

    if !GetRobloxScreenClientRect(&screenX, &screenY, &width, &height)
        return true
    match := FindVisibleEventPickup136(screenX, screenY, width, height)
    if !match
        return true
    Sleep(120)
    stableMatch := FindVisibleEventPickup136(screenX, screenY, width, height)
    if !stableMatch || stableMatch.kind != match.kind
        || Abs(stableMatch.x - match.x) > 50 || Abs(stableMatch.y - match.y) > 50
        return true

    ShardPickupBusy136 := true
    previousAbilities := canUseAbility
    previousUpgrades := canBeUpgraded
    canUseAbility := false
    canBeUpgraded := false
    movementJournal := []
    anchors := []
    collected := false
    restored := false
    failure := ""
    beforeCount := ""
    afterCount := ""
    try {
        ActivateRoblox()
        SendEvent("{" CancelPlacementKey "}")
        LastOpenedTowerID := ""
        needtocheckTowerUI := true
        Sleep(100)
        if match.kind = "shard" {
            beforeCount := ReadStableShardCount136(screenX, screenY, width, height)
            if !IsNumber(beforeCount) {
                RuntimeLogWarn("shard_counter_unreadable", "Collection skipped because the shard counter could not be read twice")
                return true
            }
        }
        if A_TickCount >= collectionDeadline - 3500
            return true
        anchors := CaptureShardCameraAnchors136(screenX, screenY, width, height)
        if anchors.Length != 2 {
            RuntimeLogWarn("shard_anchor_capture_failed", "Collection skipped because the original view could not be captured")
            return true
        }
        LogToConsole("Event drop detected (" match.kind "). Attempting collection and return.", true)
        loop 8 {
            if !RunningStrategy
                break
            if A_TickCount >= collectionDeadline - 3500
                break
            if !GetRobloxScreenClientRect(&currentX, &currentY, &currentW, &currentH)
                throw Error("Roblox client geometry disappeared")
            if currentX != screenX || currentY != screenY || currentW != width || currentH != height
                throw Error("Roblox window moved or resized during collection")
            current := FindVisibleEventPickup136(screenX, screenY, width, height)
            if !current || current.kind != match.kind
                break
            pulse := ShardApproachPulse136(current, screenX, screenY, width, height)
            if pulse
                MoveShardPulse136(pulse.key, pulse.ms, movementJournal)
            Sleep(180)
            if match.kind = "shard" {
                afterCount := ReadStableShardCount136(screenX, screenY, width, height)
                if ShardCountIncreased136(beforeCount, afterCount) {
                    collected := true
                    break
                }
            }
        }
        if !collected && match.kind = "shard" {
            Sleep(250)
            afterCount := ReadStableShardCount136(screenX, screenY, width, height)
            collected := ShardCountIncreased136(beforeCount, afterCount)
        }
    } catch Error as pickupError {
        failure := pickupError.Message
    } finally {
        ; Returning is attempted even if counter recognition or collection failed.
        try {
            if movementJournal.Length
                ReturnShardRoute136(movementJournal)
            Sleep(350)
            restored := anchors.Length = 2 && VerifyShardCameraAnchors136(anchors)
            if restored && match.kind = "logbook" && movementJournal.Length
                collected := VerifyEventPickupGone136(match, width, height)
        } catch Error as returnError {
            failure := failure " return: " returnError.Message
            restored := false
        }
        CleanupShardCameraAnchors136(anchors)
        ShardPickupBusy136 := false
        canUseAbility := RunningStrategy ? previousAbilities : false
        canBeUpgraded := RunningStrategy ? previousUpgrades : false
        LastOpenedTowerID := ""
        needtocheckTowerUI := true
    }
    if !RunningStrategy
        return false
    if failure != "" || !collected || !restored
        return StopAfterShardPickupFailure136(failure != "" ? failure : (!restored ? "return_view_mismatch" : "pickup_not_confirmed"))
    RuntimeLogInfo("event_pickup_confirmed", "Event pickup evidence and both original-view anchors matched",
        "kind=" match.kind "; before=" beforeCount "; after=" afterCount "; movements=" movementJournal.Length)
    LogToConsole("Event drop collected. Original view verified; resuming strategy.", true)
    return true
}
