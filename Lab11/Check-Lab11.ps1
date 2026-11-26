# ============================================================
# LAB 11 CHECKER - AZURE GITHUB ACTIONS / BICEP / MONITORING
# Read-only: no deployments, no changes, no secret values.
# ============================================================

# Load shared functions, supporting both repo files and Cloud Shell | iex.
try {
    $commonLoaded = $false
    if ($PSScriptRoot) {
        $localCommon = Join-Path $PSScriptRoot '../configs/common.ps1'
        if (Test-Path -LiteralPath $localCommon) {
            . $localCommon
            $commonLoaded = $true
        }
    }
    if (-not $commonLoaded) {
        $commonSource = Invoke-RestMethod `
            'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1' `
            -ErrorAction Stop
        Invoke-Expression $commonSource
    }
} catch {
    Write-Error 'Failed to load common functions.'
    throw
}

if ($Lang -notin @('LT', 'EN')) { $Lang = 'LT' }

$Setup = Initialize-Lab `
    -LocalConfigUrl 'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab11/Check-Lab11-config.json' `
    -Lang $Lang
$Cfg = $Setup.LocalConfig
$Msg = $Setup.Messages
$Check = $Cfg.Checks
$LabMsg = $Cfg.Messages
$LabName = $Cfg.LabName.$Lang
$results = @()

function Add-Result {
    param([string]$Key, [string]$Status, [string]$Message)
    Add-LabResult -Results ([ref]$script:results) -Name $Check.$Key.$Lang `
        -Status $Status -Message $Message -Messages $Msg
}

function Select-LabItem {
    param([object[]]$Items, [string]$Label)
    if ($Items.Count -eq 0) { return $null }
    if ($Items.Count -eq 1) { return $Items[0] }
    Write-Host "`n$Label" -ForegroundColor Yellow
    for ($j = 0; $j -lt $Items.Count; $j++) {
        Write-Host ("  {0}. {1}" -f ($j + 1), $Items[$j].Name)
    }
    $selection = Read-Host "1-$($Items.Count)"
    $index = 0
    if (-not [int]::TryParse([string]$selection, [ref]$index) -or
        $index -lt 1 -or $index -gt $Items.Count) {
        throw $LabMsg.SelectInvalid.$Lang
    }
    return $Items[$index - 1]
}

function Get-ResourceProperties {
    param([Parameter(Mandatory)][string]$Id)
    # Management API is used only for read-only resource metadata.
    $reply = Invoke-AzRestMethod -Path "$Id`?api-version=2023-12-01" -Method GET -ErrorAction Stop
    if ([int]$reply.StatusCode -ne 200) { throw "HTTP $($reply.StatusCode)" }
    return ($reply.Content | ConvertFrom-Json)
}

function Get-HttpJson {
    param([string]$Uri)
    $attempts = [int]$Cfg.Application.MaxAttempts
    $response = $null
    $lastStatus = 0
    $reason = $null
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing `
                -TimeoutSec ([int]$Cfg.Application.TimeoutSeconds) -ErrorAction Stop
            $lastStatus = [int]$response.StatusCode
            if ($lastStatus -eq 200) {
                $data = $response.Content | ConvertFrom-Json -ErrorAction Stop
                return [pscustomobject]@{ Status = 200; Data = $data; Error = $null }
            }
        } catch {
            $reason = $_.Exception.Message
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $lastStatus = [int]$_.Exception.Response.StatusCode
            }
        }
        if ($attempt -lt $attempts) {
            Start-Sleep -Seconds ([int]$Cfg.Application.RetryDelaySeconds)
        }
    }
    return [pscustomobject]@{ Status = $lastStatus; Data = $null; Error = $reason }
}

function Get-DeploymentState {
    param([string]$ResourceGroupName, [string]$DeploymentName)
    $deployment = Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
        -Name $DeploymentName -ErrorAction Stop
    return [string]$deployment.ProvisioningState
}

# 1. Resource group: never silently choose the wrong one.
$rg = $null
try {
    $groups = @(Get-AzResourceGroup -ErrorAction Stop | Where-Object {
        $_.ResourceGroupName -match $Cfg.ResourceGroup.Pattern
    })
    $groupItems = @($groups | ForEach-Object {
        [pscustomobject]@{ Name = $_.ResourceGroupName; Item = $_ }
    })
    if ($groupItems.Count -gt 0) {
        $rg = (Select-LabItem -Items $groupItems -Label $LabMsg.ManyRg.$Lang).Item
        Add-Result 'ResourceGroup' 'OK' $rg.ResourceGroupName
    } else {
        Add-Result 'ResourceGroup' 'ERROR' $LabMsg.NoRg.$Lang
    }
} catch {
    Add-Result 'ResourceGroup' 'WARNING' "$($LabMsg.CheckUnavailable.$Lang): $($_.Exception.Message)"
}

$rgName = if ($rg) { [string]$rg.ResourceGroupName } else { '' }

# 2. Web App: Az.Accounts/Az.Resources are available even when Az.Websites
# (Get-AzWebApp) is not installed in Cloud Shell.
$web = $null
if ($rg) {
    try {
        $webApps = @(Get-AzResource -ResourceGroupName $rgName `
            -ResourceType 'Microsoft.Web/sites' -ErrorAction Stop | Where-Object {
            $_.Name -match $Cfg.WebApp.NamePattern
        })
        $appItems = @($webApps | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; Item = $_ }
        })
        if ($appItems.Count -gt 0) {
            $web = (Select-LabItem -Items $appItems -Label $LabMsg.ManyApps.$Lang).Item
            $webDetails = Get-ResourceProperties -Id ([string]$web.ResourceId)
            Add-Result 'WebApp' 'OK' "$($web.Name) [$($webDetails.properties.state)]"
        } else {
            Add-Result 'WebApp' 'ERROR' $LabMsg.MissingApp.$Lang
        }
    } catch {
        Add-Result 'WebApp' 'WARNING' "$($LabMsg.CheckUnavailable.$Lang): $($_.Exception.Message)"
    }
} else {
    Add-Result 'WebApp' 'ERROR' $LabMsg.NoRg.$Lang
}

