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

# --- 3. TYLUS TIKRINIMAS (Be išvedimo į ekraną) ---

# A. Prenumeratos tikrinimas
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

# B. Dėstytojo teisių tikrinimas
try {
    # Ieškome rolės priskyrimo tyliai
    $assignments = Get-AzRoleAssignment -IncludeClassicAdministrators -ErrorAction SilentlyContinue
    
    # Filtruojame pagal dėstytojo el. pašto dalį (iš Global) ir Rolę (iš Local)
    $destytojas = $assignments | Where-Object { 
        ($_.SignInName -match $GlobCfg.InstructorEmailMatch -or $_.DisplayName -match $GlobCfg.InstructorEmailMatch) -and 
        $_.RoleDefinitionName -eq $LocCfg.RoleToCheck 
    }
    
    if ($destytojas) {
        $res2Text  = "[OK] - $($destytojas.RoleDefinitionName)"
        $res2Color = "Green"
    } else {
        $res2Text  = "[KLAIDA] - Dėstytojas nerastas arba neturi rolės '$($LocCfg.RoleToCheck)'"
        $res2Color = "Red"
    }
} catch {
    $res2Text  = "[KLAIDA] - Nepavyko patikrinti teisių"
    $res2Color = "Red"
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

# Išvedame suformatuotas eilutes
Write-Host "1. Prenumeratos pavadinimas: " -NoNewline
Write-Host $res1Text -ForegroundColor $res1Color

Write-Host "2. Dėstytojo prieiga:        " -NoNewline
Write-Host $res2Text -ForegroundColor $res2Color

Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""