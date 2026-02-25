# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab01/Check-Lab1-config.json"

$GlobCfg = $Setup.GlobalConfig
$LocCfg  = $Setup.LocalConfig

# --- 3. TYLUS TIKRINIMAS (Prioritetas Mantui) ---

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
    # PAKEITIMAS: Pašalintas nulūžtantis '-IncludeClassicAdministrators' parametras.
    # Pridėtas konkretus Scope, kad išvengtume kitų Azure klaidų.
    # Pakeista į '-ErrorAction Stop', kad matytume tikrą klaidą, jei tokia būtų.
    $subId = $context.Subscription.Id
    $assignments = Get-AzRoleAssignment -Scope "/subscriptions/$subId" -ErrorAction Stop
    
    $currentUser = $context.Account.Id
    
    # Atsifiltruojame visus CONTRIBUTOR, kurie nėra pats studentas
    $allContributors = $assignments | Where-Object { 
        $_.RoleDefinitionName -eq "Contributor" -and 
        $_.SignInName -ne $currentUser
    }

    if ($allContributors) {
        $totalCount = @($allContributors).Count

        # Ieškome Manto pagal Vardą ir Pavardę arba el. paštą
        $mantas = $allContributors | Where-Object { 
            ($_.DisplayName -match "Mantas" -and $_.DisplayName -match "Bartkevičius") -or
            $_.SignInName -match "Mantas.Bartkevicius"
        } | Select-Object -First 1

        if ($mantas) {
            $others = $totalCount - 1
            $suffix = if ($others -gt 0) { " (+ $others kiti)" } else { "" }
            
            # Jei Azure neduoda DisplayName, naudojame SignInName
            $dispName = if ($mantas.DisplayName) { $mantas.DisplayName } else { $mantas.SignInName }
            
            $res2Text  = "[OK] - ${dispName}${suffix}"
            $res2Color = "Green"
        } else {
            $firstOther = $allContributors | Select-Object -First 1
            $name = if ($firstOther.DisplayName) { $firstOther.DisplayName } else { $firstOther.SignInName }
            
            $res2Text  = "[OK] - $name (Bet Mantas Bartkevičius nerastas)"
            $res2Color = "Yellow" 
        }
    } else {
        $res2Text  = "[KLAIDA] - Nerasta jokių vartotojų su 'Contributor' role (išskyrus jus)"
        $res2Color = "Red"
    }

} catch {
    # Jei komanda lūžta, dabar studentas matys tikslią Azure klaidą
    $res2Text  = "[KLAIDA] - Nepavyko nuskaityti teisių: $($_.Exception.Message)"
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

Write-Host "1. Prenumeratos pavadinimas: " -NoNewline
Write-Host $res1Text -ForegroundColor $res1Color

Write-Host "2. Dėstytojo prieiga:        " -NoNewline
Write-Host $res2Text -ForegroundColor $res2Color

Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""