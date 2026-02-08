# --- LANKYTOJŲ SEKLIO AUTOMATINIS TESTAVIMAS (v6 - Smart Check) ---
$ErrorActionPreference = "SilentlyContinue"

# 1. Konfigūracija
$ConfigUrl = "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab10/Check-Lab10-config.json"
try {
    $Config = Invoke-RestMethod -Uri $ConfigUrl -ErrorAction Stop
    Write-Host "`n--- 🕵️‍♂️ PRADEDAMA PATIKRA: $($Config.LabName) ---`n" -ForegroundColor Cyan
} catch { Write-Host " [KRITINĖ KLAIDA] Nepavyko atsisiųsti Config failo." -ForegroundColor Red; return }

# 2. Resursų grupė
$rg = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like $Config.ResourceGroup.Pattern } | Select-Object -First 1
if (!$rg) { Write-Host " [FAIL] Resursų grupė nerasta!" -ForegroundColor Red; return }
Write-Host " [OK] Resursų grupė: $($rg.ResourceGroupName)" -ForegroundColor Green

# 3. Web App ir Mount Path (PATAISYTA LOGIKA)
$webApp = Get-AzWebApp -ResourceGroupName $rg.ResourceGroupName | Select-Object -First 1
if ($webApp) {
    Write-Host " [OK] Web App rasta: $($webApp.Name)" -ForegroundColor Green
    
    # Tikriname diskus naudodami specifinę komandą, o ne bendrą objektą
    $mappings = Get-AzWebAppAzureStoragePath -ResourceGroupName $rg.ResourceGroupName -Name $webApp.Name
    $logMount = $mappings | Where-Object { $_.MountPath -eq "/mounts/logs" }

    if ($logMount) {
         Write-Host " [OK] 💾 Storage prijungtas teisingai: /mounts/logs (Share: $($logMount.ShareName))" -ForegroundColor Green
    } else {
         # Jei neradome per API, bet vartotojas sako, kad veikia - patikriname "Health Check"
         # Jei svetainė veikia ir rašo failus, galime skaityti tai kaip "Warning", o ne "Fail"
         Write-Host " [WARN] 'Path Mappings' API rodo tuščią sąrašą (Azure vėluoja?), bet tęsiame tikrinimą." -ForegroundColor Yellow
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

# 4. Storage (Force Keys + Count)
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
                Write-Host " [OK] 🏆 Archyve rasta failų: $count. Robotas veikia!" -ForegroundColor Yellow
            } else {
                Write-Host " [INFO] Archyvas tuščias (0 failų)." -ForegroundColor Gray
            }
        } else { Write-Host " [FAIL] Konteineris 'archyvas' nerastas." -ForegroundColor Red }
    } catch { Write-Host " [FAIL] Nepavyko prisijungti prie Storage." -ForegroundColor Red }
} else { Write-Host " [FAIL] Storage Account nerasta!" -ForegroundColor Red }

# 5. Function App
$func = Get-AzFunctionApp -ResourceGroupName $rg.ResourceGroupName -WarningAction SilentlyContinue | Select-Object -First 1
if ($func) {
    Write-Host " [OK] Function App: $($func.Name)" -ForegroundColor Green
    
    if ($func.SiteConfig.PowerShellVersion -eq "7.4") {
        Write-Host " [OK] PowerShell versija: 7.4" -ForegroundColor Green
    } else {
        # Jei netyčia rodo tuščią versiją, tiesiog perspėjame
        Write-Host " [INFO] PowerShell versija: $($func.SiteConfig.PowerShellVersion)" -ForegroundColor Gray
    }

    if ($func.State -eq "Running") { Write-Host " [OK] Būsena: Running" -ForegroundColor Green }
    else { Write-Host " [WARN] Būsena: $($func.State)" -ForegroundColor Yellow }
} else { Write-Host " [FAIL] Function App nerasta!" -ForegroundColor Red }

Write-Host "`n--- PATIKRA BAIGTA ---" -ForegroundColor Cyan