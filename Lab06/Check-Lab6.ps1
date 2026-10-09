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

if ($Lang -notin @("LT", "EN")) { $Lang = "LT" }

$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab06/Check-Lab6-config.json" -Lang $Lang
$LocCfg = $Setup.LocalConfig
$Check = $LocCfg.Checks
$LabMsg = $LocCfg.Messages
$Msg = $Setup.Messages
$LabName = $LocCfg.LabName.$Lang
$results = @()

# ============================================================
# 1. RESOURCE GROUP
# ============================================================

try {
    $allRGs = @(Get-AzResourceGroup -ErrorAction Stop)
    $rgMatch = Find-PatternMatch -Items $allRGs -Property "ResourceGroupName" -Pattern $LocCfg.ResourceGroup.Pattern
    $targetRG = $rgMatch.First

    if ($targetRG) {
        $status = if ($rgMatch.Count -gt 1) { "WARNING" } else { "OK" }
        $message = "$($LabMsg.Found.$Lang) $($targetRG.ResourceGroupName)"
        if ($rgMatch.Count -gt 1) { $message += "; $($LabMsg.MultipleResourceGroups.$Lang)" }
        Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroup.$Lang -Status $status -Message $message -Messages $Msg
    } else {
        Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroup.$Lang -Status "ERROR" -Message $LabMsg.MainRgMissing.$Lang -Messages $Msg
    }
} catch {
    $targetRG = $null
    Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroup.$Lang -Status "WARNING" -Message $LabMsg.ResourceGroupCheckFailed.$Lang -Messages $Msg
}

# ============================================================
# 2. STORAGE ACCOUNT
# ============================================================

$storage = $null

