# --- VERSIJOS KONTROLĖ ---
$ScriptVersion = "LAB 7 TIKRINIMAS: SQL & NoSQL (v6 - Silent Mode)"
Clear-Host
Write-Host "--------------------------------------------------"
Write-Host $ScriptVersion -ForegroundColor Magenta
Write-Host "Vykdoma duomenų bazių konfigūracijos patikra..."
Write-Host "--------------------------------------------------"

# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
$ConfigUrl = "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab07/Check-Lab7-config.json"
try {
    $Setup = Initialize-Lab -LocalConfigUrl $ConfigUrl
    $LocCfg = $Setup.LocalConfig
} catch {
    $LocCfg = @{ LabName = "Azure Databases" }
}

$CurrentIdentity = az ad signed-in-user show --query userPrincipalName -o tsv
if (-not $CurrentIdentity) { $CurrentIdentity = "Studentas" }

# --- 3. DUOMENŲ RINKIMAS ---
$resourceResults = @()

# A. Resursų Grupė
$labRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match "RG-LAB07" } | Select-Object -First 1

if ($labRG) {
    $rgName = $labRG.ResourceGroupName
    $rgText = "[OK] - Rasta grupė ($rgName)"
    $rgColor = "Green"
} else {
    $rgName = ""
    $rgText = "[KLAIDA] - Nerasta grupė RG-LAB07..."
    $rgColor = "Red"
}
$resourceResults += [PSCustomObject]@{ Name = "Resursų grupė"; Text = $rgText; Color = $rgColor }

# B. SQL Serveris ir DB
$sqlServer = $null
if ($rgName) {
    $sqlServer = Get-AzSqlServer -ResourceGroupName $rgName -ErrorAction SilentlyContinue | Select-Object -First 1
}

if ($sqlServer) {
    # Randame vartotojo kurtą DB
    $db = Get-AzSqlDatabase -ServerName $sqlServer.ServerName -ResourceGroupName $sqlServer.ResourceGroupName | Where-Object { $_.DatabaseName -ne "master" } | Select-Object -First 1
    
    if ($db) {
        $dbText = "[OK] - SQL DB rasta ($($db.DatabaseName))"
        $dbColor = "Green"
        
        # 1. Geo-Replikacija (Naudojame universalų Get-AzResource)
        $repText = "[TRŪKSTA] - Nerasta Geo-Replikacija"
        $repColor = "Red"
        
        # Ieškome visų replikacijos nuorodų šiame serveryje
        $allLinks = Get-AzResource -ResourceGroupName $sqlServer.ResourceGroupName -ResourceType "Microsoft.Sql/servers/databases/replicationLinks" -ErrorAction SilentlyContinue
        if ($allLinks) {
            # Jei radome bent vieną nuorodą, kuri priklauso mūsų DB
            $dbLink = $allLinks | Where-Object { $_.ParentResource -match $db.DatabaseName } | Select-Object -First 1
            if ($dbLink) {
                $repText = "[OK] - Geo-Replikacija aktyvi"
                $repColor = "Green"
            }
        }

        # 2. Maskavimas (Data Masking)
        $maskText = "[TRŪKSTA] - Nerastos Data Masking taisyklės"
        $maskColor = "Red"
        
        # Bandome gauti taisykles tyliai
        try {
            if ($db) {
                $rules = Get-AzSqlDatabaseDataMaskingRule -ServerName $sqlServer.ServerName -ResourceGroupName $sqlServer.ResourceGroupName -DatabaseName $db.DatabaseName -ErrorAction SilentlyContinue
                if ($rules -and $rules.Count -gt 0) {
                    $maskText = "[OK] - Rasta maskavimo taisyklių: $($rules.Count)"
                    $maskColor = "Green"
                }
            }
        } catch {}

    } else {
        $dbText = "[KLAIDA] - SQL Serveris yra, bet duomenų bazės nėra"
        $dbColor = "Red"
        $repText = "-"; $maskText = "-"
    }
} else {
    $dbText = "[TRŪKSTA] - Nerastas SQL Serveris"
    $dbColor = "Red"
    $repText = "-"; $maskText = "-"
}

