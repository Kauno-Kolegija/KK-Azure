# ============================================================
# LAB 7 CHECKER - AZURE DATABASES (SQL & NoSQL)
# ============================================================

# --- Uzkrauname bendras funkcijas ---
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

$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab07/Check-Lab7-config.json" -Lang $Lang
$LocCfg = $Setup.LocalConfig
$Check = $LocCfg.Checks
$LabMsg = $LocCfg.Messages
$Msg = $Setup.Messages
$LabName = $LocCfg.LabName.$Lang
$results = @()

# ============================================================
# PAGALBINES FUNKCIJOS
# ============================================================

function Get-CosmosPartitionPaths {
    param($Container)

    if (-not $Container) { return @() }
    if ($Container.Resource -and $Container.Resource.PartitionKey -and $Container.Resource.PartitionKey.Paths) { return @($Container.Resource.PartitionKey.Paths) }
    if ($Container.PartitionKey -and $Container.PartitionKey.Paths) { return @($Container.PartitionKey.Paths) }
    if ($Container.PartitionKeyPath) { return @($Container.PartitionKeyPath) }
    return @()
}

function Get-CosmosDefaultTtl {
    param($Container)

    if (-not $Container) { return $null }
    if ($Container.Resource -and $null -ne $Container.Resource.DefaultTtl) { return $Container.Resource.DefaultTtl }
    if ($null -ne $Container.DefaultTtl) { return $Container.DefaultTtl }
    if ($null -ne $Container.TtlInSeconds) { return $Container.TtlInSeconds }
    return $null
}

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
        Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroup.$Lang -Status "ERROR" -Message $LabMsg.ResourceGroupMissing.$Lang -Messages $Msg
    }
} catch {
    $targetRG = $null
    Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroup.$Lang -Status "WARNING" -Message $LabMsg.ResourceGroupCheckFailed.$Lang -Messages $Msg
}

# ============================================================
# 2. SQL SERVERS
# ============================================================

$sqlServers = @()
$dbCopies = @()
$dbName = $null

if ($targetRG) {
    try {
        $sqlServers = @(Get-AzSqlServer -ResourceGroupName $targetRG.ResourceGroupName -ErrorAction Stop)
        $sqlServerMatch = Find-PatternMatch -Items $sqlServers -Property "ServerName" -Pattern $LocCfg.Sql.ServerNamePattern
        $matchingServers = @($sqlServerMatch.All)

        if ($matchingServers.Count -ge $LocCfg.Sql.ExpectedServerCount) {
            $serverList = ($matchingServers | ForEach-Object { "$($_.ServerName) [$($_.Location)]" }) -join ", "
            Add-LabResult -Results ([ref]$results) -Name $Check.SqlServers.$Lang -Status "OK" -Message "$($matchingServers.Count) - $serverList" -Messages $Msg
        } elseif ($matchingServers.Count -gt 0) {
            Add-LabResult -Results ([ref]$results) -Name $Check.SqlServers.$Lang -Status "ERROR" -Message ($LabMsg.SqlServerCountBad.$Lang -f $matchingServers.Count, $LocCfg.Sql.ExpectedServerCount) -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.SqlServers.$Lang -Status "ERROR" -Message $LabMsg.SqlServersMissing.$Lang -Messages $Msg
        }
    } catch {
        $matchingServers = @()
        Add-LabResult -Results ([ref]$results) -Name $Check.SqlServers.$Lang -Status "WARNING" -Message $LabMsg.SqlServersCheckFailed.$Lang -Messages $Msg
    }
} else {
    $matchingServers = @()
    Add-LabResult -Results ([ref]$results) -Name $Check.SqlServers.$Lang -Status "ERROR" -Message $LabMsg.NoResourceGroup.$Lang -Messages $Msg
}

# ============================================================
# 3. SQL DATABASE
# ============================================================

