# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų (common.ps1)."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
# DĖMESIO: Čia pakeistas failo pavadinimas į jūsų nurodytą
$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab03/Check-Lab3-config.json"
$LocCfg = $Setup.LocalConfig

# --- 3. DUOMENŲ RINKIMAS ---

# A. Randame Resursų grupę
# Ieškome grupės pagal jūsų konfigūraciją (RG-LAB03)
$targetRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match "RG-LAB03" } | Select-Object -First 1

if ($targetRG) {
    $rgText  = "[OK] - $($targetRG.ResourceGroupName)"
    $rgColor = "Green"
} else {
    $rgText  = "[KLAIDA] - Nerasta grupė RG-LAB03..."
    $rgColor = "Red"
}

# B. Resursų tikrinimas
$resourceResults = @()

# 1. Resursų Grupė
$resourceResults += [PSCustomObject]@{
    Name  = "Resursų grupė"
    Text  = $rgText
    Color = $rgColor
}

if ($targetRG) {
    # --- 1. VIRTUALUS SERVERIS (VM) ---
    $vm = Get-AzVM -ResourceGroupName $targetRG.ResourceGroupName | Select-Object -First 1
    
    if ($vm) {
        # Tikriname dydį
        $actualSize = $vm.HardwareProfile.VmSize
        $expectedSize = "Standard_B1ms"
        
        # Tikriname statusą
        $statusObj = Get-AzVM -ResourceGroupName $targetRG.ResourceGroupName -Name $vm.Name -Status
        $displayStatus = ($statusObj.Statuses | Where-Object Code -like "PowerState/*" | Select-Object -First 1).DisplayStatus
        
        if ($actualSize -eq $expectedSize) {
            $vmText = "[OK] - $($vm.Name) ($actualSize) [$displayStatus]"
            $vmColor = "Green"
        } else {
            $vmText = "[DĖMESIO] - $($vm.Name). Dydis: $actualSize (Reikėjo: $expectedSize)"
            $vmColor = "Yellow"
        }
    } else {
        $vmText = "[TRŪKSTA] - Nerastas Virtualus Serveris"
        $vmColor = "Red"
    }

    $resourceResults += [PSCustomObject]@{ Name = "Virtualus Serveris"; Text = $vmText; Color = $vmColor }

    # --- 2. FUNCTION APP ---
    # Ieškome tiesiogiai per resursus, ignoruojant WebApp komandas
    $funcApp = Get-AzResource -ResourceGroupName $targetRG.ResourceGroupName -ResourceType "Microsoft.Web/sites" | Where-Object { $_.Kind -like "*functionapp*" } | Select-Object -First 1
    
    if ($funcApp) {
        $resourceResults += [PSCustomObject]@{
            Name  = "Function App"
            Text  = "[OK] - $($funcApp.Name) ($($funcApp.Location))"
            Color = "Green"
        }

        # --- 3. FUNKCIJOS VIDUJE ---
        # Ieškome VISŲ resursų, kurių tipas yra 'sites/functions' toje grupėje
        # Tai apeina "cold start" problemą
        $allFunctions = Get-AzResource -ResourceGroupName $targetRG.ResourceGroupName -ResourceType "Microsoft.Web/sites/functions"

        # HTTP (-fun1)
        $fun1 = $allFunctions | Where-Object { $_.Name -like "*-fun1" } | Select-Object -First 1
        if ($fun1) {
            # Name būna formatu "AppVardas/FunkcijosVardas", imame tik galūnę
            $fName = $fun1.Name.Split('/')[-1]
            $resourceResults += [PSCustomObject]@{ Name = "Funkcija (HTTP)"; Text = "[OK] - $fName"; Color = "Green" }
        } else {
            $resourceResults += [PSCustomObject]@{ Name = "Funkcija (HTTP)"; Text = "[TRŪKSTA] - Nerasta funkcija *-fun1"; Color = "Red" }
        }

        # Timer (-fun2)
        $fun2 = $allFunctions | Where-Object { $_.Name -like "*-fun2" } | Select-Object -First 1
        if ($fun2) {
            $fName = $fun2.Name.Split('/')[-1]
            $resourceResults += [PSCustomObject]@{ Name = "Funkcija (Timer)"; Text = "[OK] - $fName"; Color = "Green" }
        } else {
            $resourceResults += [PSCustomObject]@{ Name = "Funkcija (Timer)"; Text = "[TRŪKSTA] - Nerasta funkcija *-fun2"; Color = "Red" }
        }

    } else {
        $resourceResults += [PSCustomObject]@{ Name = "Function App"; Text = "[TRŪKSTA] - Nerasta Function App"; Color = "Red" }
    }

} else {
    # Jei nėra grupės
    $resourceResults += [PSCustomObject]@{ Name = "Virtualus Serveris"; Text = "[KLAIDA] - Nėra grupės"; Color = "Gray" }
    $resourceResults += [PSCustomObject]@{ Name = "Function App"; Text = "[KLAIDA] - Nėra grupės"; Color = "Gray" }
}

# --- 4. IŠVEDIMAS ---
$date = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host "`n--- GALUTINIS REZULTATAS (Padarykite nuotrauką) ---" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Gray
Write-Host "$($Setup.HeaderTitle)"
if ($LocCfg.LabName) { Write-Host "$($LocCfg.LabName)" -ForegroundColor Yellow } else { Write-Host "LAB 3: Compute" -ForegroundColor Yellow }
Write-Host "Data: $date"
Write-Host "Studentas: $($Setup.StudentEmail)"
Write-Host "==================================================" -ForegroundColor Gray

$i = 1
foreach ($res in $resourceResults) {
    $label = "$i. $($res.Name):"
    
    # Lygiavimas
    $targetWidth = 30
    $neededSpaces = $targetWidth - $label.Length
    if ($neededSpaces -lt 1) { $neededSpaces = 1 }
    $padding = " " * $neededSpaces
    
    Write-Host "$label$padding" -NoNewline
    Write-Host $res.Text -ForegroundColor $res.Color
    $i++
}

Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""