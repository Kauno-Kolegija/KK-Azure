# --- KONFIGURACIJA / CONFIGURATION ---
param (
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionName, 

    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,    
    
    # VMName nebereikalingas, nes surasime patys, 
    # bet paliekame del suderinamumo (jei nurodysite - ignoruosime arba tikrinsime)
    [string]$VMName = "",           

    [string]$InstructorEmail = "Mantas.Bartkevicius@kaunokolegija.lt"
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
    $Sub = Get-AzSubscription -SubscriptionName $SubscriptionName -ErrorAction Stop
    Select-AzSubscription -Subscription $Sub | Out-Null
    Log-Result "Azure" "Prenumerata" "OK" "Rasta: $($Sub.Name)"
} catch { Log-Result "Azure" "Prenumerata" "FAIL" "Nerasta" }

$Role = Get-AzRoleAssignment -IncludeClassicAdministrators | Where-Object { $_.SignInName -eq $InstructorEmail -or $_.DisplayName -like "*Mantas Bartkevičius*" }
if ($Role) { Log-Result "Azure" "IAM Prieiga" "OK" "Yra" } else { Log-Result "Azure" "IAM Prieiga" "FAIL" "Nera" }

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
$FoundVMs = Get-AzVM -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
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
    $DataDisk = $VM.StorageProfile.DataDisks | Where-Object { $_.Name -like "*Data*" -or $_.Name -like "*$DetectedName*" } 
    if ($DataDisk) {
        $RealDisk = Get-AzDisk -ResourceGroupName $ResourceGroup -DiskName $DataDisk.Name
        if ($RealDisk.DiskSizeGB -ge 128) { Log-Result "Azure" "HDD Dydis" "OK" "$($RealDisk.DiskSizeGB) GB" } else { Log-Result "Azure" "HDD Dydis" "FAIL" "$($RealDisk.DiskSizeGB) GB" }
    } else { Log-Result "Azure" "HDD Dydis" "FAIL" "Nera" }

} else {
    Log-Result "Azure" "VM Serveris" "FAIL" "Grupeje '$ResourceGroup' nerasta jokiu serveriu."
    return
}

# --- 2. WINDOWS TIKRINIMAS ---
Write-Host "`n--- START: WINDOWS INTERNAL CHECKS ($VMName) ---" -ForegroundColor Cyan

$VMStatus = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName -Status
if ($VMStatus.Statuses[1].Code -ne "PowerState/running") {
    Write-Host "Ijungiamas serveris... (Laukite ~2 min)" -ForegroundColor Yellow
    Start-AzVM -ResourceGroupName $ResourceGroup -Name $VMName -NoWait
    do { Start-Sleep -Seconds 10; Write-Host "." -NoNewline -ForegroundColor Gray; $S = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName -Status } while ($S.Statuses[1].Code -ne "PowerState/running")
    Write-Host "`nServeris veikia. Laukiama agento (90 sek)..." -ForegroundColor Green
    Start-Sleep -Seconds 90
} else { Write-Host "Serveris veikia. Laukiama (10 sek)..."; Start-Sleep -Seconds 10 }

$TempScriptPath = "$env:TEMP\AutoCheck_$($VMName).ps1"

# --- SERVERIO VIDAUS KODAS ---
$ScriptContent = @"
`$Res = @()

# 1. Vartotojai
if (Get-LocalUser -Name "Rezultatai" -ErrorAction SilentlyContinue) { `$Res += "User_Rezultatai:OK" } else { `$Res += "User_Rezultatai:FAIL" }
if (Get-LocalGroupMember -Group "Administrators" | Where-Object {`$_.Name -like "*Rezultatai*"}) { `$Res += "User_Admin:OK" } else { `$Res += "User_Admin:FAIL" }

