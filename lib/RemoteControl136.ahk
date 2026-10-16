#Requires AutoHotkey v2.0
; These new Discord commands only read state or schedule an end-of-match action.
ReviewHandleRemote136(cmd, running, stateFile, settingsFile) {
    if cmd = "stopaftergame" {
        if !running
            return "Macro isn't running. Nothing scheduled."
        IniWrite(1, stateFile, "ReviewRemote", "StopAfterMatch")
        return "Will stop after this match. Use !cancelstop to undo."
    }
    if cmd = "cancelstop" {
        IniWrite(0, stateFile, "ReviewRemote", "StopAfterMatch")
        return "Cancelled the after-match stop."
    }
    if cmd = "summary" {
        wins := IniRead(stateFile, "State", "TotalTriumphs", "0")
        losses := IniRead(stateFile, "State", "TotalLosses", "0")
        pending := IniRead(stateFile, "ReviewRemote", "StopAfterMatch", "0")
        return "Macro: " (running ? "running" : "stopped") " | W/L: " wins "/" losses " | stop after match: " (pending = "1" ? "yes" : "no")
    }
    if cmd = "rewards"
        return HistorySummary136()
    if cmd = "recent"
        return HistorySummary136(5)
    if cmd = "performance"
        return TurboStatus136()
    if cmd = "placements"
        return PlacementSummary136()
    if cmd = "alerts" {
        enabled := IniRead(settingsFile, "ReviewAlerts", "Enabled", "0") = "1"
        return "Smart Alerts: " (enabled ? "ON" : "OFF") " | cooldown: 15m | opt-in in Settings.tds"
    }
    return ""
}
