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


# A. Studento paskyros domeno tikrinimas
#-----------------------------------------
try {
    # 1. Studento paskyros tikrinimas
    if ($studentEmail -match '(?i)@itm\.kaunokolegija\.lt$') {
        $res0Text  = "[OK] - $studentEmail"
        $res0Color = "Green"
    }
    else {
        $res0Text  = "[KLAIDA] - Naudokite @itm.kaunokolegija.lt paskyrą: $studentEmail"
        $res0Color = "Red"
    }
}
catch {
    $res0Text  = "[KLAIDA] - Nepavyko nustatyti prisijungusios paskyros"
    $res0Color = "Red"
}


# B. Prenumeratos tikrinimas
#-----------------------------------------
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

# C. Dėstytojo teisių tikrinimas
#-----------------------------------------
try {
    $currentUser = $context.Account.Id
    
    # Paimame VISUS priskyrimus be jokių ribojančių scope parametrų
    $assignments = Get-AzRoleAssignment -ErrorAction SilentlyContinue

    # Filtruojame naudodami foreach (veikia stabiliau nei Where-Object su tuščiais Azure laukais)
    $allContributors = @()
    if ($assignments) {
        foreach ($a in $assignments) {
            if ($a.RoleDefinitionName -match "Contributor" -and $a.SignInName -ne $currentUser) {
                $allContributors += $a
            }
        }
    }

    if ($allContributors.Count -gt 0) {
        $totalCount = $allContributors.Count

        # Ieškome Manto
        $mantas = $null
        foreach ($c in $allContributors) {
            if (($c.DisplayName -match "Mantas" -and $c.DisplayName -match "Bartkevičius") -or ($c.SignInName -match "Mantas.Bartkevicius")) {
                $mantas = $c
                break
            }
        }

        if ($mantas) {
            $others = $totalCount - 1
            $suffix = if ($others -gt 0) { " (+ $others kiti)" } else { "" }
            
            $dispName = if ($mantas.DisplayName) { $mantas.DisplayName } elseif ($mantas.SignInName) { $mantas.SignInName } else { "Dėstytojas" }
            
            $res2Text  = "[OK] - ${dispName}${suffix}"
            $res2Color = "Green"
        } else {
            $firstOther = $allContributors[0]
            $name = if ($firstOther.DisplayName) { $firstOther.DisplayName } elseif ($firstOther.SignInName) { $firstOther.SignInName } else { "Kolega" }
            
            $res2Text  = "[OK] - $name (Bet Mantas Bartkevičius nerastas)"
            $res2Color = "Yellow" 
        }
    } else {
        $res2Text  = "[KLAIDA] - Nerasta jokių vartotojų su 'Contributor' role (išskyrus jus). Jei ką tik pridėjote, palaukite 5-10 min!"
        $res2Color = "Red"
    }

} catch {
    $res2Text  = "[KLAIDA] - Nepavyko nuskaityti teisių: $($_.Exception.Message)"
    $res2Color = "Red"
}

# D. Budget tikrinimas
#-----------------------------------------
try {
    $accountsResponse = Invoke-AzRestMethod `
        -Method GET `
        -Uri "https://management.azure.com/providers/Microsoft.Billing/billingAccounts?api-version=2024-04-01" `
        -ErrorAction Stop

    $accounts = ($accountsResponse.Content | ConvertFrom-Json).value

    $foundBudgets = @()

    foreach ($account in $accounts) {

        $budgetUri = "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$($account.name)/providers/Microsoft.Consumption/budgets?api-version=2024-08-01"

        try {
            $budgetResponse = Invoke-AzRestMethod `
                -Method GET `
                -Uri $budgetUri `
                -ErrorAction Stop

            $budgets = ($budgetResponse.Content | ConvertFrom-Json).value

            if ($budgets) {
                $foundBudgets += $budgets
            }
        }
        catch {
            # Jei vieno billing account biudžetų patikrinti nepavyksta,
            # pereiname prie kito.
        }
    }

    if ($foundBudgets.Count -gt 0) {
        $budgetNames = $foundBudgets |
            ForEach-Object { $_.name }

        $res3Text  = "[OK] - " + ($budgetNames -join ", ")
        $res3Color = "Green"
    }
    else {
        $res3Text  = "[KLAIDA] - Budget nerastas"
        $res3Color = "Red"
    }
}
catch {
    $res3Text  = "[KLAIDA] - Nepavyko patikrinti Budget: $($_.Exception.Message)"
    $res3Color = "Red"
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

Write-Host "1. Studento paskyra:         " -NoNewline
Write-Host $res0Text -ForegroundColor $res0Color

Write-Host "2. Prenumeratos pavadinimas: " -NoNewline
Write-Host $res1Text -ForegroundColor $res1Color

Write-Host "3. Dėstytojo prieiga:        " -NoNewline
Write-Host $res2Text -ForegroundColor $res2Color

Write-Host "4. Budget tikrinimas:        " -NoNewline
Write-Host $res3Text -ForegroundColor $res3Color

Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""