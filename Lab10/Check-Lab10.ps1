# --- LANKYTOJŲ SEKLIO AUTOMATINIS TESTAVIMAS (v7 - App Type Fix) ---
if ($PSScriptRoot) {
    . (Join-Path $PSScriptRoot '../configs/common.ps1')
} else {
    Invoke-RestMethod 'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1' -ErrorAction Stop | Invoke-Expression
}

# 1. Konfigūracija
$ConfigUrl = "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab10/Check-Lab10-config.json"
try {
    $Setup = Initialize-Lab -ConfigDirectory $PSScriptRoot -LocalConfigUrl $ConfigUrl
    $Config = $Setup.LocalConfig
    Write-Host "`n--- PRADEDAMA PATIKRA: $($Config.LabName) ---`n" -ForegroundColor Cyan
} catch { Write-Host " [KRITINĖ KLAIDA] Nepavyko atsisiųsti Config failo." -ForegroundColor Red; return }

# 2. Resursų grupė
$rg = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like $Config.ResourceGroup.Pattern } | Select-Object -First 1
if (!$rg) { Write-Host " [FAIL] Resursų grupė nerasta!" -ForegroundColor Red; return }
Write-Host " [OK] Resursų grupė: $($rg.ResourceGroupName)" -ForegroundColor Green

# 3. App Service Plan
$plan = Get-AzAppServicePlan -ResourceGroupName $rg.ResourceGroupName | Select-Object -First 1
if ($plan) {
    if ($plan.Sku.Tier -in @("Free", "Basic")) {
        Write-Host " [OK] App Planas tinkamas: $($plan.Sku.Name) ($($plan.Sku.Tier))" -ForegroundColor Green
    } else {
        Write-Host " [WARN] App Planas brangus! Pasirinkta: $($plan.Sku.Tier). Rekomenduojama F1/B1." -ForegroundColor Yellow
    }
} else { Write-Host ' [FAIL] App Service planas nerastas.' -ForegroundColor Red }

# 4. Web App (PATAISYMAS: Atmetame Function Apps)
# Ieškome tikros Web App, ignoruodami "functionapp" tipą
$webApp = Get-AzWebApp -ResourceGroupName $rg.ResourceGroupName | Where-Object { $_.Kind -notlike "*functionapp*" } | Select-Object -First 1

if ($webApp) {
    Write-Host " [OK] Web App rasta: $($webApp.Name)" -ForegroundColor Green
    
    # Tikriname Mount Path (Tik jei API grąžina sėkmę - parodome)
    $mappings = Get-AzWebAppAzureStoragePath -ResourceGroupName $rg.ResourceGroupName -Name $webApp.Name
    $logMount = $mappings | Where-Object { $_.MountPath -eq "/mounts/logs" }

    if ($logMount) {
         Write-Host " [OK] Storage prijungtas teisingai: /mounts/logs" -ForegroundColor Green
    } else { Write-Host ' [FAIL] Nerastas /mounts/logs Storage prijungimas.' -ForegroundColor Red }

    # Health Check
    $url = "https://$($webApp.DefaultHostName)$($Config.WebApp.HealthEndpoint)"
    try {
        $req = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        if ($req.StatusCode -eq $Config.WebApp.ExpectedStatus) {
            Write-Host " [OK] Svetainė veikia (200 OK)" -ForegroundColor Green
        } else { Write-Host " [FAIL] Svetainė klaidų būsenoje: $($req.StatusCode)" -ForegroundColor Red }
    } catch { Write-Host " [FAIL] Svetainė nepasiekiama" -ForegroundColor Red }
} else { Write-Host " [FAIL] Web App nerasta!" -ForegroundColor Red }

# 5. Storage (Force Keys + Count)
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
                Write-Host " [OK] 🏆  Archyve rasta failų:" -ForegroundColor Green -NoNewline
                Write-Host " $count" -ForegroundColor Yellow -NoNewline
                Write-Host '. Failų buvimas nepatvirtina automatinio perkėlimo.' -ForegroundColor Gray
            } else {
                Write-Host " [INFO] Archyvas tuščias (0 failų)." -ForegroundColor Gray
            }
        } else { Write-Host " [FAIL] Konteineris 'archyvas' nerastas." -ForegroundColor Red }
    } catch { Write-Host " [FAIL] Nepavyko prisijungti prie Storage." -ForegroundColor Red }
} else { Write-Host " [FAIL] Storage Account nerasta!" -ForegroundColor Red }

# 6. Function App
$func = Get-AzFunctionApp -ResourceGroupName $rg.ResourceGroupName -WarningAction SilentlyContinue | Select-Object -First 1
if ($func) {
    Write-Host " [OK] Function App: $($func.Name)" -ForegroundColor Green
    
    if ($func.SiteConfig.PowerShellVersion -eq "7.4") {
        Write-Host " [OK] PowerShell versija: 7.4" -ForegroundColor Green
    } else {
        Write-Host " [INFO] PowerShell versija: $($func.SiteConfig.PowerShellVersion)" -ForegroundColor Gray
    }

    if ($func.State -eq $Config.FunctionApp.RequiredState) { Write-Host " [OK] Būsena: $($func.State)" -ForegroundColor Green }
    else { Write-Host " [WARN] Būsena: $($func.State)" -ForegroundColor Yellow }
} else { Write-Host " [FAIL] Function App nerasta!" -ForegroundColor Red }

Write-Host "`n--- PATIKRA BAIGTA ---" -ForegroundColor Cyan
