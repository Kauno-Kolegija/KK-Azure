
# ============================================================
# Script version checker
# ============================================================
function Get-ScriptVersion {
    try {
        $commit = Invoke-RestMethod `
            -Uri "https://api.github.com/repos/Kauno-Kolegija/KK-Azure/commits/main" `
            -Headers @{ "User-Agent" = "KK-Azure-Lab-Checker" } `
            -ErrorAction Stop

        $shortSha = $commit.sha.Substring(0, 7)
        $commitDate = ([datetime]$commit.commit.committer.date).ToLocalTime().ToString("yyyy-MM-dd HH:mm")

        return "$shortSha ($commitDate)"
    }
    catch {
        return "unknown"
    }
}
# ============================================================
# Initialize lab environment
# ============================================================
function Initialize-Lab {
    param (
        [string]$LocalConfigUrl,
        [string]$Lang = "LT"
    )

    if ($Lang -notin @("LT", "EN")) {
        $Lang = "LT"
    }

    $GlobalUrl = "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/global.json"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    try {
        $GlobalConfig = Invoke-RestMethod -Uri $GlobalUrl -ErrorAction Stop
        $LocalConfig  = Invoke-RestMethod -Uri $LocalConfigUrl -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to download configuration (JSON)."
        throw
    }

    # Global JSON uses the same localization structure as laboratory configs:
    # MessageName -> LT / EN.
    $localizedMessages = [ordered]@{}

    foreach ($property in $GlobalConfig.Messages.PSObject.Properties) {
        $entry = $property.Value

        if ($entry.PSObject.Properties.Name -contains $Lang) {
            $localizedMessages[$property.Name] = $entry.$Lang
        }
        else {
            $localizedMessages[$property.Name] = $entry
        }
    }

    $Msg = [PSCustomObject]$localizedMessages

    $context = Get-AzContext

    if (-not $context) {
        Write-Error $Msg.AzureNotConnected
        exit
    }

    $StudentEmail = $null

    if ($env:ACC_USER_NAME -and $env:ACC_USER_NAME -match "@") {
        $StudentEmail = $env:ACC_USER_NAME
    }
    elseif (Get-Command az -ErrorAction SilentlyContinue) {
        try {
            $StudentEmail = az account show --query "user.name" -o tsv 2>$null
        }
        catch {}
    }

    if (-not $StudentEmail -or $StudentEmail -match "MSI@") {
        $StudentEmail = "$($context.Account.Id) ($($Msg.SystemIdentity))"
    }

    Clear-Host
    Write-Host $Msg.Running -ForegroundColor Yellow

    $ScriptVersion = Get-ScriptVersion

    return [PSCustomObject]@{
        GlobalConfig  = $GlobalConfig
        LocalConfig   = $LocalConfig
        StudentEmail  = $StudentEmail
        HeaderTitle   = "$($GlobalConfig.KaunoKolegija) | $($GlobalConfig.ModuleName.$Lang)"
        Language      = $Lang
        Messages      = $Msg
        ScriptVersion = $ScriptVersion
    }
}

# ============================================================
# Result status / formatting
# ============================================================
function Get-LabResultStyle {
    param (
        [Parameter(Mandatory)]
        [ValidateSet("OK", "WARNING", "ERROR", "INFO")]
        [string]$Status,

        [Parameter(Mandatory)]
        [object]$Messages
    )

    switch ($Status) {
        "OK" {
            $label = if ($Messages.Ok) { $Messages.Ok } else { "OK" }
            $color = "Green"
        }

        "WARNING" {
            $label = if ($Messages.Warning) { $Messages.Warning } else { "WARNING" }
            $color = "Yellow"
        }

        "ERROR" {
            $label = if ($Messages.Error) { $Messages.Error } else { "ERROR" }
            $color = "Red"
        }

        "INFO" {
            $label = if ($Messages.Info) { $Messages.Info } else { "INFO" }
            $color = "Cyan"
        }
    }

    return [PSCustomObject]@{
        Label = $label
        Color = $color
    }
}

# ============================================================
# Common result object creation
# ============================================================
function Add-LabResult {
    param (
        [Parameter(Mandatory)]
        [ref]$Results,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet("OK", "WARNING", "ERROR", "INFO")]
        [string]$Status,

        [string]$Message = "",

        [Parameter(Mandatory)]
        [object]$Messages,

        [int]$Indent = 0
    )

    if ($null -eq $Results.Value) {
        $Results.Value = @()
    }

    $style = Get-LabResultStyle `
        -Status $Status `
        -Messages $Messages

    if ([string]::IsNullOrWhiteSpace($Message)) {
        $text = "[$($style.Label)]"
    }
    else {
        $text = "[$($style.Label)] - $Message"
    }

    $Results.Value += [PSCustomObject]@{
        Name   = $Name
        Text   = $text
        Color  = $style.Color
        Indent = $Indent
        Status = $Status
    }
}

# ============================================================
# Common pattern search
# ============================================================
function Find-PatternMatch {
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Items,

        [Parameter(Mandatory)]
        [string]$Property,

        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $matches = @(
        $Items | Where-Object {
            $propertyObject = $_.PSObject.Properties[$Property]

            $null -ne $propertyObject -and
            [string]$propertyObject.Value -match $Pattern
        }
    )

    return [PSCustomObject]@{
        First = $matches | Select-Object -First 1
        Count = $matches.Count
        All   = $matches
    }
}

# ============================================================
# Final result renderer
# ============================================================
function Show-LabResults {
    param (
        [Parameter(Mandatory)]
        [object]$Setup,

        [Parameter(Mandatory)]
        [string]$LabName,

        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Results = @(),

        [int]$LabelWidth = 35
    )

    $Msg = $Setup.Messages
    $date = Get-Date -Format "yyyy-MM-dd HH:mm"

    if ($null -eq $Results) {
        $Results = @()
    }

    Write-Host ""
    Write-Host "--- $($Msg.FinalResult) ---" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Gray
    Write-Host $Setup.HeaderTitle
    Write-Host $LabName -ForegroundColor Yellow
    Write-Host "$($Msg.Date): $date"
    Write-Host "$($Msg.Student): $($Setup.StudentEmail)"
    Write-Host "$($Msg.ScriptVersion): $($Setup.ScriptVersion)"
    Write-Host "==================================================" -ForegroundColor Gray

    $i = 1

    foreach ($res in $Results) {
        $indent = 0

        if ($null -ne $res.PSObject.Properties["Indent"]) {
            $indent = [int]$res.Indent
        }

        if ($indent -gt 0) {
            $label = (("   " * $indent) + "$($res.Name):")
        }
        else {
            $label = "$i. $($res.Name):"
            $i++
        }

        $neededSpaces = $LabelWidth - $label.Length

        if ($neededSpaces -lt 1) {
            $neededSpaces = 1
        }

        Write-Host ($label + (" " * $neededSpaces)) -NoNewline
        Write-Host $res.Text -ForegroundColor $res.Color
    }

    Write-Host "==================================================" -ForegroundColor Gray
    Write-Host ""
}
