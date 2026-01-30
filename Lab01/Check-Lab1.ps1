# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
# Atsisiunčiame "smegenis" (common.ps1), kurios moka identifikuoti studentą ir nuskaityti JSON
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų. Patikrinkite interneto ryšį."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
# Ši eilutė atlieka: JSON atsisiuntimą, TLS nustatymą, studento atpažinimą, ekrano valymą
# SVARBU: Naudojame jūsų pageidaujamą failo pavadinimą "...-config.json"
$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab01/Check-Lab1-config.json"

# Išsiimame konfigūracijas patogesniam naudojimui
$GlobCfg = $Setup.GlobalConfig
$LocCfg  = $Setup.LocalConfig

# --- 3. SPECIFINĖ LAB 1 LOGIKA ---

# A. TIKRINAME PRENUMERATĄ
$context = Get-AzContext
$subName = $context.Subscription.Name
$isNameCorrect = $subName -match $LocCfg.NamingPattern

Write-Host "1. Prenumeratos pavadinimas: $subName" -NoNewline
if ($isNameCorrect) {
    Write-Host " [OK]" -ForegroundColor Green
    $res1 = "TEISINGAS ($subName)"
} else {
    Write-Host " [NETINKAMAS]" -ForegroundColor Red
    Write-Host "   -> Reikalaujama: Grupė-Vardas-Pavardė (pvz. PI23-Jonas-Jonaitis)" -ForegroundColor Yellow
    $res1 = "NETEISINGAS ($subName)"
}

# B. TIKRINAME DĖSTYTOJO TEISES
# Naudojame Global config reikšmes (InstructorEmailMatch), kad nereikėtų hardcodinti vardo
Write-Host "2. Dėstytojo ($($GlobCfg.InstructorEmailMatch)...) teisės:" -NoNewline
try {
    $assignments = Get-AzRoleAssignment -IncludeClassicAdministrators -ErrorAction SilentlyContinue
    
    # Ieškome pagal dalinį atitikimą (Email arba DisplayName) ir Rolę
    $destytojas = $assignments | Where-Object { 
        ($_.SignInName -match $GlobCfg.InstructorEmailMatch -or $_.DisplayName -match $GlobCfg.InstructorEmailMatch) -and 
        $_.RoleDefinitionName -eq $LocCfg.RoleToCheck 
    }
    
    if ($destytojas) {
        Write-Host " [OK]" -ForegroundColor Green
        $res2 = "PRISKIRTA ($($LocCfg.RoleToCheck))"
    } else {
        Write-Host " [NERASTA]" -ForegroundColor Red
        $res2 = "DĖSTYTOJAS NERASTAS ARBA NETINKAMA ROLĖ"
    }
} catch {
    $res2 = "KLAIDA TIKRINANT"
}

# --- 4. ATASKAITA ---
$date = Get-Date -Format "yyyy-MM-dd HH:mm"
$report = @"
==================================================
$($Setup.HeaderTitle)
$($LocCfg.LabName)
Data: $date
Studentas: $($Setup.StudentEmail)
==================================================
1. Prenumeratos pavadinimas: $res1
2. Dėstytojo prieiga:        $res2
==================================================
"@

Write-Host "`n--- GALUTINIS REZULTATAS (Padarykite nuotrauką) ---" -ForegroundColor Cyan
Write-Host $report
Write-Host ""