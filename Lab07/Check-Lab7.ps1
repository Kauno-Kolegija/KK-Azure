# ============================================================
# LAB 7 CHECKER - AZURE DATABASES (SQL & NoSQL)
# ============================================================

try {
    if ($PSScriptRoot) { . (Join-Path $PSScriptRoot '../configs/common.ps1') }
    else { Invoke-RestMethod 'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1' -ErrorAction Stop | Invoke-Expression }
} catch {
    Write-Error "Failed to load common functions."
    throw
}

if ($Lang -notin @("LT", "EN")) { $Lang = "LT" }

$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab07/Check-Lab7-config.json" -Lang $Lang
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
        $message = $targetRG.ResourceGroupName
        if ($rgMatch.Count -gt 1) { $message += "; $($LabMsg.MultipleResourceGroups.$Lang)" }
        Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroup.$Lang -Status $status -Message $message -Messages $Msg
    } else {
        Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroup.$Lang -Status "ERROR" -Message $LabMsg.ResourceGroupMissing.$Lang -Messages $Msg
    }
} catch {
    $targetRG = $null
    Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroup.$Lang -Status "WARNING" -Message $LabMsg.ResourceGroupCheckFailed.$Lang -Messages $Msg
}

# ============================================================
# 2. AZURE SQL SERVERS
# ============================================================

$sqlServers = @()
$dbCandidates = @()
$primaryDb = $null
$replicationLinkFound = $false

