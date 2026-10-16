#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\WelcomeTheme136.ahk
; One-page first-run setup. Hardware inspection is only called by the consent button.
global WelcomeSetup136 := 0
global WindowsStartupPrompt136 := 0

WelcomeServers136() {
    base := "https://www.roblox.com/games/3260590327/Tower-Defense-Simulator?privateServerLinkCode="
    return [
        {Name: "Panda's", Link: base "36102411168314025055067610094878"},
        {Name: "Pedro's AWESOME banter and grind", Link: base "12900220482327030384643800033652"},
        {Name: "Gubby Realm 1", Link: base "02587049448141326433871675811056"},
        {Name: "Gubby Realm 2", Link: base "68155572089159669857100804598629"},
        {Name: "Gubby Realm 3", Link: base "09824347199034124998771751892463"}]
}

WelcomeRecommend136(ramGB, logicalCores) {
    ramKnown := IsNumber(ramGB) && ramGB > 0
    coresKnown := IsNumber(logicalCores) && logicalCores > 0
    ; These presets change waits/retries, not graphics quality. A known limit
    ; justifies safer waits even if another field is missing. Unknown hardware
    ; never justifies Standard, and hardware alone never enables Turbo.
    if (ramKnown && ramGB <= 8.5) || (coresKnown && logicalCores <= 4)
        return 2
    return ramKnown && coresKnown ? 1 : 0
}

WelcomeNativeHardware136() {
    info := {RamGB: 0, Threads: 0}
    memory := Buffer(64, 0)
    NumPut("UInt", 64, memory)
    if DllCall("kernel32\GlobalMemoryStatusEx", "Ptr", memory)
        info.RamGB := Round(NumGet(memory, 8, "UInt64") / 1073741824, 1)
    try info.Threads := DllCall("kernel32\GetActiveProcessorCount", "UShort", 0xFFFF, "UInt")
    return info
}

WelcomeReadHardware136() {
    native := WelcomeNativeHardware136()
    info := {RamGB: native.RamGB, Threads: native.Threads, CPU: "Unavailable", GPU: "Unavailable", Partial: false}
    try wmi := ComObjGet("winmgmts:\\.\root\cimv2")
    catch {
        info.Partial := true
        return info
    }
    ; Each provider can fail independently. Missing GPU metadata must not erase
    ; usable RAM/CPU counts or prevent choosing a preset.
    try {
        for pc in wmi.ExecQuery("SELECT TotalPhysicalMemory FROM Win32_ComputerSystem") {
            if IsNumber(pc.TotalPhysicalMemory) && pc.TotalPhysicalMemory > 0
                info.RamGB := Round(pc.TotalPhysicalMemory / 1073741824, 1)
        }
    } catch {
        info.Partial := true
    }
    try {
        threads := 0, cpu := ""
        for processor in wmi.ExecQuery("SELECT Name, NumberOfLogicalProcessors FROM Win32_Processor") {
            if IsNumber(processor.NumberOfLogicalProcessors) && processor.NumberOfLogicalProcessors > 0
                threads += processor.NumberOfLogicalProcessors
            if cpu = ""
                cpu := Trim(processor.Name)
        }
        if threads > 0
            info.Threads := threads
        if cpu != ""
            info.CPU := cpu
    } catch {
        info.Partial := true
    }
    try {
        gpu := ""
        for video in wmi.ExecQuery("SELECT Name FROM Win32_VideoController") {
            if Trim(video.Name) != ""
                gpu .= (gpu = "" ? "" : ", ") Trim(video.Name)
        }
        if gpu != ""
            info.GPU := gpu
    } catch {
        info.Partial := true
    }
    return info
}

WelcomeWebhookValid136(link) {
    return RegExMatch(Trim(link), "i)^https://(?:discord\.com|discordapp\.com)/api/(?:v[0-9]+/)?webhooks/[0-9]+/[a-z0-9_-]+$") != 0
}

WelcomeServerLinkValid136(link) {
    return link = "" || RegExMatch(Trim(link),
        "i)^https://www\.roblox\.com/(?:games/3260590327/[^/?#]*\?privateServerLinkCode=[a-z0-9]{32}|share\?code=[a-f0-9]{32}(?:&type=Server)?)$") != 0
}

