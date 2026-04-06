# Azure Functions profile.ps1
# This runs when the PowerShell worker starts.

if ($env:MSI_SECRET) {
    Disable-AzContextAutosave -Scope Process | Out-Null
    # Mes naudojame Managed Identity, bet jūsų atveju connection string veiks ir be šito.
    # Tačiau šis failas padeda išvengti klaidų ateityje.
    Connect-AzAccount -Identity
}