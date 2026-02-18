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

# --- 3. TYLUS TIKRINIMAS (Prioritetas Mantui) ---

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

# B. Dėstytojo teisių tikrinimas
try {
    # 1. Gauname visus teisių priskyrimus tyliai
    $assignments = Get-AzRoleAssignment -IncludeClassicAdministrators -ErrorAction SilentlyContinue
    $currentUser = (Get-AzContext).Account.Id
    
    # 2. Atsifiltruojame visus CONTRIBUTOR, kurie nėra studentas
    $allContributors = $assignments | Where-Object { 
        $_.RoleDefinitionName -eq "Contributor" -and 
        $_.SignInName -ne $currentUser
    }

    if ($allContributors) {
        # Suskaičiuojame kiek iš viso yra dėstytojų/kolegų
        # Jei $allContributors yra vienas objektas, .Count gali neveikti senesnėse PS versijose, todėl @()
        $totalCount = @($allContributors).Count

        # 3. Ieškome KONKREČIAI Manto Bartkevičiaus
        $mantas = $allContributors | Where-Object { 
            $_.DisplayName -match "Mantas" -and $_.DisplayName -match "Bartkevičius" 
        } | Select-Object -First 1

        if ($mantas) {
            # Jei radome Mantą - rodome jį
            # Papildomai parodome, jei yra daugiau žmonių
            $others = $totalCount - 1
            $suffix = if ($others -gt 0) { " (+ $others kiti)" } else { "" }
            
            $res2Text  = "[OK] - $($mantas.DisplayName)$suffix"
            $res2Color = "Green"
        } else {
            # Jei Manto neradome, bet radome kitų (pvz. Roką)
            $firstOther = $allContributors | Select-Object -First 1
            $name = if ($firstOther.DisplayName) { $firstOther.DisplayName } else { "Kolega" }
            
            $res2Text  = "[OK] - $name (Bet Mantas Bartkevičius nerastas)"
            $res2Color = "Yellow" 
        }
    } else {
        $res2Text  = "[KLAIDA] - Nerasta jokių vartotojų su 'Contributor' role (išskyrus jus)"
        $res2Color = "Red"
    }

} catch {
    $res2Text  = "[KLAIDA] - Nepavyko nuskaityti teisių."
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