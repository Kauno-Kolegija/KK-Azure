# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    if ($PSScriptRoot) {
        . (Join-Path $PSScriptRoot '../configs/common.ps1')
    } else {
        Invoke-RestMethod 'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1' -ErrorAction Stop | Invoke-Expression
    }
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų."
    throw
}

# --- 2. INICIJUOJAME DARBĄ ---
$Setup = Initialize-Lab -ConfigDirectory $PSScriptRoot -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab01/Check-Lab1-config.json"

$GlobCfg = $Setup.GlobalConfig
$LocCfg  = $Setup.LocalConfig

# --- 3. TYLUS TIKRINIMAS (Atsparus klaidoms) ---

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
    $hasRole = Test-LabInstructorRole -Email $GlobCfg.InstructorEmail -RoleName $LocCfg.RoleToCheck -SubscriptionId $context.Subscription.Id
    if ($hasRole) {
        $res2Text = "[OK] - $($GlobCfg.InstructorEmail): $($LocCfg.RoleToCheck) prenumeratoje"
        $res2Color = 'Green'
    } else {
        $res2Text = "[KLAIDA] - $($GlobCfg.InstructorEmail) neturi tiesioginės '$($LocCfg.RoleToCheck)' rolės prenumeratoje"
        $res2Color = 'Red'
    }
} catch {
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