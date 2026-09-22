# ============================================================
# LAB 2 tikrinimo skriptas
# Default kalba: LT
# EN kalbą nustato Check-Lab2-EN.ps1 paleidiklis
# ============================================================

# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    if ($PSScriptRoot) {
        . (Join-Path $PSScriptRoot '../configs/common.ps1')
    }
    else {
        Invoke-RestMethod `
            'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1' `
            -ErrorAction Stop |
            Invoke-Expression
    }
}
catch {
    # Kalbų konfigūracija dar neužkrauta
    Write-Error "Failed to load common functions."
    throw
}


# --- 2. KALBA ---
if ($Lang -notin @("LT", "EN")) {
    $Lang = "LT"
}


# --- 3. INICIJUOJAME DARBĄ ---
$Setup = Initialize-Lab `
    -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab02/Check-Lab2-config.json" `
    -Lang $Lang

$GlobCfg = $Setup.GlobalConfig
$LocCfg  = $Setup.LocalConfig

# Bendri tekstai
$Msg = $Setup.Messages

# LAB2 tekstai
$LabMsg  = $LocCfg.Messages
$LabName = $LocCfg.LabName.$Lang

$TxtResourceGroup = $LocCfg.Checks.ResourceGroup.$Lang
$TxtWebApp        = $LocCfg.Checks.WebApp.$Lang
$TxtRuntime       = $LocCfg.Checks.Runtime.$Lang
$TxtAppService    = $LocCfg.Checks.AppServicePlan.$Lang
$TxtStorage       = $LocCfg.Checks.StorageAccount.$Lang


# ============================================================
# A. RESOURCE GROUP
# ============================================================

$targetRG = Get-AzResourceGroup |
    Where-Object {
        $_.ResourceGroupName -match $LocCfg.ResourceGroupPattern
    } |
    Select-Object -First 1


if ($targetRG) {
    $rgText =
        "[$($Msg.Ok)] - $($targetRG.ResourceGroupName) ($($targetRG.Location))"

    $rgColor = "Green"
}
else {
    $rgText =
        "[$($Msg.Error)] - $($LabMsg.ResourceGroupNotFound.$Lang)"

    $rgColor = "Red"
}


# ============================================================
# REZULTATŲ MASYVAS
# ============================================================

$results = @()

$results += [PSCustomObject]@{
    Name   = $TxtResourceGroup
    Text   = $rgText
    Color  = $rgColor
    Indent = 0
}


# ============================================================
# B. WEB APP
# ============================================================

