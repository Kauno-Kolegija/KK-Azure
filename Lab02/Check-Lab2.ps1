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
        Invoke-RestMethod 'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1' -ErrorAction Stop | Invoke-Expression
    }
}
catch {
    Write-Error "Failed to load common functions."
    throw
}

# --- 2. KALBA ---
if ($Lang -notin @("LT", "EN")) { $Lang = "LT" }

# --- 3. INICIJUOJAME DARBĄ ---
$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab02/Check-Lab2-config.json" -Lang $Lang

$LocCfg = $Setup.LocalConfig
$Msg = $Setup.Messages
$LabMsg = $LocCfg.Messages
$LabName = $LocCfg.LabName.$Lang

$TxtResourceGroup = $LocCfg.Checks.ResourceGroup.$Lang
$TxtWebApp = $LocCfg.Checks.WebApp.$Lang
$TxtRuntime = $LocCfg.Checks.Runtime.$Lang
$TxtAppService = $LocCfg.Checks.AppServicePlan.$Lang
$TxtStorage = $LocCfg.Checks.StorageAccount.$Lang
$TxtCloudShellRG = $LocCfg.Checks.CloudShellResourceGroup.$Lang
$TxtCloudShellSA = $LocCfg.Checks.CloudShellStorage.$Lang

$results = @()

# ============================================================
# A. RESOURCE GROUP
# ============================================================

try {
    $allRGs = @(Get-AzResourceGroup -ErrorAction Stop)
    $rgMatch = Find-PatternMatch -Items $allRGs -Property "ResourceGroupName" -Pattern $LocCfg.ResourceGroupPattern
    $targetRG = $rgMatch.First

    if ($targetRG) {
        $status = if ($rgMatch.Count -gt 1) { "WARNING" } else { "OK" }
        $message = "$($targetRG.ResourceGroupName) ($($targetRG.Location))"
        if ($rgMatch.Count -gt 1) { $message += "; $($LabMsg.MultipleResourceGroups.$Lang)" }
        Add-LabResult -Results ([ref]$results) -Name $TxtResourceGroup -Status $status -Message $message -Messages $Msg
    }
    else {
        Add-LabResult -Results ([ref]$results) -Name $TxtResourceGroup -Status "ERROR" -Message $LabMsg.ResourceGroupNotFound.$Lang -Messages $Msg
    }
}
catch {
    $targetRG = $null
    Add-LabResult -Results ([ref]$results) -Name $TxtResourceGroup -Status "WARNING" -Message $LabMsg.ResourceGroupCheckFailed.$Lang -Messages $Msg
}

# ============================================================
# B. WEB APP + RUNTIME + APP SERVICE PLAN
# ============================================================

if ($targetRG) {
    try {
        $webApps = @(Get-AzWebApp -ResourceGroupName $targetRG.ResourceGroupName -ErrorAction Stop)
        $webApp = $webApps | Select-Object -First 1

        if ($webApp) {
            $status = if ($webApps.Count -gt 1) { "WARNING" } else { "OK" }
            $message = "$($webApp.Name) ($($webApp.Location))"
            if ($webApps.Count -gt 1) { $message += "; $($LabMsg.MultipleResources.$Lang)" }
            Add-LabResult -Results ([ref]$results) -Name $TxtWebApp -Status $status -Message $message -Messages $Msg

            $runtime = $webApp.SiteConfig.NetFrameworkVersion
            if ($runtime) {
                $runtimeVersion = $runtime -replace '^v', ''
                if ($runtimeVersion -match "^$($LocCfg.ExpectedWebApp.Runtime)(\.|$)") {
                    Add-LabResult -Results ([ref]$results) -Name $TxtRuntime -Status "OK" -Message ".NET $($LocCfg.ExpectedWebApp.Runtime)" -Messages $Msg -Indent 1
                }
                else {
                    Add-LabResult -Results ([ref]$results) -Name $TxtRuntime -Status "WARNING" -Message $runtime -Messages $Msg -Indent 1
                }
            }
            else {
                Add-LabResult -Results ([ref]$results) -Name $TxtRuntime -Status "WARNING" -Message $LabMsg.RuntimeNotDetected.$Lang -Messages $Msg -Indent 1
            }

            try {
                $planName = Split-Path $webApp.ServerFarmId -Leaf
                $plan = Get-AzAppServicePlan -ResourceGroupName $targetRG.ResourceGroupName -Name $planName -ErrorAction Stop
                $planOS = if ($plan.Reserved) { "Linux" } else { "Windows" }
                $planDisplay = "$($plan.Sku.Tier) $($plan.Sku.Name) / $planOS"

                $planOk =
                    ($plan.Sku.Name -eq $LocCfg.ExpectedWebApp.PlanSku) -and
                    ($plan.Sku.Tier -eq $LocCfg.ExpectedWebApp.PlanTier) -and
                    ($planOS -eq $LocCfg.ExpectedWebApp.OperatingSystem)

                Add-LabResult -Results ([ref]$results) -Name $TxtAppService -Status $(if ($planOk) { "OK" } else { "WARNING" }) -Message $planDisplay -Messages $Msg -Indent 1
            }
            catch {
                Add-LabResult -Results ([ref]$results) -Name $TxtAppService -Status "WARNING" -Message $LabMsg.PlanNotDetected.$Lang -Messages $Msg -Indent 1
            }
        }
        else {
            Add-LabResult -Results ([ref]$results) -Name $TxtWebApp -Status "ERROR" -Message $LabMsg.ResourceNotFound.$Lang -Messages $Msg
        }
    }
    catch {
        Add-LabResult -Results ([ref]$results) -Name $TxtWebApp -Status "WARNING" -Message $LabMsg.WebAppCheckFailed.$Lang -Messages $Msg
    }

    # ========================================================
    # C. STORAGE ACCOUNT
    # ========================================================

    try {
        $storageAccounts = @(Get-AzStorageAccount -ResourceGroupName $targetRG.ResourceGroupName -ErrorAction Stop)
        $storage = $storageAccounts | Select-Object -First 1

        if ($storage) {
            $storageSku = $storage.Sku.Name
            $status = if ($storageSku -eq $LocCfg.ExpectedStorageSku) { "OK" } else { "WARNING" }
            $message = "$($storage.StorageAccountName) ($($storage.Location)) [$storageSku]"

            if ($storageAccounts.Count -gt 1) {
                $status = "WARNING"
                $message += "; $($LabMsg.MultipleResources.$Lang)"
            }

            Add-LabResult -Results ([ref]$results) -Name $TxtStorage -Status $status -Message $message -Messages $Msg
        }
        else {
            Add-LabResult -Results ([ref]$results) -Name $TxtStorage -Status "ERROR" -Message $LabMsg.ResourceNotFound.$Lang -Messages $Msg
        }
    }
    catch {
        Add-LabResult -Results ([ref]$results) -Name $TxtStorage -Status "WARNING" -Message $LabMsg.StorageCheckFailed.$Lang -Messages $Msg
    }
}
else {
    Add-LabResult -Results ([ref]$results) -Name $TxtWebApp -Status "ERROR" -Message $LabMsg.NoResourceGroup.$Lang -Messages $Msg
    Add-LabResult -Results ([ref]$results) -Name $TxtStorage -Status "ERROR" -Message $LabMsg.NoResourceGroup.$Lang -Messages $Msg
}

