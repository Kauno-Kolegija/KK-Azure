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

$Setup = Initialize-Lab `
    -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab06/Check-Lab6-config.json" `
    -Lang $Lang

$LocCfg  = $Setup.LocalConfig
$Check   = $LocCfg.Checks
$LabMsg  = $LocCfg.Messages
$Msg     = $Setup.Messages
$LabName = $LocCfg.LabName.$Lang
if (-not $LabMsg) { $LabMsg = $LocCfg.Messages.LT }

$CurrentIdentity = az ad signed-in-user show --query userPrincipalName -o tsv 2>$null
if (-not $CurrentIdentity) { $CurrentIdentity = if ($Lang -eq 'EN') { 'Student' } else { 'Studentas' } }

$Results = @()
function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Text)
    $script:Results += [PSCustomObject]@{
        Name  = $Name
        Text  = "$(if ($Ok) { $LabMsg.Ok } else { $LabMsg.Error }) - $Text"
        Color = if ($Ok) { 'Green' } else { 'Red' }
    }
}

# --- 1. PAGRINDINĖ RESURSŲ GRUPĖ ---
$LabRG = Get-AzResourceGroup -ErrorAction SilentlyContinue |
    Where-Object { $_.ResourceGroupName -match $LocCfg.MainResourceGroupPattern } |
    Select-Object -First 1

if ($LabRG) {
    Add-Result $LabMsg.ResourceGroup $true "$($LabMsg.Found) $($LabRG.ResourceGroupName)"
} else {
    Add-Result $LabMsg.ResourceGroup $false $LabMsg.MainRgMissing
}

$Storage = $null
if ($LabRG) {
    $Storage = Get-AzStorageAccount -ResourceGroupName $LabRG.ResourceGroupName -ErrorAction SilentlyContinue |
        Where-Object { $_.StorageAccountName -match $LocCfg.StorageAccountPattern } |
        Select-Object -First 1
}

# --- 2. STORAGE ACCOUNT ---
if ($Storage) {
    Add-Result $LabMsg.StorageAccount $true "$($LabMsg.Found) $($Storage.StorageAccountName)"
} else {
    Add-Result $LabMsg.StorageAccount $false $LabMsg.StorageMissing
}

