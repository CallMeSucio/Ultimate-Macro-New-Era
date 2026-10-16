#Requires AutoHotkey v2.0
; Adaptive opt-in timing. Success samples can speed up small waits; failures never do.
global TurboState136 := {Enabled: false, Samples: 0, ResponseMs: 0, InputMs: 100}

TurboInit136(settingsFile) {
    global TurboState136
    enabled := IniRead(settingsFile, "Options", "PotatoMode", "0") = "1"
        && IniRead(settingsFile, "Review", "TurboPotato", "0") = "1"
    TurboState136.Enabled := enabled
    TurboState136.Samples := 0
    TurboState136.ResponseMs := 0
    TurboState136.InputMs := 100
    return enabled
}

TurboDelay136(fallbackMs := 100) {
    global TurboState136
    return TurboState136.Enabled ? TurboState136.InputMs : fallbackMs
}

TurboObserve136(milliseconds, confirmed) {
    global TurboState136
    if !TurboState136.Enabled || !confirmed || milliseconds < 20 || milliseconds > 10000
        return false
    TurboState136.Samples++
    TurboState136.ResponseMs := TurboState136.Samples = 1 ? milliseconds
        : Round(.75 * TurboState136.ResponseMs + .25 * milliseconds)
    TurboState136.InputMs := Max(55, Min(115, Round(45 + TurboState136.ResponseMs / 15)))
    return true
}

TurboPostEquipPause136() {
    global TurboState136
    return TurboState136.Enabled ? Max(260, 3 * TurboState136.InputMs) : 400
}

TurboStatus136() {
    global TurboState136
    summary := "Turbo Potato: " (TurboState136.Enabled ? "ON" : "OFF")
    summary .= " | confirmed samples: " TurboState136.Samples
    summary .= " | input delay: " TurboState136.InputMs " ms"
    return summary
}
