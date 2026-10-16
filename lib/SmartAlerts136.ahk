#Requires AutoHotkey v2.0
; Optional owner alerts with a persisted per-category 15-minute cooldown.
ReviewAlert136(kind, summary, settingsFile, stateFile, webhookUrl) {
    kinds := Map("equip_failure", "EquipFailure", "loss_streak", "LossStreak")
    if !kinds.Has(kind) || IniRead(settingsFile, "ReviewAlerts", "Enabled", "0") != "1"
        || IniRead(settingsFile, "ReviewAlerts", kinds[kind], "0") != "1"
        return false
    if !RegExMatch(webhookUrl, "i)^https://(canary\.|ptb\.)?discord(app)?\.com/api/(v\d{1,2}/)?webhooks/\d+/[A-Za-z0-9._-]+$")
        return false
    key := "LastAlert_" kind
    previous := IniRead(stateFile, "ReviewAlerts", key, "")
    if previous != "" {
        try {
            elapsed := DateDiff(A_Now, previous, "Seconds")
            if elapsed >= 0 && elapsed < 900
                return false
        }
    }
    uid := Trim(IniRead(settingsFile, "ReviewAlerts", "MentionUserID", ""))
    mention := RegExMatch(uid, "^\d{17,20}$") ? "<@" uid "> " : ""
    safe := StrReplace(StrReplace(StrReplace(SubStr(summary, 1, 270), "\", "\\"), '"', '\"'), "`n", " ")
    allowed := mention != "" ? '"' uid '"' : ""
    payload := '{"content":"' mention "Ultimate Macro: " safe '","allowed_mentions":{"parse":[],"users":[' allowed ']}}'
    try {
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.Open("POST", webhookUrl, false)
        http.SetRequestHeader("Content-Type", "application/json")
        http.SetTimeouts(2000, 2000, 3500, 3500)
        http.Send(payload)
        if http.Status < 200 || http.Status >= 300
            return false
        IniWrite(A_Now, stateFile, "ReviewAlerts", key)
        return true
    } catch Error {
        return false
    }
}

ReviewAlertLossStreak136(result, settingsFile, stateFile, webhookUrl) {
    if result != "Triumph" && result != "Loss"
        return false
    streak := Integer(IniRead(stateFile, "ReviewAlerts", "LossStreak", "0"))
    streak := result = "Loss" ? Min(streak + 1, 100) : 0
    IniWrite(streak, stateFile, "ReviewAlerts", "LossStreak")
    threshold := Max(2, Min(10, Integer(IniRead(settingsFile, "ReviewAlerts", "LossThreshold", "3"))))
    return streak = threshold ? ReviewAlert136("loss_streak", streak " losses in a row.",
        settingsFile, stateFile, webhookUrl) : false
}
