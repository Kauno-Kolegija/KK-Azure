# Offline regression tests. No Azure modules, credentials or network are needed.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$script:passed = 0

function Assert-True {
    param($Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    & $Body
    $script:passed++
    Microsoft.PowerShell.Utility\Write-Host "PASS: $Name"
}
function Read-Script {
    param([string]$Path)
    [scriptblock]::Create([IO.File]::ReadAllText((Join-Path $repoRoot $Path)))
}

. (Join-Path $repoRoot 'configs/common.ps1')
function Clear-Host {}
function Write-Host { param($Object, $ForegroundColor, [switch]$NoNewline) }
function Invoke-RestMethod { throw 'Unexpected network access in offline test.' }
function Get-AzContext { [pscustomobject]@{ Account = @{ Id = 'student@example.test' }; Subscription = @{ Id = 'sub'; Name = 'Group-Name-Surname' } } }

Test-Case 'All PowerShell and JSON files parse' {
    foreach ($file in Get-ChildItem -LiteralPath $repoRoot -Recurse -Filter '*.ps1') {
        $tokens = $null; $issues = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($file.FullName), [ref]$tokens, [ref]$issues)
        Assert-True ($issues.Count -eq 0) "$($file.FullName): $issues"
    }
    foreach ($file in Get-ChildItem -LiteralPath $repoRoot -Recurse -Filter '*.json') {
        $null = Get-Content -LiteralPath $file.FullName -Encoding UTF8 -Raw | ConvertFrom-Json
    }
}
Test-Case 'Local configuration is used without network access' {
    $setup = Initialize-Lab -ConfigDirectory (Join-Path $repoRoot 'Lab01') -LocalConfigUrl 'https://example.test/Check-Lab1-config.json'
    Assert-True ($setup.LocalConfig.RoleToCheck -eq 'Contributor') 'Local configuration was not loaded.'
}
Test-Case 'A missing local configuration does not silently fetch main' {
    $thrown = $false
    try { Initialize-Lab -ConfigDirectory (Join-Path $repoRoot 'Lab01') -LocalConfigUrl 'https://example.test/missing.json' -ErrorAction Stop } catch { $thrown = $true }
    Assert-True $thrown 'Missing config should fail.'
}
Test-Case 'Instructor role must match both name and subscription scope' {
    function Get-AzRoleAssignment {
        param($SignInName, $Scope, $ErrorAction)
        Assert-True ($SignInName -eq 'teacher@example.test') 'Wrong identity queried.'
        [pscustomobject]@{ RoleDefinitionName = 'Storage Account Contributor'; Scope = '/subscriptions/sub' }
        [pscustomobject]@{ RoleDefinitionName = 'Contributor'; Scope = '/subscriptions/sub/resourceGroups/rg' }
    }
    Assert-True (-not (Test-LabInstructorRole -Email 'teacher@example.test' -RoleName Contributor -SubscriptionId sub)) 'A partial role or child scope passed.'
}
Test-Case 'Direct configured instructor role passes' {
    function Get-AzRoleAssignment { [pscustomobject]@{ RoleDefinitionName = 'Contributor'; Scope = '/subscriptions/sub/' } }
    Assert-True (Test-LabInstructorRole -Email 'teacher@example.test' -RoleName Contributor -SubscriptionId sub) 'Valid assignment failed.'
}
Test-Case 'Role lookup failures propagate' {
    function Get-AzRoleAssignment { throw 'Forbidden' }
    $thrown = $false
    try { Test-LabInstructorRole -Email 'teacher@example.test' -RoleName Contributor -SubscriptionId sub } catch { $thrown = $true }
    Assert-True $thrown 'API failure was swallowed.'
}
Test-Case 'Port checks accept inclusive ranges and reject other ports' {
    Assert-True (Test-LabPortRange -Ranges @('80', '9000-9010') -Port 9005) 'Port range rejected.'
    Assert-True (-not (Test-LabPortRange -Ranges @('80', '9000-9010') -Port 3389)) 'Unrelated port accepted.'
}
Test-Case 'Outbound and UDP NSG rules do not pass inbound TCP checks' {
    $nsg = @{ SecurityRules = @(
        @{ Direction = 'Outbound'; Protocol = 'Tcp'; DestinationPortRange = '80'; Access = 'Allow'; Priority = 100 },
        @{ Direction = 'Inbound'; Protocol = 'Udp'; DestinationPortRange = '80'; Access = 'Allow'; Priority = 110 }
    ) }
    Assert-True (-not (Get-LabNsgPortRule -Nsg $nsg -Port 80 -Access Allow)) 'Wrong direction/protocol accepted.'
}
Test-Case 'An earlier deny blocks an NSG allow result' {
    $nsg = @{ SecurityRules = @(
        @{ Direction = 'Inbound'; Protocol = 'Tcp'; DestinationPortRange = '80'; Access = 'Allow'; Priority = 200 },
        @{ Direction = 'Inbound'; Protocol = '*'; DestinationPortRange = '*'; Access = 'Deny'; Priority = 100 }
    ) }
    Assert-True (-not (Get-LabNsgPortRule -Nsg $nsg -Port 80 -Access Allow)) 'Priority was ignored.'
}
Test-Case 'Augmented destination port ranges are supported' {
    $nsg = @{ SecurityRules = @(@{ Direction = 'Inbound'; Protocol = 'Tcp'; DestinationPortRanges = @('80', '9000-9010'); Access = 'Allow'; Priority = 100 }) }
    Assert-True (Get-LabNsgPortRule -Nsg $nsg -Port 9005 -Access Allow) 'Augmented rule rejected.'
}

