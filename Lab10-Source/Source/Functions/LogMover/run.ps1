param($Timer)

$connStr = $env:TargetStorageConnection
$shareName = "logs"
$containerName = "archyvas"

Write-Host "--- Perkelti log failus ---"

# 1. Prisijungimas
if ([string]::IsNullOrEmpty($connStr)) { Write-Error "Nėra Connection String"; return }
$ctx = New-AzStorageContext -ConnectionString $connStr

# 2. Gauname failų sąrašą
try {
    Write-Host " -- Skaitomi failai iš '$shareName' katalogo..."
    
    $items = Get-AzStorageFile -ShareName $shareName -Path "" -Context $ctx -ErrorAction Stop
    # Filtruojame tik .txt failus
    $filesToMove = $items | Where-Object { 
        $_.GetType().Name -match "File" -and 
        !([string]::IsNullOrEmpty($_.Name)) -and
        $_.Name.EndsWith(".txt") 
    }

    if ($filesToMove -and @($filesToMove).Count -gt 0) {
        $count = @($filesToMove).Count
        Write-Host " -- Rasta $count failų perkėlimui"
        Write-Host " -- -----------------------------"

        foreach ($file in $filesToMove) {
            $name = $file.Name
            Write-Host "   -> Kopijuoja: $name"

            try {
                # Kopijuojame į Blob
                Start-AzStorageBlobCopy -SrcShareName $shareName `
                                        -SrcFilePath $name `
                                        -DestContainer $containerName `
                                        -DestBlob $name `
                                        -Context $ctx `
                                        -DestContext $ctx `
                                        -Force -ErrorAction Stop | Out-Null
                Start-Sleep -Milliseconds 200
                Remove-AzStorageFile -ShareName $shareName -Path $name -Context $ctx
                Write-Host "   -x Perkelta ir ištrinta"
            } catch {
                Write-Error "    ! KLAIDA su failu $name : $_"
            }
        }
    } else {
        Write-Host "*.txt failų kataloge nėra."
    }

} catch {
    Write-Error "KRITINĖ KLAIDA: $_"
}

# 3. Pabaiga
Write-Host "--- PABAIGA ---"
