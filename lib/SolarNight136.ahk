ResolveSolarNight136() {
    global gamemap, difficulty
    mode := Trim(difficulty)
    if RegExMatch(mode, "i)^Night\s*1\s+(Easy|Hard)$", &match)
        return StrLower(match[1]) = "easy" ? "Easy" : "Hard"
    if StrLower(Trim(gamemap)) = "sorrowful remains" && (mode = "Easy" || mode = "Hard")
        return mode
    return ""
}

ClickSolarTemplate136(name, timeout := 12000) {
    global RunningStrategy
    deadline := A_TickCount + timeout
    previous := false
    while A_TickCount < deadline {
        if !RunningStrategy
            return false
        if getRobloxPos(, , &width, &height) {
            match := AdvancedImageSearch("Resources/" name ".png", 0, 0, width, height, 0.5, 1.5, 0.10)
            if match.status = "success" && match.score >= 0.82 {
                if previous && Abs(match.x - previous.x) <= 35 && Abs(match.y - previous.y) <= 35 {
                    ActivateRoblox()
                    if !ClickPlay136(match.x, match.y)
                        return false
                    Sleep(300)
                    RuntimeLogInfo("solar_night_card_clicked", "Selected Solar Requiem card", "card=" name)
                    return true
                }
                previous := match
            } else {
                previous := false
            }
        }
        Sleep(200)
    }
    RuntimeLogWarn("solar_night_card_missing", "Solar Requiem card was not found", "card=" name)
    return false
}

JoinSolarNight136() {
    nightDifficulty := ResolveSolarNight136()
    if nightDifficulty = ""
        return false
    if !ClickSolarTemplate136("Night 1")
        return false
    return ClickSolarTemplate136("Night 1 " nightDifficulty)
}

SolarLoadoutHeadingVisible136() {
    if !getRobloxPos(, , &width, &height)
        return false
    match := AdvancedImageSearch("Resources/SolarNight/Loadout Heading.png",
        0, Round(height * 0.2), width, Round(height * 0.5), 0.5, 1.5, 0.10)
    return match.status = "success" && match.score >= 0.80
}

PrepareSolarLoadout136() {
    global EventLoadout136, RunningStrategy
    if !SolarLoadoutHeadingVisible136() {
        Sleep(250)
        if !SolarLoadoutHeadingVisible136()
            return true
    }
    if !ClickSolarTemplate136("SolarNight/Loadout " EventLoadout136, 8000)
        return false
    disappeared := 0
    loop 16 {
        if !RunningStrategy
            return false
        disappeared := SolarLoadoutHeadingVisible136() ? 0 : disappeared + 1
        if disappeared >= 2
            return true
        Sleep(250)
    }
    RuntimeLogWarn("solar_loadout_unconfirmed", "The loadout chooser did not close after selection")
    return false
}

WaitForSolarLobby136() {
    global RunningStrategy, readyX, readyY, SolarNightLobbyConfirmed136
    SolarNightLobbyConfirmed136 := false
    deadline := A_TickCount + 60000
    stable := 0
    while A_TickCount < deadline {
        if !RunningStrategy
            return false
        if FindReadyButton(&x, &y) {
            stable++
            if stable >= 2 {
                if !PrepareSolarLoadout136()
                    return false
                readyX := x, readyY := y
                SolarNightLobbyConfirmed136 := true
                startWatchdog()
                return true
            }
        } else {
            stable := 0
        }
        Sleep(250)
    }
    RuntimeLogWarn("solar_lobby_timeout", "Night I lobby and Ready button were not confirmed")
    return false
}