# Storage mocks only expose local objects. No storage operation is performed.
function New-AzStorageContext { return 'mock-context' }
function Get-AzStorageFile { return [IO.FileInfo]::new('log.txt') }
function Start-AzStorageBlobCopy { $script:copyEvents.Add('copy') | Out-Null }
function Get-AzStorageBlobCopyState {
    $state = $script:copyStates.Dequeue()
    $script:copyEvents.Add($state) | Out-Null
    [pscustomobject]@{ Status = $state }
}
function Remove-AzStorageFile { $script:copyEvents.Add('delete') | Out-Null }
function Start-Sleep {}
function Write-Error { param($Message) $script:copyEvents.Add('error') | Out-Null }
$savedConnection = $env:TargetStorageConnection
try {
    $env:TargetStorageConnection = 'offline-test'
    Test-Case 'Pending copy is not deleted before Success' {
        $script:copyEvents = New-Object 'System.Collections.Generic.List[string]'
        $script:copyStates = New-Object 'System.Collections.Generic.Queue[string]'
        $script:copyStates.Enqueue('Pending'); $script:copyStates.Enqueue('Success')
        & (Read-Script 'Lab10-Source/V2-Automation/Source/Functions/LogMover/run.ps1')
        Assert-True (($script:copyEvents -join ',') -eq 'copy,Pending,Success,delete') 'Original was deleted too early.'
    }
    Test-Case 'Failed copy preserves the source file' {
        $script:copyEvents = New-Object 'System.Collections.Generic.List[string]'
        $script:copyStates = New-Object 'System.Collections.Generic.Queue[string]'
        $script:copyStates.Enqueue('Failed')
        & (Read-Script 'Lab10-Source/V2-Automation/Source/Functions/LogMover/run.ps1')
        Assert-True (-not $script:copyEvents.Contains('delete')) 'Failed copy deleted original.'
        Assert-True ($script:copyEvents.Contains('error')) 'Failed copy was not reported.'
    }
    Test-Case 'Copy timeout preserves the source file' {
        $script:copyEvents = New-Object 'System.Collections.Generic.List[string]'
        $script:copyStates = New-Object 'System.Collections.Generic.Queue[string]'
        $script:copyStates.Enqueue('Pending')
        $script:clockTick = 0
        function Get-Date { $script:clockTick++; ([datetime]'2026-01-01').AddMinutes(3 * $script:clockTick) }
        & (Read-Script 'Lab10-Source/V2-Automation/Source/Functions/LogMover/run.ps1')
        Assert-True (-not $script:copyEvents.Contains('delete')) 'Timed-out copy deleted original.'
        Assert-True ($script:copyEvents.Contains('error')) 'Timeout was not reported.'
    }
} finally { $env:TargetStorageConnection = $savedConnection }