if ($targetRG) {

    $webApp = Get-AzWebApp `
        -ResourceGroupName $targetRG.ResourceGroupName `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1


    if ($webApp) {

        # ----------------------------------------------------
        # Web App pagrindinė eilutė
        # ----------------------------------------------------

        $results += [PSCustomObject]@{
            Name   = $TxtWebApp
            Text   = "[$($Msg.Ok)] - $($webApp.Name) ($($webApp.Location))"
            Color  = "Green"
            Indent = 0
        }


        # ----------------------------------------------------
        # Runtime
        # ----------------------------------------------------

        $runtime = $webApp.SiteConfig.NetFrameworkVersion

        if ($runtime) {

            $runtimeVersion = $runtime -replace '^v', ''

            if ($runtimeVersion -match "^$($LocCfg.ExpectedWebApp.Runtime)(\.|$)") {

                $runtimeText =
                    "[$($Msg.Ok)] - .NET $($LocCfg.ExpectedWebApp.Runtime)"

                $runtimeColor = "Green"
            }
            else {
                $runtimeText =
                    "[$($Msg.Error)] - $runtime"

                $runtimeColor = "Yellow"
            }
        }
        else {
            $runtimeText =
                "[$($Msg.Error)] - $($LabMsg.RuntimeNotDetected.$Lang)"

            $runtimeColor = "Yellow"
        }


        $results += [PSCustomObject]@{
            Name   = $TxtRuntime
            Text   = $runtimeText
            Color  = $runtimeColor
            Indent = 1
        }


        # ----------------------------------------------------
        # App Service Plan
        # ----------------------------------------------------

        try {

            $planName = Split-Path $webApp.ServerFarmId -Leaf

            $plan = Get-AzAppServicePlan `
                -ResourceGroupName $targetRG.ResourceGroupName `
                -Name $planName `
                -ErrorAction Stop


            $planOS = if ($plan.Reserved) {
                "Linux"
            }
            else {
                "Windows"
            }


            $skuName = $plan.Sku.Name
            $skuTier = $plan.Sku.Tier


            $planDisplay =
                "$skuTier $skuName / $planOS"


            $planOk =
                ($skuName -eq $LocCfg.ExpectedWebApp.PlanSku) -and
                ($skuTier -eq $LocCfg.ExpectedWebApp.PlanTier) -and
                ($planOS -eq $LocCfg.ExpectedWebApp.OperatingSystem)


            if ($planOk) {
                $planText =
                    "[$($Msg.Ok)] - $planDisplay"

                $planColor = "Green"
            }
            else {
                $planText =
                    "[$($Msg.Error)] - $planDisplay"

                $planColor = "Yellow"
            }
        }
        catch {
            $planText =
                "[$($Msg.Error)] - $($LabMsg.PlanNotDetected.$Lang)"

            $planColor = "Yellow"
        }


        $results += [PSCustomObject]@{
            Name   = $TxtAppService
            Text   = $planText
            Color  = $planColor
            Indent = 1
        }
    }
    else {

        $results += [PSCustomObject]@{
            Name   = $TxtWebApp
            Text   = "[$($LabMsg.MissingStatus.$Lang)] - $($LabMsg.ResourceNotFound.$Lang)"
            Color  = "Red"
            Indent = 0
        }
    }


    # ========================================================
    # C. STORAGE ACCOUNT
    # ========================================================

    $storage = Get-AzStorageAccount `
        -ResourceGroupName $targetRG.ResourceGroupName `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1


    if ($storage) {

        $storageSku = $storage.Sku.Name

        if ($storageSku -eq $LocCfg.ExpectedStorageSku) {
            $storageColor = "Green"
            $storageStatus = $Msg.Ok
        }
        else {
            $storageColor = "Yellow"
            $storageStatus = $Msg.Error
        }


        $storageText =
            "[$storageStatus] - " +
            "$($storage.StorageAccountName) " +
            "($($storage.Location)) " +
            "[$storageSku]"


        $results += [PSCustomObject]@{
            Name   = $TxtStorage
            Text   = $storageText
            Color  = $storageColor
            Indent = 0
        }
    }
    else {

        $results += [PSCustomObject]@{
            Name   = $TxtStorage
            Text   = "[$($LabMsg.MissingStatus.$Lang)] - $($LabMsg.ResourceNotFound.$Lang)"
            Color  = "Red"
            Indent = 0
        }
    }

    # ============================================================
    # D. CLOUD SHELL RESOURCE GROUP
    # ============================================================

    $cloudShellRG = Get-AzResourceGroup |
        Where-Object {
            $_.ResourceGroupName -match $LocCfg.CloudShell.ResourceGroupPattern
        } |
        Select-Object -First 1


    if ($cloudShellRG) {

        $results += [PSCustomObject]@{
            Name   = $LocCfg.Checks.CloudShellResourceGroup.$Lang
            Text   = "[$($Msg.Ok)] - $($cloudShellRG.ResourceGroupName) ($($cloudShellRG.Location))"
            Color  = "Green"
            Indent = 0
        }


        $cloudShellStorage = Get-AzStorageAccount `
            -ResourceGroupName $cloudShellRG.ResourceGroupName `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1


        if ($cloudShellStorage) {

            $results += [PSCustomObject]@{
                Name   = $LocCfg.Checks.CloudShellStorage.$Lang
                Text   = "[$($Msg.Ok)] - $($cloudShellStorage.StorageAccountName) ($($cloudShellStorage.Location)) [$($cloudShellStorage.Sku.Name)]"
                Color  = "Green"
                Indent = 0
            }
        }
        else {

            $results += [PSCustomObject]@{
                Name   = $LocCfg.Checks.CloudShellStorage.$Lang
                Text   = "[$($LabMsg.MissingStatus.$Lang)] - $($LabMsg.ResourceNotFound.$Lang)"
                Color  = "Red"
                Indent = 0
            }
        }
    }
    else {

        $results += [PSCustomObject]@{
            Name   = $LocCfg.Checks.CloudShellResourceGroup.$Lang
            Text   = "[$($LabMsg.MissingStatus.$Lang)] - $($LabMsg.ResourceNotFound.$Lang)"
            Color  = "Red"
            Indent = 0
        }
    }
}
else {

    # Jei nėra RG, kitų resursų netikriname

    $results += [PSCustomObject]@{
        Name   = $TxtWebApp
        Text   = "[$($Msg.Error)] - $($LabMsg.NoResourceGroup.$Lang)"
        Color  = "Gray"
        Indent = 0
    }


    $results += [PSCustomObject]@{
        Name   = $TxtStorage
        Text   = "[$($Msg.Error)] - $($LabMsg.NoResourceGroup.$Lang)"
        Color  = "Gray"
        Indent = 0
    }
}


# ============================================================
# GALUTINIS REZULTATAS
# ============================================================

$date = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host ""
Write-Host "--- $($Msg.FinalResult) ---" -ForegroundColor Cyan

Write-Host "==================================================" `
    -ForegroundColor Gray

Write-Host $Setup.HeaderTitle
Write-Host $LabName -ForegroundColor Yellow

Write-Host "$($Msg.Date): $date"
Write-Host "$($Msg.Student): $($Setup.StudentEmail)"

Write-Host "==================================================" `
    -ForegroundColor Gray


$mainNumber = 1

foreach ($res in $results) {

    if ($res.Indent -eq 1) {
        $label = "   $($res.Name):"
    }
    else {
        $label = "$mainNumber. $($res.Name):"
        $mainNumber++
    }


    $targetWidth = 39

    $spaces = $targetWidth - $label.Length

    if ($spaces -lt 1) {
        $spaces = 1
    }


    Write-Host ($label + (" " * $spaces)) -NoNewline

    Write-Host $res.Text `
        -ForegroundColor $res.Color
}


Write-Host "==================================================" `
    -ForegroundColor Gray

Write-Host ""