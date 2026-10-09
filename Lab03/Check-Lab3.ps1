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
$Setup = Initialize-Lab `
    -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab03/Check-Lab3-config.json" `
    -Lang $Lang

$LocCfg  = $Setup.LocalConfig
$Check   = $LocCfg.Checks
$LabMsg  = $LocCfg.Messages
$Msg     = $Setup.Messages
$LabName = $LocCfg.LabName.$Lang

$OkStatus      = $Msg.Ok
$ErrorStatus   = $Msg.Error
$WarningStatus = $Msg.Warning

# ============================================================
# A. RESOURCE GROUP
# ============================================================

$targetRG = $null
$rgText = $null
$rgColor = "Red"

try {
    $matchingRGs = @(
        Get-AzResourceGroup -ErrorAction Stop |
        Where-Object { $_.ResourceGroupName -match $LocCfg.ResourceGroupPattern }
    )

    $targetRG = $matchingRGs | Select-Object -First 1

    if ($targetRG) {
        if ($matchingRGs.Count -gt 1) {
            $rgText  = "[$WarningStatus] - $($targetRG.ResourceGroupName) ($($targetRG.Location)); $($LabMsg.MultipleResourceGroups.$Lang)"
            $rgColor = "Yellow"
        }
        else {
            $rgText  = "[$OkStatus] - $($targetRG.ResourceGroupName) ($($targetRG.Location))"
            $rgColor = "Green"
        }
    }
    else {
        $rgText  = "[$ErrorStatus] - $($LabMsg.ResourceGroupNotFound.$Lang)"
        $rgColor = "Red"
    }
}
catch {
    $rgText  = "[$WarningStatus] - $($LabMsg.ResourceGroupCheckFailed.$Lang)"
    $rgColor = "Yellow"
}

# ============================================================
# B. REZULTATU SARASAS
# ============================================================

$resourceResults = @()

$resourceResults += [PSCustomObject]@{
    Name  = $Check.ResourceGroup.$Lang
    Text  = $rgText
    Color = $rgColor
}

# ============================================================
# C. VM IR DISKAI
# ============================================================

