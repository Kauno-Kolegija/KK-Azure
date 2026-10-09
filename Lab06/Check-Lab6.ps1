# ============================================================
# LAB 6 CHECKER - STORAGE SERVICES
# ============================================================

# --- Užkrauname bendras funkcijas ---
try {
    if ($PSScriptRoot) {
        . (Join-Path $PSScriptRoot '../configs/common.ps1')
    }
    else {
        Invoke-RestMethod `
            'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1' `
            -ErrorAction Stop |
            Invoke-Expression
    }
}
catch {
    Write-Error "Failed to load common functions."
    throw
}

# --- Kalba ---
if ($Lang -notin @("LT", "EN")) {
    $Lang = "LT"
}

# --- Inicializacija ---
$Setup = Initialize-Lab `
    -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab06/Check-Lab6-config.json" `
    -Lang $Lang

$LocCfg  = $Setup.LocalConfig
$Check   = $LocCfg.Checks
$LabMsg  = $LocCfg.Messages
$Msg     = $Setup.Messages
$LabName = $LocCfg.LabName.$Lang

$OkStatus      = $Msg.Ok
$ErrorStatus   = $Msg.Error
$WarningStatus = $Msg.Warning

$results = @()

function Add-Result {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Color = "White",
        [int]$Indent = 0
    )

    $script:results += [PSCustomObject]@{
        Name   = $Name
        Text   = $Text
        Color  = $Color
        Indent = $Indent
    }
}

# ============================================================
# 1. RESOURCE GROUP
# ============================================================

$targetRG = $null

try {
    $matchingRGs = @(
        Get-AzResourceGroup -ErrorAction Stop |
        Where-Object ResourceGroupName -Match $LocCfg.ResourceGroup.Pattern
    )

    $targetRG = $matchingRGs | Select-Object -First 1

    if ($targetRG) {
        if ($matchingRGs.Count -gt 1) {
            Add-Result $Check.ResourceGroup.$Lang `
                "[$WarningStatus] - $($LabMsg.Found.$Lang) $($targetRG.ResourceGroupName); $($LabMsg.MultipleResourceGroups.$Lang)" `
                "Yellow"
        }
        else {
            Add-Result $Check.ResourceGroup.$Lang `
                "[$OkStatus] - $($LabMsg.Found.$Lang) $($targetRG.ResourceGroupName)" `
                "Green"
        }
    }
    else {
        Add-Result $Check.ResourceGroup.$Lang `
            "[$ErrorStatus] - $($LabMsg.MainRgMissing.$Lang)" `
            "Red"
    }
}
catch {
    Add-Result $Check.ResourceGroup.$Lang `
        "[$WarningStatus] - $($LabMsg.ResourceGroupCheckFailed.$Lang)" `
        "Yellow"
}

# ============================================================
# 2. STORAGE ACCOUNT
# ============================================================

$storage = $null

