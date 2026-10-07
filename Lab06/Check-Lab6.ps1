# ============================================================
# LAB 6 CHECKER - STORAGE SERVICES
# ============================================================

# --- Užkrauname bendras funkcijas ---
try {
    if ($PSScriptRoot) {
        . (Join-Path $PSScriptRoot '../configs/common.ps1')
    } else {
        Invoke-RestMethod 'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1' -ErrorAction Stop | Invoke-Expression
    }
} catch {
    Write-Error "Failed to load common functions."
    throw
}

# --- Kalba ---
if ($Lang -notin @("LT", "EN")) { $Lang = "LT" }

# --- Inicializacija ---
$Setup = Initialize-Lab `
    -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab06/Check-Lab6-config.json" `
    -Lang $Lang

$LocCfg  = $Setup.LocalConfig
$Check   = $LocCfg.Checks
$LabMsg  = $LocCfg.Messages
$Msg     = $Setup.Messages
$LabName = $LocCfg.LabName.$Lang

$OkStatus    = $Msg.Ok
$ErrorStatus = $Msg.Error

$results = @()

function Add-Result {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Color = "White"
    )

    $script:results += [PSCustomObject]@{
        Name  = $Name
        Text  = $Text
        Color = $Color
    }
}

# ============================================================
# 1. RESOURCE GROUP
# ============================================================

$targetRG = Get-AzResourceGroup -ErrorAction SilentlyContinue |
    Where-Object ResourceGroupName -Match $LocCfg.ResourceGroup.Pattern |
    Select-Object -First 1

if ($targetRG) {
    Add-Result $Check.ResourceGroup.$Lang `
        "[$OkStatus] - $($LabMsg.Found.$Lang) $($targetRG.ResourceGroupName)" `
        "Green"
} else {
    Add-Result $Check.ResourceGroup.$Lang `
        "[$ErrorStatus] - $($LabMsg.MainRgMissing.$Lang)" `
        "Red"
}

$storage = $null

if ($targetRG) {
    $storage = Get-AzStorageAccount -ResourceGroupName $targetRG.ResourceGroupName -ErrorAction SilentlyContinue |
        Where-Object StorageAccountName -Match $LocCfg.StorageAccount.NamePattern |
        Select-Object -First 1
}

# ============================================================
# 2. STORAGE ACCOUNT
# ============================================================

if ($storage) {
    Add-Result $Check.StorageAccount.$Lang `
        "[$OkStatus] - $($LabMsg.Found.$Lang) $($storage.StorageAccountName)" `
        "Green"
} else {
    Add-Result $Check.StorageAccount.$Lang `
        "[$ErrorStatus] - $($LabMsg.StorageMissing.$Lang)" `
        "Red"
}

