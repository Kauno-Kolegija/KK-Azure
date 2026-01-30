# --- VERSIJOS KONTROLĖ ---
$ScriptVersion = "SCRIPT VERSIJA: v6.0 (Azure CLI metodas)"
Clear-Host
Write-Host "--------------------------------------------------"
Write-Host $ScriptVersion -ForegroundColor Magenta
Write-Host "Vykdoma patikra... Tai gali užtrukti kelias sekundes."
Write-Host "--------------------------------------------------"

# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    # Testavimo metu paliekame v=random, kad nereikėtų jums vargti
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1?v=$(Get-Random)" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų (common.ps1)."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab03/Check-Lab3-config.json"
$LocCfg = $Setup.LocalConfig

# --- 3. DUOMENŲ RINKIMAS ---

# A. Randame Resursų grupę
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
        $actualSize = $vm.HardwareProfile.VmSize
        $expectedSize = "Standard_B1ms"
        
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
    $funcApp = Get-AzResource -ResourceGroupName $targetRG.ResourceGroupName -ResourceType "Microsoft.Web/sites" | Where-Object { $_.Kind -like "*functionapp*" } | Select-Object -First 1
    
    if ($funcApp) {
        $resourceResults += [PSCustomObject]@{
            Name  = "Function App"
            Text  = "[OK] - $($funcApp.Name) ($($funcApp.Location))"
            Color = "Green"
        }

        # --- 3. FUNKCIJOS (NAUDOJANT AZURE CLI) ---
        # Tai yra "branduolinis" variantas. Jei PowerShell nemato, CLI pamatys.
        # Cloud Shell aplinkoje 'az' komanda yra instaliuota standartiškai.
        
        Write-Host "   (Tikrinamas funkcijų sąrašas per Azure CLI...)" -ForegroundColor DarkGray
        
        try {
            # Gauname JSON sąrašą tiesiai iš API
            $cliOutput = az functionapp function list --resource-group $targetRG.ResourceGroupName --name $funcApp.Name --output json | ConvertFrom-Json
        } catch {
            $cliOutput = @()
        }

        # HTTP (-fun1)
        # Azure CLI grąžina pilną ID, pvz: .../functions/Bartukas-fun1
        $fun1 = $cliOutput | Where-Object { $_.name -like "*/$($Setup.LastName)-fun1" -or $_.name -like "*/*-fun1" } | Select-Object -First 1
        
        if ($fun1) {
            # Išvalome vardą
            $cleanName = $fun1.name.Split('/')[-1]
            $resourceResults += [PSCustomObject]@{ Name = "Funkcija (HTTP)"; Text = "[OK] - $cleanName"; Color = "Green" }
        } else {
            $resourceResults += [PSCustomObject]@{ Name = "Funkcija (HTTP)"; Text = "[TRŪKSTA] - Nerasta funkcija *-fun1"; Color = "Red" }
        }

        # Timer (-fun2)
        $fun2 = $cliOutput | Where-Object { $_.name -like "*/$($Setup.LastName)-fun2" -or $_.name -like "*/*-fun2" } | Select-Object -First 1
        
        if ($fun2) {
            $cleanName = $fun2.name.Split('/')[-1]
            $resourceResults += [PSCustomObject]@{ Name = "Funkcija (Timer)"; Text = "[OK] - $cleanName"; Color = "Green" }
        } else {
            $resourceResults += [PSCustomObject]@{ Name = "Funkcija (Timer)"; Text = "[TRŪKSTA] - Nerasta funkcija *-fun2"; Color = "Red" }
        }

    } else {
        $resourceResults += [PSCustomObject]@{ Name = "Function App"; Text = "[TRŪKSTA] - Nerasta Function App"; Color = "Red" }
    }

} else {
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