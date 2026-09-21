# --- KONFIGURACIJA / CONFIGURATION ---
param (
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionName, 

    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,    
    
    # Jei VMName nenurodytas, automatiškai pasirenkame tik vienintelę VM.
    [string]$VMName = "",           

    [string]$InstructorEmail = "Mantas.Bartkevicius@kaunokolegija.lt",
    [switch]$StartVM
)

# Kintamieji
$global:Report = New-Object System.Collections.ArrayList
$global:FileContents = New-Object System.Collections.ArrayList 
$global:AzTotal = 0; $global:AzPass = 0; $global:WinTotal = 0; $global:WinPass = 0

function Log-Result {
    param ([string]$Category, [string]$Item, [string]$Status, [string]$Details)
    if ($Category -eq "Azure") { $global:AzTotal++; if ($Status -eq "OK") { $global:AzPass++ } }
    elseif ($Category -eq "Windows") { $global:WinTotal++; if ($Status -eq "OK") { $global:WinPass++ } }

    $obj = [PSCustomObject]@{ Kategorija=$Category; Tikrinimas=$Item; Busena=$Status; Detales=$Details }
    $global:Report.Add($obj) | Out-Null
    $Color = "Red"; if ($Status -eq "OK") { $Color = "Green" }
    Write-Host "[$Category][$Status] $Item - $Details" -ForegroundColor $Color
}

# --- 1. AZURE TIKRINIMAS ---
Write-Host "`n--- START: AZURE CHECKS ($SubscriptionName) ---" -ForegroundColor Cyan
if (-not (Get-AzContext)) { Connect-AzAccount }

# 1.1 Prenumerata & IAM
try {
    $subscriptions = @(Get-AzSubscription -SubscriptionName $SubscriptionName -ErrorAction Stop)
    if ($subscriptions.Count -ne 1) { throw "Prenumeratos pavadinimas turi atitikti vieną prenumeratą." }
    $Sub = $subscriptions[0]
    Set-AzContext -SubscriptionId $Sub.Id -TenantId $Sub.TenantId -ErrorAction Stop | Out-Null
    Log-Result "Azure" "Prenumerata" "OK" "Rasta: $($Sub.Name)"
} catch { Log-Result "Azure" "Prenumerata" "FAIL" "Nerasta arba nepavyko pasirinkti"; throw }

$scope = "/subscriptions/$($Sub.Id)"
try {
    $Role = @(Get-AzRoleAssignment -SignInName $InstructorEmail -Scope $scope -ErrorAction Stop | Where-Object {
        $_.RoleDefinitionName -eq 'Contributor' -and $_.Scope.TrimEnd('/') -eq $scope
    })
    if ($Role.Count -gt 0) { Log-Result 'Azure' 'IAM Prieiga' 'OK' 'Contributor prenumeratoje' }
    else { Log-Result 'Azure' 'IAM Prieiga' 'FAIL' 'Nerasta tiesioginė Contributor rolė prenumeratoje' }
} catch { Log-Result 'Azure' 'IAM Prieiga' 'FAIL' "Nepavyko patikrinti: $($_.Exception.Message)" }