# 2. F: Diskas
if (Test-Path "F:\") {
    `$Vol = Get-Volume -DriveLetter F
    if (`$Vol.FileSystemLabel -eq "Data") { `$Res += "Disk_Label:OK" } else { `$Res += "Disk_Label:FAIL" }

    # 3. Ieskome failu
    `$files = Get-ChildItem -Path "F:\" -Filter "*.txt" -Recurse -ErrorAction SilentlyContinue
    
    if (`$files) {
        foreach (`$f in `$files) {
            if (`$f.Name -like "dumpfile.txt") {
                `$Res += "FOUND_DUMPFILE:OK"
            } 
            elseif (`$f.Name -like "info*.txt") {
                `$Res += "FOUND_TXT_`$(`$f.Name):OK"
                try {
                    `$bytes = [System.IO.File]::ReadAllBytes(`$f.FullName)
                    `$b64 = [Convert]::ToBase64String(`$bytes)
                    `$safeName = `$f.Name -replace '[^a-zA-Z0-9]', ''
                    `$Res += "CONTENT_`$(`$safeName):`$b64"
                } catch {
                   `$Res += "CONTENT_ERROR:Failas nenuskaitytas"
                }
            }
        }
    } else {
         `$Res += "SEARCH_TXT:FAIL_NerastaJokiuFailu"
    }
} else {
    `$Res += "Disk_F:FAIL_Nerastas"
}

Write-Output (`$Res -join ";")
"@

Set-Content -Path $TempScriptPath -Value $ScriptContent -Encoding ASCII

try {
    Write-Host "Vykdomas kodas serveryje..." -ForegroundColor Cyan
    $Run = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -Name $VMName -CommandId 'RunPowerShellScript' -ScriptPath $TempScriptPath -ErrorAction Stop
    
    $StringOutput = ""
    if ($Run.Value -and $Run.Value.Message) { $StringOutput = $Run.Value.Message }
    elseif ($Run.Value -and $Run.Value.Value) { $StringOutput = $Run.Value.Value }
    elseif ($Run.Message) { $StringOutput = $Run.Message }
    elseif ($Run.Output) { $StringOutput = $Run.Output }
    elseif ($Run -is [string]) { $StringOutput = $Run }
    else { $StringOutput = $Run | Out-String }

    if ([string]::IsNullOrWhiteSpace($StringOutput)) {
        Log-Result "Windows" "Check" "FAIL" "Serveris negražino duomenų."
    } else {
        $InternalResults = $StringOutput -split ";"
        foreach ($R in $InternalResults) {
            $R = $R.Trim()
            if ([string]::IsNullOrEmpty($R)) { continue }
            if ($R -notmatch "^(User_|Disk_|FOUND_|CONTENT_|SEARCH_)") { continue }

            $Parts = $R -split ":", 2
            
            if ($Parts[0] -like "CONTENT_*") {
                if ($Parts[1] -ne "Failas nenuskaitytas" -and $Parts[1] -ne "ErrorReadingFile") {
                    try {
                        $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Parts[1]))
                        $fName = $Parts[0].Replace("CONTENT_", "")
                        $global:FileContents.Add("--- TURINYS: $fName ---`n$decoded`n") | Out-Null
                    } catch {}
                }
            } elseif ($Parts.Count -ge 2) {
                $CheckName = $Parts[0]
                $CheckStatus = $Parts[1]
                if ($CheckName -eq "FOUND_DUMPFILE") { Log-Result "Windows" "Failas: dumpfile" $CheckStatus "Rastas" }
                elseif ($CheckName -like "FOUND_TXT_*") { Log-Result "Windows" "Failas: $($CheckName.Replace('FOUND_TXT_', ''))" $CheckStatus "Rastas/Nuskaitytas" }
                else { Log-Result "Windows" $CheckName $CheckStatus "Vidinis" }
            }
        }
    }

} catch {
    Log-Result "Windows" "Klaida" "FAIL" "Skripto klaida: $($_.Exception.Message)"
} finally {
    if (Test-Path $TempScriptPath) { Remove-Item $TempScriptPath -ErrorAction SilentlyContinue }
}

Write-Host "Serveris paliekamas ijungtas..." -ForegroundColor Yellow

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