# --- KONFIGŪRACIJOS GAVIMAS ---
$configUrl = "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab01/Check-Lab1-config.json"

# Priverstinis TLS 1.2 protokolas (saugumo reikalavimas atsisiuntimui)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

try {
    # Atsisiunčiame ir konvertuojame JSON į PowerShell objektą
    $config = Invoke-RestMethod -Uri $configUrl -ErrorAction Stop
} catch {
    Write-Error "Nepavyko atsisiųsti laboratorinio darbo konfigūracijos. Patikrinkite interneto ryšį."
    exit
}

# --- NAUDOJAME KINTAMUOSIUS IŠ FAILO ---
$destytojoEmail = $config.InstructorEmail
$regexPattern = $config.NamingPattern
$university = $config.KaunoKolegija
$moduleName = $config.ModuleName
$labTitle = $config.LabName

Clear-Host
Write-Host "--- $labTitle ---" -ForegroundColor Cyan
Write-Host "Vykdoma konfigūracijos analizė..." -ForegroundColor Gray

# 1. Tikriname prenumeratos pavadinimą
$context = Get-AzContext
if (-not $context) {
    Write-Error "Neprisijungta prie Azure! Prašome perkrauti Cloud Shell."
    exit
}
$subName = $context.Subscription.Name
# Regex: Tikrina ar yra formatas pagal konfigūraciją
$isNameCorrect = $subName -match $regexPattern

Write-Host "`n1. Prenumeratos pavadinimas: $subName" -NoNewline
if ($isNameCorrect) {
    Write-Host " [OK]" -ForegroundColor Green
    $res1 = "TEISINGAS ($subName)"
} else {
    Write-Host " [NETINKAMAS FORMATAS]" -ForegroundColor Red
    Write-Host "   -> Reikalaujama: Grupė-Vardas-Pavardė (pvz. PI23-Jonas-Jonaitis)" -ForegroundColor Yellow
    $res1 = "NETEISINGAS ($subName)"
}

# 2. Tikriname dėstytojo teises
Write-Host "`n2. Ieškoma vartotojo ($destytojoEmail) teisių..." -NoNewline
try {
    # Ieškome specifinės rolės priskyrimo
    $assignments = Get-AzRoleAssignment -IncludeClassicAdministrators -ErrorAction SilentlyContinue
    $destytojoRole = $assignments | Where-Object { $_.SignInName -eq $destytojoEmail -or $_.DisplayName -match "Mantas Bartkevičius" }
    
    if ($destytojoRole) {
        # Tikriname ar rolė yra Contributor
        if ($destytojoRole.RoleDefinitionName -eq "Contributor") {
            Write-Host " [OK]" -ForegroundColor Green
            $res2 = "PRISKIRTA (Contributor)"
        } else {
            Write-Host " [RASTA KITA ROLĖ: $($destytojoRole.RoleDefinitionName)]" -ForegroundColor Yellow
            $res2 = "NETINKAMA ROLĖ ($($destytojoRole.RoleDefinitionName))"
        }
    } else {
        Write-Host " [NERASTA]" -ForegroundColor Red
        $res2 = "VARTOTOJAS NERASTAS ARBA NĖRA TEISIŲ"
    }
} catch {
    Write-Host " [KLAIDA]" -ForegroundColor Red
    $res2 = "KLAIDA TIKRINANT ($($_.Exception.Message))"
}

# --- REZULTATŲ GENERAVIMAS ---
$date = Get-Date -Format "yyyy-MM-dd HH:mm"
$studentEmail = $null

# 1 BŪDAS: Tikriname specialų Cloud Shell aplinkos kintamąjį (Patikimiausias)
if ($env:ACC_USER_NAME -and $env:ACC_USER_NAME -match "@") {
    $studentEmail = $env:ACC_USER_NAME
}

# 2 BŪDAS: Jei kintamojo nėra, bandome per Azure CLI (User Name)
if (-not $studentEmail) {
    try {
        $cliUser = az account show --query "user.name" -o tsv 2>$null
        if ($cliUser -and $cliUser -match "@" -and $cliUser -notmatch "MSI@") {
            $studentEmail = $cliUser
        }
    } catch {}
}

# 3 BŪDAS: Jei vis tiek tuščia, imame Context ID (Techninis/MSI)
if (-not $studentEmail) {
    $studentEmail = "$($context.Account.Id) (Cloud Shell Identity)"
}

$report = @"
==================================================
$university | $moduleName 
$labTitle
Data: $date
Studentas: $studentEmail
==================================================
1. Prenumeratos pavadinimas: $res1
2. Dėstytojo prieiga:        $res2
==================================================
"@

# Išvedimas tik į ekraną
Write-Host "`n--- GALUTINIS REZULTATAS (Padarykite ekrano nuotrauką) ---" -ForegroundColor Cyan
Write-Host $report
Write-Host ""