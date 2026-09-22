# ============================================================
# LAB 3 - Azure Virtual Resources validation
# ============================================================

# --- 1. KALBA ---
if ($Lang -notin @("LT", "EN")) {
    $Lang = "LT"
}

# --- 2. UŽKRAUNAME BENDRAS FUNKCIJAS ---
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

# --- 3. INICIJUOJAME DARBĄ ---
$Setup = Initialize-Lab `
    -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab03/Check-Lab3-config.json" `
    -Lang $Lang

$LocCfg = $Setup.LocalConfig
$Check  = $LocCfg.Checks
$Msg    = $LocCfg.Messages

# Bendri statusai
$OkStatus    = $Setup.Messages.Ok
$ErrorStatus = $Setup.Messages.Error

if ($Msg.MissingStatus.$Lang) {
    $MissingStatus = $Msg.MissingStatus.$Lang
}
elseif ($Lang -eq "EN") {
    $MissingStatus = "MISSING"
}
else {
    $MissingStatus = "TRŪKSTA"
}

# --- 4. DUOMENŲ RINKIMAS ---

# ============================================================
# A. RESOURCE GROUP
# ============================================================

$targetRG = Get-AzResourceGroup |
    Where-Object {
        $_.ResourceGroupName -match $LocCfg.ResourceGroupPattern
    } |
    Select-Object -First 1

if ($targetRG) {
    $rgText  = "[$OkStatus] - $($targetRG.ResourceGroupName) ($($targetRG.Location))"
    $rgColor = "Green"
}
else {
    $rgText  = "[$ErrorStatus] - $($Msg.ResourceGroupNotFound.$Lang)"
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

    $vm = Get-AzVM `
        -ResourceGroupName $targetRG.ResourceGroupName |
        Select-Object -First 1

    if ($vm) {

        # ----------------------------------------------------
        # VM dydis ir būsena
        # ----------------------------------------------------

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

        # ----------------------------------------------------
        # OS DISKAS
        # ----------------------------------------------------

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
            $osDiskText  = "[$MissingStatus] - $($Msg.OsDiskNotFound.$Lang)"
            $osDiskColor = "Red"
        }

        # ----------------------------------------------------
        # DATA DISKAI
        # ----------------------------------------------------

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
                $diskText = "[$OkStatus] - $($Msg.DataDiskFound.$Lang): $diskCount ($($diskSizes -join ', '))"
            }
            else {
                $diskText = "[$OkStatus] - $($Msg.DataDiskFound.$Lang): $diskCount"
            }

            $diskColor = "Green"
        }
        else {
            $diskText  = "[$MissingStatus] - $($Msg.DataDiskNotFound.$Lang)"
            $diskColor = "Red"
        }
    }
    else {
        $vmText      = "[$MissingStatus] - $($Msg.VirtualMachineNotFound.$Lang)"
        $vmColor     = "Red"

        $osDiskText  = "---"
        $osDiskColor = "Gray"

        $diskText    = "---"
        $diskColor   = "Gray"
    }

    # VM
    $resourceResults += [PSCustomObject]@{
        Name  = $Check.VirtualMachine.$Lang
        Text  = $vmText
        Color = $vmColor
    }

    # Diskai rodomi tik jei VM egzistuoja
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
        Where-Object {
            $_.Kind -like "*functionapp*"
        } |
        Select-Object -First 1

    if ($funcApp) {

        $resourceResults += [PSCustomObject]@{
            Name  = $Check.FunctionApp.$Lang
            Text  = "[$OkStatus] - $($funcApp.Name)"
            Color = "Green"
        }

        # ====================================================
        # E. FUNKCIJOS
        # ====================================================

        Write-Host `
            "   ($($Msg.CheckingFunctions.$Lang))" `
            -ForegroundColor DarkGray

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

        # ----------------------------------------------------
        # HTTP FUNCTION
        # ----------------------------------------------------

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
                Text  = "[$MissingStatus] - $($Msg.HttpFunctionNotFound.$Lang)"
                Color = "Red"
            }
        }

        # ----------------------------------------------------
        # TIMER FUNCTION
        # ----------------------------------------------------

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
                Text  = "[$MissingStatus] - $($Msg.TimerFunctionNotFound.$Lang)"
                Color = "Red"
            }
        }
    }
    else {

        $resourceResults += [PSCustomObject]@{
            Name  = $Check.FunctionApp.$Lang
            Text  = "[$MissingStatus] - $($Msg.FunctionAppNotFound.$Lang)"
            Color = "Red"
        }
    }
}
else {

    # ========================================================
    # RESOURCE GROUP NERASTA
    # ========================================================

    $resourceResults += [PSCustomObject]@{
        Name  = $Check.VirtualMachine.$Lang
        Text  = "[$ErrorStatus] - $($Msg.NoResourceGroup.$Lang)"
        Color = "Gray"
    }

    $resourceResults += [PSCustomObject]@{
        Name  = $Check.FunctionApp.$Lang
        Text  = "[$ErrorStatus] - $($Msg.NoResourceGroup.$Lang)"
        Color = "Gray"
    }
}

# ============================================================
# 5. IŠVEDIMAS
# ============================================================

$date = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host `
    "`n--- $($Setup.Messages.FinalResult) ---" `
    -ForegroundColor Cyan

Write-Host `
    "==================================================" `
    -ForegroundColor Gray

Write-Host $Setup.HeaderTitle

if ($LocCfg.LabName.$Lang) {
    Write-Host `
        $LocCfg.LabName.$Lang `
        -ForegroundColor Yellow
}
else {
    Write-Host `
        "LAB 3" `
        -ForegroundColor Yellow
}

Write-Host "$($Setup.Messages.Date): $date"
Write-Host "$($Setup.Messages.Student): $($Setup.StudentEmail)"

Write-Host `
    "==================================================" `
    -ForegroundColor Gray

# ============================================================
# 6. REZULTATŲ FORMATAVIMAS
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

    if ($neededSpaces -lt 1) {
        $neededSpaces = 1
    }

    $padding = " " * $neededSpaces

    Write-Host `
        "$label$padding" `
        -NoNewline

    Write-Host `
        $res.Text `
        -ForegroundColor $res.Color
}

Write-Host `
    "==================================================" `
    -ForegroundColor Gray

Write-Host ""