$webId = if ($web) { [string]$web.ResourceId } else { '' }

# 3. App Service Plan: identify it by Web App serverFarmId.
if ($web) {
    try {
        $webResource = Get-ResourceProperties -Id ([string]$webId)
        $planId = [string]$webResource.properties.serverFarmId
        if (-not $planId) { throw 'serverFarmId unavailable' }
        $plan = Get-ResourceProperties -Id $planId
        $sku = [string]$plan.sku.name
        $tier = [string]$plan.sku.tier
        $planName = [string]$plan.name
        $planLinux = [bool]$plan.properties.reserved
        if ($sku -eq $Cfg.AppServicePlan.ExpectedSku -and $planLinux) {
            Add-Result 'AppServicePlan' 'OK' "$planName ($sku / $tier / Linux)"
        } elseif ($sku -in @($Cfg.AppServicePlan.AcceptedSku) -and $planLinux) {
            Add-Result 'AppServicePlan' 'WARNING' "$planName ($sku / $tier); $($LabMsg.WrongSku.$Lang)"
        } else {
            Add-Result 'AppServicePlan' 'ERROR' "$planName ($sku / $tier); Linux=$planLinux"
        }
    } catch {
        Add-Result 'AppServicePlan' 'WARNING' "$($LabMsg.CheckUnavailable.$Lang): $($_.Exception.Message)"
    }
} else { Add-Result 'AppServicePlan' 'ERROR' $LabMsg.MissingPlan.$Lang }

# 4. Runtime: read Web App config/web (not app settings; no secrets).
if ($web) {
    try {
        $cfgResource = Get-ResourceProperties -Id "$webId/config/web"
        $runtime = [string]$cfgResource.properties.linuxFxVersion
        if ($runtime -match $Cfg.WebApp.ExpectedRuntimePattern) {
            Add-Result 'NodeRuntime' 'OK' $runtime
        } else {
            Add-Result 'NodeRuntime' 'ERROR' "${runtime}; expected Node.js 24 on Linux"
        }
    } catch {
        Add-Result 'NodeRuntime' 'WARNING' "$($LabMsg.CheckUnavailable.$Lang): $($_.Exception.Message)"
    }
} else { Add-Result 'NodeRuntime' 'ERROR' $LabMsg.MissingApp.$Lang }

# 5. V1 ARM deployment history.
if ($rg) {
    try {
        $state = Get-DeploymentState -ResourceGroupName $rgName -DeploymentName $Cfg.Deployments.V1
        $status = if ($state -eq 'Succeeded') { 'OK' } else { 'ERROR' }
        Add-Result 'BicepV1' $status "$($Cfg.Deployments.V1): $state"
    } catch { Add-Result 'BicepV1' 'WARNING' $LabMsg.MissingDeployment.$Lang }
} else { Add-Result 'BicepV1' 'ERROR' $LabMsg.NoRg.$Lang }

