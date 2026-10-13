# ============================================================
# LAB 8 CHECKER - AZURE WEB APPS
# ============================================================

# --- Load common functions ---
try {
    if ($PSScriptRoot) {
        . (Join-Path $PSScriptRoot '../configs/common.ps1')
    } else {
        Invoke-RestMethod 'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1' -ErrorAction Stop | Invoke-Expression
    }
} catch {
    Write-Error "Failed to load common functions."
    throw
}

if ($Lang -notin @('LT', 'EN')) { $Lang = 'LT' }

$Setup = Initialize-Lab -LocalConfigUrl 'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab08/Check-Lab8-config.json' -Lang $Lang
$LocCfg = $Setup.LocalConfig
$Check = $LocCfg.Checks
$LabMsg = $LocCfg.Messages
$Msg = $Setup.Messages
$LabName = $LocCfg.LabName.$Lang
$results = @()

# ============================================================
# 1. RESOURCE GROUP
# ============================================================

try {
    $allRGs = @(Get-AzResourceGroup -ErrorAction Stop)
    $rgMatch = Find-PatternMatch -Items $allRGs -Property 'ResourceGroupName' -Pattern $LocCfg.ResourceGroup.Pattern
    $targetRG = $rgMatch.First

    if ($targetRG) {
        $status = if ($rgMatch.Count -gt 1) { 'WARNING' } else { 'OK' }
        $message = "$($LabMsg.Found.$Lang) $($targetRG.ResourceGroupName)"
        if ($rgMatch.Count -gt 1) { $message += "; $($LabMsg.MultipleResourceGroups.$Lang)" }
        Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroup.$Lang -Status $status -Message $message -Messages $Msg
    } else {
        Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroup.$Lang -Status 'ERROR' -Message $LabMsg.ResourceGroupMissing.$Lang -Messages $Msg
    }
} catch {
    $targetRG = $null
    Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroup.$Lang -Status 'WARNING' -Message $LabMsg.ResourceGroupCheckFailed.$Lang -Messages $Msg
}

# ============================================================
# 2. APP SERVICE PLAN
# ============================================================

$appPlan = $null

