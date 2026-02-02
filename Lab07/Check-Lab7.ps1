# --- VERSIJOS KONTROLĖ ---
$ScriptVersion = "LAB 7 TIKRINIMAS: SQL & NoSQL (Final v4 - Fixed)"
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
    $rgName = $null
    $rgText = "[KLAIDA] - Nerasta grupė RG-LAB07..."
    $rgColor = "Red"
}
$resourceResults += [PSCustomObject]@{ Name = "Resursų grupė"; Text = $rgText; Color = $rgColor }

# B. SQL Serveris ir DB
$sqlServer = Get-AzSqlServer | Where-Object { $_.ResourceGroupName -match "RG-LAB07" } | Select-Object -First 1

if ($sqlServer) {
    # Randame vartotojo kurtą DB
    $db = Get-AzSqlDatabase -ServerName $sqlServer.ServerName -ResourceGroupName $sqlServer.ResourceGroupName | Where-Object { $_.DatabaseName -ne "master" } | Select-Object -First 1
    
    if ($db) {
        $dbText = "[OK] - SQL DB rasta ($($db.DatabaseName))"
        $dbColor = "Green"
        
        # 1. Geo-Replikacija (NAUDOJAME Get-AzResource, KAD NEPRAŠYTŲ INPUT)
        # Ieškome resursų, kurių tipas yra replicationLinks, priklausiančių šiam serveriui
        $allLinks = Get-AzResource -ResourceGroupName $sqlServer.ResourceGroupName -ResourceType "Microsoft.Sql/servers/databases/replicationLinks" -ErrorAction SilentlyContinue
        
        # Filtruojame pagal mūsų DB pavadinimą (ParentResource turi formatą: serveris/database)
        $dbLinks = $allLinks | Where-Object { $_.ParentResource -match "$($sqlServer.ServerName)/$($db.DatabaseName)" } | Select-Object -First 1

        if ($dbLinks) {
            # Partnerio serverio ID būna ilgas, pasiimame tik pavadinimą
            $repText = "[OK] - Geo-Replikacija aktyvi (Link: $($dbLinks.Name))"
            $repColor = "Green"
        } else {
            $repText = "[TRŪKSTA] - Nerasta Geo-Replikacija (Replicas)"
            $repColor = "Red"
        }

        # 2. Maskavimas (Data Masking)
        $masking = $null
        try {
            $masking = Get-AzSqlDatabaseDataMaskingRule -ServerName $sqlServer.ServerName -ResourceGroupName $sqlServer.ResourceGroupName -DatabaseName $db.DatabaseName -ErrorAction SilentlyContinue
        } catch {}

        if ($masking) {
            $maskCount = $masking.Count
            $maskText = "[OK] - Rasta maskavimo taisyklių: $maskCount"
            $maskColor = "Green"
        } else {
            $maskText = "[TRŪKSTA] - Nerastos Data Masking taisyklės"
            $maskColor = "Red"
        }

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
$cosmos = $null
if ($rgName) {
    $cosmos = Get-AzCosmosDBAccount -ResourceGroupName $rgName -ErrorAction SilentlyContinue
}
if (-not $cosmos) {
    $cosmos = Get-AzCosmosDBAccount | Where-Object { $_.ResourceGroupName -match "RG-LAB07" } | Select-Object -First 1
}

if ($cosmos) {
    # 1. Consistency (Pataisyta vieta: savybė yra ConsistencyPolicy viduje)
    $consLevel = $cosmos.ConsistencyPolicy.DefaultConsistencyLevel
    
    if ($consLevel -eq "Eventual") {
        $cosConText = "[OK] - Konsistencija: Eventual"
        $cosConColor = "Green"
    } else {
        $cosConText = "[INFO] - Konsistencija: $consLevel (Rekomenduota: Eventual)"
        $cosConColor = "Yellow"
    }
    
    # 2. Global Distribution
    $locCount = $cosmos.Locations.Count
    if ($locCount -ge 2) {
        $cosRegText = "[OK] - Globali replikacija aktyvi (Regionų: $locCount)"
        $cosRegColor = "Green"
    } else {
        $cosRegText = "[DĖMESIO] - Rasta tik 1 lokacija (Trūksta globalios replikacijos)"
        $cosRegColor = "Yellow"
    }
    
    $cosText = "[OK] - Cosmos DB paskyra rasta"
    $cosColor = "Green"

} else {
    $cosText = "[TRŪKSTA] - Nerasta Cosmos DB paskyra"
    $cosColor = "Red"
    $cosConText = "-"; $cosRegText = "-"
}

$resourceResults += [PSCustomObject]@{ Name = "Cosmos DB (NoSQL)"; Text = $cosText; Color = $cosColor }
if ($cosmos) {
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