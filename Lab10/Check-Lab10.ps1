# --- LANKYTOJŲ SEKLIO AUTOMATINIS TESTAVIMAS (v2 - Su skaičiavimu) ---
$ErrorActionPreference = "SilentlyContinue"

# 1. Konfigūracijos gavimas
$ConfigUrl = "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab10/Check-Lab10-config.json"

try {
    $Config = Invoke-RestMethod -Uri $ConfigUrl -ErrorAction Stop
    # Jei norite be emoji, galite tiesiog ištrinti 🕵️‍♂️ simbolį žemiau
    Write-Host "`n--- 🕵️‍♂️ PRADEDAMA PATIKRA: $($Config.LabName) ---`n" -ForegroundColor Cyan
} catch {
    Write-Host " [KRITINĖ KLAIDA] Nepavyko atsisiųsti konfigūracijos failo ($ConfigUrl)" -ForegroundColor Red
    return
}

# 2. Ieškome Resursų grupės
$rg = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like $Config.ResourceGroup.Pattern } | Select-Object -First 1

if ($rg) {
    Write-Host " [OK] Resursų grupė rasta: $($rg.ResourceGroupName)" -ForegroundColor Green
} else {
    Write-Host " [FAIL] Resursų grupė nerasta! (Turi atitikti '$($Config.ResourceGroup.Pattern)')" -ForegroundColor Red
    return
}

# 3. Ieškome Web App
$webApp = Get-AzWebApp -ResourceGroupName $rg.ResourceGroupName | Select-Object -First 1

if ($webApp) {
    Write-Host " [OK] Web App rasta: $($webApp.Name)" -ForegroundColor Green
    
    $url = "https://$($webApp.DefaultHostName)$($Config.WebApp.HealthEndpoint)"
    try {
        $request = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
        if ($request.StatusCode -eq $Config.WebApp.ExpectedStatus) {
            Write-Host " [OK] Svetainė veikia (Health Check: $($request.StatusCode))" -ForegroundColor Green
        } else {
            Write-Host " [FAIL] Svetainė grąžina klaidą: $($request.StatusCode)" -ForegroundColor Red
        }
    } catch {
        Write-Host " [FAIL] Svetainė nepasiekiama ($url)" -ForegroundColor Red
    }
} else {
    Write-Host " [FAIL] Web App nerasta!" -ForegroundColor Red
}

# 4. Ieškome Storage ir Konteinerio (SU SKAIČIAVIMU)
$storage = Get-AzStorageAccount -ResourceGroupName $rg.ResourceGroupName | Select-Object -First 1

if ($storage) {
    Write-Host " [OK] Storage Account rasta: $($storage.StorageAccountName)" -ForegroundColor Green
    
    $ctx = $storage.Context
    $share = Get-AzStorageShare -Name $Config.Storage.FileShareName -Context $ctx
    $container = Get-AzStorageContainer -Name $Config.Storage.BlobContainerName -Context $ctx

    if ($share) { 
        Write-Host " [OK] File Share '$($Config.Storage.FileShareName)' egzistuoja" -ForegroundColor Green 
    } else { 
        Write-Host " [FAIL] File Share '$($Config.Storage.FileShareName)' nerasta" -ForegroundColor Red 
    }

    if ($container) { 
        Write-Host " [OK] Blob Container '$($Config.Storage.BlobContainerName)' egzistuoja" -ForegroundColor Green 
        
        # --- NAUJA DALIS: Skaičiuojame failus ---
        $blobs = Get-AzStorageBlob -Container $Config.Storage.BlobContainerName -Context $ctx
        # @($blobs).Count užtikrina, kad veiks net jei failas tik 1 arba 0
        $count = @($blobs).Count 

        if ($count -gt 0) {
            Write-Host " [OK] 🏆 Archyve rasta failų: $count. Robotas veikia!" -ForegroundColor Yellow
        } else {
            Write-Host " [INFO] Archyvas tuščias (0 failų). (Robotas dar nespėjo suveikti arba nėra logų)" -ForegroundColor Gray
        }
    } else { 
        Write-Host " [FAIL] Blob Container '$($Config.Storage.BlobContainerName)' nerastas" -ForegroundColor Red 
    }

} else {
    Write-Host " [FAIL] Storage Account nerasta!" -ForegroundColor Red
}

# 5. Ieškome Function App
$funcApp = Get-AzFunctionApp -ResourceGroupName $rg.ResourceGroupName | Where-Object { $_.Kind -like "*functionapp*" } | Select-Object -First 1

if ($funcApp) {
    Write-Host " [OK] Function App rasta: $($funcApp.Name)" -ForegroundColor Green
    if ($funcApp.State -eq $Config.FunctionApp.RequiredState) {
         Write-Host " [OK] Funkcijos būsena: $($funcApp.State)" -ForegroundColor Green
    } else {
         Write-Host " [WARN] Funkcija sustabdyta! (Būsena: $($funcApp.State))" -ForegroundColor Yellow
    }
} else {
    Write-Host " [FAIL] Function App nerasta!" -ForegroundColor Red
}

Write-Host "`n--- PATIKRA BAIGTA ---" -ForegroundColor Cyan