if ($targetRG) {
    try {
        $sqlServers = @(Get-AzSqlServer -ResourceGroupName $targetRG.ResourceGroupName -ErrorAction Stop)
        $serverMatch = Find-PatternMatch -Items $sqlServers -Property "ServerName" -Pattern $LocCfg.Sql.ServerPattern

        if ($serverMatch.Count -ge 2) {
            Add-LabResult -Results ([ref]$results) -Name $Check.SqlServers.$Lang -Status "OK" -Message ($serverMatch.All.ServerName -join ", ") -Messages $Msg
        } elseif ($serverMatch.Count -eq 1) {
            Add-LabResult -Results ([ref]$results) -Name $Check.SqlServers.$Lang -Status "ERROR" -Message $LabMsg.SecondSqlServerMissing.$Lang -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.SqlServers.$Lang -Status "ERROR" -Message $LabMsg.SqlServerMissing.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.SqlServers.$Lang -Status "WARNING" -Message $LabMsg.SqlServerCheckFailed.$Lang -Messages $Msg
    }
} else {
    Add-LabResult -Results ([ref]$results) -Name $Check.SqlServers.$Lang -Status "ERROR" -Message $LabMsg.NoResourceGroup.$Lang -Messages $Msg
}

# ============================================================
# 3. SQL DATABASE + GEO-REPLICATION
# ============================================================

if ($sqlServers.Count -gt 0) {
    try {
        foreach ($server in $sqlServers) {
            $dbs = @(Get-AzSqlDatabase -ResourceGroupName $server.ResourceGroupName -ServerName $server.ServerName -ErrorAction Stop | Where-Object DatabaseName -NE "master")
            foreach ($db in $dbs) {
                if ($db.DatabaseName -match $LocCfg.Sql.DatabasePattern) {
                    $dbCandidates += [PSCustomObject]@{ Server = $server; Database = $db }
                }
            }
        }

        if ($dbCandidates.Count -gt 0) {
            $primaryDb = $dbCandidates | Select-Object -First 1
            $uniqueDbNames = @($dbCandidates.Database.DatabaseName | Sort-Object -Unique)
            $status = if ($uniqueDbNames.Count -gt 1) { "WARNING" } else { "OK" }
            Add-LabResult -Results ([ref]$results) -Name $Check.SqlDatabase.$Lang -Status $status -Message ($uniqueDbNames -join ", ") -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.SqlDatabase.$Lang -Status "ERROR" -Message $LabMsg.SqlDatabaseMissing.$Lang -Messages $Msg
        }

        foreach ($item in $dbCandidates) {
            try {
                $links = @(Get-AzSqlDatabaseReplicationLink -ResourceGroupName $item.Server.ResourceGroupName -ServerName $item.Server.ServerName -DatabaseName $item.Database.DatabaseName -ErrorAction Stop)
                if ($links.Count -gt 0) { $replicationLinkFound = $true; break }
            } catch {}
        }

        if ($replicationLinkFound) {
            Add-LabResult -Results ([ref]$results) -Name $Check.GeoReplication.$Lang -Status "OK" -Message $LabMsg.GeoReplicationOk.$Lang -Messages $Msg
        } elseif ($sqlServers.Count -ge 2 -and $dbCandidates.Count -ge 2) {
            Add-LabResult -Results ([ref]$results) -Name $Check.GeoReplication.$Lang -Status "WARNING" -Message $LabMsg.GeoReplicationUnconfirmed.$Lang -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.GeoReplication.$Lang -Status "ERROR" -Message $LabMsg.GeoReplicationMissing.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.SqlDatabase.$Lang -Status "WARNING" -Message $LabMsg.SqlDatabaseCheckFailed.$Lang -Messages $Msg
        Add-LabResult -Results ([ref]$results) -Name $Check.GeoReplication.$Lang -Status "WARNING" -Message $LabMsg.GeoReplicationCheckFailed.$Lang -Messages $Msg
    }
} else {
    Add-LabResult -Results ([ref]$results) -Name $Check.SqlDatabase.$Lang -Status "ERROR" -Message $LabMsg.SqlDatabaseMissing.$Lang -Messages $Msg
    Add-LabResult -Results ([ref]$results) -Name $Check.GeoReplication.$Lang -Status "ERROR" -Message $LabMsg.GeoReplicationMissing.$Lang -Messages $Msg
}

# ============================================================
# 4. DYNAMIC DATA MASKING
# ============================================================

if ($primaryDb) {
    try {
        $rules = @(Get-AzSqlDatabaseDataMaskingRule -ResourceGroupName $primaryDb.Server.ResourceGroupName -ServerName $primaryDb.Server.ServerName -DatabaseName $primaryDb.Database.DatabaseName -ErrorAction Stop)
        $expectedColumns = @($LocCfg.Sql.MaskingColumns)
        $foundColumns = @($rules | ForEach-Object { $_.ColumnName } | Sort-Object -Unique)
        $missingColumns = @($expectedColumns | Where-Object { $_ -notin $foundColumns })

        if ($missingColumns.Count -eq 0) {
            Add-LabResult -Results ([ref]$results) -Name $Check.DataMasking.$Lang -Status "OK" -Message ($expectedColumns -join ", ") -Messages $Msg
        } elseif ($rules.Count -gt 0) {
            Add-LabResult -Results ([ref]$results) -Name $Check.DataMasking.$Lang -Status "WARNING" -Message "$($LabMsg.MaskingPartial.$Lang): $($missingColumns -join ', ')" -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.DataMasking.$Lang -Status "ERROR" -Message $LabMsg.MaskingMissing.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.DataMasking.$Lang -Status "WARNING" -Message $LabMsg.MaskingCheckFailed.$Lang -Messages $Msg
    }
} else {
    Add-LabResult -Results ([ref]$results) -Name $Check.DataMasking.$Lang -Status "ERROR" -Message $LabMsg.SqlDatabaseMissing.$Lang -Messages $Msg
}

# ============================================================
# 5. COSMOS DB ACCOUNT
# ============================================================

$cosmos = $null
if ($targetRG) {
    try {
        $allCosmos = @(Get-AzCosmosDBAccount -ResourceGroupName $targetRG.ResourceGroupName -ErrorAction Stop)
        $cosmosMatch = Find-PatternMatch -Items $allCosmos -Property "Name" -Pattern $LocCfg.Cosmos.AccountPattern
        $cosmos = $cosmosMatch.First

        if ($cosmos) {
            $status = if ($cosmosMatch.Count -gt 1) { "WARNING" } else { "OK" }
            $message = $cosmos.Name
            if ($cosmosMatch.Count -gt 1) { $message += "; $($LabMsg.MultipleCosmosAccounts.$Lang)" }
            Add-LabResult -Results ([ref]$results) -Name $Check.CosmosAccount.$Lang -Status $status -Message $message -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.CosmosAccount.$Lang -Status "ERROR" -Message $LabMsg.CosmosMissing.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.CosmosAccount.$Lang -Status "WARNING" -Message $LabMsg.CosmosCheckFailed.$Lang -Messages $Msg
    }
} else {
    Add-LabResult -Results ([ref]$results) -Name $Check.CosmosAccount.$Lang -Status "ERROR" -Message $LabMsg.NoResourceGroup.$Lang -Messages $Msg
}

# ============================================================
# 6. COSMOS DATABASE + CONTAINER + TTL
# ============================================================

if ($cosmos -and $targetRG) {
    try {
        $cosmosDb = Get-AzCosmosDBSqlDatabase -ResourceGroupName $targetRG.ResourceGroupName -AccountName $cosmos.Name -Name $LocCfg.Cosmos.DatabaseName -ErrorAction Stop

        if ($cosmosDb) {
            Add-LabResult -Results ([ref]$results) -Name $Check.CosmosDatabase.$Lang -Status "OK" -Message $LocCfg.Cosmos.DatabaseName -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.CosmosDatabase.$Lang -Status "ERROR" -Message $LabMsg.CosmosDatabaseMissing.$Lang -Messages $Msg
        }

        $container = Get-AzCosmosDBSqlContainer -ResourceGroupName $targetRG.ResourceGroupName -AccountName $cosmos.Name -DatabaseName $LocCfg.Cosmos.DatabaseName -Name $LocCfg.Cosmos.ContainerName -ErrorAction Stop

        if ($container) {
            $partitionPaths = @($container.Resource.PartitionKey.Paths)
            $partitionOk = $partitionPaths -contains $LocCfg.Cosmos.PartitionKey
            $ttlValue = $container.Resource.DefaultTtl
            $ttlEnabled = $null -ne $ttlValue

            if ($partitionOk) {
                Add-LabResult -Results ([ref]$results) -Name $Check.CosmosContainer.$Lang -Status "OK" -Message "$($LocCfg.Cosmos.ContainerName); $($LocCfg.Cosmos.PartitionKey)" -Messages $Msg
            } else {
                Add-LabResult -Results ([ref]$results) -Name $Check.CosmosContainer.$Lang -Status "ERROR" -Message $LabMsg.PartitionKeyWrong.$Lang -Messages $Msg
            }

            Add-LabResult -Results ([ref]$results) -Name $Check.CosmosTtl.$Lang -Status $(if ($ttlEnabled) { "OK" } else { "ERROR" }) -Message $(if ($ttlEnabled) { "TTL=$ttlValue" } else { $LabMsg.TtlMissing.$Lang }) -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.CosmosContainer.$Lang -Status "ERROR" -Message $LabMsg.CosmosContainerMissing.$Lang -Messages $Msg
            Add-LabResult -Results ([ref]$results) -Name $Check.CosmosTtl.$Lang -Status "ERROR" -Message $LabMsg.TtlMissing.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.CosmosDatabase.$Lang -Status "WARNING" -Message $LabMsg.CosmosStructureCheckFailed.$Lang -Messages $Msg
        Add-LabResult -Results ([ref]$results) -Name $Check.CosmosContainer.$Lang -Status "WARNING" -Message $LabMsg.CosmosStructureCheckFailed.$Lang -Messages $Msg
        Add-LabResult -Results ([ref]$results) -Name $Check.CosmosTtl.$Lang -Status "WARNING" -Message $LabMsg.CosmosStructureCheckFailed.$Lang -Messages $Msg
    }
} else {
    Add-LabResult -Results ([ref]$results) -Name $Check.CosmosDatabase.$Lang -Status "ERROR" -Message $LabMsg.CosmosMissing.$Lang -Messages $Msg
    Add-LabResult -Results ([ref]$results) -Name $Check.CosmosContainer.$Lang -Status "ERROR" -Message $LabMsg.CosmosMissing.$Lang -Messages $Msg
    Add-LabResult -Results ([ref]$results) -Name $Check.CosmosTtl.$Lang -Status "ERROR" -Message $LabMsg.CosmosMissing.$Lang -Messages $Msg
}

# ============================================================
# GALUTINIS REZULTATAS
# ============================================================

Show-LabResults -Setup $Setup -LabName $LabName -Results $results -LabelWidth 32