if ($targetRG) {
    try {
        $allStorage = @(Get-AzStorageAccount -ResourceGroupName $targetRG.ResourceGroupName -ErrorAction Stop)
        $storageMatch = Find-PatternMatch -Items $allStorage -Property "StorageAccountName" -Pattern $LocCfg.StorageAccount.NamePattern
        $storage = $storageMatch.First

        if ($storage) {
            $status = if ($storageMatch.Count -gt 1) { "WARNING" } else { "OK" }
            $message = "$($LabMsg.Found.$Lang) $($storage.StorageAccountName)"
            if ($storageMatch.Count -gt 1) { $message += "; $($LabMsg.MultipleStorageAccounts.$Lang)" }
            Add-LabResult -Results ([ref]$results) -Name $Check.StorageAccount.$Lang -Status $status -Message $message -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.StorageAccount.$Lang -Status "ERROR" -Message $LabMsg.StorageMissing.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.StorageAccount.$Lang -Status "WARNING" -Message $LabMsg.StorageCheckFailed.$Lang -Messages $Msg
    }
} else {
    Add-LabResult -Results ([ref]$results) -Name $Check.StorageAccount.$Lang -Status "ERROR" -Message $LabMsg.StorageMissing.$Lang -Messages $Msg
}

if ($storage) {
    $storageName = $storage.StorageAccountName
    $rgName = $targetRG.ResourceGroupName

    # ========================================================
    # 3. STORAGE CONFIGURATION
    # ========================================================

    $skuOk = $storage.Sku.Name -eq $LocCfg.StorageAccount.Sku
    $tierOk = $storage.AccessTier -eq $LocCfg.StorageAccount.AccessTier
    $storageConfig = "$($storage.Sku.Name) + $($storage.AccessTier)"

    if ($skuOk -and $tierOk) {
        Add-LabResult -Results ([ref]$results) -Name $Check.StorageConfig.$Lang -Status "OK" -Message $storageConfig -Messages $Msg
    } else {
        Add-LabResult -Results ([ref]$results) -Name $Check.StorageConfig.$Lang -Status "WARNING" -Message "$($LabMsg.StorageConfigBad.$Lang) (SKU=$($storage.Sku.Name), Tier=$($storage.AccessTier))" -Messages $Msg
    }

    # ========================================================
    # 4. DATA PROTECTION
    # ========================================================

    try {
        $blobProps = Get-AzStorageBlobServiceProperty -ResourceGroupName $rgName -StorageAccountName $storageName -ErrorAction Stop
        $fileProps = Get-AzStorageFileServiceProperty -ResourceGroupName $rgName -StorageAccountName $storageName -ErrorAction Stop

        $versioningOk = $blobProps.IsVersioningEnabled -eq $true
        $blobSoftDeleteOk = $blobProps.DeleteRetentionPolicy.Enabled -eq $true
        $containerSoftDeleteOk = $blobProps.ContainerDeleteRetentionPolicy.Enabled -eq $true
        $fileSoftDeleteOk = $fileProps.ShareDeleteRetentionPolicy.Enabled -eq $true

        if ($versioningOk -and $blobSoftDeleteOk -and $containerSoftDeleteOk -and $fileSoftDeleteOk) {
            Add-LabResult -Results ([ref]$results) -Name $Check.DataProtection.$Lang -Status "OK" -Message $LabMsg.ProtectionOk.$Lang -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.DataProtection.$Lang -Status "WARNING" -Message $LabMsg.ProtectionBad.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.DataProtection.$Lang -Status "WARNING" -Message $LabMsg.ProtectionCheckFailed.$Lang -Messages $Msg
    }

    # ========================================================
    # 5. BLOB CONTAINERS
    # ========================================================

    try {
        $containers = @(Get-AzRmStorageContainer -ResourceGroupName $rgName -StorageAccountName $storageName -ErrorAction Stop)

        $studentBlobOk = (Find-PatternMatch -Items $containers -Property "Name" -Pattern $LocCfg.Blob.StudentContainerPattern).Count -gt 0
        $staticWebsiteOk = @($containers | Where-Object Name -EQ $LocCfg.Blob.StaticWebsiteContainer).Count -gt 0
        $explorerContainerOk = @($containers | Where-Object Name -EQ $LocCfg.Blob.StorageExplorerContainer).Count -gt 0

        if ($studentBlobOk -and $staticWebsiteOk -and $explorerContainerOk) {
            Add-LabResult -Results ([ref]$results) -Name $Check.BlobContainers.$Lang -Status "OK" -Message $LabMsg.ContainersOk.$Lang -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.BlobContainers.$Lang -Status "ERROR" -Message $LabMsg.ContainersBad.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.BlobContainers.$Lang -Status "WARNING" -Message $LabMsg.ContainersCheckFailed.$Lang -Messages $Msg
    }

    # ========================================================
    # 6. AZURE FILES + SNAPSHOT
    # ========================================================

    try {
        $shares = @(Get-AzRmStorageShare -ResourceGroupName $rgName -StorageAccountName $storageName -IncludeSnapshot -ErrorAction Stop)
        $shareOk = @($shares | Where-Object { $_.Name -eq $LocCfg.AzureFiles.ShareName -and -not $_.SnapshotTime }).Count -gt 0
        $snapshotOk = @($shares | Where-Object { $_.Name -eq $LocCfg.AzureFiles.ShareName -and $_.SnapshotTime }).Count -gt 0

        if ($shareOk -and $snapshotOk) {
            Add-LabResult -Results ([ref]$results) -Name $Check.AzureFiles.$Lang -Status "OK" -Message "$($LocCfg.AzureFiles.ShareName) + snapshot" -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.AzureFiles.$Lang -Status "ERROR" -Message $LabMsg.FilesBad.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.AzureFiles.$Lang -Status "WARNING" -Message $LabMsg.FilesCheckFailed.$Lang -Messages $Msg
    }

    # ========================================================
    # 7. STORAGE FIREWALL / VNET
    # ========================================================

    try {
        $storageNetwork = Get-AzStorageAccount -ResourceGroupName $rgName -Name $storageName -ErrorAction Stop
        $defaultDenyOk = $storageNetwork.NetworkRuleSet.DefaultAction -eq $LocCfg.Network.DefaultAction
        $vnetRuleOk = @($storageNetwork.NetworkRuleSet.VirtualNetworkRules).Count -gt 0

        if ($defaultDenyOk -and $vnetRuleOk) {
            Add-LabResult -Results ([ref]$results) -Name $Check.Firewall.$Lang -Status "OK" -Message $LabMsg.FirewallOk.$Lang -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.Firewall.$Lang -Status "ERROR" -Message $LabMsg.FirewallBad.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.Firewall.$Lang -Status "WARNING" -Message $LabMsg.FirewallCheckFailed.$Lang -Messages $Msg
    }
} else {
    foreach ($item in @(
        $Check.StorageConfig.$Lang,
        $Check.DataProtection.$Lang,
        $Check.BlobContainers.$Lang,
        $Check.AzureFiles.$Lang,
        $Check.Firewall.$Lang
    )) {
        Add-LabResult -Results ([ref]$results) -Name $item -Status "ERROR" -Message $LabMsg.StorageMissing.$Lang -Messages $Msg
    }
}

# ============================================================
# 8. VM AFTER RESOURCE GROUP MOVE
# Tikriname galutinę būseną, o ne patį Move veiksmą.
# ============================================================

try {
    $vmRg = Get-AzResourceGroup -Name $LocCfg.VirtualMachine.ResourceGroupName -ErrorAction Stop

    try {
        $vm = Get-AzVM -ResourceGroupName $LocCfg.VirtualMachine.ResourceGroupName -Name $LocCfg.VirtualMachine.Name -ErrorAction Stop

        if ($vm) {
            Add-LabResult -Results ([ref]$results) -Name $Check.VirtualMachine.$Lang -Status "OK" -Message $LocCfg.VirtualMachine.ResourceGroupName -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.VirtualMachine.$Lang -Status "ERROR" -Message $LabMsg.VmBad.$Lang -Messages $Msg
        }
    } catch {
        # RG egzistuoja, todėl laikome, kad VM tiesiog nerasta.
        Add-LabResult -Results ([ref]$results) -Name $Check.VirtualMachine.$Lang -Status "ERROR" -Message $LabMsg.VmBad.$Lang -Messages $Msg
    }
} catch {
    # Jei galutinė VM RG neegzistuoja, tai yra ne techninis checkerio gedimas,
    # o neįvykdytas LAB reikalavimas.
    Add-LabResult -Results ([ref]$results) -Name $Check.VirtualMachine.$Lang -Status "ERROR" -Message $LabMsg.VmBad.$Lang -Messages $Msg
}

# ============================================================
# GALUTINIS REZULTATAS
# ============================================================

Show-LabResults -Setup $Setup -LabName $LabName -Results $results -LabelWidth 34
