# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
# Atsisiunčiame konfigūraciją ir identifikuojame studentą
$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab02/Check-Lab2-config.json"

$LocCfg = $Setup.LocalConfig

# --- 3. TYLUS TIKRINIMAS (Be išvedimo į ekraną) ---

# A. Randame Resursų grupę
# Ieškome pirmos grupės, kuri atitinka šabloną (pvz. RG-LAB02-...)
$targetRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match $LocCfg.ResourceGroupPattern } | Select-Object -First 1

if ($targetRG) {
    $rgText  = "[OK] - $($targetRG.ResourceGroupName)"
    $rgColor = "Green"
} else {
    $rgText  = "[KLAIDA] - Nerasta grupė pagal šabloną '$($LocCfg.ResourceGroupPattern)'"
    $rgColor = "Red"
}

# B. Tikriname resursus (Web App, Storage ir t.t. iš JSON)
$resourceResults = @()

if ($targetRG) {
    # Pasiimame visus resursus toje grupėje vienu ypu
    $allResources = Get-AzResource -ResourceGroupName $targetRG.ResourceGroupName
    
    foreach ($req in $LocCfg.RequiredResources) {
        # Ieškome specifinio tipo (pvz. Microsoft.Web/sites)
        $found = $allResources | Where-Object { $_.ResourceType -eq $req.Type } | Select-Object -First 1
        
        if ($found) {
            $resourceResults += [PSCustomObject]@{
                Name  = $req.Name
                Text  = "[OK] - $($found.Name)"
                Color = "Green"
            }
        } else {
            $resourceResults += [PSCustomObject]@{
                Name  = $req.Name
                Text  = "[TRŪKSTA] - Nerastas resursas"
                Color = "Red"
            }
        }
    }
} else {
    # Jei nėra grupės, visi resursai automatiškai neegzistuoja
    foreach ($req in $LocCfg.RequiredResources) {
        $resourceResults += [PSCustomObject]@{
            Name  = $req.Name
            Text  = "[KLAIDA] - Nėra resursų grupės"
            Color = "Gray"
        }
    }
}

# --- 4. GALUTINIS REZULTATAS (Ataskaitai) ---
$date = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host "`n--- GALUTINIS REZULTATAS (Padarykite nuotrauką) ---" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Gray
Write-Host "$($Setup.HeaderTitle)"
Write-Host "$($LocCfg.LabName)"
Write-Host "Data: $date"
Write-Host "Studentas: $($Setup.StudentEmail)"
Write-Host "==================================================" -ForegroundColor Gray

# 1. Išvedame Resursų grupę
Write-Host "1. Resursų grupė:            " -NoNewline
Write-Host $rgText -ForegroundColor $rgColor

# 2. Išvedame kitus resursus dinamiškai
$i = 2
foreach ($res in $resourceResults) {
    # Formatuojame tarpus, kad lygiuotųsi gražiai
    $label = "$i. $($res.Name):"
    $padding = " " * (25 - $label.Length) # Dinaminis lygiavimas
    if ($padding.Length -lt 1) { $padding = " " }
    
    Write-Host "$label$padding" -NoNewline
    Write-Host $res.Text -ForegroundColor $res.Color
    $i++
}

Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""