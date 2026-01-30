# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab02/Check-Lab2-config.json"
$LocCfg = $Setup.LocalConfig

# --- 3. TYLUS TIKRINIMAS ---

# A. Randame Resursų grupę
$targetRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match $LocCfg.ResourceGroupPattern } | Select-Object -First 1

if ($targetRG) {
    $rgText  = "[OK] - $($targetRG.ResourceGroupName)"
    $rgColor = "Green"
} else {
    $rgText  = "[KLAIDA] - Nerasta grupė '$($LocCfg.ResourceGroupPattern)...'"
    $rgColor = "Red"
}

# B. Tikriname resursus
$resourceResults = @()

# Visada pridedame RG kaip pirmą elementą į sąrašą
$resourceResults += [PSCustomObject]@{
    Name  = "Resursų grupė"
    Text  = $rgText
    Color = $rgColor
}

if ($targetRG) {
    $allResources = Get-AzResource -ResourceGroupName $targetRG.ResourceGroupName
    
    foreach ($req in $LocCfg.RequiredResources) {
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
    # Jei nėra grupės, kitiems resursams rašome klaidą
    foreach ($req in $LocCfg.RequiredResources) {
        $resourceResults += [PSCustomObject]@{
            Name  = $req.Name
            Text  = "[KLAIDA] - Nėra resursų grupės"
            Color = "Gray"
        }
    }
}

# --- 4. GALUTINIS REZULTATAS ---
$date = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host "`n--- GALUTINIS REZULTATAS (Padarykite nuotrauką) ---" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Gray
Write-Host "$($Setup.HeaderTitle)"
Write-Host "$($LocCfg.LabName)"
Write-Host "Data: $date"
Write-Host "Studentas: $($Setup.StudentEmail)"
Write-Host "==================================================" -ForegroundColor Gray

# Dinaminis išvedimas su numeracija
$i = 1
foreach ($res in $resourceResults) {
    # Formatuojame: "1. Pavadinimas:        "
    $label = "$i. $($res.Name):"
    
    # Lygiavimas (padding), kad stulpeliai būtų gražūs (iki 30 simbolių)
    $paddingLength = 30 - $label.Length
    if ($paddingLength -lt 1) { $paddingLength = 1 }
    $padding = " " * $paddingLength
    
    Write-Host "$label$padding" -NoNewline
    Write-Host $res.Text -ForegroundColor $res.Color
    $i++
}

Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""