# ============================================================
# D. CLOUD SHELL
# Tikrinama nepriklausomai nuo pagrindinės LAB02 RG
# ============================================================

try {
    $allRGs = @(Get-AzResourceGroup -ErrorAction Stop)
    $cloudShellMatch = Find-PatternMatch -Items $allRGs -Property "ResourceGroupName" -Pattern $LocCfg.CloudShell.ResourceGroupPattern
    $cloudShellRG = $cloudShellMatch.First

    if ($cloudShellRG) {
        $status = if ($cloudShellMatch.Count -gt 1) { "WARNING" } else { "OK" }
        $message = "$($cloudShellRG.ResourceGroupName) ($($cloudShellRG.Location))"
        if ($cloudShellMatch.Count -gt 1) { $message += "; $($LabMsg.MultipleResourceGroups.$Lang)" }
        Add-LabResult -Results ([ref]$results) -Name $TxtCloudShellRG -Status $status -Message $message -Messages $Msg

        try {
            $cloudShellStorageAccounts = @(Get-AzStorageAccount -ResourceGroupName $cloudShellRG.ResourceGroupName -ErrorAction Stop)
            $cloudShellStorage = $cloudShellStorageAccounts | Select-Object -First 1

            if ($cloudShellStorage) {
                $status = if ($cloudShellStorageAccounts.Count -gt 1) { "WARNING" } else { "OK" }
                $message = "$($cloudShellStorage.StorageAccountName) ($($cloudShellStorage.Location)) [$($cloudShellStorage.Sku.Name)]"
                if ($cloudShellStorageAccounts.Count -gt 1) { $message += "; $($LabMsg.MultipleResources.$Lang)" }
                Add-LabResult -Results ([ref]$results) -Name $TxtCloudShellSA -Status $status -Message $message -Messages $Msg
            }
            else {
                Add-LabResult -Results ([ref]$results) -Name $TxtCloudShellSA -Status "ERROR" -Message $LabMsg.ResourceNotFound.$Lang -Messages $Msg
            }
        }
        catch {
            Add-LabResult -Results ([ref]$results) -Name $TxtCloudShellSA -Status "WARNING" -Message $LabMsg.CloudShellStorageCheckFailed.$Lang -Messages $Msg
        }
    }
    else {
        Add-LabResult -Results ([ref]$results) -Name $TxtCloudShellRG -Status "ERROR" -Message $LabMsg.ResourceNotFound.$Lang -Messages $Msg
    }
}
catch {
    Add-LabResult -Results ([ref]$results) -Name $TxtCloudShellRG -Status "WARNING" -Message $LabMsg.CloudShellCheckFailed.$Lang -Messages $Msg
}

# ============================================================
# GALUTINIS REZULTATAS
# ============================================================

Show-LabResults -Setup $Setup -LabName $LabName -Results $results -LabelWidth 39