if ($Storage) {
    $StorageName = $Storage.StorageAccountName
    $RgName = $LabRG.ResourceGroupName

    # --- 3. STORAGE KONFIGŪRACIJA ---
    $SkuOk = ($Storage.Sku.Name -eq $LocCfg.ExpectedStorageSku)
    $TierOk = ($Storage.AccessTier -eq $LocCfg.ExpectedAccessTier)
    Add-Result $LabMsg.StorageConfig ($SkuOk -and $TierOk) $(if ($SkuOk -and $TierOk) { $LabMsg.StorageConfigOk } else { "$($LabMsg.StorageConfigBad) (SKU=$($Storage.Sku.Name), Tier=$($Storage.AccessTier))" })

    # --- 4. DATA PROTECTION (management plane; firewall netrukdo) ---
    try {
        $BlobProps = Get-AzStorageBlobServiceProperty -ResourceGroupName $RgName -StorageAccountName $StorageName -ErrorAction Stop
        $FileProps = Get-AzStorageFileServiceProperty -ResourceGroupName $RgName -StorageAccountName $StorageName -ErrorAction Stop

        $VersioningOk = ($BlobProps.IsVersioningEnabled -eq $true)
        $BlobSoftDeleteOk = ($BlobProps.DeleteRetentionPolicy.Enabled -eq $true)
        $ContainerSoftDeleteOk = ($BlobProps.ContainerDeleteRetentionPolicy.Enabled -eq $true)
        $FileSoftDeleteOk = ($FileProps.ShareDeleteRetentionPolicy.Enabled -eq $true)
        $ProtectionOk = $VersioningOk -and $BlobSoftDeleteOk -and $ContainerSoftDeleteOk -and $FileSoftDeleteOk
        Add-Result $LabMsg.DataProtection $ProtectionOk $(if ($ProtectionOk) { $LabMsg.ProtectionOk } else { $LabMsg.ProtectionBad })
    } catch {
        Add-Result $LabMsg.DataProtection $false $LabMsg.ProtectionBad
    }

    # --- 5. BLOB KONTEINERIAI (management plane; netikriname turinio dėl FW) ---
    try {
        $Containers = @(Get-AzRmStorageContainer -ResourceGroupName $RgName -StorageAccountName $StorageName -ErrorAction Stop)
        $StudentBlobOk = @($Containers | Where-Object { $_.Name -match $LocCfg.BlobContainerPattern }).Count -gt 0
        $ExplorerContainerOk = @($Containers | Where-Object { $_.Name -eq $LocCfg.StorageExplorerContainer }).Count -gt 0
        $ContainersOk = $StudentBlobOk -and $ExplorerContainerOk
        Add-Result $LabMsg.BlobContainers $ContainersOk $(if ($ContainersOk) { $LabMsg.ContainersOk } else { $LabMsg.ContainersBad })
    } catch {
        Add-Result $LabMsg.BlobContainers $false $LabMsg.ContainersBad
    }

    # --- 6. AZURE FILES + SNAPSHOT (management plane) ---
    try {
        $Shares = @(Get-AzRmStorageShare -ResourceGroupName $RgName -StorageAccountName $StorageName -IncludeSnapshot -ErrorAction Stop)
        $ShareOk = @($Shares | Where-Object { $_.Name -eq $LocCfg.FileShareName -and -not $_.SnapshotTime }).Count -gt 0
        $SnapshotOk = @($Shares | Where-Object { $_.Name -eq $LocCfg.FileShareName -and $_.SnapshotTime }).Count -gt 0
        $FilesOk = $ShareOk -and $SnapshotOk
        Add-Result $LabMsg.AzureFiles $FilesOk $(if ($FilesOk) { $LabMsg.FilesOk } else { $LabMsg.FilesBad })
    } catch {
        Add-Result $LabMsg.AzureFiles $false $LabMsg.FilesBad
    }

    # --- 7. STORAGE FIREWALL / VNET ---
    $DefaultDenyOk = ($Storage.NetworkRuleSet.DefaultAction -eq 'Deny')
    $VNetRules = @($Storage.NetworkRuleSet.VirtualNetworkRules)
    $VNetRuleOk = $VNetRules.Count -gt 0
    $FirewallOk = $DefaultDenyOk -and $VNetRuleOk
    Add-Result $LabMsg.Firewall $FirewallOk $(if ($FirewallOk) { $LabMsg.FirewallOk } else { $LabMsg.FirewallBad })
} else {
    Add-Result $LabMsg.StorageConfig $false $LabMsg.StorageMissing
    Add-Result $LabMsg.DataProtection $false $LabMsg.StorageMissing
    Add-Result $LabMsg.BlobContainers $false $LabMsg.StorageMissing
    Add-Result $LabMsg.AzureFiles $false $LabMsg.StorageMissing
    Add-Result $LabMsg.Firewall $false $LabMsg.StorageMissing
}

# --- 8. VM PO PERKĖLIMO ---
$Vm = Get-AzVM -ResourceGroupName $LocCfg.VmResourceGroupName -Name $LocCfg.VmName -ErrorAction SilentlyContinue
Add-Result $LabMsg.VirtualMachine ([bool]$Vm) $(if ($Vm) { $LabMsg.VmOk } else { $LabMsg.VmBad })

# --- IŠVEDIMAS ---
$date = Get-Date -Format 'yyyy-MM-dd HH:mm'
Write-Host "`n--- GALUTINIS REZULTATAS ---" -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Gray
if ($Setup.HeaderTitle) { Write-Host $Setup.HeaderTitle }
Write-Host $LabMsg.LabName -ForegroundColor Yellow
Write-Host "Data: $date"
Write-Host "Studentas: $CurrentIdentity"
Write-Host "$($Msg.ScriptVersion): $($Setup.ScriptVersion)"
Write-Host '==================================================' -ForegroundColor Gray

foreach ($res in $Results) {
    $label = "$($res.Name):"
    $targetWidth = 27
    $padding = ' ' * [Math]::Max(1, $targetWidth - $label.Length)
    Write-Host "$label$padding" -NoNewline
    Write-Host $res.Text -ForegroundColor $res.Color
}
Write-Host '==================================================' -ForegroundColor Gray
Write-Host ''