if ($targetRG) {
    try {
        $plans = @(Get-AzAppServicePlan -ResourceGroupName $targetRG.ResourceGroupName -ErrorAction Stop)
        $planMatch = Find-PatternMatch -Items $plans -Property 'Name' -Pattern $LocCfg.AppServicePlan.NamePattern
        $appPlan = if ($planMatch.First) { $planMatch.First } else { $plans | Select-Object -First 1 }

        if ($appPlan) {
            $tier = [string]$appPlan.Sku.Tier
            $sku = [string]$appPlan.Sku.Name
            $isExactSku = $sku -ieq $LocCfg.AppServicePlan.ExpectedSku
            $isUnsupported = $tier -in @('Free', 'Shared')

            if ($isExactSku) {
                Add-LabResult -Results ([ref]$results) -Name $Check.AppServicePlan.$Lang -Status 'OK' -Message "$($appPlan.Name) - $tier / $sku" -Messages $Msg
            } elseif ($isUnsupported) {
                Add-LabResult -Results ([ref]$results) -Name $Check.AppServicePlan.$Lang -Status 'ERROR' -Message "$($appPlan.Name) - $tier / $sku; $($LabMsg.PlanUnsupported.$Lang)" -Messages $Msg
            } else {
                Add-LabResult -Results ([ref]$results) -Name $Check.AppServicePlan.$Lang -Status 'WARNING' -Message "$($appPlan.Name) - $tier / $sku; $($LabMsg.PlanDifferent.$Lang)" -Messages $Msg
            }
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.AppServicePlan.$Lang -Status 'ERROR' -Message $LabMsg.PlanMissing.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.AppServicePlan.$Lang -Status 'WARNING' -Message $LabMsg.PlanCheckFailed.$Lang -Messages $Msg
    }
} else {
    Add-LabResult -Results ([ref]$results) -Name $Check.AppServicePlan.$Lang -Status 'ERROR' -Message $LabMsg.NoResourceGroup.$Lang -Messages $Msg
}

# ============================================================
# 3. SCALE OUT
# Expected count is in config so it can be changed later without
# changing the checker code.
# ============================================================

if ($appPlan) {
    try {
        $instanceCount = [int]$appPlan.Sku.Capacity
        $expectedCount = [int]$LocCfg.AppServicePlan.ExpectedInstanceCount

        if ($instanceCount -eq $expectedCount) {
            Add-LabResult -Results ([ref]$results) -Name $Check.ScaleOut.$Lang -Status 'OK' -Message "$instanceCount $($LabMsg.Instances.$Lang)" -Messages $Msg
        } elseif ($instanceCount -gt $expectedCount) {
            Add-LabResult -Results ([ref]$results) -Name $Check.ScaleOut.$Lang -Status 'WARNING' -Message "$instanceCount $($LabMsg.Instances.$Lang); $($LabMsg.TooManyInstances.$Lang)" -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.ScaleOut.$Lang -Status 'ERROR' -Message "$instanceCount $($LabMsg.Instances.$Lang); $($LabMsg.ExpectedInstances.$Lang) $expectedCount" -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.ScaleOut.$Lang -Status 'WARNING' -Message $LabMsg.ScaleCheckFailed.$Lang -Messages $Msg
    }
} else {
    Add-LabResult -Results ([ref]$results) -Name $Check.ScaleOut.$Lang -Status 'ERROR' -Message $LabMsg.PlanMissing.$Lang -Messages $Msg
}

# ============================================================
# 4. WEB APP
# ============================================================

$webApp = $null

if ($targetRG) {
    try {
        $webApps = @(Get-AzWebApp -ResourceGroupName $targetRG.ResourceGroupName -ErrorAction Stop)
        $webMatch = Find-PatternMatch -Items $webApps -Property 'Name' -Pattern $LocCfg.WebApp.NamePattern
        $webApp = $webMatch.First

        if ($webApp) {
            $status = if ($webMatch.Count -gt 1) { 'WARNING' } else { 'OK' }
            $message = "$($LabMsg.Found.$Lang) $($webApp.Name)"
            if ($webMatch.Count -gt 1) { $message += "; $($LabMsg.MultipleWebApps.$Lang)" }
            Add-LabResult -Results ([ref]$results) -Name $Check.WebApp.$Lang -Status $status -Message $message -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.WebApp.$Lang -Status 'ERROR' -Message $LabMsg.WebAppMissing.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.WebApp.$Lang -Status 'WARNING' -Message $LabMsg.WebAppCheckFailed.$Lang -Messages $Msg
    }
} else {
    Add-LabResult -Results ([ref]$results) -Name $Check.WebApp.$Lang -Status 'ERROR' -Message $LabMsg.NoResourceGroup.$Lang -Messages $Msg
}

# ============================================================
# 5. DEPLOYMENT SLOT
# We verify final state (slot exists), not the historical Swap action.
# ============================================================

$targetSlot = $null

if ($webApp) {
    try {
        $slots = @(Get-AzWebAppSlot -ResourceGroupName $targetRG.ResourceGroupName -Name $webApp.Name -ErrorAction Stop)
        $targetSlot = $slots | Where-Object {
            ([string]$_.Name -match $LocCfg.DeploymentSlot.NamePattern) -or
            ($_.PSObject.Properties['Slot'] -and [string]$_.Slot -match $LocCfg.DeploymentSlot.NamePattern)
        } | Select-Object -First 1

        if ($targetSlot) {
            $slotName = if ($targetSlot.PSObject.Properties['Slot'] -and $targetSlot.Slot) { $targetSlot.Slot } else { ([string]$targetSlot.Name -split '/')[-1] }
            Add-LabResult -Results ([ref]$results) -Name $Check.DeploymentSlot.$Lang -Status 'OK' -Message $slotName -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.DeploymentSlot.$Lang -Status 'ERROR' -Message $LabMsg.SlotMissing.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.DeploymentSlot.$Lang -Status 'WARNING' -Message $LabMsg.SlotCheckFailed.$Lang -Messages $Msg
    }
} else {
    Add-LabResult -Results ([ref]$results) -Name $Check.DeploymentSlot.$Lang -Status 'ERROR' -Message $LabMsg.WebAppMissing.$Lang -Messages $Msg
}

# ============================================================
# 6. APPLICATION INSIGHTS
# Check the Application Insights component created for LAB08.
# ============================================================

if ($targetRG) {
    try {
        $insights = @(Get-AzResource -ResourceGroupName $targetRG.ResourceGroupName -ResourceType 'Microsoft.Insights/components' -ErrorAction Stop)

        if ($insights.Count -gt 0) {
            $names = @($insights | ForEach-Object { $_.Name }) -join ', '
            Add-LabResult -Results ([ref]$results) -Name $Check.ApplicationInsights.$Lang -Status 'OK' -Message $names -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.ApplicationInsights.$Lang -Status 'ERROR' -Message $LabMsg.ApplicationInsightsMissing.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.ApplicationInsights.$Lang -Status 'WARNING' -Message $LabMsg.ApplicationInsightsCheckFailed.$Lang -Messages $Msg
    }
} else {
    Add-LabResult -Results ([ref]$results) -Name $Check.ApplicationInsights.$Lang -Status 'ERROR' -Message $LabMsg.NoResourceGroup.$Lang -Messages $Msg
}

# ============================================================
# 7. METRIC ALERT
# Prefer an alert scoped to the LAB08 Web App. If a metric alert exists
# in the RG but scope cannot be confirmed, return WARNING instead of ERROR.
# ============================================================

if ($targetRG) {
    try {
        $alerts = @(Get-AzMetricAlertRuleV2 -ResourceGroupName $targetRG.ResourceGroupName -ErrorAction Stop)

        if ($alerts.Count -gt 0) {
            $scopedAlert = $null

            if ($webApp) {
                $scopedAlert = $alerts | Where-Object {
                    @($_.Scopes) -contains $webApp.Id
                } | Select-Object -First 1
            }

            if ($scopedAlert) {
                Add-LabResult -Results ([ref]$results) -Name $Check.MetricAlert.$Lang -Status 'OK' -Message $scopedAlert.Name -Messages $Msg
            } else {
                Add-LabResult -Results ([ref]$results) -Name $Check.MetricAlert.$Lang -Status 'WARNING' -Message "$($alerts[0].Name); $($LabMsg.AlertScopeNotConfirmed.$Lang)" -Messages $Msg
            }
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.MetricAlert.$Lang -Status 'ERROR' -Message $LabMsg.AlertMissing.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.MetricAlert.$Lang -Status 'WARNING' -Message $LabMsg.AlertCheckFailed.$Lang -Messages $Msg
    }
} else {
    Add-LabResult -Results ([ref]$results) -Name $Check.MetricAlert.$Lang -Status 'ERROR' -Message $LabMsg.NoResourceGroup.$Lang -Messages $Msg
}

# ============================================================
# RESULTS
# ============================================================

Show-LabResults -Setup $Setup -LabName $LabName -Results $results