# 6. Key Vault: check independently of Web App, to avoid cascading failures.
if ($rg) {
    try {
        $vaults = @(Get-AzResource -ResourceGroupName $rgName `
            -ResourceType 'Microsoft.KeyVault/vaults' -ErrorAction Stop)
        if ($web) {
            $suffix = ([string]$web.Name) -replace '^lab11', ''
            $expectedVault = [string]$Cfg.KeyVault.NamePrefix + $suffix
            $vault = $vaults | Where-Object { $_.Name -ieq $expectedVault } | Select-Object -First 1
        } else {
            $vault = $vaults | Where-Object {
                $_.Name -like "$($Cfg.KeyVault.NamePrefix)*"
            } | Select-Object -First 1
        }
        if ($vault) {
            if ($web) { Add-Result 'KeyVault' 'OK' $vault.Name }
            else { Add-Result 'KeyVault' 'WARNING' "$($vault.Name); Web App identity not confirmed" }
        } else {
            Add-Result 'KeyVault' 'ERROR' $LabMsg.MissingVault.$Lang
        }
    } catch {
        Add-Result 'KeyVault' 'WARNING' "$($LabMsg.CheckUnavailable.$Lang): $($_.Exception.Message)"
    }
} else { Add-Result 'KeyVault' 'ERROR' $LabMsg.NoRg.$Lang }

# 7. V2 ARM deployment history.
if ($rg) {
    try {
        $state = Get-DeploymentState -ResourceGroupName $rgName -DeploymentName $Cfg.Deployments.V2
        $status = if ($state -eq 'Succeeded') { 'OK' } else { 'ERROR' }
        Add-Result 'BicepV2' $status "$($Cfg.Deployments.V2): $state"
    } catch { Add-Result 'BicepV2' 'WARNING' $LabMsg.MissingDeployment.$Lang }
} else { Add-Result 'BicepV2' 'ERROR' $LabMsg.NoRg.$Lang }

# 8–10. Live endpoints. The application intentionally displays DEMO text,
# so we never download or print App Settings or Key Vault secret values.
$healthResponse = $null
$readyResponse = $null
if ($web) {
    $baseUrl = "https://$($web.Name).azurewebsites.net"
    $healthResponse = Get-HttpJson -Uri "$baseUrl/health"
    $readyResponse  = Get-HttpJson -Uri "$baseUrl/ready"
}

if ($healthResponse -and $healthResponse.Status -eq 200 -and $healthResponse.Data) {
    $health = $healthResponse.Data
    $version = [string]$health.version
    $status = if ($health.status -eq 'ok' -and $version -eq $Cfg.Application.ExpectedVersion) { 'OK' } else { 'ERROR' }
    $suffixNote = if ($status -eq 'ERROR') { "; $($LabMsg.WrongVersion.$Lang)" } else { '' }
    Add-Result 'Health' $status "HTTP 200; status=$($health.status); version=$version$suffixNote"
} else {
    $http = if ($healthResponse) { $healthResponse.Status } else { 'N/A' }
    Add-Result 'Health' 'ERROR' "HTTP $http; $($LabMsg.WebRequestFailed.$Lang)"
}

if ($readyResponse -and $readyResponse.Status -eq 200 -and $readyResponse.Data) {
    $ready = $readyResponse.Data
    $isReady = $ready.status -eq 'ready' -and [string]$ready.version -eq $Cfg.Application.ExpectedVersion -and
               $ready.keyVaultRequired -eq $true
    if ($isReady) { Add-Result 'Readiness' 'OK' 'HTTP 200; ready; Key Vault required' }
    else { Add-Result 'Readiness' 'ERROR' "HTTP 200; status=$($ready.status); keyVaultRequired=$($ready.keyVaultRequired)" }
} else {
    $http = if ($readyResponse) { $readyResponse.Status } else { 'N/A' }
    Add-Result 'Readiness' 'ERROR' "HTTP $http; $($LabMsg.NotReady.$Lang)"
}

if ($healthResponse -and $healthResponse.Data -and $readyResponse -and $readyResponse.Data -and
    $healthResponse.Data.keyVaultConfigLoaded -eq $true -and
    $healthResponse.Data.demoMessageVisible -eq $true -and
    $readyResponse.Data.demoMessageVisible -eq $true) {
    Add-Result 'DemoConfig' 'OK' 'keyVaultConfigLoaded=true; demoMessageVisible=true'
} else {
    Add-Result 'DemoConfig' 'ERROR' $LabMsg.NotDemo.$Lang
}

Show-LabResults -Setup $Setup -LabName $LabName -Results $results
