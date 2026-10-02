# ============================================================
# LAB 3 - Azure Virtual Resources validation
# ============================================================

# --- 1. KALBA ---
if ($Lang -notin @("LT", "EN")) { $Lang = "LT" }

# --- 2. UŽKRAUNAME BENDRAS FUNKCIJAS ---
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

# --- 3. INICIJUOJAME DARBĄ ---
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
$MissingStatus = if ($Lang -eq "EN") { "MISSING" } else { "TRŪKSTA" }

# ============================================================
# A. RESOURCE GROUP
# ============================================================

$targetRG = Get-AzResourceGroup |
    Where-Object { $_.ResourceGroupName -match $LocCfg.ResourceGroupPattern } |
    Select-Object -First 1

if ($targetRG) {
    $rgText  = "[$OkStatus] - $($targetRG.ResourceGroupName) ($($targetRG.Location))"
    $rgColor = "Green"
}
else {
    $rgText  = "[$ErrorStatus] - $($LabMsg.ResourceGroupNotFound.$Lang)"
    $rgColor = "Red"
}

# ============================================================
# B. REZULTATŲ SĄRAŠAS
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
    $vm = Get-AzVM -ResourceGroupName $targetRG.ResourceGroupName | Select-Object -First 1

    if ($vm) {
        $actualSize = $vm.HardwareProfile.VmSize

        $statusObj = Get-AzVM `
            -ResourceGroupName $targetRG.ResourceGroupName `
            -Name $vm.Name `
            -Status

        $displayStatus = (
            $statusObj.Statuses |
            Where-Object Code -like "PowerState/*" |
            Select-Object -First 1
        ).DisplayStatus

        $vmText  = "[$OkStatus] - $($vm.Name) ($actualSize) [$displayStatus]"
        $vmColor = "Green"

        # OS diskas
        $osDiskName = $vm.StorageProfile.OsDisk.Name

        $osDisk = Get-AzDisk `
            -ResourceGroupName $targetRG.ResourceGroupName `
            -DiskName $osDiskName `
            -ErrorAction SilentlyContinue

        if ($osDisk) {
            $osDiskText  = "[$OkStatus] - $($osDisk.Sku.Name)"
            $osDiskColor = "Green"
        }
        else {
            $osDiskText  = "[$MissingStatus] - $($LabMsg.OsDiskNotFound.$Lang)"
            $osDiskColor = "Red"
        }

        # Duomenų diskai
        $dataDisks = $vm.StorageProfile.DataDisks
        $diskCount = @($dataDisks).Count

        if ($diskCount -ge 1) {
            $diskSizes = @()

            foreach ($dataDisk in $dataDisks) {
                if ($dataDisk.ManagedDisk.Id) {
                    $disk = Get-AzDisk `
                        -ResourceGroupName $targetRG.ResourceGroupName `
                        -DiskName $dataDisk.Name `
                        -ErrorAction SilentlyContinue

                    if ($disk) {
                        $diskSizes += "$($disk.DiskSizeGB) GiB"
                    }
                }
            }

            if ($diskSizes.Count -gt 0) {
                $diskText = "[$OkStatus] - $($LabMsg.DataDiskFound.$Lang): $diskCount ($($diskSizes -join ', '))"
            }
            else {
                $diskText = "[$OkStatus] - $($LabMsg.DataDiskFound.$Lang): $diskCount"
            }

            $diskColor = "Green"
        }
        else {
            $diskText  = "[$MissingStatus] - $($LabMsg.DataDiskNotFound.$Lang)"
            $diskColor = "Red"
        }
    }
    else {
        $vmText      = "[$MissingStatus] - $($LabMsg.VirtualMachineNotFound.$Lang)"
        $vmColor     = "Red"
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

    $funcApp = Get-AzResource `
        -ResourceGroupName $targetRG.ResourceGroupName `
        -ResourceType "Microsoft.Web/sites" |
        Where-Object { $_.Kind -like "*functionapp*" } |
        Select-Object -First 1

    if ($funcApp) {
        $resourceResults += [PSCustomObject]@{
            Name  = $Check.FunctionApp.$Lang
            Text  = "[$OkStatus] - $($funcApp.Name)"
            Color = "Green"
        }

        Write-Host "   ($($LabMsg.CheckingFunctions.$Lang))" -ForegroundColor DarkGray

        try {
            $cliOutput = az functionapp function list `
                --resource-group $targetRG.ResourceGroupName `
                --name $funcApp.Name `
                --output json 2>$null |
                ConvertFrom-Json
        }
        catch {
            $cliOutput = @()
        }

        # HTTP funkcija
        $fun1 = $cliOutput |
            Where-Object {
                $_.name -like "*/$($Setup.LastName)-fun1" -or
                $_.name -like "*/*-fun1"
            } |
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
                Text  = "[$MissingStatus] - $($LabMsg.HttpFunctionNotFound.$Lang)"
                Color = "Red"
            }
        }

        # Timer funkcija
        $fun2 = $cliOutput |
            Where-Object {
                $_.name -like "*/$($Setup.LastName)-fun2" -or
                $_.name -like "*/*-fun2"
            } |
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
                Text  = "[$MissingStatus] - $($LabMsg.TimerFunctionNotFound.$Lang)"
                Color = "Red"
            }
        }
    }
    else {
        $resourceResults += [PSCustomObject]@{
            Name  = $Check.FunctionApp.$Lang
            Text  = "[$MissingStatus] - $($LabMsg.FunctionAppNotFound.$Lang)"
            Color = "Red"
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
# REZULTATŲ FORMATAVIMAS
# ============================================================

$i = 1

foreach ($res in $resourceResults) {
    if ($res.Name -match "^ -") {
        $label = "   $($res.Name):"
    }
    else {
        $label = "$i. $($res.Name):"
        $i++
    }

    $targetWidth = 30
    $neededSpaces = $targetWidth - $label.Length
    if ($neededSpaces -lt 1) { $neededSpaces = 1 }

    $padding = " " * $neededSpaces

    Write-Host "$label$padding" -NoNewline
    Write-Host $res.Text -ForegroundColor $res.Color
}

Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""