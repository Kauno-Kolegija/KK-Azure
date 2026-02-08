# --- LANKYTOJŲ SEKLIO AUTOMATINIS TESTAVIMAS (v5 - Deep Check) ---
$ErrorActionPreference = "SilentlyContinue"

# 1. Konfigūracija
$ConfigUrl = "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab10/Check-Lab10-config.json"
try {
    $Config = Invoke-RestMethod -Uri $ConfigUrl -ErrorAction Stop
    Write-Host "`n--- PRADEDAMA PATIKRA: $($Config.LabName) ---`n" -ForegroundColor Cyan
} catch { Write-Host " [KRITINĖ KLAIDA] Nepavyko atsisiųsti Config failo." -ForegroundColor Red; return }

# 2. Resursų grupė
$rg = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like $Config.ResourceGroup.Pattern } | Select-Object -First 1
if (!$rg) { Write-Host " [FAIL] Resursų grupė nerasta! (Turi atitikti '$($Config.ResourceGroup.Pattern)')" -ForegroundColor Red; return }
Write-Host " [OK] Resursų grupė: $($rg.ResourceGroupName)" -ForegroundColor Green

# 3. App Service Plan (NAUJA: Tikriname kainodaros lygį)
$plan = Get-AzAppServicePlan -ResourceGroupName $rg.ResourceGroupName | Select-Object -First 1
if ($plan) {
    if ($plan.Sku.Tier -in @("Free", "Basic")) {
        Write-Host " [OK] App Planas tinkamas: $($plan.Sku.Name) ($($plan.Sku.Tier))" -ForegroundColor Green
    } else {
        Write-Host " [WARN] App Planas brangus! Pasirinkta: $($plan.Sku.Tier). Rekomenduojama F1/B1." -ForegroundColor Yellow
    }
}

# 4. Web App ir Mount Path (NAUJA: Tikriname ar diskas prijungtas)
$webApp = Get-AzWebApp -ResourceGroupName $rg.ResourceGroupName | Select-Object -First 1
if ($webApp) {
    Write-Host " [OK] Web App rasta: $($webApp.Name)" -ForegroundColor Green
    
    # Tikriname Mount Path
    $storageMount = $webApp.SiteConfig.AzureStorageAccounts
    if ($storageMount -and ($storageMount.GetEnumerator() | Where-Object { $_.Value.MountPath -eq "/mounts/logs" })) {
         Write-Host " [OK] Storage prijungtas teisingai: /mounts/logs" -ForegroundColor Green
    } else {
         Write-Host " [FAIL] Web App neturi prijungto disko '/mounts/logs'!" -ForegroundColor Red
    }

    # Health Check
    $url = "https://$($webApp.DefaultHostName)$($Config.WebApp.HealthEndpoint)"
    try {
        $req = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
        if ($req.StatusCode -eq $Config.WebApp.ExpectedStatus) {
            Write-Host " [OK] Svetainė veikia (200 OK)" -ForegroundColor Green
        } else { Write-Host " [FAIL] Svetainė klaidų būsenoje: $($req.StatusCode)" -ForegroundColor Red }
    } catch { Write-Host " [FAIL] Svetainė nepasiekiama" -ForegroundColor Red }
} else { Write-Host " [FAIL] Web App nerasta!" -ForegroundColor Red }

# 5. Storage (Raktai + Skaičiavimas)
$storage = Get-AzStorageAccount -ResourceGroupName $rg.ResourceGroupName | Select-Object -First 1
if ($storage) {
    try {
        $keys = Get-AzStorageAccountKey -ResourceGroupName $rg.ResourceGroupName -Name $storage.StorageAccountName -ErrorAction Stop
        $ctx = New-AzStorageContext -StorageAccountName $storage.StorageAccountName -StorageAccountKey $keys[0].Value
        
        $share = Get-AzStorageShare -Name $Config.Storage.FileShareName -Context $ctx
        if ($share) { Write-Host " [OK] File Share '$($Config.Storage.FileShareName)' yra." -ForegroundColor Green }
        else { Write-Host " [FAIL] File Share nerasta." -ForegroundColor Red }

        $container = Get-AzStorageContainer -Name $Config.Storage.BlobContainerName -Context $ctx
        if ($container) {
            $blobs = Get-AzStorageBlob -Container $Config.Storage.BlobContainerName -Context $ctx
            $count = @($blobs).Count
            if ($count -gt 0) {
                Write-Host " [OK] 🏆 Archyve rasta failų: $count. Robotas veikia!" -ForegroundColor Green -NoNewline
                Write-Host "  $count." -ForegroundColor Yellow -NoNewline
                Write-Host "  Robotas veikia!" -ForegroundColor Green
            } else {
                Write-Host " [INFO] Archyvas tuščias (0 failų)." -ForegroundColor Gray
            }
        } else { Write-Host " [FAIL] Konteineris 'archyvas' nerastas." -ForegroundColor Red }
    } catch { Write-Host " [FAIL] Nepavyko prisijungti prie Storage." -ForegroundColor Red }
} else { Write-Host " [FAIL] Storage Account nerasta!" -ForegroundColor Red }

# 6. Function App (NAUJA: Tikriname PowerShell versiją)
$func = Get-AzFunctionApp -ResourceGroupName $rg.ResourceGroupName -WarningAction SilentlyContinue | Select-Object -First 1
if ($func) {
    Write-Host " [OK] Function App: $($func.Name)" -ForegroundColor Green
    
    # Versijos tikrinimas
    if ($func.SiteConfig.PowerShellVersion -eq "7.4") {
        Write-Host " [OK] PowerShell versija: 7.4 (Teisinga)" -ForegroundColor Green
    } else {
        Write-Host " [WARN] Neteisinga PowerShell versija: $($func.SiteConfig.PowerShellVersion). Reikėjo 7.4." -ForegroundColor Yellow
    }

    if ($func.State -eq "Running") { Write-Host " [OK] Būsena: Running" -ForegroundColor Green }
    else { Write-Host " [WARN] Būsena: $($func.State)" -ForegroundColor Yellow }
} else { Write-Host " [FAIL] Function App nerasta!" -ForegroundColor Red }

Write-Host "`n--- PATIKRA BAIGTA ---" -ForegroundColor Cyan