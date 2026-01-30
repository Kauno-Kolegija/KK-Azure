# Lab02/Check-Lab2.ps1

# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
# Atsisiunčiame ir įvykdome common.ps1, kad gautume funkciją 'Initialize-Lab'
irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex

# --- 2. INICIJUOJAME DARBĄ ---
# Ši viena eilutė padaro viską: parsiunčia configus, randa studentą, išvalo ekraną
$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab02/Check-Lab2-config.json"

# Išsiimame kintamuosius patogiam naudojimui
$LocCfg = $Setup.LocalConfig
$GlobCfg = $Setup.GlobalConfig

# --- 3. SPECIFINĖ LAB 2 PATIKRA ---
# Čia rašote tik tai, kas unikalu šiam darbui

# A. Randame Resursų grupę
$targetRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match $LocCfg.ResourceGroupPattern } | Select-Object -First 1

if ($targetRG) {
    Write-Host "1. Resursų grupė:" -NoNewline
    Write-Host " RASTA ($($targetRG.ResourceGroupName))" -ForegroundColor Green
    $rgStatus = "OK ($($targetRG.ResourceGroupName))"
} else {
    Write-Host "1. Resursų grupė:" -NoNewline
    Write-Host " NERASTA" -ForegroundColor Red
    $rgStatus = "NERASTA"
}

# B. Tikriname resursus (jei grupė yra)
$resReport = ""
if ($targetRG) {
    $allResources = Get-AzResource -ResourceGroupName $targetRG.ResourceGroupName
    foreach ($req in $LocCfg.RequiredResources) {
        $found = $allResources | Where-Object { $_.ResourceType -eq $req.Type } | Select-Object -First 1
        Write-Host "2. $($req.Name):" -NoNewline
        
        if ($found) {
            Write-Host " RASTA" -ForegroundColor Green
            $resReport += "$($req.Name): OK`n"
        } else {
            Write-Host " NERASTA" -ForegroundColor Red
            $resReport += "$($req.Name): TRŪKSTA`n"
        }
    }
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
1. Resursų grupė: $rgStatus
--------------------------------------------------
$resReport
==================================================
"@

Write-Host "`n--- GALUTINIS REZULTATAS ---" -ForegroundColor Cyan
Write-Host $report