WelcomeSave136(path, ownsVIP, link, mode, webhook, consent, launchOnStartup := 0) {
    link := Trim(link), webhook := Trim(webhook)
    if (ownsVIP != 0 && ownsVIP != 1) || mode < 1 || mode > 3
        || (launchOnStartup != 0 && launchOnStartup != 1)
        || !WelcomeServerLinkValid136(link) || (!ownsVIP && link = "")
        || (webhook != "" && !WelcomeWebhookValid136(webhook))
        || (consent != "granted" && consent != "declined")
        throw ValueError("Please finish your server and performance choices first.")
    ; Completion is cleared first so an interrupted save remains recoverable.
    IniWrite(0, path, "Welcome", "Completed")
    IniWrite(ownsVIP, path, "Welcome", "OwnsVIP")
    IniWrite(consent, path, "Welcome", "HardwareConsent")
    IniWrite(link, path, "Options", "VipLink")
    IniWrite(link != "" ? 1 : 0, path, "Options", "UseVipServer")
    IniWrite(mode > 1 ? 1 : 0, path, "Options", "PotatoMode")
    IniWrite(mode = 3 ? 1 : 0, path, "Review", "TurboPotato")
    IniWrite(webhook, path, "Webhook", "Link")
    IniWrite(webhook != "" ? 1 : 0, path, "Webhook", "Enabled")
    IniWrite(launchOnStartup, path, "Options", "LaunchOnWindowsStartup")
    IniWrite(1, path, "Welcome", "StartupPromptAnswered")
    IniWrite(1, path, "Welcome", "Completed")
}

WindowsStartupFolder136() {
    return EnvGet("APPDATA") "\Microsoft\Windows\Start Menu\Programs\Startup"
}

WindowsStartupShortcutName136() {
    return "Ultimate Macro - Startup.lnk"
}

WindowsStartupSignature136() {
    return "Ultimate Macro managed Windows startup v1"
}

WindowsStartupLaunchArgs136(launcher) {
    return '/d /s /c ""' launcher '" --windows-startup"'
}

