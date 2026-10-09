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

$LocCfg = $Setup.LocalConfig
$Msg    = $Setup.Messages
$LabMsg = $LocCfg.Messages
$LabName = $LocCfg.LabName.$Lang

$TxtResourceGroup = $LocCfg.Checks.ResourceGroup.$Lang
$TxtWebApp        = $LocCfg.Checks.WebApp.$Lang
$TxtRuntime       = $LocCfg.Checks.Runtime.$Lang
$TxtAppService    = $LocCfg.Checks.AppServicePlan.$Lang
$TxtStorage       = $LocCfg.Checks.StorageAccount.$Lang
$TxtCloudShellRG  = $LocCfg.Checks.CloudShellResourceGroup.$Lang
$TxtCloudShellSA  = $LocCfg.Checks.CloudShellStorage.$Lang

$results = @()

# ============================================================
# A. RESOURCE GROUP
# ============================================================

try {
    $matchingRGs = @(
        Get-AzResourceGroup -ErrorAction Stop |
        Where-Object { $_.ResourceGroupName -match $LocCfg.ResourceGroupPattern }
    )

    $targetRG = $matchingRGs | Select-Object -First 1

    if ($targetRG) {
        if ($matchingRGs.Count -gt 1) {
            $rgText = "[$($Msg.Warning)] - $($targetRG.ResourceGroupName) ($($targetRG.Location)); $($LabMsg.MultipleResourceGroups.$Lang)"
            $rgColor = "Yellow"
        }
        else {
            $rgText = "[$($Msg.Ok)] - $($targetRG.ResourceGroupName) ($($targetRG.Location))"
            $rgColor = "Green"
        }
    }
    else {
        $rgText = "[$($Msg.Error)] - $($LabMsg.ResourceGroupNotFound.$Lang)"
        $rgColor = "Red"
    }
}
catch {
    $targetRG = $null
    $rgText = "[$($Msg.Warning)] - $($LabMsg.ResourceGroupCheckFailed.$Lang)"
    $rgColor = "Yellow"
}

$results += [PSCustomObject]@{
    Name   = $TxtResourceGroup
    Text   = $rgText
    Color  = $rgColor
    Indent = 0
}

# ============================================================
# B. WEB APP + RUNTIME + APP SERVICE PLAN
# ============================================================