if ($storage) {

    $storageName = $storage.StorageAccountName
    $rgName = $targetRG.ResourceGroupName

    # ========================================================
    # 3. STORAGE CONFIGURATION
    # ========================================================

    $skuOk = $storage.Sku.Name -eq $LocCfg.StorageAccount.Sku
    $tierOk = $storage.AccessTier -eq $LocCfg.StorageAccount.AccessTier
    $storageConfigOk = $skuOk -and $tierOk

    if ($storageConfigOk) {
        Add-Result $Check.StorageConfig.$Lang `
            "[$OkStatus] - $($storage.Sku.Name) + $($storage.AccessTier)" `
            "Green"
    } else {
        Add-Result $Check.StorageConfig.$Lang `
            "[$ErrorStatus] - $($LabMsg.StorageConfigBad.$Lang) (SKU=$($storage.Sku.Name), Tier=$($storage.AccessTier))" `
            "Red"
    }

    # ========================================================
    # 4. DATA PROTECTION
    # Management plane - Storage firewall netrukdo.
    # ========================================================

    try {
        $blobProps = Get-AzStorageBlobServiceProperty `
            -ResourceGroupName $rgName `
            -StorageAccountName $storageName `
            -ErrorAction Stop

        $fileProps = Get-AzStorageFileServiceProperty `
            -ResourceGroupName $rgName `
            -StorageAccountName $storageName `
            -ErrorAction Stop

        $versioningOk = $blobProps.IsVersioningEnabled -eq $true
        $blobSoftDeleteOk = $blobProps.DeleteRetentionPolicy.Enabled -eq $true
        $containerSoftDeleteOk = $blobProps.ContainerDeleteRetentionPolicy.Enabled -eq $true
        $fileSoftDeleteOk = $fileProps.ShareDeleteRetentionPolicy.Enabled -eq $true

        $protectionOk = (
            $versioningOk -and
            $blobSoftDeleteOk -and
            $containerSoftDeleteOk -and
            $fileSoftDeleteOk
        )

        if ($protectionOk) {
            Add-Result $Check.DataProtection.$Lang `
                "[$OkStatus] - $($LabMsg.ProtectionOk.$Lang)" `
                "Green"
        } else {
            Add-Result $Check.DataProtection.$Lang `
                "[$ErrorStatus] - $($LabMsg.ProtectionBad.$Lang)" `
                "Red"
        }
    } catch {
        Add-Result $Check.DataProtection.$Lang `
            "[$ErrorStatus] - $($LabMsg.ProtectionBad.$Lang)" `
            "Red"
    }

    # ========================================================
    # 5. BLOB CONTAINERS
    # Management plane - netikriname turinio dėl Storage FW.
    # ========================================================

    try {
        $containers = @(Get-AzRmStorageContainer `
            -ResourceGroupName $rgName `
            -StorageAccountName $storageName `
            -ErrorAction Stop)

        $studentBlobOk = @(
            $containers | Where-Object Name -Match $LocCfg.Blob.StudentContainerPattern
        ).Count -gt 0

        $staticWebsiteOk = @(
            $containers | Where-Object Name -EQ $LocCfg.Blob.StaticWebsiteContainer
        ).Count -gt 0

        $explorerContainerOk = @(
            $containers | Where-Object Name -EQ $LocCfg.Blob.StorageExplorerContainer
        ).Count -gt 0

        $containersOk = $studentBlobOk -and $staticWebsiteOk -and $explorerContainerOk

        if ($containersOk) {
            Add-Result $Check.BlobContainers.$Lang `
                "[$OkStatus] - $($LabMsg.ContainersOk.$Lang)" `
                "Green"
        } else {
            Add-Result $Check.BlobContainers.$Lang `
                "[$ErrorStatus] - $($LabMsg.ContainersBad.$Lang)" `
                "Red"
        }
    } catch {
        Add-Result $Check.BlobContainers.$Lang `
            "[$ErrorStatus] - $($LabMsg.ContainersBad.$Lang)" `
            "Red"
    }

    # ========================================================
    # 6. AZURE FILES + SNAPSHOT
    # Management plane - Storage firewall netrukdo.
    # ========================================================

    try {
        $shares = @(Get-AzRmStorageShare `
            -ResourceGroupName $rgName `
            -StorageAccountName $storageName `
            -IncludeSnapshot `
            -ErrorAction Stop)

        $shareOk = @(
            $shares | Where-Object {
                $_.Name -eq $LocCfg.AzureFiles.ShareName -and -not $_.SnapshotTime
            }
        ).Count -gt 0

        $snapshotOk = @(
            $shares | Where-Object {
                $_.Name -eq $LocCfg.AzureFiles.ShareName -and $_.SnapshotTime
            }
        ).Count -gt 0

        $filesOk = $shareOk -and $snapshotOk

        if ($filesOk) {
            Add-Result $Check.AzureFiles.$Lang `
                "[$OkStatus] - $($LocCfg.AzureFiles.ShareName) + snapshot" `
                "Green"
        } else {
            Add-Result $Check.AzureFiles.$Lang `
                "[$ErrorStatus] - $($LabMsg.FilesBad.$Lang)" `
                "Red"
        }
    } catch {
        Add-Result $Check.AzureFiles.$Lang `
            "[$ErrorStatus] - $($LabMsg.FilesBad.$Lang)" `
            "Red"
    }

    # ========================================================
    # 7. STORAGE FIREWALL / VNET
    # ========================================================

    $storage = Get-AzStorageAccount `
        -ResourceGroupName $rgName `
        -Name $storageName `
        -ErrorAction SilentlyContinue

    $defaultDenyOk = $storage.NetworkRuleSet.DefaultAction -eq $LocCfg.Network.DefaultAction
    $vnetRuleOk = @($storage.NetworkRuleSet.VirtualNetworkRules).Count -gt 0
    $firewallOk = $defaultDenyOk -and $vnetRuleOk

    if ($firewallOk) {
        Add-Result $Check.Firewall.$Lang `
            "[$OkStatus] - $($LabMsg.FirewallOk.$Lang)" `
            "Green"
    } else {
        Add-Result $Check.Firewall.$Lang `
            "[$ErrorStatus] - $($LabMsg.FirewallBad.$Lang)" `
            "Red"
    }

} else {

    Add-Result $Check.StorageConfig.$Lang `
        "[$ErrorStatus] - $($LabMsg.StorageMissing.$Lang)" `
        "Red"

    Add-Result $Check.DataProtection.$Lang `
        "[$ErrorStatus] - $($LabMsg.StorageMissing.$Lang)" `
        "Red"

    Add-Result $Check.BlobContainers.$Lang `
        "[$ErrorStatus] - $($LabMsg.StorageMissing.$Lang)" `
        "Red"

    Add-Result $Check.AzureFiles.$Lang `
        "[$ErrorStatus] - $($LabMsg.StorageMissing.$Lang)" `
        "Red"

    Add-Result $Check.Firewall.$Lang `
        "[$ErrorStatus] - $($LabMsg.StorageMissing.$Lang)" `
        "Red"
}

# ============================================================
# 8. VM AFTER RESOURCE GROUP MOVE
# ============================================================

$vm = Get-AzVM `
    -ResourceGroupName $LocCfg.VirtualMachine.ResourceGroupName `
    -Name $LocCfg.VirtualMachine.Name `
    -ErrorAction SilentlyContinue

if ($vm) {
    Add-Result $Check.VirtualMachine.$Lang `
        "[$OkStatus] - $($LocCfg.VirtualMachine.ResourceGroupName)" `
        "Green"
} else {
    Add-Result $Check.VirtualMachine.$Lang `
        "[$ErrorStatus] - $($LabMsg.VmBad.$Lang)" `
        "Red"
}

# ============================================================
# GALUTINIS REZULTATAS
# ============================================================

$date = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host ""
Write-Host "--- $($Msg.FinalResult) ---" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Gray
Write-Host $Setup.HeaderTitle
Write-Host $LabName -ForegroundColor Yellow
Write-Host "$($Msg.Date): $date"
Write-Host "$($Msg.Student): $($Setup.StudentEmail)"
Write-Host "$($Msg.ScriptVersion): $($Setup.ScriptVersion)"
Write-Host "==================================================" -ForegroundColor Gray

$i = 1

foreach ($res in $results) {

    $label = "$i. $($res.Name):"
    $targetWidth = 34

    $spaces = $targetWidth - $label.Length
    if ($spaces -lt 1) { $spaces = 1 }

    Write-Host "$label$(" " * $spaces)" -NoNewline
    Write-Host $res.Text -ForegroundColor $res.Color

    $i++
}

Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""
