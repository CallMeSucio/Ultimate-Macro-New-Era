#Requires AutoHotkey v2.0
; Setup-only native button painting. Controls retain normal Tab/Space behavior.
class WelcomeTheme136 {
    __New(page) {
        this.Page := page, this.Buttons := Map(), this.Icons := []
        this.EditInputs := Map()
        this.ComboInputs := Map()
        this.ButtonCallback := CallbackCreate(ObjBindMethod(this, "ButtonProc"), , 6)
        this.InputCallback := CallbackCreate(ObjBindMethod(this, "InputProc"), , 6)
        this.DrawCallback := ObjBindMethod(this, "Draw")
        this.MeasureCallback := ObjBindMethod(this, "Measure")
        this.ScrollCallback := ObjBindMethod(this, "Scroll")
        this.WheelCallback := ObjBindMethod(this, "Wheel")
        OnMessage(0x2B, this.DrawCallback)
        OnMessage(0x2C, this.MeasureCallback)
        OnMessage(0x115, this.ScrollCallback)
        OnMessage(0x20A, this.WheelCallback)
        iconPath := A_ScriptDir "\icon.ico"
        if !FileExist(iconPath)
            iconPath := A_ScriptDir "\..\icon.ico"
        this.IconPath := iconPath
        if FileExist(iconPath) {
            for kind, size in [32, 16] {
                size := Round(size * A_ScreenDPI / 96)
                icon := DllCall("user32\LoadImageW", "Ptr", 0, "Str", iconPath, "UInt", 1,
                    "Int", size, "Int", size, "UInt", 0x10, "Ptr")
                if icon {
                    this.Icons.Push(icon)
                    DllCall("user32\SendMessageW", "Ptr", page.Window.Hwnd, "UInt", 0x80,
                        "Ptr", kind = 1 ? 1 : 0, "Ptr", icon, "Ptr")
                }
            }
        }
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", page.Window.Hwnd,
            "UInt", 20, "Int*", 1, "UInt", 4)
    }

    Add(guiObj, x, y, w, label, callback, primary := false, width := 150) {
        guiObj.SetFont("s10 w400 cE2E4E7", "Segoe UI")
        button := guiObj.Add("Button", "x" x " y" y " w" width " h" w " +0xB", label)
        DllCall("comctl32\SetWindowSubclass", "Ptr", button.Hwnd, "Ptr", this.ButtonCallback, "UPtr", 1, "UPtr", 0)
        DllCall("user32\SendMessageW", "Ptr", button.Hwnd, "UInt", 0xF4, "Ptr", 0xB, "Ptr", true)
        this.Buttons[button.Hwnd] := {Control: button, Primary: primary, Quiet: false}
        button.OnEvent("Click", callback)
        return button
    }

    ButtonProc(hwnd, msg, wParam, lParam, subclassId, data) {
        ; AHK updates default-button styles during focus changes. Keep native
        ; keyboard behavior while retaining the setup's owner-drawn appearance.
        if msg = 0xF4 {
            style := DllCall("user32\GetWindowLongPtrW", "Ptr", hwnd, "Int", -16, "Ptr")
            DllCall("user32\SetWindowLongPtrW", "Ptr", hwnd, "Int", -16, "Ptr", (style & ~15) | 11)
            DllCall("user32\InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", true)
            return 0
        }
        return DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }

    StyleInput(ctrl) {
        ctrl.Opt("-Border -E0x200 Background181818")
        if ctrl.Type = "Edit"
            this.EditInputs[ctrl.Hwnd] := true
        else {
            this.ComboInputs[ctrl.Hwnd] := true
            DllCall("user32\SendMessageW", "Ptr", ctrl.Hwnd, "UInt", 0x153,
                "Ptr", -1, "Ptr", Round(26 * A_ScreenDPI / 96))
        }
        DllCall("comctl32\SetWindowSubclass", "Ptr", ctrl.Hwnd, "Ptr", this.InputCallback, "UPtr", 2, "UPtr", 0)
        DllCall("user32\SetWindowPos", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 0, "Int", 0,
            "Int", 0, "Int", 0, "UInt", 0x27)
        bounds := Buffer(16)
        DllCall("user32\GetWindowRect", "Ptr", ctrl.Hwnd, "Ptr", bounds)
        width := NumGet(bounds, 8, "Int") - NumGet(bounds, 0, "Int")
        height := NumGet(bounds, 12, "Int") - NumGet(bounds, 4, "Int")
        curve := Round(10 * A_ScreenDPI / 96)
        inset := 0
        region := DllCall("gdi32\CreateRoundRectRgn", "Int", inset, "Int", inset, "Int", width - inset,
            "Int", height - inset, "Int", curve, "Int", curve, "Ptr")
        if !DllCall("user32\SetWindowRgn", "Ptr", ctrl.Hwnd, "Ptr", region, "Int", true)
            DllCall("gdi32\DeleteObject", "Ptr", region)
    }

    InputProc(hwnd, msg, wParam, lParam, subclassId, data) {
        if this.ComboInputs.Has(hwnd) {
            if msg = 0x85 || msg = 0x14
                return 1
            if msg = 0xF {
                paint := Buffer(A_PtrSize = 8 ? 72 : 64, 0)
                DllCall("user32\BeginPaint", "Ptr", hwnd, "Ptr", paint, "Ptr")
                this.DrawCombo(hwnd)
                DllCall("user32\EndPaint", "Ptr", hwnd, "Ptr", paint)
                return 0
            }
        }
        result := DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
        if msg = 0x83 && this.EditInputs.Has(hwnd) {
            padding := Round(4 * A_ScreenDPI / 96)
            NumPut("Int", NumGet(lParam, 4, "Int") + padding, lParam, 4)
            NumPut("Int", NumGet(lParam, 12, "Int") - padding, lParam, 12)
            return 0
        }
        if this.ComboInputs.Has(hwnd) {
            if msg = 7 || msg = 8 || msg = 0xF4 || msg = 0x14E
                DllCall("user32\InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", false)
            return result
        }
        if msg = 0xF || msg = 0x85 || msg = 7 || msg = 8 {
            bounds := Buffer(16)
            DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", bounds)
            width := NumGet(bounds, 8, "Int") - NumGet(bounds, 0, "Int")
            height := NumGet(bounds, 12, "Int") - NumGet(bounds, 4, "Int")
            NumPut("Int", 0, "Int", 0, "Int", width, "Int", height, bounds)
            dc := DllCall("user32\GetWindowDC", "Ptr", hwnd, "Ptr")
            focused := DllCall("user32\GetFocus", "Ptr") = hwnd
            brush := DllCall("gdi32\CreateSolidBrush", "UInt", 0x181818, "Ptr")
            loop 4 {
                DllCall("user32\FrameRect", "Ptr", dc, "Ptr", bounds, "Ptr", brush)
                DllCall("user32\InflateRect", "Ptr", bounds, "Int", -1, "Int", -1)
            }
            DllCall("gdi32\DeleteObject", "Ptr", brush)
            pen := DllCall("gdi32\CreatePen", "Int", 0, "Int", 1, "UInt", focused ? 0x906945 : 0x353535, "Ptr")
            oldPen := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", pen, "Ptr")
            oldBrush := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", DllCall("gdi32\GetStockObject", "Int", 5, "Ptr"), "Ptr")
            curve := Round(10 * A_ScreenDPI / 96)
            edge := this.ComboInputs.Has(hwnd) ? Round(3 * A_ScreenDPI / 96) : 1
            DllCall("gdi32\RoundRect", "Ptr", dc, "Int", edge, "Int", edge, "Int", width - edge, "Int", height - edge,
                "Int", curve, "Int", curve)
            DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldPen)
            DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldBrush)
            DllCall("gdi32\DeleteObject", "Ptr", pen)
            DllCall("user32\ReleaseDC", "Ptr", hwnd, "Ptr", dc)
        }
        return result
    }

    DrawCombo(hwnd) {
        bounds := Buffer(16)
        DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", bounds)
        width := NumGet(bounds, 8, "Int") - NumGet(bounds, 0, "Int")
        height := NumGet(bounds, 12, "Int") - NumGet(bounds, 4, "Int")
        dc := DllCall("user32\GetWindowDC", "Ptr", hwnd, "Ptr")
        focused := DllCall("user32\GetFocus", "Ptr") = hwnd
        brush := DllCall("gdi32\CreateSolidBrush", "UInt", 0x181818, "Ptr")
        pen := DllCall("gdi32\CreatePen", "Int", 0, "Int", 1, "UInt", focused ? 0x906945 : 0x353535, "Ptr")
        oldBrush := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", brush, "Ptr")
        oldPen := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", pen, "Ptr")
        curve := Round(10 * A_ScreenDPI / 96)
        DllCall("gdi32\RoundRect", "Ptr", dc, "Int", 0, "Int", 0, "Int", width, "Int", height,
            "Int", curve, "Int", curve)
        length := DllCall("user32\GetWindowTextLengthW", "Ptr", hwnd)
        caption := Buffer((length + 1) * 2, 0)
        DllCall("user32\GetWindowTextW", "Ptr", hwnd, "Ptr", caption, "Int", length + 1)
        font := DllCall("user32\SendMessageW", "Ptr", hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
        oldFont := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
        NumPut("Int", Round(10 * A_ScreenDPI / 96), "Int", 0, "Int", width - Round(28 * A_ScreenDPI / 96), "Int", height, bounds)
        DllCall("gdi32\SetBkMode", "Ptr", dc, "Int", 1)
        DllCall("gdi32\SetTextColor", "Ptr", dc, "UInt", 0xE7E4E2)
        DllCall("user32\DrawTextW", "Ptr", dc, "Ptr", caption, "Int", length, "Ptr", bounds, "UInt", 0x8824)
        x := width - Round(16 * A_ScreenDPI / 96), y := Round(height / 2)
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", DllCall("gdi32\GetStockObject", "Int", 19, "Ptr"))
        DllCall("gdi32\SetDCPenColor", "Ptr", dc, "UInt", 0xA89D96)
        DllCall("gdi32\MoveToEx", "Ptr", dc, "Int", x - 4, "Int", y - 2, "Ptr", 0)
        DllCall("gdi32\LineTo", "Ptr", dc, "Int", x, "Int", y + 2)
        DllCall("gdi32\LineTo", "Ptr", dc, "Int", x + 4, "Int", y - 2)
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldFont)
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldPen)
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldBrush)
        DllCall("gdi32\DeleteObject", "Ptr", pen)
        DllCall("gdi32\DeleteObject", "Ptr", brush)
        DllCall("user32\ReleaseDC", "Ptr", hwnd, "Ptr", dc)
    }

    Draw(wParam, lParam, *) {
        handleOffset := A_PtrSize = 8 ? 24 : 20
        hwnd := NumGet(lParam, handleOffset, "Ptr")
        if this.ComboInputs.Has(hwnd)
            return this.DrawComboItem(hwnd, lParam, handleOffset)
        if !this.Buttons.Has(hwnd)
            return
        entry := this.Buttons[hwnd], state := NumGet(lParam, 16, "UInt")
        dc := NumGet(lParam, handleOffset + A_PtrSize, "Ptr"), offset := handleOffset + 2 * A_PtrSize
        rect := Buffer(16)
        DllCall("kernel32\RtlMoveMemory", "Ptr", rect, "Ptr", lParam + offset, "UPtr", 16)
        disabled := (state & 4) != 0, pressed := (state & 1) != 0
        color := disabled ? 0x202020 : (entry.Primary ? (pressed ? 0x714321 : 0x92562A) : (pressed ? 0x303030 : 0x242424))
        border := disabled ? 0x303030 : (entry.Primary ? 0xA56A3B : 0x404040)
        if entry.Quiet && !pressed
            color := border := 0x121212
        brush := DllCall("gdi32\CreateSolidBrush", "UInt", 0x121212, "Ptr")
        DllCall("user32\FillRect", "Ptr", dc, "Ptr", rect, "Ptr", brush)
        DllCall("gdi32\DeleteObject", "Ptr", brush)
        brush := DllCall("gdi32\CreateSolidBrush", "UInt", color, "Ptr")
        pen := DllCall("gdi32\CreatePen", "Int", 0, "Int", 1, "UInt", border, "Ptr")
        oldBrush := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", brush, "Ptr")
        oldPen := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", pen, "Ptr")
        radius := Round(14 * A_ScreenDPI / 96)
        DllCall("gdi32\RoundRect", "Ptr", dc, "Int", NumGet(rect, 0, "Int"), "Int", NumGet(rect, 4, "Int"),
            "Int", NumGet(rect, 8, "Int"), "Int", NumGet(rect, 12, "Int"), "Int", radius, "Int", radius)
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldBrush)
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldPen)
        DllCall("gdi32\DeleteObject", "Ptr", brush)
        DllCall("gdi32\DeleteObject", "Ptr", pen)
        DllCall("user32\InflateRect", "Ptr", rect, "Int", -1, "Int", -1)
        font := DllCall("user32\SendMessageW", "Ptr", hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
        previousFont := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
        DllCall("gdi32\SetBkMode", "Ptr", dc, "Int", 1)
        DllCall("gdi32\SetTextColor", "Ptr", dc, "UInt", disabled ? 0x808080 : (entry.Quiet ? 0xB5A89C : 0xE7E4E2))
        DllCall("user32\DrawTextW", "Ptr", dc, "Str", entry.Control.Text, "Int", -1, "Ptr", rect, "UInt", 0x825)
        if (state & 0x10) && !(state & 0x200) {
            DllCall("user32\InflateRect", "Ptr", rect, "Int", -3, "Int", -3)
            DllCall("user32\DrawFocusRect", "Ptr", dc, "Ptr", rect)
        }
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", previousFont)
        return true
    }

    Measure(wParam, lParam, msg, hwnd) {
        if hwnd = this.Page.Form.Hwnd && NumGet(lParam, 0, "UInt") = 3 {
            NumPut("UInt", Round(26 * A_ScreenDPI / 96), lParam, 16)
            return true
        }
    }

    DrawComboItem(hwnd, data, handleOffset) {
        dc := NumGet(data, handleOffset + A_PtrSize, "Ptr")
        rect := Buffer(16)
        DllCall("kernel32\RtlMoveMemory", "Ptr", rect, "Ptr", data + handleOffset + 2 * A_PtrSize, "UPtr", 16)
        selected := (NumGet(data, 16, "UInt") & 1) != 0
        brush := DllCall("gdi32\CreateSolidBrush", "UInt", selected ? 0x68472B : 0x181818, "Ptr")
        DllCall("user32\FillRect", "Ptr", dc, "Ptr", rect, "Ptr", brush)
        DllCall("gdi32\DeleteObject", "Ptr", brush)
        index := NumGet(data, 8, "UInt")
        if index = 0xFFFFFFFF
            return true
        length := DllCall("user32\SendMessageW", "Ptr", hwnd, "UInt", 0x149, "Ptr", index, "Ptr", 0, "Ptr")
        if length < 0
            return true
        caption := Buffer((length + 1) * 2, 0)
        DllCall("user32\SendMessageW", "Ptr", hwnd, "UInt", 0x148, "Ptr", index, "Ptr", caption)
        NumPut("Int", NumGet(rect, 0, "Int") + Round(10 * A_ScreenDPI / 96), rect, 0)
        DllCall("gdi32\SetBkMode", "Ptr", dc, "Int", 1)
        DllCall("gdi32\SetTextColor", "Ptr", dc, "UInt", 0xE7E4E2)
        font := DllCall("user32\SendMessageW", "Ptr", hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
        oldFont := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
        DllCall("user32\DrawTextW", "Ptr", dc, "Ptr", caption, "Int", length, "Ptr", rect, "UInt", 0x8824)
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldFont)
        return true
    }

    Scroll(wParam, lParam, msg, hwnd) {
        if hwnd != this.Page.Form.Hwnd
            return
        code := wParam & 0xFFFF, page := this.Page
        if code = 4 || code = 5 {
            info := Buffer(28, 0)
            NumPut("UInt", 28, "UInt", 0x10, info)
            DllCall("user32\GetScrollInfo", "Ptr", hwnd, "Int", 1, "Ptr", info)
            page.ScrollTo(NumGet(info, 24, "Int"))
        } else if code <= 3
            page.ScrollTo(page.ScrollOffset + (code = 0 ? -28 : code = 1 ? 28 : code = 2 ? -page.Viewport : page.Viewport))
        return 0
    }

    Wheel(wParam, lParam, msg, hwnd) {
        page := this.Page
        if hwnd != page.Window.Hwnd && !DllCall("user32\IsChild", "Ptr", page.Window.Hwnd, "Ptr", hwnd)
            return
        if !page.MaxScroll
            return
        delta := (wParam >> 16) & 0xFFFF
        if delta >= 32768
            delta -= 65536
        page.ScrollTo(page.ScrollOffset - delta / 120 * 72)
        return 0
    }

    Dispose() {
        OnMessage(0x2B, this.DrawCallback, 0)
        OnMessage(0x2C, this.MeasureCallback, 0)
        OnMessage(0x115, this.ScrollCallback, 0)
        OnMessage(0x20A, this.WheelCallback, 0)
        for icon in this.Icons
            DllCall("user32\DestroyIcon", "Ptr", icon)
        this.Buttons.Clear()
        CallbackFree(this.ButtonCallback)
        CallbackFree(this.InputCallback)
        this.Page := 0
    }
}
