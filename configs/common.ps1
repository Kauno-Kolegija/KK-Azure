
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

    $Msg = $GlobalConfig.Messages.$Lang

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
# Final result renderer
# ============================================================
function Show-LabResults {
    param (
        [Parameter(Mandatory)]
        [object]$Setup,

        [Parameter(Mandatory)]
        [string]$LabName,

        [Parameter(Mandatory)]
        [array]$Results,

        [int]$LabelWidth = 35
    )

    $Msg = $Setup.Messages
    $date = Get-Date -Format "yyyy-MM-dd HH:mm"

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
        if ($null -ne $res.PSObject.Properties['Indent']) {
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
        if ($neededSpaces -lt 1) { $neededSpaces = 1 }

        Write-Host ($label + (" " * $neededSpaces)) -NoNewline
        Write-Host $res.Text -ForegroundColor $res.Color
    }

    Write-Host "==================================================" -ForegroundColor Gray
    Write-Host ""
}