if ($targetRG) {
    try {
        $webApps = @(
            Get-AzWebApp `
                -ResourceGroupName $targetRG.ResourceGroupName `
                -ErrorAction Stop
        )

        $webApp = $webApps | Select-Object -First 1

        if ($webApp) {
            if ($webApps.Count -gt 1) {
                $webText = "[$($Msg.Warning)] - $($webApp.Name) ($($webApp.Location)); $($LabMsg.MultipleResources.$Lang)"
                $webColor = "Yellow"
            }
            else {
                $webText = "[$($Msg.Ok)] - $($webApp.Name) ($($webApp.Location))"
                $webColor = "Green"
            }

            $results += [PSCustomObject]@{
                Name   = $TxtWebApp
                Text   = $webText
                Color  = $webColor
                Indent = 0
            }

            # Runtime
            $runtime = $webApp.SiteConfig.NetFrameworkVersion

            if ($runtime) {
                $runtimeVersion = $runtime -replace '^v', ''

                if ($runtimeVersion -match "^$($LocCfg.ExpectedWebApp.Runtime)(\.|$)") {
                    $runtimeText = "[$($Msg.Ok)] - .NET $($LocCfg.ExpectedWebApp.Runtime)"
                    $runtimeColor = "Green"
                }
                else {
                    $runtimeText = "[$($Msg.Warning)] - $runtime"
                    $runtimeColor = "Yellow"
                }
            }
            else {
                $runtimeText = "[$($Msg.Warning)] - $($LabMsg.RuntimeNotDetected.$Lang)"
                $runtimeColor = "Yellow"
            }

            $results += [PSCustomObject]@{
                Name   = $TxtRuntime
                Text   = $runtimeText
                Color  = $runtimeColor
                Indent = 1
            }

            # App Service Plan
            try {
                $planName = Split-Path $webApp.ServerFarmId -Leaf

                $plan = Get-AzAppServicePlan `
                    -ResourceGroupName $targetRG.ResourceGroupName `
                    -Name $planName `
                    -ErrorAction Stop

                $planOS = if ($plan.Reserved) { "Linux" } else { "Windows" }
                $skuName = $plan.Sku.Name
                $skuTier = $plan.Sku.Tier
                $planDisplay = "$skuTier $skuName / $planOS"

                $planOk =
                    ($skuName -eq $LocCfg.ExpectedWebApp.PlanSku) -and
                    ($skuTier -eq $LocCfg.ExpectedWebApp.PlanTier) -and
                    ($planOS -eq $LocCfg.ExpectedWebApp.OperatingSystem)

                if ($planOk) {
                    $planText = "[$($Msg.Ok)] - $planDisplay"
                    $planColor = "Green"
                }
                else {
                    $planText = "[$($Msg.Warning)] - $planDisplay"
                    $planColor = "Yellow"
                }
            }
            catch {
                $planText = "[$($Msg.Warning)] - $($LabMsg.PlanNotDetected.$Lang)"
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
                Text   = "[$($Msg.Error)] - $($LabMsg.ResourceNotFound.$Lang)"
                Color  = "Red"
                Indent = 0
            }
        }
    }
    catch {
        $results += [PSCustomObject]@{
            Name   = $TxtWebApp
            Text   = "[$($Msg.Warning)] - $($LabMsg.WebAppCheckFailed.$Lang)"
            Color  = "Yellow"
            Indent = 0
        }
    }

    # ========================================================
    # C. STORAGE ACCOUNT
    # ========================================================

    try {
        $storageAccounts = @(
            Get-AzStorageAccount `
                -ResourceGroupName $targetRG.ResourceGroupName `
                -ErrorAction Stop
        )

        $storage = $storageAccounts | Select-Object -First 1

        if ($storage) {
            $storageSku = $storage.Sku.Name

            if ($storageSku -eq $LocCfg.ExpectedStorageSku) {
                $storageStatus = $Msg.Ok
                $storageColor = "Green"
            }
            else {
                $storageStatus = $Msg.Warning
                $storageColor = "Yellow"
            }

            $storageText =
                "[$storageStatus] - " +
                "$($storage.StorageAccountName) " +
                "($($storage.Location)) " +
                "[$storageSku]"

            if ($storageAccounts.Count -gt 1) {
                $storageText += "; $($LabMsg.MultipleResources.$Lang)"
                $storageColor = "Yellow"
            }

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
                Text   = "[$($Msg.Error)] - $($LabMsg.ResourceNotFound.$Lang)"
                Color  = "Red"
                Indent = 0
            }
        }
    }
    catch {
        $results += [PSCustomObject]@{
            Name   = $TxtStorage
            Text   = "[$($Msg.Warning)] - $($LabMsg.StorageCheckFailed.$Lang)"
            Color  = "Yellow"
            Indent = 0
        }
    }
}
else {
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
# D. CLOUD SHELL
# Tikrinama nepriklausomai nuo pagrindinės LAB02 RG
# ============================================================

try {
    $cloudShellRGs = @(
        Get-AzResourceGroup -ErrorAction Stop |
        Where-Object {
            $_.ResourceGroupName -match $LocCfg.CloudShell.ResourceGroupPattern
        }
    )

    $cloudShellRG = $cloudShellRGs | Select-Object -First 1

    if ($cloudShellRG) {
        if ($cloudShellRGs.Count -gt 1) {
            $cloudShellRgText = "[$($Msg.Warning)] - $($cloudShellRG.ResourceGroupName) ($($cloudShellRG.Location)); $($LabMsg.MultipleResourceGroups.$Lang)"
            $cloudShellRgColor = "Yellow"
        }
        else {
            $cloudShellRgText = "[$($Msg.Ok)] - $($cloudShellRG.ResourceGroupName) ($($cloudShellRG.Location))"
            $cloudShellRgColor = "Green"
        }

        $results += [PSCustomObject]@{
            Name   = $TxtCloudShellRG
            Text   = $cloudShellRgText
            Color  = $cloudShellRgColor
            Indent = 0
        }

        try {
            $cloudShellStorageAccounts = @(
                Get-AzStorageAccount `
                    -ResourceGroupName $cloudShellRG.ResourceGroupName `
                    -ErrorAction Stop
            )

            $cloudShellStorage = $cloudShellStorageAccounts | Select-Object -First 1

            if ($cloudShellStorage) {
                $cloudShellStorageText =
                    "[$($Msg.Ok)] - $($cloudShellStorage.StorageAccountName) " +
                    "($($cloudShellStorage.Location)) [$($cloudShellStorage.Sku.Name)]"

                $cloudShellStorageColor = "Green"

                if ($cloudShellStorageAccounts.Count -gt 1) {
                    $cloudShellStorageText =
                        "[$($Msg.Warning)] - $($cloudShellStorage.StorageAccountName) " +
                        "($($cloudShellStorage.Location)) [$($cloudShellStorage.Sku.Name)]; " +
                        "$($LabMsg.MultipleResources.$Lang)"
                    $cloudShellStorageColor = "Yellow"
                }

                $results += [PSCustomObject]@{
                    Name   = $TxtCloudShellSA
                    Text   = $cloudShellStorageText
                    Color  = $cloudShellStorageColor
                    Indent = 0
                }
            }
            else {
                $results += [PSCustomObject]@{
                    Name   = $TxtCloudShellSA
                    Text   = "[$($Msg.Error)] - $($LabMsg.ResourceNotFound.$Lang)"
                    Color  = "Red"
                    Indent = 0
                }
            }
        }
        catch {
            $results += [PSCustomObject]@{
                Name   = $TxtCloudShellSA
                Text   = "[$($Msg.Warning)] - $($LabMsg.CloudShellStorageCheckFailed.$Lang)"
                Color  = "Yellow"
                Indent = 0
            }
        }
    }
    else {
        $results += [PSCustomObject]@{
            Name   = $TxtCloudShellRG
            Text   = "[$($Msg.Error)] - $($LabMsg.ResourceNotFound.$Lang)"
            Color  = "Red"
            Indent = 0
        }
    }
}
catch {
    $results += [PSCustomObject]@{
        Name   = $TxtCloudShellRG
        Text   = "[$($Msg.Warning)] - $($LabMsg.CloudShellCheckFailed.$Lang)"
        Color  = "Yellow"
        Indent = 0
    }
}

# ============================================================
# GALUTINIS REZULTATAS
# ============================================================

Show-LabResults `
    -Setup $Setup `
    -LabName $LabName `
    -Results $results `
    -LabelWidth 39