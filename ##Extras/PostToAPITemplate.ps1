$scriptName = 'TelementryTest'  # change per script

$success  = $true
$errorMsg = $null

try {
    # --- your real script logic here ---
    # if anything fails, it will drop to catch
}
catch {
    $success  = $false
    $errorMsg = $_.Exception.Message
}


$payload = @{
    script = $scriptName
    host   = $env:COMPUTERNAME
    ok     = [int]$success
    error  = $errorMsg

}


$maxRetries   = 5
$delaySeconds = 10

for ($i = 1; $i -le $maxRetries; $i++) {
    try {
        $resp = Invoke-RestMethod -Uri "https://telementry.isame12.no/telemmentry.php" `
            -Method Post `
            -Headers @{
                "Content-Type" = "application/json"
                "X-Api-Key"    = "BRRRRR_skibidi_dop_dop_dop_yes_yes!"
            } `
            -Body ($payload | ConvertTo-Json -Depth 5) `
            -ErrorAction Stop

        Write-Output "Telemetry sent (attempt $i). Server replied: $resp"
        break
    }
    catch {
        if ($i -eq $maxRetries) {
            Write-Output "Telemetry failed after $maxRetries attempts: $($_.Exception.Message)"
        } else {
            Write-Output "Attempt $i failed: $($_.Exception.Message). Retrying in $delaySeconds seconds..."
            Start-Sleep -Seconds $delaySeconds
        }
    }
}