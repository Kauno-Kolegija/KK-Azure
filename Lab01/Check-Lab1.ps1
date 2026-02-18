# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
# Setup grąžina visus kintamuosius ir išveda pradinę antraštę
$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab01/Check-Lab1-config.json"

$GlobCfg = $Setup.GlobalConfig
$LocCfg  = $Setup.LocalConfig

# --- 3. TYLUS TIKRINIMAS (Supaprastintas variantas) ---

# A. Prenumeratos tikrinimas (Paliekame kaip buvo)
$context = Get-AzContext
$subName = $context.Subscription.Name
$isNameCorrect = $subName -match $LocCfg.NamingPattern

if ($isNameCorrect) {
    $res1Text  = "[OK] - $subName"
    $res1Color = "Green"
} else {
    $res1Text  = "[KLAIDA] - $subName (Netinkamas formatas)"
    $res1Color = "Red"
}

# B. Dėstytojo teisių tikrinimas (Supaprastintas)
try {
    # Gauname visus teisių priskyrimus
    $assignments = Get-AzRoleAssignment -IncludeClassicAdministrators -ErrorAction SilentlyContinue
    
    # Ieškome bet kokio įrašo, kuris:
    # 1. Turi rolę 'Contributor'
    # 2. NĖRA studento paskyra (pagal prisijungusį vartotoją)
    # 3. Yra arba "Mantas" (pagal vardą) arba turi "@itm.kaunokolegija" (pagal domeną)
    
    $currentUser = (Get-AzContext).Account.Id
    
    $destytojas = $assignments | Where-Object { 
        $_.RoleDefinitionName -eq "Contributor" -and 
        $_.SignInName -ne $currentUser -and
        ($_.DisplayName -match "Mantas" -or $_.SignInName -match "kaunokolegija" -or $_.DisplayName -match "Bartkevičius")
    } | Select-Object -First 1
    
    if ($destytojas) {
        # Jei radome, parodome ką radome (Vardą arba ID)
        $foundName = if ($destytojas.DisplayName) { $destytojas.DisplayName } else { "Dėstytojas" }
        $res2Text  = "[OK] - $foundName (Contributor)"
        $res2Color = "Green"
    } else {
        $res2Text  = "[KLAIDA] - Nerasta 'Contributor' rolė dėstytojui (Mantas Bartkevičius)"
        $res2Color = "Red"
    }
} catch {
    $res2Text  = "[KLAIDA] - Nepavyko nuskaityti teisių. Bandykite dar kartą."
    $res2Color = "Red"
}

# --- 4. GALUTINIS REZULTATAS (Ataskaitai) ---
$date = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host "`n--- GALUTINIS REZULTATAS (Padarykite nuotrauką) ---" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Gray
Write-Host "$($Setup.HeaderTitle)"
Write-Host "$($LocCfg.LabName)" -ForegroundColor Yellow
Write-Host "Data: $date"
Write-Host "Studentas: $($Setup.StudentEmail)"
Write-Host "==================================================" -ForegroundColor Gray

# Išvedame suformatuotas eilutes
Write-Host "1. Prenumeratos pavadinimas: " -NoNewline
Write-Host $res1Text -ForegroundColor $res1Color

Write-Host "2. Dėstytojo prieiga:        " -NoNewline
Write-Host $res2Text -ForegroundColor $res2Color

Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""