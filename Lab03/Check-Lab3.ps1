# ============================================================
# LAB 3 - Azure Virtual Resources validation
# ============================================================

# --- 1. KALBA ---
if ($Lang -notin @("LT", "EN")) { $Lang = "LT" }

# --- 2. UZKRAUNAME BENDRAS FUNKCIJAS ---
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

# --- 3. INICIJUOJAME DARBA ---
$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab03/Check-Lab3-config.json" -Lang $Lang

$LocCfg = $Setup.LocalConfig
$Check = $LocCfg.Checks
$LabMsg = $LocCfg.Messages
$Msg = $Setup.Messages
$LabName = $LocCfg.LabName.$Lang
$results = @()

# ============================================================
# A. RESOURCE GROUP
# ============================================================

$targetRG = $null

try {
    $allRGs = @(Get-AzResourceGroup -ErrorAction Stop)
    $rgMatch = Find-PatternMatch -Items $allRGs -Property "ResourceGroupName" -Pattern $LocCfg.ResourceGroupPattern
    $targetRG = $rgMatch.First

    if ($targetRG) {
        $status = if ($rgMatch.Count -gt 1) { "WARNING" } else { "OK" }
        $message = "$($targetRG.ResourceGroupName) ($($targetRG.Location))"
        if ($rgMatch.Count -gt 1) { $message += "; $($LabMsg.MultipleResourceGroups.$Lang)" }
        Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroup.$Lang -Status $status -Message $message -Messages $Msg
    }
    else {
        Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroup.$Lang -Status "ERROR" -Message $LabMsg.ResourceGroupNotFound.$Lang -Messages $Msg
    }
}
catch {
    Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroup.$Lang -Status "WARNING" -Message $LabMsg.ResourceGroupCheckFailed.$Lang -Messages $Msg
}

# ============================================================
# B. VM IR DISKAI
# ============================================================