if ($targetRG) {
    $vm = $null

    try {
        $vms = @(
            Get-AzVM -ResourceGroupName $targetRG.ResourceGroupName -ErrorAction Stop
        )

        $vm = $vms | Select-Object -First 1

        if ($vm) {
            $actualSize = $vm.HardwareProfile.VmSize

            try {
                $statusObj = Get-AzVM `
                    -ResourceGroupName $targetRG.ResourceGroupName `
                    -Name $vm.Name `
                    -Status `
                    -ErrorAction Stop

                $displayStatus = (
                    $statusObj.Statuses |
                    Where-Object Code -like "PowerState/*" |
                    Select-Object -First 1
                ).DisplayStatus
            }
            catch {
                $displayStatus = $LabMsg.StatusNotDetected.$Lang
            }

            if ($vms.Count -gt 1) {
                $vmText  = "[$WarningStatus] - $($vm.Name) ($actualSize) [$displayStatus]; $($LabMsg.MultipleVirtualMachines.$Lang)"
                $vmColor = "Yellow"
            }
            else {
                $vmText  = "[$OkStatus] - $($vm.Name) ($actualSize) [$displayStatus]"
                $vmColor = "Green"
            }

            # OS diskas
            $osDiskName = $vm.StorageProfile.OsDisk.Name

            try {
                $osDisk = Get-AzDisk `
                    -ResourceGroupName $targetRG.ResourceGroupName `
                    -DiskName $osDiskName `
                    -ErrorAction Stop

                $osDiskText  = "[$OkStatus] - $($osDisk.Sku.Name)"
                $osDiskColor = "Green"
            }
            catch {
                $osDiskText  = "[$WarningStatus] - $($LabMsg.OsDiskCheckFailed.$Lang)"
                $osDiskColor = "Yellow"
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
                            $disk = Get-AzDisk `
                                -ResourceGroupName $targetRG.ResourceGroupName `
                                -DiskName $dataDisk.Name `
                                -ErrorAction Stop

                            $diskSizes += "$($disk.DiskSizeGB) GiB"
                        }
                        catch {
                            $diskReadFailed = $true
                        }
                    }
                }

                if ($diskReadFailed) {
                    $diskText  = "[$WarningStatus] - $($LabMsg.DataDiskFound.$Lang): $diskCount; $($LabMsg.DataDiskDetailsCheckFailed.$Lang)"
                    $diskColor = "Yellow"
                }
                elseif ($diskSizes.Count -gt 0) {
                    $diskText  = "[$OkStatus] - $($LabMsg.DataDiskFound.$Lang): $diskCount ($($diskSizes -join ', '))"
                    $diskColor = "Green"
                }
                else {
                    $diskText  = "[$OkStatus] - $($LabMsg.DataDiskFound.$Lang): $diskCount"
                    $diskColor = "Green"
                }
            }
            else {
                $diskText  = "[$ErrorStatus] - $($LabMsg.DataDiskNotFound.$Lang)"
                $diskColor = "Red"
            }
        }
        else {
            $vmText      = "[$ErrorStatus] - $($LabMsg.VirtualMachineNotFound.$Lang)"
            $vmColor     = "Red"
            $osDiskText  = "---"
            $osDiskColor = "Gray"
            $diskText    = "---"
            $diskColor   = "Gray"
        }
    }
    catch {
        $vmText      = "[$WarningStatus] - $($LabMsg.VirtualMachineCheckFailed.$Lang)"
        $vmColor     = "Yellow"
        $osDiskText  = "---"
        $osDiskColor = "Gray"
        $diskText    = "---"
        $diskColor   = "Gray"
    }

    $resourceResults += [PSCustomObject]@{
        Name  = $Check.VirtualMachine.$Lang
        Text  = $vmText
        Color = $vmColor
    }

    if ($vm) {
        $resourceResults += [PSCustomObject]@{
            Name  = " - $($Check.OsDisk.$Lang)"
            Text  = $osDiskText
            Color = $osDiskColor
        }

        $resourceResults += [PSCustomObject]@{
            Name  = " - $($Check.DataDisk.$Lang)"
            Text  = $diskText
            Color = $diskColor
        }
    }

    # ========================================================
    # D. FUNCTION APP
    # ========================================================

    $funcApp = $null

    try {
        $funcApps = @(
            Get-AzResource `
                -ResourceGroupName $targetRG.ResourceGroupName `
                -ResourceType "Microsoft.Web/sites" `
                -ErrorAction Stop |
            Where-Object { $_.Kind -like "*functionapp*" }
        )

        $funcApp = $funcApps | Select-Object -First 1

        if ($funcApp) {
            if ($funcApps.Count -gt 1) {
                $funcText  = "[$WarningStatus] - $($funcApp.Name); $($LabMsg.MultipleFunctionApps.$Lang)"
                $funcColor = "Yellow"
            }
            else {
                $funcText  = "[$OkStatus] - $($funcApp.Name)"
                $funcColor = "Green"
            }

            $resourceResults += [PSCustomObject]@{
                Name  = $Check.FunctionApp.$Lang
                Text  = $funcText
                Color = $funcColor
            }

            Write-Host "   ($($LabMsg.CheckingFunctions.$Lang))" -ForegroundColor DarkGray

            $functionListOk = $true
            $cliOutput = @()

            try {
                $jsonText = az functionapp function list `
                    --resource-group $targetRG.ResourceGroupName `
                    --name $funcApp.Name `
                    --output json 2>$null

                if ($LASTEXITCODE -ne 0) {
                    throw "Azure CLI returned exit code $LASTEXITCODE"
                }

                $cliOutput = @($jsonText | ConvertFrom-Json)
            }
            catch {
                $functionListOk = $false
            }

            if ($functionListOk) {
                # HTTP funkcija - mokomojoje aplinkoje pakanka pavadinimo *-fun1
                $fun1 = $cliOutput |
                    Where-Object { $_.name -like "*/*-fun1" } |
                    Select-Object -First 1

                if ($fun1) {
                    $cleanName = $fun1.name.Split('/')[-1]
                    $resourceResults += [PSCustomObject]@{
                        Name  = $Check.HttpFunction.$Lang
                        Text  = "[$OkStatus] - $cleanName"
                        Color = "Green"
                    }
                }
                else {
                    $resourceResults += [PSCustomObject]@{
                        Name  = $Check.HttpFunction.$Lang
                        Text  = "[$ErrorStatus] - $($LabMsg.HttpFunctionNotFound.$Lang)"
                        Color = "Red"
                    }
                }

                # Timer funkcija - mokomojoje aplinkoje pakanka pavadinimo *-fun2
                $fun2 = $cliOutput |
                    Where-Object { $_.name -like "*/*-fun2" } |
                    Select-Object -First 1

                if ($fun2) {
                    $cleanName = $fun2.name.Split('/')[-1]
                    $resourceResults += [PSCustomObject]@{
                        Name  = $Check.TimerFunction.$Lang
                        Text  = "[$OkStatus] - $cleanName"
                        Color = "Green"
                    }
                }
                else {
                    $resourceResults += [PSCustomObject]@{
                        Name  = $Check.TimerFunction.$Lang
                        Text  = "[$ErrorStatus] - $($LabMsg.TimerFunctionNotFound.$Lang)"
                        Color = "Red"
                    }
                }
            }
            else {
                $resourceResults += [PSCustomObject]@{
                    Name  = $Check.HttpFunction.$Lang
                    Text  = "[$WarningStatus] - $($LabMsg.FunctionListCheckFailed.$Lang)"
                    Color = "Yellow"
                }

                $resourceResults += [PSCustomObject]@{
                    Name  = $Check.TimerFunction.$Lang
                    Text  = "[$WarningStatus] - $($LabMsg.FunctionListCheckFailed.$Lang)"
                    Color = "Yellow"
                }
            }
        }
        else {
            $resourceResults += [PSCustomObject]@{
                Name  = $Check.FunctionApp.$Lang
                Text  = "[$ErrorStatus] - $($LabMsg.FunctionAppNotFound.$Lang)"
                Color = "Red"
            }
        }
    }
    catch {
        $resourceResults += [PSCustomObject]@{
            Name  = $Check.FunctionApp.$Lang
            Text  = "[$WarningStatus] - $($LabMsg.FunctionAppCheckFailed.$Lang)"
            Color = "Yellow"
        }
    }
}
else {
    $resourceResults += [PSCustomObject]@{
        Name  = $Check.VirtualMachine.$Lang
        Text  = "[$ErrorStatus] - $($LabMsg.NoResourceGroup.$Lang)"
        Color = "Gray"
    }

    $resourceResults += [PSCustomObject]@{
        Name  = $Check.FunctionApp.$Lang
        Text  = "[$ErrorStatus] - $($LabMsg.NoResourceGroup.$Lang)"
        Color = "Gray"
    }
}

# ============================================================
# GALUTINIS REZULTATAS
# ============================================================

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

# ============================================================
# GALUTINIS REZULTATAS
# ============================================================

Show-LabResults `
    -Setup $Setup `
    -LabName $LabName `
    -Results $results `
    -LabelWidth 30