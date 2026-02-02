# --- VERSIJOS KONTROLĖ ---
$ScriptVersion = "LAB 7 TIKRINIMAS: SQL & NoSQL (v10 - Universal Scan) "
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
        
        # 1. Geo-Replikacija (Metodas: Ieškome bet kokių replikacijos objektų grupėje)
        $repText = "[TRŪKSTA] - Nerasta Geo-Replikacija"
        $repColor = "Red"
        
        # Skenuojame visus resursus grupėje
        $allResources = Get-AzResource -ResourceGroupName $rgName -ErrorAction SilentlyContinue
        
        # Ieškome resurso, kurio tipas yra replicationLinks
        $linkFound = $allResources | Where-Object { $_.ResourceType -eq "Microsoft.Sql/servers/databases/replicationLinks" } | Select-Object -First 1
        
        if ($linkFound) {
            $repText = "[OK] - Geo-Replikacija aktyvi"
            $repColor = "Green"
        }

        # 2. Maskavimas (Data Masking)
        $maskText = "[TRŪKSTA] - Nerastos Data Masking taisyklės"
        $maskColor = "Red"
        
        try {
            $rules = Get-AzSqlDatabaseDataMaskingRule -ServerName $sqlServer.ServerName -ResourceGroupName $sqlServer.ResourceGroupName -DatabaseName $db.DatabaseName -ErrorAction SilentlyContinue
            if ($rules -and $rules.Count -gt 0) {
                $maskText = "[OK] - Rasta maskavimo taisyklių: $($rules.Count)"
                $maskColor = "Green"
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


# C. Cosmos DB (Smart Loop)
$cosText = "[TRŪKSTA] - Nerasta Cosmos DB paskyra"
$cosColor = "Red"
$cosConText = "-"; $cosRegText = "-"
$bestCosmosFound = $false

if ($rgName) {
    # Gauname VISAS Cosmos DB paskyras grupėje
    $allCosmos = Get-AzCosmosDBAccount -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    
    foreach ($cosmosCandidate in $allCosmos) {
        # Tikriname kiekvieną paskyrą - ieškome tos, kuri turi daugiau nei 1 regioną
        $tempLocCount = $cosmosCandidate.Locations.Count
        
        if ($tempLocCount -ge 2) {
            $cosmosObj = $cosmosCandidate
            $bestCosmosFound = $true
            break 
        }
    }
    
    # Jei neradome geros, imame bet kurią
    if (-not $bestCosmosFound -and $allCosmos) {
        $cosmosObj = $allCosmos | Select-Object -First 1
    }
}

if ($cosmosObj) {
    $cosText = "[OK] - Cosmos DB paskyra rasta ($($cosmosObj.Name))"
    $cosColor = "Green"

    # 3. Tikriname Consistency
    $consLevel = $cosmosObj.ConsistencyPolicy.DefaultConsistencyLevel
    if ($consLevel -eq "Eventual") {
        $cosConText = "[OK] - Konsistencija: Eventual"
        $cosConColor = "Green"
    } else {
        $cosConText = "[INFO] - Konsistencija: $consLevel (Rekomenduota: Eventual)"
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