if ($targetRG) {
    $vm = $null

    try {
        $vms = @(Get-AzVM -ResourceGroupName $targetRG.ResourceGroupName -ErrorAction Stop)
        $vm = $vms | Select-Object -First 1

        if ($vm) {
            $actualSize = $vm.HardwareProfile.VmSize

            try {
                $statusObj = Get-AzVM -ResourceGroupName $targetRG.ResourceGroupName -Name $vm.Name -Status -ErrorAction Stop
                $displayStatus = ($statusObj.Statuses | Where-Object Code -like "PowerState/*" | Select-Object -First 1).DisplayStatus
            }
            catch {
                $displayStatus = $LabMsg.StatusNotDetected.$Lang
            }

            $status = if ($vms.Count -gt 1) { "WARNING" } else { "OK" }
            $message = "$($vm.Name) ($actualSize) [$displayStatus]"
            if ($vms.Count -gt 1) { $message += "; $($LabMsg.MultipleVirtualMachines.$Lang)" }
            Add-LabResult -Results ([ref]$results) -Name $Check.VirtualMachine.$Lang -Status $status -Message $message -Messages $Msg

            # OS diskas
            $osDiskName = $vm.StorageProfile.OsDisk.Name
            try {
                $osDisk = Get-AzDisk -ResourceGroupName $targetRG.ResourceGroupName -DiskName $osDiskName -ErrorAction Stop
                Add-LabResult -Results ([ref]$results) -Name $Check.OsDisk.$Lang -Status "OK" -Message $osDisk.Sku.Name -Messages $Msg -Indent 1
            }
            catch {
                Add-LabResult -Results ([ref]$results) -Name $Check.OsDisk.$Lang -Status "WARNING" -Message $LabMsg.OsDiskCheckFailed.$Lang -Messages $Msg -Indent 1
            }

            # Duomenu diskai
            $dataDisks = @($vm.StorageProfile.DataDisks)
            $diskCount = $dataDisks.Count

            if ($diskCount -ge 1) {
                $diskSizes = @()
                $diskReadFailed = $false

                foreach ($dataDisk in $dataDisks) {
                    if ($dataDisk.ManagedDisk.Id) {
                        try {
                            $disk = Get-AzDisk -ResourceGroupName $targetRG.ResourceGroupName -DiskName $dataDisk.Name -ErrorAction Stop
                            $diskSizes += "$($disk.DiskSizeGB) GiB"
                        }
                        catch {
                            $diskReadFailed = $true
                        }
                    }
                }

                if ($diskReadFailed) {
                    $message = "$($LabMsg.DataDiskFound.$Lang): $diskCount; $($LabMsg.DataDiskDetailsCheckFailed.$Lang)"
                    Add-LabResult -Results ([ref]$results) -Name $Check.DataDisk.$Lang -Status "WARNING" -Message $message -Messages $Msg -Indent 1
                }
                elseif ($diskSizes.Count -gt 0) {
                    $message = "$($LabMsg.DataDiskFound.$Lang): $diskCount ($($diskSizes -join ', '))"
                    Add-LabResult -Results ([ref]$results) -Name $Check.DataDisk.$Lang -Status "OK" -Message $message -Messages $Msg -Indent 1
                }
                else {
                    Add-LabResult -Results ([ref]$results) -Name $Check.DataDisk.$Lang -Status "OK" -Message "$($LabMsg.DataDiskFound.$Lang): $diskCount" -Messages $Msg -Indent 1
                }
            }
            else {
                Add-LabResult -Results ([ref]$results) -Name $Check.DataDisk.$Lang -Status "ERROR" -Message $LabMsg.DataDiskNotFound.$Lang -Messages $Msg -Indent 1
            }
        }
        else {
            Add-LabResult -Results ([ref]$results) -Name $Check.VirtualMachine.$Lang -Status "ERROR" -Message $LabMsg.VirtualMachineNotFound.$Lang -Messages $Msg
        }
    }
    catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.VirtualMachine.$Lang -Status "WARNING" -Message $LabMsg.VirtualMachineCheckFailed.$Lang -Messages $Msg
    }

    # ========================================================
    # C. FUNCTION APP
    # ========================================================

    try {
        $funcApps = @(
            Get-AzResource -ResourceGroupName $targetRG.ResourceGroupName -ResourceType "Microsoft.Web/sites" -ErrorAction Stop |
            Where-Object { $_.Kind -like "*functionapp*" }
        )

        $funcApp = $funcApps | Select-Object -First 1

        if ($funcApp) {
            $status = if ($funcApps.Count -gt 1) { "WARNING" } else { "OK" }
            $message = $funcApp.Name
            if ($funcApps.Count -gt 1) { $message += "; $($LabMsg.MultipleFunctionApps.$Lang)" }
            Add-LabResult -Results ([ref]$results) -Name $Check.FunctionApp.$Lang -Status $status -Message $message -Messages $Msg

            Write-Host "   ($($LabMsg.CheckingFunctions.$Lang))" -ForegroundColor DarkGray

            $functionListOk = $true
            $cliOutput = @()

            try {
                $jsonText = az functionapp function list --resource-group $targetRG.ResourceGroupName --name $funcApp.Name --output json 2>$null
                if ($LASTEXITCODE -ne 0) { throw "Azure CLI returned exit code $LASTEXITCODE" }
                $cliOutput = @($jsonText | ConvertFrom-Json)
            }
            catch {
                $functionListOk = $false
            }

            if ($functionListOk) {
                # Mokomojoje aplinkoje pakanka funkciju pavadinimu *-fun1 ir *-fun2.
                $fun1 = $cliOutput | Where-Object { $_.name -like "*/*-fun1" } | Select-Object -First 1
                if ($fun1) {
                    Add-LabResult -Results ([ref]$results) -Name $Check.HttpFunction.$Lang -Status "OK" -Message $fun1.name.Split('/')[-1] -Messages $Msg -Indent 1
                }
                else {
                    Add-LabResult -Results ([ref]$results) -Name $Check.HttpFunction.$Lang -Status "ERROR" -Message $LabMsg.HttpFunctionNotFound.$Lang -Messages $Msg -Indent 1
                }

                $fun2 = $cliOutput | Where-Object { $_.name -like "*/*-fun2" } | Select-Object -First 1
                if ($fun2) {
                    Add-LabResult -Results ([ref]$results) -Name $Check.TimerFunction.$Lang -Status "OK" -Message $fun2.name.Split('/')[-1] -Messages $Msg -Indent 1
                }
                else {
                    Add-LabResult -Results ([ref]$results) -Name $Check.TimerFunction.$Lang -Status "ERROR" -Message $LabMsg.TimerFunctionNotFound.$Lang -Messages $Msg -Indent 1
                }
            }
            else {
                Add-LabResult -Results ([ref]$results) -Name $Check.HttpFunction.$Lang -Status "WARNING" -Message $LabMsg.FunctionListCheckFailed.$Lang -Messages $Msg -Indent 1
                Add-LabResult -Results ([ref]$results) -Name $Check.TimerFunction.$Lang -Status "WARNING" -Message $LabMsg.FunctionListCheckFailed.$Lang -Messages $Msg -Indent 1
            }
        }
        else {
            Add-LabResult -Results ([ref]$results) -Name $Check.FunctionApp.$Lang -Status "ERROR" -Message $LabMsg.FunctionAppNotFound.$Lang -Messages $Msg
        }
    }
    catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.FunctionApp.$Lang -Status "WARNING" -Message $LabMsg.FunctionAppCheckFailed.$Lang -Messages $Msg
    }
}
else {
    Add-LabResult -Results ([ref]$results) -Name $Check.VirtualMachine.$Lang -Status "ERROR" -Message $LabMsg.NoResourceGroup.$Lang -Messages $Msg
    Add-LabResult -Results ([ref]$results) -Name $Check.FunctionApp.$Lang -Status "ERROR" -Message $LabMsg.NoResourceGroup.$Lang -Messages $Msg
}

# ============================================================
# GALUTINIS REZULTATAS
# ============================================================

Show-LabResults -Setup $Setup -LabName $LabName -Results $results -LabelWidth 30
