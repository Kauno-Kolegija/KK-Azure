# English launcher

$Lang = "EN"

try {
    Invoke-RestMethod `
        "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab04/Check-Lab4.ps1" `
        -ErrorAction Stop |
        Invoke-Expression
}
catch {
    Write-Error "Failed to load LAB 4 validation script."
    throw
}