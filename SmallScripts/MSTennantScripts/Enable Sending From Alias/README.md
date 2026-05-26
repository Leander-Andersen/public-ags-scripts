# Enable Sending From Alias

Enables the tenant-wide **Send From Alias** setting in Exchange Online so that users can send email from any of their Outlook aliases — not just their primary address. This is a one-time tenant configuration that Microsoft does not enable by default.

Requires a **Global Administrator** or **Exchange Online Administrator** account.

## Usage

Run in PowerShell as a regular user (no local admin required):

```powershell
.\EnableSendingFromAlias.ps1
```

You will be prompted for your admin UPN and then taken through a modern auth / MFA sign-in in the browser.

## What it does

| Step | Detail |
|---|---|
| Module check | Installs `ExchangeOnlineManagement` from the PowerShell Gallery if not already present |
| Sign in | Connects to Exchange Online with modern auth — supports MFA |
| Check state | Reads the current `SendFromAliasEnabled` value on the organisation config |
| Enable | If not already enabled, sets `SendFromAliasEnabled = $true` and verifies the change applied |
| Clean up | Disconnects the Exchange Online session and clears variables from memory |

If the setting is already enabled the script reports this and exits cleanly without making any changes.

## After running

Users may need to close and reopen Outlook before the new setting takes effect. The change applies to the entire tenant — no per-user configuration is needed.
