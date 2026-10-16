#Requires AutoHotkey v2.0
; Local-only match history. Rewards are unknown unless OCR evidence exists.
HistoryPath136() {
    dir := A_AppData "\Ultimate_Macro\History"
    try DirCreate(dir)
    catch Error
        return ""
    return dir "\session-history-136.tsv"
}

HistoryField136(value) {
    value := StrReplace(StrReplace(StrReplace(String(value), "`t", " "), "`n", " "), "`r", " ")
    value := Trim(value)
    if RegExMatch(value, "^[=+\-@]")
        value := "'" value
    return SubStr(value, 1, 160)
}

HistoryAppend136(result, seconds, mapName, coins := "", gems := "", exp := "") {
    if result != "Triumph" && result != "Loss"
        return false
    if seconds < 0 || seconds > 86400
        return false
    p := HistoryPath136()
    if p = ""
        return false
    try {
        if FileExist(p) && FileGetSize(p) > 2097152
            return false
        if !FileExist(p)
            FileAppend("timestamp`tresult`truntime_seconds`tmap`tcoins`tgems`texp`n", p, "UTF-8")
        fields := [FormatTime(, "yyyy-MM-dd HH:mm:ss"), result, seconds, mapName, coins, gems, exp]
        line := ""
        for i, value in fields
            line .= (i = 1 ? "" : "`t") HistoryField136(value)
        FileAppend(line "`n", p, "UTF-8")
        return true
    } catch Error {
        return false
    }
}

HistorySummary136(count := 0) {
    p := HistoryPath136()
    if p = "" || !FileExist(p)
        return "No confirmed matches recorded yet."
    try rows := StrSplit(FileRead(p, "UTF-8"), "`n", "`r")
    catch Error
        return "History unavailable."
    wins := 0, losses := 0, coins := 0, gems := 0, coinsUnknown := 0, gemsUnknown := 0
    recent := []
    for i, row in rows {
        if i = 1 || row = ""
            continue
        c := StrSplit(row, "`t")
        if c.Length != 7 || (c[2] != "Triumph" && c[2] != "Loss")
            continue
        if c[2] = "Triumph"
            wins++
        else
            losses++
        if RegExMatch(c[5], "^\d+$")
            coins += Integer(c[5])
        else
            coinsUnknown++
        if RegExMatch(c[6], "^\d+$")
            gems += Integer(c[6])
        else
            gemsUnknown++
        recent.Push(c[1] ": " c[2] " | " c[4])
    }
    if count > 0 {
        if recent.Length = 0
            return "No completed matches."
        txt := "Recent results:`n"
        start := Max(1, recent.Length - Min(count, 6) + 1)
        loop recent.Length - start + 1
            txt .= recent[start + A_Index - 1] "`n"
        return RTrim(txt, "`n")
    }
    summary := Format("History: {1} matches | {2} wins | {3} losses`n", wins + losses, wins, losses)
    summary .= Format("Verified coins: {1} ({2} unknown)`n", coins, coinsUnknown)
    summary .= Format("Verified gems: {1} ({2} unknown)", gems, gemsUnknown)
    return summary
}

ReviewStopAfterMatch136(stateFile) {
    if IniRead(stateFile, "ReviewRemote", "StopAfterMatch", "0") != "1"
        return false
    IniWrite(0, stateFile, "ReviewRemote", "StopAfterMatch")
    IniWrite(0, stateFile, "State", "Running")
    IniDelete(stateFile, "State", "StartTime")
    return true
}