Test-Case 'Lab03 rejects a 32 GiB data disk' {
    function Get-AzResourceGroup { [pscustomobject]@{ ResourceGroupName = 'RG-LAB03-Test'; Location = 'norwayeast' } }
    function Get-AzVM {
        [pscustomobject]@{ Name = 'vm'; HardwareProfile = @{ VmSize = 'Standard_B1ms' }; StorageProfile = @{ DataDisks = @(@{ DiskSizeGB = 32 }) }; Statuses = @(@{ Code = 'PowerState/running'; DisplayStatus = 'Running' }) }
    }
    function Get-AzResource {}
    . (Join-Path $repoRoot 'Lab03/Check-Lab3.ps1')
    Assert-True ($diskColor -eq 'Red') 'Wrong-sized disk passed.'
}
Test-Case 'Lab04 rejects a peering to an unrelated VNet' {
    function Get-AzResourceGroup { [pscustomobject]@{ ResourceGroupName = 'RG-LAB04-Test' } }
    function Get-AzVirtualNetwork {
        [pscustomobject]@{ Name = 'VNet-Admin'; Id = '/admin'; VirtualNetworkPeerings = @(@{ RemoteVirtualNetwork = @{ Id = '/unrelated' }; PeeringState = 'Connected' }) }
        [pscustomobject]@{ Name = 'VNet-Warehouse'; Id = '/warehouse'; Subnets = @() }
    }
    function Get-AzVM {}
    . (Join-Path $repoRoot 'Lab04/Check-Lab4.ps1')
    Assert-True ($peerColor -eq 'Red') 'Unrelated peering passed.'
}
Test-Case 'Two SQL servers without a replication link do not pass' {
    function Get-AzResourceGroup { [pscustomobject]@{ ResourceGroupName = 'RG-LAB07-Test' } }
    function Get-AzSqlServer { @([pscustomobject]@{ ServerName = 'one'; ResourceGroupName = 'RG-LAB07-Test' }, [pscustomobject]@{ ServerName = 'two'; ResourceGroupName = 'RG-LAB07-Test' }) }
    function Get-AzSqlDatabase { [pscustomobject]@{ DatabaseName = 'db' } }
    function Get-AzSqlDatabaseReplicationLink {}
    function Get-AzSqlDatabaseDataMaskingRule {}
    function Get-AzCosmosDBAccount {}
    . (Join-Path $repoRoot 'Lab07/Check-Lab7.ps1')
    Assert-True ($repColor -eq 'Red') 'Two servers were mistaken for replication.'
}
Test-Case 'Both exam payloads fail missing required files despite unrelated txt files' {
    function Get-LocalUser { [pscustomobject]@{ SID = 'student-sid' } }
    function Get-LocalGroupMember { [pscustomobject]@{ SID = 'student-sid' } }
    function Get-Volume { [pscustomobject]@{ FileSystemLabel = 'Data' } }
    function Test-Path { return $true }
    function Get-ChildItem { [pscustomobject]@{ Name = 'unrelated.txt' } }
    foreach ($path in @('SAT-egzaminas/#2026_check_results.ps1', 'SAT-egzaminas/#2026_check_results2.ps1')) {
        $ast = (Read-Script $path).Ast
        $assignment = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$ScriptContent' }, $true)
        $payload = $assignment.Right.PipelineElements[0].Expression.Value
        $output = & ([scriptblock]::Create($payload))
        $result = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($output.Substring('EXAM_JSON:'.Length))) | ConvertFrom-Json
        Assert-True ($result.Checks.FOUND_DUMPFILE -eq 'FAIL') 'Missing dumpfile was not failed.'
        Assert-True ($result.Checks.FOUND_INFO -eq 'FAIL') 'Missing info files were not failed.'
        Assert-True (@($result.Checks.PSObject.Properties).Count -eq 6) 'Grading denominator is not fixed.'
    }
}
Test-Case 'V2 deployment stops when Azure CLI fails' {
    function az { $global:LASTEXITCODE = 1 }
    function Compress-Archive {}
    function Remove-Item {}
    $thrown = $false
    try { & (Join-Path $repoRoot 'Lab10-Source/V2-Automation/Build/Deploy-App.ps1') -ResourceGroup rg -WebAppName web } catch { $thrown = $true }
    Assert-True $thrown 'Deployment failure was reported as success.'
}
Microsoft.PowerShell.Utility\Write-Host "All $script:passed offline regression tests passed."