if ($matchingServers.Count -gt 0) {
    try {
        foreach ($server in $matchingServers) {
            $serverDbs = @(Get-AzSqlDatabase -ResourceGroupName $targetRG.ResourceGroupName -ServerName $server.ServerName -ErrorAction Stop | Where-Object { $_.DatabaseName -ne "master" })
            foreach ($candidate in $serverDbs) {
                if ($candidate.DatabaseName -match $LocCfg.Sql.DatabaseNamePattern) {
                    $dbCopies += [PSCustomObject]@{ Server = $server; Database = $candidate }
                }
            }
        }

        if ($dbCopies.Count -gt 0) {
            $dbName = $dbCopies[0].Database.DatabaseName
            $dbConfigOk = $dbCopies[0].Database.Edition -eq $LocCfg.Sql.DatabaseEdition -and $dbCopies[0].Database.CurrentServiceObjectiveName -eq $LocCfg.Sql.ServiceObjective
            $status = if ($dbConfigOk) { "OK" } else { "WARNING" }
            $message = "$dbName - $($dbCopies[0].Database.Edition) / $($dbCopies[0].Database.CurrentServiceObjectiveName)"
            if (-not $dbConfigOk) { $message += "; $($LabMsg.SqlDatabaseConfigBad.$Lang)" }
            Add-LabResult -Results ([ref]$results) -Name $Check.SqlDatabase.$Lang -Status $status -Message $message -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.SqlDatabase.$Lang -Status "ERROR" -Message $LabMsg.SqlDatabaseMissing.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.SqlDatabase.$Lang -Status "WARNING" -Message $LabMsg.SqlDatabaseCheckFailed.$Lang -Messages $Msg
    }
} else {
    Add-LabResult -Results ([ref]$results) -Name $Check.SqlDatabase.$Lang -Status "ERROR" -Message $LabMsg.SqlDatabaseMissing.$Lang -Messages $Msg
}

# ============================================================
# 4. GEO-REPLICATION
# Tikriname tikra replication link, o ne vien 2 serveriu egzistavima.
# ============================================================

if ($dbCopies.Count -gt 0 -and $dbName) {
    try {
        $replicationLinks = @()

        foreach ($copy in $dbCopies) {
            try {
                $links = @(Get-AzSqlDatabaseReplicationLink -ResourceGroupName $targetRG.ResourceGroupName -ServerName $copy.Server.ServerName -DatabaseName $dbName -PartnerResourceGroupName $targetRG.ResourceGroupName -ErrorAction Stop)
                if ($links) { $replicationLinks += $links }
            } catch {}
        }

        if ($replicationLinks.Count -gt 0) {
            $states = @($replicationLinks | ForEach-Object { $_.ReplicationState } | Where-Object { $_ } | Sort-Object -Unique)
            $stateText = if ($states.Count -gt 0) { $states -join ", " } else { $LabMsg.Active.$Lang }
            Add-LabResult -Results ([ref]$results) -Name $Check.GeoReplication.$Lang -Status "OK" -Message "$($LabMsg.GeoReplicationFound.$Lang) ($stateText)" -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.GeoReplication.$Lang -Status "ERROR" -Message $LabMsg.GeoReplicationMissing.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.GeoReplication.$Lang -Status "WARNING" -Message $LabMsg.GeoReplicationCheckFailed.$Lang -Messages $Msg
    }
} else {
    Add-LabResult -Results ([ref]$results) -Name $Check.GeoReplication.$Lang -Status "ERROR" -Message $LabMsg.SqlDatabaseMissing.$Lang -Messages $Msg
}

# ============================================================
# 5. DYNAMIC DATA MASKING
# ============================================================

if ($dbCopies.Count -gt 0 -and $dbName) {
    try {
        $maskRules = @()

        foreach ($copy in $dbCopies) {
            $rules = @(
                Get-AzSqlDatabaseDataMaskingRule `
                    -ResourceGroupName $targetRG.ResourceGroupName `
                    -ServerName $copy.Server.ServerName `
                    -DatabaseName $dbName `
                    -ErrorAction SilentlyContinue
            )

            if ($rules.Count -gt 0) {
                $maskRules = $rules
                break
            }
        }

        if ($maskRules.Count -gt 0) {
            $columns = @(
                $maskRules |
                ForEach-Object { $_.ColumnName } |
                Where-Object { $_ } |
                Sort-Object -Unique
            )

            Add-LabResult -Results ([ref]$results) -Name $Check.DataMasking.$Lang -Status "OK" -Message ($columns -join ", ") -Messages $Msg
        }
        else {
            Add-LabResult -Results ([ref]$results) -Name $Check.DataMasking.$Lang -Status "ERROR" -Message $LabMsg.DataMaskingMissing.$Lang -Messages $Msg
        }
    }
    catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.DataMasking.$Lang -Status "WARNING" -Message "$($LabMsg.DataMaskingCheckFailed.$Lang): $($_.Exception.Message)" -Messages $Msg
    }
}
else {
    Add-LabResult -Results ([ref]$results) -Name $Check.DataMasking.$Lang -Status "ERROR" -Message $LabMsg.SqlDatabaseMissing.$Lang -Messages $Msg
}

# ============================================================
# 6. COSMOS DB ACCOUNT
# Vieno regiono paskyra yra teisinga - replikacijos netikriname.
# ============================================================

$cosmos = $null
$cosmosDb = $null
$container = $null

if ($targetRG) {
    try {
        $allCosmos = @(Get-AzCosmosDBAccount -ResourceGroupName $targetRG.ResourceGroupName -ErrorAction Stop)
        $cosmosMatch = Find-PatternMatch -Items $allCosmos -Property "Name" -Pattern $LocCfg.Cosmos.AccountNamePattern
        $cosmos = $cosmosMatch.First

        if ($cosmos) {
            $status = if ($cosmosMatch.Count -gt 1) { "WARNING" } else { "OK" }
            $message = "$($LabMsg.Found.$Lang) $($cosmos.Name)"
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
# 7. COSMOS SQL DATABASE
# ============================================================

if ($cosmos) {
    try {
        $cosmosDbs = @(Get-AzCosmosDBSqlDatabase -ResourceGroupName $targetRG.ResourceGroupName -AccountName $cosmos.Name -ErrorAction Stop)
        $dbMatch = Find-PatternMatch -Items $cosmosDbs -Property "Name" -Pattern $LocCfg.Cosmos.DatabaseNamePattern
        $cosmosDb = $dbMatch.First

        if ($cosmosDb) {
            Add-LabResult -Results ([ref]$results) -Name $Check.CosmosDatabase.$Lang -Status "OK" -Message $cosmosDb.Name -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.CosmosDatabase.$Lang -Status "ERROR" -Message $LabMsg.CosmosDatabaseMissing.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.CosmosDatabase.$Lang -Status "WARNING" -Message $LabMsg.CosmosDatabaseCheckFailed.$Lang -Messages $Msg
    }
} else {
    Add-LabResult -Results ([ref]$results) -Name $Check.CosmosDatabase.$Lang -Status "ERROR" -Message $LabMsg.CosmosMissing.$Lang -Messages $Msg
}

# ============================================================
# 8. COSMOS CONTAINER
# ============================================================

if ($cosmos -and $cosmosDb) {
    try {
        $containers = @(Get-AzCosmosDBSqlContainer -ResourceGroupName $targetRG.ResourceGroupName -AccountName $cosmos.Name -DatabaseName $cosmosDb.Name -ErrorAction Stop)
        $containerMatch = Find-PatternMatch -Items $containers -Property "Name" -Pattern $LocCfg.Cosmos.ContainerNamePattern
        $container = $containerMatch.First

        if ($container) {
            Add-LabResult -Results ([ref]$results) -Name $Check.CosmosContainer.$Lang -Status "OK" -Message $container.Name -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.CosmosContainer.$Lang -Status "ERROR" -Message $LabMsg.CosmosContainerMissing.$Lang -Messages $Msg
        }
    } catch {
        Add-LabResult -Results ([ref]$results) -Name $Check.CosmosContainer.$Lang -Status "WARNING" -Message $LabMsg.CosmosContainerCheckFailed.$Lang -Messages $Msg
    }
} else {
    Add-LabResult -Results ([ref]$results) -Name $Check.CosmosContainer.$Lang -Status "ERROR" -Message $LabMsg.CosmosDatabaseMissing.$Lang -Messages $Msg
}

# ============================================================
# 9. PARTITION KEY
# ============================================================

if ($container) {
    $partitionPaths = @(Get-CosmosPartitionPaths $container)

    if ($partitionPaths -contains $LocCfg.Cosmos.PartitionKey) {
        Add-LabResult -Results ([ref]$results) -Name $Check.PartitionKey.$Lang -Status "OK" -Message $LocCfg.Cosmos.PartitionKey -Messages $Msg
    } else {
        $actual = if ($partitionPaths.Count -gt 0) { $partitionPaths -join ", " } else { $LabMsg.NotDetected.$Lang }
        Add-LabResult -Results ([ref]$results) -Name $Check.PartitionKey.$Lang -Status "ERROR" -Message "$($LabMsg.PartitionKeyBad.$Lang): $actual" -Messages $Msg
    }
} else {
    Add-LabResult -Results ([ref]$results) -Name $Check.PartitionKey.$Lang -Status "ERROR" -Message $LabMsg.CosmosContainerMissing.$Lang -Messages $Msg
}

# ============================================================
# 10. TTL
# On (no default) Cosmos DB konteineryje atitinka Default TTL = -1.
# ============================================================

if ($container) {
    $ttl = Get-CosmosDefaultTtl $container

    if ($ttl -eq $LocCfg.Cosmos.ExpectedDefaultTtl) {
        Add-LabResult -Results ([ref]$results) -Name $Check.Ttl.$Lang -Status "OK" -Message $LabMsg.TtlEnabled.$Lang -Messages $Msg
    } elseif ($null -eq $ttl) {
        Add-LabResult -Results ([ref]$results) -Name $Check.Ttl.$Lang -Status "ERROR" -Message $LabMsg.TtlDisabled.$Lang -Messages $Msg
    } else {
        Add-LabResult -Results ([ref]$results) -Name $Check.Ttl.$Lang -Status "WARNING" -Message "$($LabMsg.TtlDifferent.$Lang): $ttl" -Messages $Msg
    }
} else {
    Add-LabResult -Results ([ref]$results) -Name $Check.Ttl.$Lang -Status "ERROR" -Message $LabMsg.CosmosContainerMissing.$Lang -Messages $Msg
}

# ============================================================
# GALUTINIS REZULTATAS
# ============================================================

Show-LabResults -Setup $Setup -LabName $LabName -Results $results -LabelWidth 34
