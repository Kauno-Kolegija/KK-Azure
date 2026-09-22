# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
}
catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų (common.ps1)."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
$Setup = Initialize-Lab `
    -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab02/Check-Lab2-config.json"

$LocCfg = $Setup.LocalConfig


# ============================================================
# 3. DUOMENŲ RINKIMAS
# ============================================================

# A. Randame Resursų grupę
$targetRG = Get-AzResourceGroup |
    Where-Object {
        $_.ResourceGroupName -match $LocCfg.ResourceGroupPattern
    } |
    Select-Object -First 1


if ($targetRG) {

    $rgText = "[OK] - $($targetRG.ResourceGroupName) ($($targetRG.Location))"
    $rgColor = "Green"
}
else {

    $rgText = "[KLAIDA] - Nerasta grupė '$($LocCfg.ResourceGroupPattern)...'"
    $rgColor = "Red"
}


# Rezultatų masyvas
$resourceResults = @()


# ============================================================
# 1. RESOURCE GROUP
# ============================================================

$resourceResults += [PSCustomObject]@{
    Name   = "Resursų grupė"
    Text   = $rgText
    Color  = $rgColor
    Indent = 0
}


# ============================================================
# 2. WEB APP
# ============================================================

if ($targetRG) {

    $webApp = Get-AzWebApp `
        -ResourceGroupName $targetRG.ResourceGroupName `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1


    if ($webApp) {

        # Pagrindinė Web App eilutė
        $resourceResults += [PSCustomObject]@{
            Name   = "Web App (Svetainė)"
            Text   = "[OK] - $($webApp.Name) ($($webApp.Location))"
            Color  = "Green"
            Indent = 0
        }


        # ----------------------------------------------------
        # Runtime tikrinimas
        # ----------------------------------------------------

        $runtime = $null

        # Windows Web App atveju .NET versija paprastai yra
        # SiteConfig.NetFrameworkVersion
        if ($webApp.SiteConfig.NetFrameworkVersion) {

            $runtime = $webApp.SiteConfig.NetFrameworkVersion
        }


        if ($runtime) {

            # Pvz. v10.0 -> .NET 10
            $runtimeDisplay = $runtime

            if ($runtime -match '^v?10') {
                $runtimeDisplay = ".NET 10"
                $runtimeText = "[OK] - $runtimeDisplay"
                $runtimeColor = "Green"
            }
            else {
                $runtimeText = "[KLAIDA] - $runtime"
                $runtimeColor = "Yellow"
            }
        }
        else {

            $runtimeText = "[KLAIDA] - Nepavyko nustatyti"
            $runtimeColor = "Yellow"
        }


        $resourceResults += [PSCustomObject]@{
            Name   = "Runtime"
            Text   = $runtimeText
            Color  = $runtimeColor
            Indent = 1
        }


        # ----------------------------------------------------
        # App Service Plan tikrinimas
        # ----------------------------------------------------

        try {

            # ServerFarmId paprastai baigiasi App Service Plan pavadinimu
            $planName = Split-Path $webApp.ServerFarmId -Leaf

            $plan = Get-AzAppServicePlan `
                -ResourceGroupName $targetRG.ResourceGroupName `
                -Name $planName `
                -ErrorAction Stop


            # OS nustatymas
            $planOS = if ($plan.Reserved -eq $true) {
                "Linux"
            }
            else {
                "Windows"
            }


            # SKU
            $skuName = $plan.Sku.Name
            $skuTier = $plan.Sku.Tier


            # D1 paprastai yra Shared tier
            $planDisplay = "$skuTier $skuName / $planOS"


            $planOk =
                ($planOS -eq "Windows") -and
                (
                    ($skuName -eq "D1") -or
                    ($skuTier -eq "Shared")
                )


            if ($planOk) {

                $planText = "[OK] - $planDisplay"
                $planColor = "Green"
            }
            else {

                $planText = "[KLAIDA] - $planDisplay"
                $planColor = "Yellow"
            }
        }
        catch {

            $planText = "[KLAIDA] - Nepavyko nustatyti App Service Plan"
            $planColor = "Yellow"
        }


        $resourceResults += [PSCustomObject]@{
            Name   = "App Service Plan"
            Text   = $planText
            Color  = $planColor
            Indent = 1
        }

    }
    else {

        $resourceResults += [PSCustomObject]@{
            Name   = "Web App (Svetainė)"
            Text   = "[TRŪKSTA] - Nerastas resursas"
            Color  = "Red"
            Indent = 0
        }
    }


    # ========================================================
    # 3. STORAGE ACCOUNT
    # ========================================================

    $storage = Get-AzStorageAccount `
        -ResourceGroupName $targetRG.ResourceGroupName `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1


    if ($storage) {

        $storageText =
            "[OK] - $($storage.StorageAccountName) " +
            "($($storage.Location)) [$($storage.Sku.Name)]"

        $storageColor = if ($storage.Sku.Name -eq "Standard_LRS") {
            "Green"
        }
        else {
            "Yellow"
        }


        $resourceResults += [PSCustomObject]@{
            Name   = "Storage Account (Saugykla)"
            Text   = $storageText
            Color  = $storageColor
            Indent = 0
        }
    }
    else {

        $resourceResults += [PSCustomObject]@{
            Name   = "Storage Account (Saugykla)"
            Text   = "[TRŪKSTA] - Nerastas resursas"
            Color  = "Red"
            Indent = 0
        }
    }

}
else {

    $resourceResults += [PSCustomObject]@{
        Name   = "Web App (Svetainė)"
        Text   = "[KLAIDA] - Nėra resursų grupės"
        Color  = "Gray"
        Indent = 0
    }

    $resourceResults += [PSCustomObject]@{
        Name   = "Storage Account (Saugykla)"
        Text   = "[KLAIDA] - Nėra resursų grupės"
        Color  = "Gray"
        Indent = 0
    }
}


# ============================================================
# 4. GALUTINIS REZULTATAS
# ============================================================

$date = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host "`n--- GALUTINIS REZULTATAS (Padarykite nuotrauką) ---" `
    -ForegroundColor Cyan

Write-Host "==================================================" `
    -ForegroundColor Gray

Write-Host "$($Setup.HeaderTitle)"

Write-Host "$($LocCfg.LabName)" `
    -ForegroundColor Yellow

Write-Host "Data: $date"
Write-Host "Studentas: $($Setup.StudentEmail)"

Write-Host "==================================================" `
    -ForegroundColor Gray


$mainNumber = 1

foreach ($res in $resourceResults) {

    if ($res.Indent -eq 1) {

        # Sub-elementai po Web App
        $label = "   $($res.Name):"
    }
    else {

        $label = "$mainNumber. $($res.Name):"
        $mainNumber++
    }


    $targetWidth = 39

    $neededSpaces = $targetWidth - $label.Length

    if ($neededSpaces -lt 1) {
        $neededSpaces = 1
    }

    $padding = " " * $neededSpaces


    Write-Host "$label$padding" -NoNewline

    Write-Host $res.Text `
        -ForegroundColor $res.Color
}


Write-Host "==================================================" `
    -ForegroundColor Gray

Write-Host ""