$resourceResults += [PSCustomObject]@{ Name = "SQL Duomenų bazė"; Text = $dbText; Color = $dbColor }
if ($repText -ne "-") { $resourceResults += [PSCustomObject]@{ Name = "Geo-Replikacija"; Text = $repText; Color = $repColor } }
if ($maskText -ne "-") { $resourceResults += [PSCustomObject]@{ Name = "Data Masking"; Text = $maskText; Color = $maskColor } }


# C. Cosmos DB
$cosText = "[TRŪKSTA] - Nerasta Cosmos DB paskyra"
$cosColor = "Red"
$cosConText = "-"; $cosRegText = "-"
$cosmosObj = $null

# 1. Ieškome per universalų Get-AzResource (niekada neprašo parametrų)
if ($rgName) {
    $cosmosRes = Get-AzResource -ResourceGroupName $rgName -ResourceType "Microsoft.DocumentDB/databaseAccounts" -ErrorAction SilentlyContinue | Select-Object -First 1
    
    if ($cosmosRes) {
        $cosText = "[OK] - Cosmos DB paskyra rasta ($($cosmosRes.Name))"
        $cosColor = "Green"
        
        # 2. Bandome gauti detalesnį objektą (tik kai jau žinome vardą)
        try {
            $cosmosObj = Get-AzCosmosDBAccount -ResourceGroupName $rgName -Name $cosmosRes.Name -ErrorAction SilentlyContinue
        } catch {}
    }
}

if ($cosmosObj) {
    # 3. Tikriname Consistency
    $consLevel = $cosmosObj.ConsistencyPolicy.DefaultConsistencyLevel
    if ($consLevel -eq "Eventual") {
        $cosConText = "[OK] - Konsistencija: Eventual"
        $cosConColor = "Green"
    } else {
        $cosConText = "[INFO] - Konsistencija: $consLevel"
        $cosConColor = "Yellow"
    }
    
    # 4. Tikriname Regionus
    $locCount = $cosmosObj.Locations.Count
    if ($locCount -ge 2) {
        $cosRegText = "[OK] - Globali replikacija aktyvi (Regionų: $locCount)"
        $cosRegColor = "Green"
    } else {
        $cosRegText = "[DĖMESIO] - Rasta tik 1 lokacija"
        $cosRegColor = "Yellow"
    }
} elseif ($cosmosRes) {
    # Jei radome resursą, bet nepavyko gauti detalių (pvz. teisių problema), vis tiek užskaitome egzistavimą
    $cosConText = "[INFO] - Nepavyko nuskaityti nustatymų"
    $cosConColor = "Gray"
    $cosRegText = "[INFO] - Nepavyko nuskaityti regionų"
    $cosRegColor = "Gray"
}

$resourceResults += [PSCustomObject]@{ Name = "Cosmos DB (NoSQL)"; Text = $cosText; Color = $cosColor }
if ($cosColor -eq "Green") {
    $resourceResults += [PSCustomObject]@{ Name = " - Replikacija"; Text = $cosRegText; Color = $cosRegColor }
    $resourceResults += [PSCustomObject]@{ Name = " - Konsistencija"; Text = $cosConText; Color = $cosConColor }
}

# --- 4. IŠVEDIMAS ---
$date = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host "`n--- GALUTINIS REZULTATAS (Padarykite nuotrauką) ---" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Gray
if ($Setup.HeaderTitle) { Write-Host "$($Setup.HeaderTitle)" }
Write-Host "$($LocCfg.LabName)" -ForegroundColor Yellow
Write-Host "Data: $date"
Write-Host "Studentas: $CurrentIdentity"
Write-Host "==================================================" -ForegroundColor Gray

foreach ($res in $resourceResults) {
    $label = "$($res.Name):"
    $targetWidth = 35
    $neededSpaces = $targetWidth - $label.Length
    if ($neededSpaces -lt 1) { $neededSpaces = 1 }
    $padding = " " * $neededSpaces
    Write-Host "$label$padding" -NoNewline
    Write-Host $res.Text -ForegroundColor $res.Color
}
Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""