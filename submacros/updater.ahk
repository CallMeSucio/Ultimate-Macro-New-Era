#Requires AutoHotkey v2.0
#SingleInstance Force

if (A_LineFile = A_ScriptFullPath)
    ExitApp()

CheckForUpdate(currentVer) {
    static ReleaseApi := "https://api.github.com/repos/UltimateMacro/Ultimate-Macro-New-Era/releases/latest"
    static PreferredAsset := "TDS_Macro.zip"

    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("GET", ReleaseApi, false)
        whr.SetRequestHeader("Accept", "application/vnd.github+json")
        whr.SetRequestHeader("X-GitHub-Api-Version", "2022-11-28")
        whr.SetRequestHeader("User-Agent", "Ultimate-Macro-New-Era/" currentVer)
        whr.SetTimeouts(10000, 10000, 20000, 20000)
        whr.Send()

        if (whr.Status != 200)
            return 0

        release := JSON.parse(whr.ResponseText)
        if !release.Has("tag_name")
            return 0

        latestTag := release["tag_name"]
        if !RegExMatch(latestTag, "i)^v?\d+(?:\.\d+){1,3}(?:[A-Za-z]|[-+][0-9A-Za-z.-]+)?$")
            return 0

        latestVer := NormalizeMacroVersion(latestTag)
        installedVer := NormalizeMacroVersion(currentVer)
        if (CompareMacroVersions(latestVer, installedVer) <= 0)
            return 0

        downloadURL := ""
        digest := ""
        if release.Has("assets") {
            for asset in release["assets"] {
                if !asset.Has("name") || asset["name"] != PreferredAsset
                    continue
                if !asset.Has("browser_download_url") || !asset.Has("digest")
                    continue

                candidateURL := asset["browser_download_url"]
                candidateDigest := asset["digest"]
                if !RegExMatch(candidateURL,
                    "i)^https://github\.com/UltimateMacro/Ultimate-Macro-New-Era/releases/download/")
                    continue
                if !RegExMatch(candidateDigest, "i)^sha256:[0-9a-f]{64}$")
                    continue

                downloadURL := candidateURL
                digest := candidateDigest
                break
            }
        }

        if (downloadURL = "" || digest = "")
            return 0

        releaseBody := release.Has("body") && release["body"] ? release["body"] : ""
        updateMsg := "New version " latestTag " is available!`n"
        updateMsg .= "Current version: " currentVer "`n`n"

        if (releaseBody != "") {
            if (StrLen(releaseBody) > 800)
                releaseBody := SubStr(releaseBody, 1, 800) "...`n(Full changelog on GitHub)"
            updateMsg .= "Changelog:`n--------------------------------`n" releaseBody
            updateMsg .= "`n--------------------------------`n`n"
        }

        updateMsg .=
            "The update is downloaded to a staging directory, checksum-verified, and validated before replacement. Existing strategies are preserved and a rollback backup is retained.`n`n"
        updateMsg .= "Do you want to update now?"

        if (MsgBox(updateMsg, "Update Available", "YesNo Iconi") != "Yes")
            return 0

        safeUpdater := A_ScriptDir "\submacros\safe_update.ps1"
        if !FileExist(safeUpdater) {
            MsgBox("safe_update.ps1 was not found. The update was cancelled without changing the installation.`n`n" safeUpdater,
                "Update Error", "Iconx")
            return 0
        }

        currentPid := DllCall("Kernel32.dll\GetCurrentProcessId", "UInt")
        tempUpdater := A_Temp "\UltimateMacro_safe_update_" currentPid "_" A_TickCount ".ps1"
        FileCopy(safeUpdater, tempUpdater, 1)

        command := "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File " QuoteArg(tempUpdater)
        command .= " -DownloadUrl " QuoteArg(downloadURL)
        command .= " -MacroDir " QuoteArg(A_ScriptDir)
        command .= " -ExpectedSha256 " QuoteArg(digest)
        command .= " -ExpectedVersion " QuoteArg(latestTag)
        command .= " -WaitPid " currentPid
        command .= " -SelfDelete"

        Run(command, , "Hide")
        ExitApp()
    } catch Error {
        return 0
    }

    return 0
}

NormalizeMacroVersion(version) {
    version := Trim(version)
    return RegExReplace(version, "i)^v", "")
}

CompareMacroVersions(leftVersion, rightVersion) {
    ; Compare core versions numerically, not as strings (rc.10 > rc.9).
    ; Stable versions sort above -rc/-beta prereleases, while the project's
    ; legacy letter patch suffix (e.g. 1.3.4a) sorts after 1.3.4.
    leftText := RegExReplace(NormalizeMacroVersion(leftVersion), "\+.*$", "")
    rightText := RegExReplace(NormalizeMacroVersion(rightVersion), "\+.*$", "")
    leftCore := RegExReplace(leftText, "[^0-9.].*$", "")
    rightCore := RegExReplace(rightText, "[^0-9.].*$", "")
    if (leftCore = "" || rightCore = "")
        return StrCompare(leftText, rightText, false)

    lParts := StrSplit(leftCore, ".")
    rParts := StrSplit(rightCore, ".")
    count := Max(lParts.Length, rParts.Length)
    Loop count {
        l := (A_Index <= lParts.Length && lParts[A_Index] != "") ? Integer(lParts[A_Index]) : 0
        r := (A_Index <= rParts.Length && rParts[A_Index] != "") ? Integer(rParts[A_Index]) : 0
        if l > r
            return 1
        if l < r
            return -1
    }

    lSuffix := SubStr(leftText, StrLen(leftCore) + 1)
    rSuffix := SubStr(rightText, StrLen(rightCore) + 1)
    if lSuffix = rSuffix
        return 0
    ; -rc/-beta suffix: prerelease is older than the stable release.
    ; A letter-only suffix is a legacy follow-up release, not a prerelease.
    if lSuffix = ""
        return SubStr(rSuffix, 1, 1) = "-" ? 1 : -1
    if rSuffix = ""
        return SubStr(lSuffix, 1, 1) = "-" ? -1 : 1
    if (SubStr(lSuffix, 1, 1) = "-") != (SubStr(rSuffix, 1, 1) = "-")
        return SubStr(lSuffix, 1, 1) = "-" ? -1 : 1

    ; Project builds use labels such as -rc.4-hotfix.1.
    ; Treat both dot and dash as separators so rc.5 > rc.4-hotfix.1.
    lParts := StrSplit(LTrim(lSuffix, "-"), ".-")
    rParts := StrSplit(LTrim(rSuffix, "-"), ".-")
    count := Min(lParts.Length, rParts.Length)
    Loop count {
        l := lParts[A_Index]
        r := rParts[A_Index]
        lNumeric := RegExMatch(l, "^\d+$") != 0
        rNumeric := RegExMatch(r, "^\d+$") != 0
        if (lNumeric && rNumeric) {
            if Integer(l) > Integer(r)
                return 1
            if Integer(l) < Integer(r)
                return -1
        } else if (lNumeric != rNumeric) {
            return lNumeric ? -1 : 1
        } else {
            delta := StrCompare(l, r, false)
            if delta != 0
                return delta > 0 ? 1 : -1
        }
    }
    if lParts.Length = rParts.Length
        return 0
    return lParts.Length > rParts.Length ? 1 : -1
}

QuoteArg(value) {
    value := StrReplace(value, '"', '\"')
    return '"' value '"'
}