# 1.2 RG & Tags
$RG = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue
if ($RG) {
    if ($RG.Location -in @("polandcentral", "swedencentral", "germanywestcentral")) { Log-Result "Azure" "RG Regionas" "OK" "Tinkamas" } else { Log-Result "Azure" "RG Regionas" "FAIL" "Netinkamas" }
    
    $tags = $RG.Tags
    $tagStr = if ($tags) { ($tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; " } else { "Nera" }
    if ($tags -and (($tags["Environment"] -eq "Exam") -or ($tags["Enviroment"] -eq "Exam"))) { Log-Result "Azure" "RG Zymos" "OK" $tagStr } else { Log-Result "Azure" "RG Zymos" "FAIL" $tagStr }
} else { Log-Result "Azure" "RG Grupe" "FAIL" "Nerasta"; return }

# 1.3 AUTO-DETECT VNet (Nauja dalis)
$VNet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue | Select-Object -First 1
if ($VNet) {
    if ($VNet.Name -like "VNet-*") {
        Log-Result "Azure" "VNet Tinklas" "OK" "Rastas: $($VNet.Name)"
    } else {
        Log-Result "Azure" "VNet Tinklas" "FAIL" "Rastas, bet blogas pavadinimas: $($VNet.Name)"
    }
} else {
    Log-Result "Azure" "VNet Tinklas" "FAIL" "Nerasta jokio Virtual Network"
}

# 1.4 AUTO-DETECT VM (Esminis pakeitimas)
# Ieskome bet kokio VM toje grupeje
$FoundVMs = @(Get-AzVM -ResourceGroupName $ResourceGroup -ErrorAction Stop)
if ($VMName) { $FoundVMs = @($FoundVMs | Where-Object Name -eq $VMName) }
if ($FoundVMs.Count -gt 1) { throw 'Grupėje yra kelios VM. Nurodykite -VMName.' }
$VM = $null

if ($FoundVMs) {
    # Imame pirma rasta serveri
    $VM = $FoundVMs | Select-Object -First 1
    $DetectedName = $VM.Name
    
    # Patikriname ar pavadinimas atitinka standarta (VM1-...)
    if ($DetectedName -like "VM1-*") {
        Log-Result "Azure" "VM Serveris" "OK" "Rastas: $DetectedName (Auto-detected)"
    } else {
        Log-Result "Azure" "VM Serveris" "OK" "Rastas: $DetectedName (Nestandartinis vardas)"
    }
    
    # Atnaujiname kintamaji, kad Windows dalis zinotu prie ko jungtis
    $VMName = $DetectedName 

    # HDD Tikrinimas
    $DataDisks = @($VM.StorageProfile.DataDisks)
    $validDisks = @($DataDisks | Where-Object { $_.DiskSizeGB -ge 128 })
    if ($validDisks.Count -gt 0) { Log-Result 'Azure' 'HDD Dydis' 'OK' 'Rastas bent 128 GiB duomenų diskas' }
    else { Log-Result 'Azure' 'HDD Dydis' 'FAIL' 'Nerastas bent 128 GiB duomenų diskas' }

} else {
    Log-Result "Azure" "VM Serveris" "FAIL" "Grupeje '$ResourceGroup' nerasta jokiu serveriu."
    return
}

# --- 2. WINDOWS TIKRINIMAS ---
Write-Host "`n--- START: WINDOWS INTERNAL CHECKS ($VMName) ---" -ForegroundColor Cyan

$VMStatus = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName -Status -ErrorAction Stop
$powerState = ($VMStatus.Statuses | Where-Object Code -like 'PowerState/*' | Select-Object -First 1).Code
if ($powerState -ne 'PowerState/running') {
    if (-not $StartVM) { throw 'VM išjungta. Įjunkite ją arba nurodykite -StartVM (po patikros VM liks įjungta).' }
    Start-AzVM -ResourceGroupName $ResourceGroup -Name $VMName -NoWait -ErrorAction Stop | Out-Null
    $deadline = (Get-Date).AddMinutes(5)
    do {
        if ((Get-Date) -ge $deadline) { throw 'VM neįsijungė per 5 minutes.' }
        Start-Sleep -Seconds 10
        $status = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName -Status -ErrorAction Stop
        $powerState = ($status.Statuses | Where-Object Code -like 'PowerState/*' | Select-Object -First 1).Code
    } while ($powerState -ne 'PowerState/running')
}
$TempScriptPath = Join-Path ([IO.Path]::GetTempPath()) ('ExamCheck-' + [guid]::NewGuid().ToString('N') + '.ps1')
$ScriptContent = @'
$checks = [ordered]@{ User_Rezultatai = 'FAIL'; User_Admin = 'FAIL'; Disk_F = 'FAIL'; Disk_Label = 'FAIL'; FOUND_DUMPFILE = 'FAIL'; FOUND_INFO = 'FAIL' }
$contents = @()
$user = Get-LocalUser -Name 'Rezultatai' -ErrorAction SilentlyContinue
if ($user) {
    $checks.User_Rezultatai = 'OK'
    $members = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction SilentlyContinue)
    if ($members | Where-Object { $_.SID -eq $user.SID }) { $checks.User_Admin = 'OK' }
}
if (Test-Path 'F:\') {
    $checks.Disk_F = 'OK'
    $volume = Get-Volume -DriveLetter F -ErrorAction SilentlyContinue
    if ($volume.FileSystemLabel -eq 'Data') { $checks.Disk_Label = 'OK' }
    $files = @(Get-ChildItem -LiteralPath 'F:\' -Filter '*.txt' -File -Recurse -ErrorAction SilentlyContinue)
    if ($files | Where-Object Name -eq 'dumpfile.txt') { $checks.FOUND_DUMPFILE = 'OK' }
    $infoFiles = @($files | Where-Object Name -like 'info*.txt')
    if ($infoFiles.Count -gt 0) {
        $checks.FOUND_INFO = 'OK'
        # Run Command atsakymas ribotas: grąžiname iki dviejų failų ištraukas.
        foreach ($file in ($infoFiles | Select-Object -First 2)) {
            try {
                $reader = [IO.File]::OpenText($file.FullName)
                try {
                    $buffer = New-Object char[] 128
                    $length = $reader.Read($buffer, 0, $buffer.Length)
                    $preview = ''
                    if ($length -gt 0) { $preview = -join $buffer[0..($length - 1)] }
                    $truncated = -not $reader.EndOfStream
                } finally { $reader.Dispose() }
                $contents += @{ Name = $file.Name; Preview = $preview; Truncated = $truncated }
            } catch { $checks.FOUND_INFO = 'FAIL' }
        }
    }
}
$result = @{ Checks = $checks; Files = $contents } | ConvertTo-Json -Depth 5 -Compress
Write-Output ('EXAM_JSON:' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($result)))
'@
$expectedChecks = @('User_Rezultatai', 'User_Admin', 'Disk_F', 'Disk_Label', 'FOUND_DUMPFILE', 'FOUND_INFO')
$internal = $null
try {
    Set-Content -LiteralPath $TempScriptPath -Value $ScriptContent -Encoding UTF8 -ErrorAction Stop
    $run = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -Name $VMName -CommandId 'RunPowerShellScript' -ScriptPath $TempScriptPath -ErrorAction Stop
    $output = @($run.Value | ForEach-Object { $_.Message }) -join "`n"
    if ($output -notmatch 'EXAM_JSON:([A-Za-z0-9+/=]+)') { throw 'VM negrąžino patikros duomenų.' }
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1]))
    $internal = $json | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Warning "Windows patikra nepavyko: $($_.Exception.Message)"
} finally {
    if (Test-Path -LiteralPath $TempScriptPath) { Remove-Item -LiteralPath $TempScriptPath -Force }
}
# Vardiklis fiksuotas: dingę rezultatai ir nerasti failai visuomet FAIL.
foreach ($check in $expectedChecks) {
    $status = 'FAIL'
    if ($internal -and $internal.Checks.$check -eq 'OK') { $status = 'OK' }
    Log-Result 'Windows' $check $status 'VM patikra'
}
foreach ($file in $internal.Files) {
    $suffix = if ($file.Truncated) { ' (ištrauka)' } else { '' }
    $global:FileContents.Add("--- TURINYS: $($file.Name)$suffix ---`n$($file.Preview)`n") | Out-Null
}
Write-Host 'VM būsena po patikros nekeičiama.' -ForegroundColor Yellow

# --- 3. REZULTATAI ---
$AzScore = 0; if ($global:AzTotal -gt 0) { $AzScore = [math]::Round(($global:AzPass / $global:AzTotal) * 100, 0) }
$WinScore = 0; if ($global:WinTotal -gt 0) { $WinScore = [math]::Round(($global:WinPass / $global:WinTotal) * 100, 0) }

$Header = @"
=========================================
REZULTATU ATASKAITA (REPORT)
Studentas: $SubscriptionName
Data: $(Get-Date)
=========================================
AZURE: $AzScore % ($global:AzPass/$global:AzTotal)
WINDOWS: $WinScore % ($global:WinPass/$global:WinTotal)
"@

$TableText = $global:Report | Format-Table -AutoSize | Out-String
$FilesText = "`n--- FAILU TURINYS ---`n" + ($global:FileContents -join "`n")

Write-Host $Header -ForegroundColor Magenta
Write-Host $TableText
Write-Host $FilesText -ForegroundColor Gray

$FinalContent = $Header + $TableText + $FilesText
$FinalContent | Out-File -FilePath "Result_$($SubscriptionName).txt" -Encoding UTF8
Write-Host "Issaugota i faila." -ForegroundColor Cyan
