# --- NUSTATYMAI ---
$destytojoEmail = "Mantas.Bartkevicius@kaunokolegija.lt"
$ataskaitosFailas = "Lab1_Rezultatas.txt"

# Priverstinis TLS 1.2 protokolas (saugumo reikalavimas atsisiuntimui)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Clear-Host
Write-Host "--- 1 Laboratorinio darbo patikra (Azure) ---" -ForegroundColor Cyan
Write-Host "Vykdoma konfigūracijos analizė..." -ForegroundColor Gray

# 1. Tikriname prenumeratos pavadinimą
$context = Get-AzContext
if (-not $context) {
    Write-Error "Neprisijungta prie Azure! Prašome perkrauti Cloud Shell."
    exit
}
$subName = $context.Subscription.Name
# Regex: Tikrina ar yra formatas "Tekstas-Tekstas-Tekstas" (pvz. PI23-Jonas-Jonaitis)
$isNameCorrect = $subName -match "^[A-Za-z0-9ĄČĘĖĮŠŲŪŽąčęėįšųūž]+-[A-Za-z0-9ĄČĘĖĮŠŲŪŽąčęėįšųūž]+-[A-Za-z0-9ĄČĘĖĮŠŲŪŽąčęėįšųūž]+" 

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
$studentEmail = $context.Account.Id

$report = @"
==================================================
KAUNO KOLEGIJA | AZURE LAB 1 ATASKAITA
Data: $date
Studentas: $studentEmail
==================================================
1. Prenumeratos pavadinimas: $res1
2. Dėstytojo prieiga:        $res2
==================================================
"@

# Išvedimas
Write-Host "`n--- GALUTINIS REZULTATAS ---" -ForegroundColor Cyan
Write-Host $report
$report | Out-File $ataskaitosFailas -Encoding UTF8

Write-Host "`nAtaskaita sugeneruota faile: $ataskaitosFailas" -ForegroundColor Magenta
Write-Host "Atsisiųskite failą su komanda: download $ataskaitosFailas" -ForegroundColor White