WindowsStartupNormalizePath136(path) {
    return StrLower(RTrim(StrReplace(Trim(path, ' "'), "/", "\"), "\"))
}

WindowsStartupManagedShortcuts136(startupFolder) {
    links := []
    if !DirExist(startupFolder)
        return links
    shell := ComObject("WScript.Shell")
    Loop Files startupFolder "\*.lnk", "F" {
        try {
            shortcut := shell.CreateShortcut(A_LoopFileFullPath)
            if shortcut.Description = WindowsStartupSignature136()
                links.Push({Path: A_LoopFileFullPath, Target: shortcut.TargetPath,
                    Arguments: shortcut.Arguments, WorkingDirectory: shortcut.WorkingDirectory})
        }
    }
    return links
}

ReadWindowsStartupState136(launcher := A_ScriptDir "\Ultimate Macro.cmd", startupFolder := "") {
    startupFolder := startupFolder = "" ? WindowsStartupFolder136() : startupFolder
    expected := WindowsStartupNormalizePath136(launcher)
    SplitPath(launcher, , &launcherDir)
    links := WindowsStartupManagedShortcuts136(startupFolder)
    valid := 0, stale := false, selectedPath := ""
    for link in links {
        pointsHere := WindowsStartupNormalizePath136(link.Target) = WindowsStartupNormalizePath136(EnvGet("ComSpec"))
            && InStr(link.Arguments, expected) && InStr(link.Arguments, "--windows-startup")
            && WindowsStartupNormalizePath136(link.WorkingDirectory) = WindowsStartupNormalizePath136(launcherDir)
        if pointsHere {
            valid++
            selectedPath := link.Path
        } else
            stale := true
    }
    return {Enabled: valid > 0, Stale: stale, Duplicates: links.Length,
        Path: selectedPath, Conflict: FileExist(startupFolder "\" WindowsStartupShortcutName136()) != "" && valid = 0 && links.Length = 0}
}

SetWindowsStartup136(enable, launcher := A_ScriptDir "\Ultimate Macro.cmd", startupFolder := "", &message := "") {
    message := ""
    startupFolder := startupFolder = "" ? WindowsStartupFolder136() : startupFolder
    name := startupFolder "\" WindowsStartupShortcutName136()
    try {
        links := WindowsStartupManagedShortcuts136(startupFolder)
        if !enable {
            for link in links
                FileDelete(link.Path)
            return true
        }
        if !FileExist(launcher)
            throw Error("Ultimate Macro launcher is missing.")
        DirCreate(startupFolder)
        ownedCanonical := false
        for link in links {
            if WindowsStartupNormalizePath136(link.Path) = WindowsStartupNormalizePath136(name)
                ownedCanonical := true
        }
        if FileExist(name) && !ownedCanonical
            throw Error("An unrelated Startup shortcut already uses the Ultimate Macro shortcut name.")
        shell := ComObject("WScript.Shell")
        shortcut := shell.CreateShortcut(name)
        shortcut.TargetPath := EnvGet("ComSpec")
        shortcut.Arguments := WindowsStartupLaunchArgs136(launcher)
        SplitPath(launcher, , &launcherDir)
        shortcut.WorkingDirectory := launcherDir
        shortcut.IconLocation := launcherDir "\icon.ico,0"
        shortcut.WindowStyle := 7
        shortcut.Description := WindowsStartupSignature136()
        shortcut.Save()
        for link in links {
            if WindowsStartupNormalizePath136(link.Path) != WindowsStartupNormalizePath136(name)
                FileDelete(link.Path)
        }
        return true
    } catch Error as startupErr136 {
        message := startupErr136.Message
        return false
    }
}

WindowsStartupLaunchFromArgs136(args) {
    for arg in args {
        if StrLower(arg) = "--windows-startup" || StrLower(arg) = "--noninteractive"
            return true
    }
    return false
}

WindowsStartupPromptNeeded136(setupCompleted, answered, launchedFromWindows) {
    return setupCompleted = 1 && answered = "" && !launchedFromWindows
}

WelcomeLayout136(workHeight, dpi) {
    height := Min(688, Floor(workHeight * 96 / dpi) - 48)
    return {Height: height, Viewport: Max(120, height - 208)}
}

class WelcomePage136 {
    __New(path, existingLink, mode, webhook, onFinish, launcher := "", startupFolder := "") {
        this.Path := path, this.ExistingLink := existingLink, this.OnFinish := onFinish
        this.Launcher := launcher = "" ? A_ScriptDir "\Ultimate Macro.cmd" : launcher
        this.StartupFolder := startupFolder, this.StartupChoice := -1
        this.OwnsVIP := -1, this.Consent := "", this.TestedLink := "", this.Busy := false
        this.Recommended := 0, this.ModeAccepted := false
        this.ScrollOffset := 0, this.MaxScroll := 0, this.Viewport := 476
        this.BaseY := Map(), this.Servers := WelcomeServers136()
        this.Window := Gui("-MaximizeBox -MinimizeBox", "Ultimate Macro Setup")
        this.Window.BackColor := "121212"
        this.Window.MarginX := 0, this.Window.MarginY := 0
        this.Window.OnEvent("Close", (*) => ExitApp())
        this.Window.OnEvent("Escape", (*) => this.Status("Finish setup to continue, or close the window to leave."))
        this.Form := Gui("-Caption +Parent" this.Window.Hwnd " +0x200000 +E0x10000")
        this.Form.Title := "Setup options"
        this.Form.BackColor := "121212"
        this.Form.MarginX := 0, this.Form.MarginY := 0
        this.Theme := WelcomeTheme136(this)
        this.Text(this.Window, 32, 20, 520, 42, "Ultimate Macro Setup", 21, "E2E4E7", 600)
        this.Text(this.Window, 32, 65, 596, 22, "Let's get everything ready.", 10, "969DA8")
        if FileExist(this.Theme.IconPath)
            this.HeaderIcon := this.Window.Add("Picture", "x564 y18 w64 h64 Icon1", this.Theme.IconPath)
        g := this.Form
        this.Section(0, "01 · Server")
        this.Text(g, 32, 46, 230, 24, "Do you own the VIP gamepass?", 10)
        g.SetFont("s10 cE2E4E7", "Segoe UI")
        this.Yes := g.Add("Radio", "x256 y44 w150 h26 Group", "Yes, I do")
        this.No := g.Add("Radio", "x428 y44 w174 h26", "No, I don't")
        this.Yes.OnEvent("Click", (*) => this.ServerChoice(1))
        this.No.OnEvent("Click", (*) => this.ServerChoice(0))
        this.ServerList := g.Add("DropDownList", "x32 y86 w416 Hidden +0x210", this.ServerNames())
        this.ServerList.Choose(Random(1, this.Servers.Length))
        this.ServerList.OnEvent("Change", (*) => this.Update())
        this.ServerEdit := g.Add("Edit", "x32 y86 w596 h30 Hidden", existingLink)
        this.ServerEdit.OnEvent("Change", (*) => this.Update())
        this.Shuffle := this.Button(g, 464, 85, 164, "Reassign", (*) => this.Reassign())
        this.Shuffle.Visible := false

        this.Section(168, "02 · Performance", "Check your PC or choose a performance preset.")
        this.Permission := this.Text(g, 32, 228, 596, 24,
            "Check processor, memory and graphics locally, with your permission.", 9, "969DA8")
        this.Check := this.Button(g, 32, 264, 164, "Allow PC check", (*) => this.CheckPC())
        this.Manual := this.Button(g, 212, 264, 164, "Choose manually", (*) => this.ChooseManually())
        this.Hardware := this.Text(g, 32, 228, 420, 22, "", 10, "969DA8")
        this.Hardware.Visible := false
        this.Recommendation := this.Text(g, 32, 254, 596, 24, "", 11, "E2E4E7", 600)
        this.Recommendation.Visible := false
        this.Accept := this.Button(g, 32, 284, 180, "Use recommendation", (*) => this.AcceptRecommendation())
        this.Accept.Visible := false
        this.Details := this.Button(g, 480, 225, 148, "What is checked?", (*) => this.ShowSpecs())
        this.Details.Visible := false
        g.SetFont("s10 cE2E4E7", "Segoe UI")
        this.Mode := g.Add("DropDownList", "x32 y284 w416 Hidden +0x210", ["Standard", "Potato Mode", "Potato + Turbo Potato"])
        this.Mode.Choose(mode)
        this.Mode.OnEvent("Change", (*) => this.Update())

        this.Section(344, "03 · Discord notifications", "Paste a Discord webhook, or set this up later.")
        this.Text(g, 552, 346, 76, 22, "Optional", 9, "969DA8")
        g.SetFont("s10 cE2E4E7", "Segoe UI")
        this.Webhook := g.Add("Edit", "x32 y405 w400 h30 Password Center", webhook)
        DllCall("user32\SendMessageW", "Ptr", this.Webhook.Hwnd, "UInt", 0x1501, "Ptr", 0,
            "WStr", "Discord webhook URL")
        this.Webhook.OnEvent("Change", (*) => this.WebhookChanged())
        this.Test := this.Button(g, 448, 404, 180, "Send test notification", (*) => this.TestWebhook())
        this.Test.Enabled := WelcomeWebhookValid136(webhook)
        this.Help := this.Button(g, 32, 444, 148, "Webhook setup help", (*) => this.WebhookHelp())
        this.Skip := this.Button(g, 480, 444, 148, "Set up later", (*) => this.SkipWebhook())
        this.WebhookStatus := this.Text(g, 196, 444, 268, 32, "", 9, "969DA8")
        this.ContentHeight := 480
        for button in [this.Help, this.Skip, this.Details]
            this.Theme.Buttons[button.Hwnd].Quiet := true

        this.Error := this.Text(this.Window, 32, 0, 596, 24, "", 9, "E3A6A6")
        this.Error.Visible := false
        this.FooterLine := this.Window.Add("Progress", "x32 y0 w596 h1 Disabled Background292929", 0)
        this.Reassurance := this.Text(this.Window, 32, 0, 390, 22, "You can change these anytime in Settings.", 9, "969DA8")
        this.StartupPrompt := this.Text(this.Window, 32, 0, 184, 32,
            "Open the macro on computer startup?", 9, "E2E4E7", 400)
        this.StartupYes := this.Button(this.Window, 222, 0, 78, "Yes", (*) => this.SetStartupChoice(1), true, 36)
        this.StartupNo := this.Button(this.Window, 308, 0, 78, "No", (*) => this.SetStartupChoice(0), false, 36)
        this.Finish := this.Button(this.Window, 454, 0, 174, "Finish Setup", (*) => this.Complete(), true, 36)
        this.Finish.Enabled := false
        ApplyDarkInputTheme(g)
        for input in [this.ServerList, this.ServerEdit, this.Mode, this.Webhook]
            this.Theme.StyleInput(input)
        for hwnd, ctrl in g {
            ctrl.GetPos(, &y)
            this.BaseY[hwnd] := y
            try ctrl.OnEvent("Focus", (c, *) => this.EnsureVisible(c))
        }
    }

    Text(guiObj, x, y, w, h, text, size := 10, color := "E2E4E7", weight := 400) {
        guiObj.SetFont("s" size " w" weight " c" color, "Segoe UI")
        return guiObj.Add("Text", "x" x " y" y " w" w " h" h " BackgroundTrans", text)
    }

    Button(guiObj, x, y, width, label, callback, primary := false, height := 32) {
        return this.Theme.Add(guiObj, x, y, height, label, callback, primary, width)
    }

    Section(y, title, instruction := "") {
        if y
            this.Form.Add("Progress", "x32 y" (y - 16) " w596 h1 Disabled Background292929", 0)
        this.Text(this.Form, 32, y, 596, 26, title, 13, "C8D9EF", 600)
        if instruction != ""
            this.Text(this.Form, 32, y + 31, 596, 22, instruction, 10, "969DA8")
    }

    Show() {
        MonitorGetWorkArea(, &left, &top, &right, &bottom)
        layout := WelcomeLayout136(bottom - top, A_ScreenDPI)
        h := layout.Height, this.Viewport := layout.Viewport
        this.MaxScroll := Max(0, this.ContentHeight - this.Viewport)
        this.Error.Move(, h - 102)
        this.FooterLine.Move(, h - 76)
        this.Reassurance.Visible := false
        this.StartupPrompt.Move(32, h - 62)
        this.StartupYes.Move(222, h - 62)
        this.StartupNo.Move(308, h - 62)
        this.Finish.Move(, h - 58)
        this.Window.Show("w660 h" h)
        this.Form.Show("x0 y100 w660 h" this.Viewport " NoActivate")
        this.ScrollTo(0)
        this.Yes.Focus()
    }

    ScrollTo(position) {
        this.ScrollOffset := Round(Max(0, Min(this.MaxScroll, position)))
        for hwnd, ctrl in this.Form
            ctrl.Move(, this.BaseY[hwnd] - this.ScrollOffset)
        info := Buffer(28, 0)
        NumPut("UInt", 28, "UInt", 0x17, "Int", 0, "Int", this.ContentHeight - 1,
            "UInt", this.Viewport, "Int", this.ScrollOffset, info)
        DllCall("user32\SetScrollInfo", "Ptr", this.Form.Hwnd, "Int", 1, "Ptr", info, "Int", true)
        DllCall("user32\RedrawWindow", "Ptr", this.Form.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x185)
    }

    EnsureVisible(ctrl) {
        if !this.BaseY.Has(ctrl.Hwnd)
            return
        y := this.BaseY[ctrl.Hwnd]
        ctrl.GetPos(, , , &height)
        if y < this.ScrollOffset
            this.ScrollTo(y - 8)
        else if y + height > this.ScrollOffset + this.Viewport
            this.ScrollTo(y + height - this.Viewport + 8)
    }

    Dispose() {
        this.Form.Destroy()
        this.Window.Destroy()
        this.Theme.Dispose()
    }

    ServerNames() {
        names := []
        for server in this.Servers
            names.Push(server.Name)
        return names
    }

    ServerChoice(ownsVIP) {
        this.OwnsVIP := ownsVIP
        this.ServerList.Visible := !ownsVIP
        this.Shuffle.Visible := !ownsVIP
        this.ServerEdit.Visible := ownsVIP
        if ownsVIP
            DllCall("user32\SendMessageW", "Ptr", this.ServerEdit.Hwnd, "UInt", 0x1501, "Ptr", 0, "WStr", "Your TDS private-server link (optional)")
        this.Update()
    }

    Reassign() {
        this.ServerList.Choose(Mod(this.ServerList.Value, this.Servers.Length) + 1)
        this.Update()
    }

    SelectedLink() {
        return this.OwnsVIP = 0 ? this.Servers[this.ServerList.Value].Link : Trim(this.ServerEdit.Value)
    }

    ChooseManually() {
        if this.Consent = ""
            this.Consent := "declined"
        this.ModeAccepted := true
        this.Permission.Visible := false
        this.Hardware.Text := HasProp(this, "PCDetails") ? this.Hardware.Text : ""
        this.Hardware.Visible := HasProp(this, "PCDetails")
        this.Mode.Visible := true
        this.Recommendation.Visible := this.Recommended != 0
        this.BaseY[this.Mode.Hwnd] := this.Recommended ? 284 : (HasProp(this, "PCDetails") ? 260 : 230)
        this.Mode.Move(, this.BaseY[this.Mode.Hwnd] - this.ScrollOffset)
        this.Accept.Visible := false
        this.Manual.Visible := false
        this.Check.Visible := false
        this.Details.Visible := true
        this.Details.Text := HasProp(this, "PCDetails") ? "View hardware" : "About presets"
        this.Update()
        if WinActive("ahk_id " this.Window.Hwnd)
            this.Mode.Focus()
    }

    AcceptRecommendation() {
        if !this.Recommended
            return
        this.Mode.Choose(this.Recommended)
        this.ModeAccepted := true
        this.Mode.Visible := false
        this.Accept.Visible := false
        this.Manual.Visible := true
        this.Manual.Text := "Choose manually"
        this.Manual.Move(32, 284 - this.ScrollOffset)
        this.BaseY[this.Manual.Hwnd] := 284
        this.Recommendation.Text := "Selected: " this.Mode.Text
        this.Recommendation.Visible := true
        this.Update()
    }

    CheckPC() {
        if this.Busy
            return
        this.Busy := true, this.Check.Enabled := false, this.Consent := "granted"
        this.Permission.Visible := false
        this.Hardware.Text := "Checking your PC locally..."
        this.Hardware.Visible := true
        try {
            info := WelcomeReadHardware136()
            ram := info.RamGB, cores := info.Threads
            this.Recommended := WelcomeRecommend136(ram, cores)
            this.ModeAccepted := false
            this.Mode.Visible := false
            this.Check.Visible := false
            this.Hardware.Text := this.Recommended ? ram " GB RAM · " cores " threads" : "Some PC details were unavailable."
            this.PCDetails := ("CPU: " info.CPU "`nRAM: " (ram > 0 ? ram " GB" : "Unavailable")
                "`nThreads: " (cores > 0 ? cores : "Unavailable") "`nGraphics: " info.GPU)
            if info.Partial
                this.PCDetails .= "`n`nSome details were unavailable. Basic Windows RAM/CPU counts were retained."
            this.PCDetails .= "`n`n" (this.Recommended = 1
                ? "Why Standard: no low-RAM or low-thread-count limit was detected. Start here; choose Potato if TDS stutters or menus are missed."
                : this.Recommended = 2
                ? "Why Potato: limited RAM or CPU threads favor longer waits and fewer repeated UI checks."
                : "Not enough reliable data to suggest a preset. Choose manually.")
            this.Details.Visible := true
            this.Details.Text := "View hardware"
            this.Recommendation.Text := this.Recommended ? "Recommended: " (this.Recommended = 2 ? "Potato Mode" : "Standard") : "Choose a preset manually"
            this.Recommendation.Visible := true
            this.Accept.Visible := this.Recommended != 0
            this.Manual.Visible := true
            this.Manual.Move(228, 284 - this.ScrollOffset)
            this.BaseY[this.Manual.Hwnd] := 284
            if !this.Recommended
                this.ChooseManually()
        } catch {
            this.ChooseManually()
            this.Hardware.Text := "Couldn't read PC specs. Choose a preset below."
            this.Hardware.Visible := true
            this.BaseY[this.Mode.Hwnd] := 260
            this.Mode.Move(, 260 - this.ScrollOffset)
        } finally {
            this.Busy := false, this.Check.Enabled := true
        }
        this.Update()
        if WinActive("ahk_id " this.Window.Hwnd) && this.Accept.Visible
            this.Accept.Focus()
    }

    ShowSpecs() {
        details := HasProp(this, "PCDetails") ? this.PCDetails "`n`n" : ""
        MsgBox(details "The PC check reads only your processor, RAM and graphics model, after you allow it. Setup does not save or upload these details.`n`nStandard uses normal waits. Potato gives the game more time and reduces repeated UI checks. Turbo adapts Potato waits using confirmed responses.`n`nHardware provides an initial preset, not a measurement of Roblox performance or connection delay. Turbo needs a stable real run first.", "Performance details", "Owner" this.Window.Hwnd)
    }

    WebhookChanged() {
        this.TestedLink := ""
        this.WebhookStatus.Text := ""
        this.Update()
    }

    SkipWebhook() {
        this.Webhook.Value := "", this.TestedLink := ""
        this.WebhookStatus.Text := ""
        this.Update()
    }

    WebhookHelp() {
        MsgBox("In Discord on desktop:`n`n1. Open your server and edit the text channel you want.`n2. Open Integrations > Webhooks > New Webhook.`n3. Copy Webhook URL and paste it here.`n`nYou need permission to manage webhooks. Keep the URL private.", "Connect Discord", "Owner" this.Window.Hwnd)
    }

    TestWebhook() {
        if this.Busy
            return
        link := Trim(this.Webhook.Value)
        if !WelcomeWebhookValid136(link) {
            this.WebhookStatus.Text := "Paste a complete HTTPS Discord webhook URL first."
            return
        }
        this.Busy := true, this.Test.Enabled := false, this.Finish.Enabled := false
        this.WebhookStatus.Text := "Sending one test notification..."
        try {
            request := ComObject("WinHttp.WinHttpRequest.5.1")
            request.Open("POST", link, true)
            request.Option[6] := false
            request.SetTimeouts(2000, 2000, 3000, 3000)
            request.SetRequestHeader("Content-Type", "application/json")
            request.Send('{"content":"Ultimate Macro is connected. Your setup test was successful.","allowed_mentions":{"parse":[]}}')
            if !request.WaitForResponse(5)
                throw Error("timeout")
            if link != Trim(this.Webhook.Value)
                return
            if request.Status = 200 || request.Status = 204 {
                this.TestedLink := link
                this.WebhookStatus.Text := "Connected. Check your Discord channel for the test message."
            } else
                this.WebhookStatus.Text := "Discord didn't accept the test. Check the URL or choose Set up later."
        } catch {
            this.WebhookStatus.Text := "Couldn't send the test. Check your connection or choose Set up later."
        } finally {
            this.Busy := false, this.Test.Enabled := true
            this.Update()
        }
    }

    Status(message) {
        this.Error.Text := message
        this.Error.Visible := message != ""
    }

    Update() {
        serverReady := this.OwnsVIP >= 0 && WelcomeServerLinkValid136(this.SelectedLink())
        modeReady := this.Consent != "" && this.ModeAccepted && this.Mode.Value > 0
        webhook := Trim(this.Webhook.Value)
        validWebhook := webhook = "" || WelcomeWebhookValid136(webhook)
        ready := serverReady && modeReady && validWebhook && this.StartupChoice >= 0 && !this.Busy
        this.Finish.Enabled := ready
        this.Test.Enabled := webhook != "" && validWebhook && !this.Busy
        this.Status(!validWebhook ? "Check the webhook URL or choose Set up later."
            : (this.OwnsVIP >= 0 && !serverReady ? "Enter a valid TDS private-server link, or leave it blank." : ""))
    }

    SetStartupChoice(choice) {
        this.StartupChoice := choice
        this.StartupYes.Text := "Yes"
        this.StartupNo.Text := "No"
        this.Theme.Buttons[this.StartupYes.Hwnd].Primary := choice = 1
        this.Theme.Buttons[this.StartupNo.Hwnd].Primary := choice = 0
        this.StartupYes.Redraw()
        this.StartupNo.Redraw()
        this.Update()
    }

    Complete() {
        if this.Busy || !this.Finish.Enabled
            return
        if !SetWindowsStartup136(this.StartupChoice = 1, this.Launcher, this.StartupFolder, &startupMessage) {
            this.Status("Couldn't update Windows startup: " startupMessage)
            return
        }
        try WelcomeSave136(this.Path, this.OwnsVIP, this.SelectedLink(), this.Mode.Value,
            this.Webhook.Value, this.Consent, this.StartupChoice)
        catch {
            this.Status("Couldn't save setup. Check your choices and folder access, then try again.")
            return
        }
        this.OnFinish.Call(this)
    }
}

class WindowsStartupPromptPage136 {
    __New(onChoice, repair := false) {
        this.OnChoice := onChoice, this.Repair := repair, this.Theme := WelcomeTheme136(this)
        this.Window := Gui("-MaximizeBox -MinimizeBox", "Ultimate Macro")
        this.Window.BackColor := "121212", this.Window.MarginX := 0, this.Window.MarginY := 0
        this.Window.OnEvent("Close", (*) => this.Close())
        this.Window.OnEvent("Escape", (*) => this.Close())
        if FileExist(this.Theme.IconPath)
            this.HeaderIcon := this.Window.Add("Picture", "x24 y20 w40 h40 Icon1", this.Theme.IconPath)
        this.Window.SetFont("s15 w600 cE2E4E7", "Segoe UI")
        this.Window.Add("Text", "x78 y22 w430 h30 BackgroundTrans", repair ? "Startup shortcut needs repair" : "Start Ultimate Macro with Windows?")
        this.Window.SetFont("s10 w400 c969DA8", "Segoe UI")
        this.Window.Add("Text", "x78 y58 w430 h42 BackgroundTrans",
            repair ? "The saved Startup shortcut is missing or points to an old folder. Repair it now?"
                : "Would you like Ultimate Macro to open automatically when you sign in to your computer?")
        this.Status := this.Window.Add("Text", "x24 y106 w480 h24 BackgroundTrans cE3A6A6", "")
        this.Status.Visible := false
        this.Yes := this.Theme.Add(this.Window, 218, 140, 38, repair ? "Repair now" : "Yes", (*) => this.Choose(1), true, 126)
        this.No := this.Theme.Add(this.Window, 356, 140, 38, repair ? "Turn off" : "No", (*) => this.Choose(0), false, 126)
    }

    Show() {
        this.Window.Show("w528 h194")
        this.Yes.Focus()
    }

    Choose(choice) {
        if !this.OnChoice.Call(this, choice)
            return
        this.Dispose()
    }

    Close() {
        this.Dispose()
        SetTimer(ShowQAConsentOnStartup136, -1900)
    }

    Dispose() {
        this.Window.Destroy()
        this.Theme.Dispose()
        global WindowsStartupPrompt136
        WindowsStartupPrompt136 := 0
    }
}

WindowsStartupStatusText136(launcher := A_ScriptDir "\Ultimate Macro.cmd") {
    state := ReadWindowsStartupState136(launcher)
    if state.Enabled && !state.Stale
        return "Startup is enabled."
    if state.Stale
        return "A previous Startup shortcut needs repair."
    if state.Conflict
        return "Startup could not be enabled because its shortcut name is already in use."
    return "Startup is disabled."
}

WindowsStartupPreferenceChange136(ctrl, *) {
    global SettingsFile, WindowsStartupStatusCtrl, WindowsStartupCtrl
    enabled := ctrl.Value = 1
    if !SetWindowsStartup136(enabled, A_ScriptDir "\Ultimate Macro.cmd", , &message) {
        actual := ReadWindowsStartupState136()
        ctrl.Value := actual.Enabled ? 1 : 0
        WindowsStartupStatusCtrl.Text := "Couldn't update startup: " message
        return
    }
    IniWrite(1, SettingsFile, "Welcome", "StartupPromptAnswered")
    IniWrite(enabled ? 1 : 0, SettingsFile, "Options", "LaunchOnWindowsStartup")
    WindowsStartupCtrl.Value := enabled ? 1 : 0
    WindowsStartupStatusCtrl.Text := WindowsStartupStatusText136()
}

WindowsStartupCheckOnLaunch136() {
    global SettingsFile, WindowsStartupPrompt136, WindowsStartupCtrl, WindowsStartupStatusCtrl
    launchedFromWindows := WindowsStartupLaunchFromArgs136(A_Args)
    completed := IniRead(SettingsFile, "Welcome", "Completed", 0)
    answered := IniRead(SettingsFile, "Welcome", "StartupPromptAnswered", "")
    preference := IniRead(SettingsFile, "Options", "LaunchOnWindowsStartup", 0) = 1
    state := ReadWindowsStartupState136()
    WindowsStartupCtrl.Value := state.Enabled ? 1 : 0
    WindowsStartupStatusCtrl.Text := WindowsStartupStatusText136()
    if launchedFromWindows {
        SetTimer(ShowQAConsentOnStartup136, -1900)
        return
    }
    if !preference && (state.Stale || state.Enabled)
        SetWindowsStartup136(false)
    if WindowsStartupPromptNeeded136(completed, answered, launchedFromWindows) {
        WindowsStartupPrompt136 := WindowsStartupPromptPage136(WindowsStartupPromptChoice136, false)
        WindowsStartupPrompt136.Show()
        return
    }
    if preference && (!state.Enabled || state.Stale) {
        WindowsStartupPrompt136 := WindowsStartupPromptPage136(WindowsStartupPromptChoice136, true)
        WindowsStartupPrompt136.Show()
        return
    }
    SetTimer(ShowQAConsentOnStartup136, -1900)
}

WindowsStartupPromptChoice136(page, choice) {
    global SettingsFile, WindowsStartupCtrl, WindowsStartupStatusCtrl
    enabled := choice = 1
    if !SetWindowsStartup136(enabled, A_ScriptDir "\Ultimate Macro.cmd", , &message) {
        page.Status.Text := "Couldn't update Windows startup: " message
        page.Status.Visible := true
        return false
    }
    IniWrite(1, SettingsFile, "Welcome", "StartupPromptAnswered")
    IniWrite(enabled ? 1 : 0, SettingsFile, "Options", "LaunchOnWindowsStartup")
    if IsSet(WindowsStartupCtrl)
        WindowsStartupCtrl.Value := enabled ? 1 : 0
    if IsSet(WindowsStartupStatusCtrl)
        WindowsStartupStatusCtrl.Text := WindowsStartupStatusText136()
    SetTimer(ShowQAConsentOnStartup136, -1900)
    return true
}

WelcomeOpen136() {
    global SettingsFile, VipLink, PotatoMode, WebhookLink, WelcomeSetup136
    mode := PotatoMode ? (IniRead(SettingsFile, "Review", "TurboPotato", 0) = 1 ? 3 : 2) : 1
    WelcomeSetup136 := WelcomePage136(SettingsFile, VipLink, mode, WebhookLink, WelcomeFinished136,
        A_ScriptDir "\Ultimate Macro.cmd")
    WelcomeSetup136.Show()
}

WelcomeFinished136(page) {
    global MainGui, VipLink, UseVipServer, PotatoMode, WebhookLink, WebhookEnabled, SettingsFile
    global VipLinkCtrl, PotatoModeCtrl, TurboPotatoCtrl, WebhookLinkCtrl, WelcomeSetup136
    global WindowsStartupCtrl, WindowsStartupStatusCtrl
    VipLink := page.SelectedLink(), UseVipServer := VipLink != "" ? 1 : 0
    PotatoMode := page.Mode.Value > 1 ? 1 : 0
    WebhookLink := Trim(page.Webhook.Value), WebhookEnabled := WebhookLink != "" ? 1 : 0
    VipLinkCtrl.Value := VipLink
    PotatoModeCtrl.Value := PotatoMode
    TurboPotatoCtrl.Value := page.Mode.Value = 3 ? 1 : 0
    WebhookLinkCtrl.Value := WebhookLink
    if IsSet(WindowsStartupCtrl)
        WindowsStartupCtrl.Value := page.StartupChoice
    if IsSet(WindowsStartupStatusCtrl)
        WindowsStartupStatusCtrl.Text := WindowsStartupStatusText136(A_ScriptDir "\Ultimate Macro.cmd")
    TurboInit136(SettingsFile)
    RefreshVipServerStatus()
    RefreshWebhookStatus()
    page.Dispose()
    WelcomeSetup136 := 0
    MainGui.Show("w700 h565")
    SetTimer(ShowQAConsentOnStartup136, -1900)
}
