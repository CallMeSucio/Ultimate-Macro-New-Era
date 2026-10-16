#Requires AutoHotkey v2.0
; Logs confirmed differences between recorded and actual client coordinates.
PlacementReviewPath136() {
    dir := A_AppData "\Ultimate_Macro\History"
    try DirCreate(dir)
    catch Error
        return ""
    return dir "\placement-corrections-136.tsv"
}

PlacementReview136(towerID, slot, expectedX, expectedY, actualX, actualY) {
    global StrategyWidth, StrategyHeight, StateFile, SettingsFile
    if Round(expectedX) = Round(actualX) && Round(expectedY) = Round(actualY)
        return false
    if !getRobloxPos(, , &w, &h) || w <= 0 || h <= 0
        return false
    fromX := Round(expectedX * StrategyWidth / w), fromY := Round(expectedY * StrategyHeight / h)
    toX := Round(actualX * StrategyWidth / w), toY := Round(actualY * StrategyHeight / h)
    strategy := IniRead(StateFile, "State", "Strategy", "")
    SplitPath(strategy, &strategyName)
    cleanId := RegExReplace(String(towerID), "[^A-Za-z0-9_-]", "")
    cleanName := RegExReplace(strategyName, "[^A-Za-z0-9._-]", "_")
    suggestion := "SpawnTower(" fromX ", " fromY ", " slot ", " cleanId ") -> SpawnTower(" toX ", " toY ", " slot ", " cleanId ")"
    LogToConsole("Placement correction suggestion for tower " cleanId ": " suggestion, true)
    try RuntimeLogInfo("placement_correction_suggested", "Confirmed offset; strategy edit suggested", "tower=" cleanId "; old=" fromX "," fromY "; new=" toX "," toY)
    try AutoLogsEvent(StateFile, "placement_correction", "tower=" cleanId "; before=" fromX "," fromY "; after=" toX "," toY)
    p := PlacementReviewPath136()
    if p = ""
        return true
    try {
        if FileExist(p) && FileGetSize(p) > 2097152
            return true
        if !FileExist(p)
            FileAppend("timestamp`tstrategy`ttower_id`tslot`tfrom_x`tfrom_y`tto_x`tto_y`n", p, "UTF-8")
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "`t" cleanName "`t" cleanId "`t" slot "`t" fromX "`t" fromY "`t" toX "`t" toY "`n", p, "UTF-8")
    }
    return true
}

PlacementSummary136() {
    p := PlacementReviewPath136()
    if p = "" || !FileExist(p)
        return "No confirmed placement corrections yet."
    try rows := StrSplit(FileRead(p, "UTF-8"), "`n", "`r")
    catch Error
        return "Placement history unavailable."
    found := []
    for i, row in rows {
        if i = 1 || row = ""
            continue
        c := StrSplit(row, "`t")
        if c.Length = 8
            found.Push(c[2] " | tower " c[3] " | (" c[5] "," c[6] ") -> (" c[7] "," c[8] ")")
    }
    if !found.Length
        return "No confirmed placement corrections yet."
    start := Max(1, found.Length - 3)
    result := "Latest placement suggestions:`n"
    loop found.Length - start + 1
        result .= found[start + A_Index - 1] "`n"
    return RTrim(result, "`n")
}