if ($targetRG) {
    try {
        $storageAccounts = @(
            Get-AzStorageAccount `
                -ResourceGroupName $targetRG.ResourceGroupName `
                -ErrorAction Stop |
            Where-Object StorageAccountName -Match $LocCfg.StorageAccount.NamePattern
        )

        $storage = $storageAccounts | Select-Object -First 1

        if ($storage) {
            if ($storageAccounts.Count -gt 1) {
                Add-Result $Check.StorageAccount.$Lang `
                    "[$WarningStatus] - $($LabMsg.Found.$Lang) $($storage.StorageAccountName); $($LabMsg.MultipleStorageAccounts.$Lang)" `
                    "Yellow"
            }
            else {
                Add-Result $Check.StorageAccount.$Lang `
                    "[$OkStatus] - $($LabMsg.Found.$Lang) $($storage.StorageAccountName)" `
                    "Green"
            }
        }
        else {
            Add-Result $Check.StorageAccount.$Lang `
                "[$ErrorStatus] - $($LabMsg.StorageMissing.$Lang)" `
                "Red"
        }
    }
    catch {
        Add-Result $Check.StorageAccount.$Lang `
            "[$WarningStatus] - $($LabMsg.StorageCheckFailed.$Lang)" `
            "Yellow"
    }
}
else {
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

    if ($skuOk -and $tierOk) {
        Add-Result $Check.StorageConfig.$Lang `
            "[$OkStatus] - $($storage.Sku.Name) + $($storage.AccessTier)" `
            "Green"
    }
    else {
        # Storage Account yra sukurtas, todėl netinkamą SKU / tier laikome įspėjimu.
        Add-Result $Check.StorageConfig.$Lang `
            "[$WarningStatus] - $($LabMsg.StorageConfigBad.$Lang) (SKU=$($storage.Sku.Name), Tier=$($storage.AccessTier))" `
            "Yellow"
    }

    # ========================================================
    # 4. DATA PROTECTION
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

        if ($versioningOk -and $blobSoftDeleteOk -and $containerSoftDeleteOk -and $fileSoftDeleteOk) {
            Add-Result $Check.DataProtection.$Lang `
                "[$OkStatus] - $($LabMsg.ProtectionOk.$Lang)" `
                "Green"
        }
        else {
            Add-Result $Check.DataProtection.$Lang `
                "[$WarningStatus] - $($LabMsg.ProtectionBad.$Lang)" `
                "Yellow"
        }
    }
    catch {
        Add-Result $Check.DataProtection.$Lang `
            "[$WarningStatus] - $($LabMsg.ProtectionCheckFailed.$Lang)" `
            "Yellow"
    }

    # ========================================================
    # 5. BLOB CONTAINERS
    # ========================================================

    try {
        $containers = @(
            Get-AzRmStorageContainer `
                -ResourceGroupName $rgName `
                -StorageAccountName $storageName `
                -ErrorAction Stop
        )

        $studentBlobOk = @(
            $containers | Where-Object Name -Match $LocCfg.Blob.StudentContainerPattern
        ).Count -gt 0

        $staticWebsiteOk = @(
            $containers | Where-Object Name -EQ $LocCfg.Blob.StaticWebsiteContainer
        ).Count -gt 0

        $explorerContainerOk = @(
            $containers | Where-Object Name -EQ $LocCfg.Blob.StorageExplorerContainer
        ).Count -gt 0

        if ($studentBlobOk -and $staticWebsiteOk -and $explorerContainerOk) {
            Add-Result $Check.BlobContainers.$Lang `
                "[$OkStatus] - $($LabMsg.ContainersOk.$Lang)" `
                "Green"
        }
        else {
            Add-Result $Check.BlobContainers.$Lang `
                "[$ErrorStatus] - $($LabMsg.ContainersBad.$Lang)" `
                "Red"
        }
    }
    catch {
        Add-Result $Check.BlobContainers.$Lang `
            "[$WarningStatus] - $($LabMsg.ContainersCheckFailed.$Lang)" `
            "Yellow"
    }

    # ========================================================
    # 6. AZURE FILES + SNAPSHOT
    # ========================================================

    try {
        $shares = @(
            Get-AzRmStorageShare `
                -ResourceGroupName $rgName `
                -StorageAccountName $storageName `
                -IncludeSnapshot `
                -ErrorAction Stop
        )

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

        if ($shareOk -and $snapshotOk) {
            Add-Result $Check.AzureFiles.$Lang `
                "[$OkStatus] - $($LocCfg.AzureFiles.ShareName) + snapshot" `
                "Green"
        }
        else {
            Add-Result $Check.AzureFiles.$Lang `
                "[$ErrorStatus] - $($LabMsg.FilesBad.$Lang)" `
                "Red"
        }
    }
    catch {
        Add-Result $Check.AzureFiles.$Lang `
            "[$WarningStatus] - $($LabMsg.FilesCheckFailed.$Lang)" `
            "Yellow"
    }

    # ========================================================
    # 7. STORAGE FIREWALL / VNET
    # ========================================================

    try {
        $storageNetwork = Get-AzStorageAccount `
            -ResourceGroupName $rgName `
            -Name $storageName `
            -ErrorAction Stop

        $defaultDenyOk = $storageNetwork.NetworkRuleSet.DefaultAction -eq $LocCfg.Network.DefaultAction
        $vnetRuleOk = @($storageNetwork.NetworkRuleSet.VirtualNetworkRules).Count -gt 0

        if ($defaultDenyOk -and $vnetRuleOk) {
            Add-Result $Check.Firewall.$Lang `
                "[$OkStatus] - $($LabMsg.FirewallOk.$Lang)" `
                "Green"
        }
        else {
            Add-Result $Check.Firewall.$Lang `
                "[$ErrorStatus] - $($LabMsg.FirewallBad.$Lang)" `
                "Red"
        }
    }
    catch {
        Add-Result $Check.Firewall.$Lang `
            "[$WarningStatus] - $($LabMsg.FirewallCheckFailed.$Lang)" `
            "Yellow"
    }
}
else {
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
# Tikriname galutinę būseną, o ne patį Move veiksmą.
# ============================================================

try {
    $vm = Get-AzVM `
        -ResourceGroupName $LocCfg.VirtualMachine.ResourceGroupName `
        -Name $LocCfg.VirtualMachine.Name `
        -ErrorAction Stop

    if ($vm) {
        Add-Result $Check.VirtualMachine.$Lang `
            "[$OkStatus] - $($LocCfg.VirtualMachine.ResourceGroupName)" `
            "Green"
    }
    else {
        Add-Result $Check.VirtualMachine.$Lang `
            "[$ErrorStatus] - $($LabMsg.VmBad.$Lang)" `
            "Red"
    }
}
catch {
    # Get-AzVM su konkrečiu RG/Name grąžina klaidą ir tada, kai VM nėra.
    # Patikriname, ar pati RG egzistuoja: jei taip, laikome, kad VM tiesiog nerasta.
    try {
        $vmRg = Get-AzResourceGroup `
            -Name $LocCfg.VirtualMachine.ResourceGroupName `
            -ErrorAction Stop

        Add-Result $Check.VirtualMachine.$Lang `
            "[$ErrorStatus] - $($LabMsg.VmBad.$Lang)" `
            "Red"
    }
    catch {
        Add-Result $Check.VirtualMachine.$Lang `
            "[$WarningStatus] - $($LabMsg.VmCheckFailed.$Lang)" `
            "Yellow"
    }
}

# ============================================================
# GALUTINIS REZULTATAS
# ============================================================

Show-LabResults `
    -Setup $Setup `
    -LabName $LabName `
    -Results $results `
    -LabelWidth 34