WaitForSolarNightIntro136(timeout := 12000) {
    global RunningStrategy
    if ResolveSolarNight136() = ""
        return true

    deadline := A_TickCount + timeout
    attempts := 0
    introDetected := false
    stableAbsentSamples := 0
    while A_TickCount < deadline {
        if !RunningStrategy
            return false
        if !GetRobloxScreenClientRect(&screenX, &screenY, &screenW, &screenH) {
            Sleep(250)
            continue
        }

        try {
            intro := ReadGameText136(screenX, screenY + Round(screenH * 0.86), Round(screenW * 0.38),
                Round(screenH * 0.14), {lang: "en-US", scale: 1.6, grayscale: 1})
            match := InStr(StrLower(intro.Text), "hold to skip")
                ? intro.FindString("Hold to Skip", {CaseSense: false, IgnoreLinebreaks: true}) : ""
        } catch Error as introError {
            RuntimeLogWarn("solar_night_intro_ocr_failed", "Could not read the Night 1 intro skip control",
                "error=" introError.Message)
            return false
        }

        if (match && OcrMatchTargetsGameUI(match, "Night 1 intro skip")) {
            introDetected := true
            stableAbsentSamples := 0
            attempts++
            targetX := Round(match.x + match.w / 2 - screenX)
            targetY := Round(match.y + match.h / 2 - screenY)
            if !HoldRobloxButton136(targetX, targetY, 2500)
                return false

            absentSamples := 0
            loop 5 {
                if !GetRobloxScreenClientRect(&screenX, &screenY, &screenW, &screenH)
                    return false
                try {
                    check := ReadGameText136(screenX, screenY + Round(screenH * 0.86), Round(screenW * 0.38),
                        Round(screenH * 0.14), {lang: "en-US", scale: 1.6, grayscale: 1})
                    stillVisible := InStr(StrLower(check.Text), "hold to skip") > 0
                } catch Error as verifyError {
                    RuntimeLogWarn("solar_night_intro_verify_failed", "Could not verify the Night 1 intro skip result",
                        "error=" verifyError.Message)
                    return false
                }
                if stillVisible
                    break
                absentSamples++
                if (absentSamples < 5)
                    Sleep(350)
            }

            if (absentSamples >= 5) {
                RuntimeLogInfo("solar_night_intro_skip_confirmed", "Held and verified the Night 1 intro skip control",
                    "attempt=" attempts "; stable_absent_samples=" absentSamples)
                return true
            }
            RuntimeLogWarn("solar_night_intro_skip_retry", "The Night 1 intro skip control remained visible after a hold",
                "attempt=" attempts)
            if attempts >= 2
                return false
            continue
        }

        if introDetected {
            stableAbsentSamples++
            if (stableAbsentSamples >= 5) {
                RuntimeLogInfo("solar_night_intro_skip_confirmed", "The Night 1 intro skip control stayed absent",
                    "attempt=" attempts "; stable_absent_samples=" stableAbsentSamples)
                return true
            }
        } else {
            stableAbsentSamples := 0
        }
        Sleep(350)
    }

    if introDetected {
        RuntimeLogWarn("solar_night_intro_timeout", "The Night 1 intro skip control did not disappear after a hold",
            "attempts=" attempts)
        return false
    }
    RuntimeLogInfo("solar_night_intro_not_present", "No Night 1 intro skip control appeared during startup")
    return true
}

HoldRobloxButton136(x, y, duration) {
    if !ActivateRoblox() || !WinWaitActive("ahk_id " GetRobloxHWND(), , 1)
        return false

    oldCoord := A_CoordModeMouse
    oldCritical := A_IsCritical
    Critical("On")
    try {
        CoordMode("Mouse", "Client")
        MouseMove(x, y, 0)
        NudgeRobloxHover136()
        Sleep(150)
        SendEvent("{LButton down}")
        Sleep(duration)
    } finally {
        SendEvent("{LButton up}")
        CoordMode("Mouse", oldCoord)
        Critical(oldCritical)
    }
    return true
}

NudgeRobloxHover136() {
    DllCall("user32\mouse_event", "UInt", 1, "Int", 1, "Int", 0, "UInt", 0, "UPtr", 0)
}
