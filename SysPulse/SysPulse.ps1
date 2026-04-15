#Requires -Version 5.1
<#
.SYNOPSIS
    SysPulse  - Windows System Diagnostic & Analysis Tool
.DESCRIPTION
    Collects, analyses, and reports on hardware, firmware, drivers, power,
    security, and event-log data on any Windows machine regardless of
    manufacturer.  All output is written to a timestamped folder so the
    results can be attached to a support ticket or reviewed offline.
.NOTES
    Version : 1.0
    Requires: Windows 10/11, PowerShell 5.1+
              Must be run as Administrator for full data collection.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# -----------------------------------------------------------------------------
#  GLOBAL CONSTANTS
# -----------------------------------------------------------------------------
$Script:VERSION   = '1.0'
$Script:TOOL_NAME = 'SysPulse'
$Script:OutRoot   = ''          # populated by New-OutputFolder

# -----------------------------------------------------------------------------
#  EMBEDDED SMTP CONFIG  (managed by Invoke-PackageSmtp  -  do not edit manually)
#  Password is AES-256 encrypted.  Key and ciphertext are both required to decrypt.
# =SMTP-BEGIN=
$Script:_SmtpServer = ''
$Script:_SmtpPort   = 587
$Script:_SmtpSSL    = $true
$Script:_SmtpFrom   = ''
$Script:_SmtpTo     = ''
$Script:_SmtpUser   = ''
$Script:_SmtpEPwd   = ''
$Script:_SmtpKey    = ''
# =SMTP-END=
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
#  SECTION 1  - USER INTERFACE & HELP
# -----------------------------------------------------------------------------

function SysPulseHelp {
    <#
    .SYNOPSIS Displays the built-in help text and changelog.
    #>
    $help = @"

+==============================================================================+
|              SysPulse v$($Script:VERSION)  - Windows Diagnostic Tool                     |
+==============================================================================+

USAGE
  Run the script then choose an option from the interactive menu, or call
  individual functions directly in a PowerShell session after dot-sourcing:
      . .\SysPulse.ps1

FUNCTIONS (by category)
  System Detection  : ProcDetect
  BIOS / Firmware   : Show-BiosInfo, Get-BatteryFirmware, Get-ECFirmwareVersion,
                      Get-TouchpadFirmwareVersion
  Power Management  : Show-PowerButtonActions, Show-LidCloseActions,
                      Show-CriticalBatteryActions, Show-PowerSlider
  Battery & Thermal : Get-ChargePercent, Get-Temperature
  Hardware          : Get-BluetoothInfo, Show-DeviceManagerStatus, Get-DiskSmartData
  Memory            : Get-MemoryDetails
  Display           : Get-DisplayScale, Get-DSCStatus
  Applications      : Get-TeamsVersion, Get-OfficeVersion, Get-ZoomVersion,
                      Test-ProgramInstalled <name>
  Events & History  : Get-RebootHistory, Get-UnexpectedShutdownCount, Get-WEREvents
  System Health     : Invoke-KnownIssuesScan, Get-MissingWindowsUpdates
  Data Collection   : Invoke-QuickData, Invoke-PowerBattery, Invoke-NetworkWAN,
                      Invoke-BootSecurity, Invoke-HWDDriver, Invoke-WINEvtDump,
                      Invoke-WINPreload, Invoke-All
  Crash Dumps       : Find-KernelDumps, Get-MiniDumps
  Analysis          : Invoke-IdleAnalysis, ConvertTo-HtmlReport
  Utility           : Get-ActiveFirewall, Get-PluginVersion <path>,
                      Get-RegistryData <path>

CHANGELOG
  1.0   - Initial release.  Manufacturer-agnostic rewrite of the original
          Lenovo-only CDAT tool.  All Lenovo WMI / BIOS interfaces removed;
          replaced with standard Windows WMI, CIM, registry, and event-log
          queries that work on any OEM hardware.

"@
    $help | more
}

function Show-VersionBanner {
    Write-Host ""
    Write-Host "  +============================================================+" -ForegroundColor Cyan
    Write-Host "  |                                                            |" -ForegroundColor Cyan
    Write-Host "  |   ____   _   _  ___   ____  _   _  _   ___   ___           |" -ForegroundColor Cyan
    Write-Host "  |  / ___| | | | |/ __| |  _ \| | | || | / __| / _ \          |" -ForegroundColor Cyan
    Write-Host "  |  \___ \ | |_| |\__ \ | |_) | |_| || | \__ \|  __/          |" -ForegroundColor Cyan
    Write-Host "  |   ___) | \__, ||___/ |  __/ \__,_||_| |___/ \___|          |" -ForegroundColor Cyan
    Write-Host "  |  |____/  |___/       |_|                                   |" -ForegroundColor Cyan
    Write-Host "  |                                                            |" -ForegroundColor DarkCyan
    Write-Host "  |      Windows System Diagnostic & Analysis Tool  v$($Script:VERSION)       |" -ForegroundColor DarkCyan
    Write-Host "  +============================================================+" -ForegroundColor Cyan
    Write-Host ""
}

# -----------------------------------------------------------------------------
#  SECTION 2  - INTERNAL HELPERS
# -----------------------------------------------------------------------------

function New-OutputFolder {
    <# Creates a timestamped output directory and sets $Script:OutRoot. #>
    $stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
    $serial  = (Get-CimInstance Win32_BIOS).SerialNumber -replace '[\\/:*?"<>|]', '_'
    $folder  = "$env:USERPROFILE\Desktop\SysPulse_${serial}_${stamp}"
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $Script:OutRoot = $folder
    Write-Host "  Output folder: $folder" -ForegroundColor Green
    return $folder
}

function Write-Log {
    param(
        [string]$Path,
        [string]$Content,
        [switch]$Append
    )
    if ($Append) {
        Add-Content -Path $Path -Value $Content -Encoding UTF8
    } else {
        Set-Content  -Path $Path -Value $Content -Encoding UTF8
    }
}

function Get-RegistryData {
    <#
    .SYNOPSIS
        Reads all values under a registry key and returns them as a hashtable.
    .PARAMETER KeyPath
        Full registry path, e.g. 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    #>
    param([string]$KeyPath)
    $result = [ordered]@{}
    if (Test-Path $KeyPath) {
        $item = Get-Item -Path $KeyPath
        foreach ($name in $item.GetValueNames()) {
            $result[$name] = $item.GetValue($name)
        }
    }
    return $result
}

function Get-PluginVersion {
    <#
    .SYNOPSIS Reads the embedded version resource from an executable or DLL.
    .PARAMETER FilePath  Full path to the binary.
    #>
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) {
        Write-Warning "File not found: $FilePath"
        return $null
    }
    $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($FilePath)
    return [PSCustomObject]@{
        ProductVersion = $vi.ProductVersion
        FileVersion    = $vi.FileVersion
        CompanyName    = $vi.CompanyName
        Description    = $vi.FileDescription
    }
}

function Test-ProgramInstalled {
    <#
    .SYNOPSIS Returns $true if an application with the given display name is found in the registry.
    .PARAMETER Name  Full or partial display name of the application.
    #>
    param([string]$Name)
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($path in $regPaths) {
        $found = Get-ItemProperty $path |
                 Where-Object { $_.DisplayName -like "*$Name*" }
        if ($found) { return $true }
    }
    return $false
}

function Convert-WuaResultCodeToName {
    param([int]$Code)
    switch ($Code) {
        1 { 'In Progress' }
        2 { 'Succeeded' }
        3 { 'Succeeded With Errors' }
        4 { 'Failed' }
        5 { 'Aborted' }
        default { "Unknown ($Code)" }
    }
}

function Get-WuaHistory {
    <# Returns the Windows Update installation history as objects. #>
    try {
        $session    = New-Object -ComObject Microsoft.Update.Session
        $searcher   = $session.CreateUpdateSearcher()
        $histCount  = $searcher.GetTotalHistoryCount()
        if ($histCount -eq 0) { return @() }
        $entries = $searcher.QueryHistory(0, $histCount)
        $results = foreach ($e in $entries) {
            [PSCustomObject]@{
                Date        = $e.Date
                Title       = $e.Title
                Result      = Convert-WuaResultCodeToName $e.ResultCode
                Description = $e.Description
            }
        }
        return $results
    } catch {
        Write-Warning "Could not retrieve WUA history: $_"
        return @()
    }
}

function Get-NumberOfDays {
    param([datetime]$Start, [datetime]$End)
    return [math]::Ceiling(($End - $Start).TotalDays)
}

# -----------------------------------------------------------------------------
#  SECTION 3  - SYSTEM DETECTION
# -----------------------------------------------------------------------------

function ProcDetect {
    <#
    .SYNOPSIS
        Identifies the processor family (Intel / AMD / ARM-Qualcomm / other).
    .OUTPUTS
        Returns a string: 'Intel', 'AMD', 'ARM', or 'Unknown'.
        Also writes a console message.
    #>
    $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
    $family = switch -Wildcard ($cpu) {
        '*Intel*'      { 'Intel' }
        '*AMD*'        { 'AMD'   }
        '*Qualcomm*'   { 'ARM'   }
        '*ARM*'        { 'ARM'   }
        default        { 'Unknown' }
    }
    Write-Host "  Processor family detected: $family ($cpu)" -ForegroundColor Cyan
    return $family
}

# -----------------------------------------------------------------------------
#  SECTION 4  - BIOS & FIRMWARE
# -----------------------------------------------------------------------------

function Show-BiosInfo {
    <#
    .SYNOPSIS
        Displays BIOS / UEFI information from standard Windows WMI.
    #>
    $bios = Get-CimInstance Win32_BIOS
    $board = Get-CimInstance Win32_BaseBoard
    Write-Host "`n  -- BIOS / Firmware --------------------------------" -ForegroundColor Yellow
    Write-Host ("  Manufacturer : {0}" -f $bios.Manufacturer)
    Write-Host ("  Version      : {0}" -f $bios.SMBIOSBIOSVersion)
    Write-Host ("  Release Date : {0}" -f $bios.ReleaseDate)
    Write-Host ("  Serial       : {0}" -f $bios.SerialNumber)
    Write-Host ("  Board Mfr    : {0}" -f $board.Manufacturer)
    Write-Host ("  Board Product: {0}" -f $board.Product)
    Write-Host ("  Board Version: {0}" -f $board.Version)
    Write-Host ""
    return $bios
}

function Get-BatteryFirmware {
    <#
    .SYNOPSIS
        Reads the battery firmware / chemistry version from the registry.
    #>
    $batKey = 'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI'
    $batPath = Get-ChildItem $batKey -Recurse |
               Where-Object { $_.PSChildName -like 'PNP0C0A*' -or $_.Name -like '*Battery*' } |
               Select-Object -First 1
    if ($batPath) {
        $fw = (Get-ItemProperty "$($batPath.PSPath)\Device Parameters" -Name FirmwareRevision).FirmwareRevision
        if ($fw) {
            Write-Host "  Battery Firmware : $fw"
            return $fw
        }
    }
    # Fallback via WMI
    $bat = Get-CimInstance -Namespace root\cimv2 -ClassName Win32_Battery |
           Select-Object -First 1
    if ($bat) {
        Write-Host "  Battery Chemistry: $($bat.Chemistry)  Status: $($bat.BatteryStatus)"
        return $bat
    }
    Write-Host "  Battery firmware information not available."
}

function Get-ECFirmwareVersion {
    <#
    .SYNOPSIS
        Reads the Embedded Controller firmware version from the registry
        (written by the ACPI/EC driver on initialisation).
    #>
    $key   = 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS'
    $props = Get-ItemProperty $key
    $ec    = $props.ECFirmwareRevision
    if ($ec) {
        Write-Host "  EC Firmware Version: $ec"
    } else {
        Write-Host "  EC Firmware Version: (not exposed by this system)"
    }
    return $ec
}

function Get-TouchpadFirmwareVersion {
    <#
    .SYNOPSIS
        Reads the touchpad firmware version from the HID device registry entries.
        Works with Synaptics, ELAN, and other common touchpad vendors.
    #>
    $touchpadKeys = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\HID' -Recurse |
                    Where-Object { $_.Name -match 'VID_06CB|VID_04F3|VID_044E|Touchpad|SynTP' }

    foreach ($key in $touchpadKeys) {
        $props = Get-ItemProperty $key.PSPath
        $fw    = if     ($props.'FirmwareVersion') { $props.'FirmwareVersion' }
                elseif ($props.'FWVersion')        { $props.'FWVersion'       }
                else                               { $props.'DriverVersion'   }
        if ($fw) {
            Write-Host "  Touchpad Firmware: $fw  ($($key.PSChildName))"
            return $fw
        }
    }
    # Fallback: read from OEM driver inf
    $synReg = 'HKLM:\SOFTWARE\Synaptics\SynTP\Install'
    if (Test-Path $synReg) {
        $ver = (Get-ItemProperty $synReg).DriverVersion
        Write-Host "  Touchpad Driver (Synaptics): $ver"
        return $ver
    }
    Write-Host "  Touchpad firmware information not available."
}

# -----------------------------------------------------------------------------
#  SECTION 5  - POWER MANAGEMENT
# -----------------------------------------------------------------------------

function Get-PowerActionLabel {
    param([string]$GuidStr, [string]$SubGuid, [string]$SettingGuid)
    $val = powercfg /query $GuidStr $SubGuid $SettingGuid 2>$null |
           Select-String 'Current AC Power Setting Index|Current DC Power Setting Index' |
           ForEach-Object { ($_ -split ':')[1].Trim() } |
           Select-Object -First 1
    $intVal = [convert]::ToInt32($val, 16)
    $label = switch ($intVal) {
        0 { 'Do nothing' }
        1 { 'Sleep' }
        2 { 'Hibernate' }
        3 { 'Shut down' }
        4 { 'Turn off the display' }
        default { "Unknown ($intVal)" }
    }
    return $label
}

function Show-PowerButtonActions {
    <# Reads power-button press actions for AC and DC from the active power plan. #>
    $activeGuid = (powercfg /getactivescheme) -replace '.*GUID: ([a-f0-9-]+).*','$1'
    # Power button sub-GUID and setting GUIDs (standard Windows values)
    $subGuid     = '4f971e89-eebd-4455-a8de-9e59040e7347'
    $btnGuid     = '7648efa3-dd9c-4e3e-b566-50f929386280'

    $ac = Get-PowerActionLabel $activeGuid $subGuid $btnGuid
    Write-Host "  Power Button (AC) : $ac"
    $dc = (powercfg /query $activeGuid $subGuid $btnGuid 2>$null) |
          Select-String 'Current DC' | ForEach-Object { ($_ -split ':')[1].Trim() }
    if ($dc) {
        $dcLabel = switch ([convert]::ToInt32($dc, 16)) {
            0       { 'Do nothing' }
            1       { 'Sleep' }
            2       { 'Hibernate' }
            3       { 'Shut down' }
            4       { 'Turn off the display' }
            default { 'Unknown' }
        }
        Write-Host "  Power Button (DC) : $dcLabel"
    }
}

function Show-LidCloseActions {
    <# Reads lid-close actions for AC and DC. #>
    $activeGuid = (powercfg /getactivescheme) -replace '.*GUID: ([a-f0-9-]+).*','$1'
    $subGuid    = '4f971e89-eebd-4455-a8de-9e59040e7347'
    $lidGuid    = '5ca83367-6e45-459f-a27b-476b1d01c936'

    $raw = powercfg /query $activeGuid $subGuid $lidGuid 2>$null
    $ac  = ($raw | Select-String 'Current AC' | ForEach-Object { ($_ -split ':')[1].Trim() })
    $dc  = ($raw | Select-String 'Current DC' | ForEach-Object { ($_ -split ':')[1].Trim() })

    $label = { param($h)
        switch ([convert]::ToInt32($h, 16)) {
            0       { 'Do nothing' }
            1       { 'Sleep' }
            2       { 'Hibernate' }
            3       { 'Shut down' }
            4       { 'Turn off the display' }
            default { 'Unknown' }
        }
    }
    Write-Host ("  Lid Close (AC): {0}" -f (& $label $ac))
    Write-Host ("  Lid Close (DC): {0}" -f (& $label $dc))
}

function Show-CriticalBatteryActions {
    <# Reads the action taken when the battery hits critical level. #>
    $activeGuid = (powercfg /getactivescheme) -replace '.*GUID: ([a-f0-9-]+).*','$1'
    $subGuid    = 'e73a048d-bf27-4f12-9731-8b2076e8891f'
    $critGuid   = '637ea02f-bbcb-4015-8e2c-a1c7b9c0b546'

    $raw = powercfg /query $activeGuid $subGuid $critGuid 2>$null
    $ac  = ($raw | Select-String 'Current AC' | ForEach-Object { ($_ -split ':')[1].Trim() })
    $dc  = ($raw | Select-String 'Current DC' | ForEach-Object { ($_ -split ':')[1].Trim() })

    $label = { param($h)
        switch ([convert]::ToInt32($h, 16)) {
            0       { 'Do nothing' }
            1       { 'Sleep' }
            2       { 'Hibernate' }
            3       { 'Shut down' }
            4       { 'Turn off the display' }
            default { 'Unknown' }
        }
    }
    Write-Host ("  Critical Battery Action (AC): {0}" -f (& $label $ac))
    Write-Host ("  Critical Battery Action (DC): {0}" -f (& $label $dc))
}

function Show-PowerSlider {
    <#
    .SYNOPSIS
        Reads the Windows Power Mode slider position from the registry and maps
        it to Best Battery Life / Balanced / Best Performance.
    #>
    $activeScheme = (powercfg /getactivescheme) -replace '.*GUID: ([a-f0-9-]+).*','$1'
    $label = switch ($activeScheme) {
        'a1841308-3541-4fab-bc81-f71556f20b4a' { 'Best Battery Life (Power Saver)' }
        '381b4222-f694-41f0-9685-ff5bb260df2e' { 'Balanced' }
        '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' { 'Best Performance (High Performance)' }
        'e9a42b02-d5df-448d-aa00-03f14749eb61' { 'Best Performance (Ultimate)' }
        default { "Custom ($activeScheme)" }
    }
    # Also check the OverlayScheme for Modern Slider (Win10 20H1+)
    $overlayKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
    $overlay = (Get-ItemProperty $overlayKey -Name ActiveOverlayAcPowerScheme).ActiveOverlayAcPowerScheme
    if ($overlay) {
        $label = switch ($overlay) {
            '{961cc777-2547-4f9d-8174-7d86181b8a7a}' { 'Best Battery Life'   }
            '{00000000-0000-0000-0000-000000000000}' { 'Balanced'            }
            '{ded574b5-45a0-4f42-8737-46345c09c238}' { 'Best Performance'    }
            default { "Custom ($overlay)" }
        }
    }
    Write-Host "  Power Slider: $label"
    return $label
}

# -----------------------------------------------------------------------------
#  SECTION 6  - BATTERY & THERMAL
# -----------------------------------------------------------------------------

function Get-ChargePercent {
    <#
    .SYNOPSIS  Current battery charge as a percentage of design capacity.
    #>
    $batt = Get-CimInstance -Namespace root\cimv2 -ClassName Win32_Battery |
            Select-Object -First 1
    if (-not $batt) {
        Write-Host "  Battery: No battery detected (desktop system)."
        return $null
    }
    $pct = $batt.EstimatedChargeRemaining
    Write-Host "  Battery charge: $pct%  Status: $($batt.BatteryStatus)"

    # Try to get full charge / design capacity via WMI BatteryFullChargedCapacity
    $full   = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity).FullChargedCapacity
    $design = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData).DesignedCapacity
    if ($full -and $design) {
        $health = [math]::Round(($full / $design) * 100, 1)
        Write-Host "  Battery health (wear): $health%  (Full=$full mWh, Design=$design mWh)"
    }
    return $pct
}

function Get-Temperature {
    <#
    .SYNOPSIS  Reads CPU/system thermal zone temperatures.
    #>
    $temps = Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature
    if (-not $temps) {
        Write-Host "  Thermal zone data not available (may require elevated privileges)."
        return
    }
    Write-Host "`n  -- Thermal Zones -----------------------------------" -ForegroundColor Yellow
    foreach ($zone in $temps) {
        $celsius    = [math]::Round(($zone.CurrentTemperature / 10) - 273.15, 1)
        $fahrenheit = [math]::Round($celsius * 9/5 + 32, 1)
        Write-Host ("  {0,-40} {1,6}  degC  /  {2,6}  degF" -f $zone.InstanceName, $celsius, $fahrenheit)
    }
    Write-Host ""
}

# -----------------------------------------------------------------------------
#  SECTION 7  - HARDWARE & DEVICES
# -----------------------------------------------------------------------------

function Get-BluetoothInfo {
    <#
    .SYNOPSIS  Lists all Bluetooth adapters and devices with driver information.
    #>
    Write-Host "`n  -- Bluetooth ---------------------------------------" -ForegroundColor Yellow
    $btDevices = Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue
    if (-not $btDevices) {
        Write-Host "  No Bluetooth devices found."
        return
    }
    $btDevices | ForEach-Object {
        $dv = Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_DriverVersion','DEVPKEY_Device_DriverDate','DEVPKEY_Device_HardwareIds' -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            Name        = $_.FriendlyName
            Status      = $_.Status
            InstanceId  = $_.InstanceId
            DriverVer   = ($dv | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_DriverVersion' }).Data
            DriverDate  = ($dv | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_DriverDate'    }).Data
            HardwareId  = (($dv | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_HardwareIds'  }).Data | Select-Object -First 1)
        }
    } | Format-Table -AutoSize
}

function Show-DeviceManagerStatus {
    <#
    .SYNOPSIS  Lists all PnP devices with their status codes translated to English.
    #>
    $statusMap = @{
        0  = 'Device is working properly'
        1  = 'Device is not configured correctly'
        2  = 'Windows cannot load the driver for this device'
        3  = 'Driver for this device might be corrupted'
        4  = 'Device is not working properly  - driver or registry may be bad'
        5  = 'Driver for the device requires a resource that Windows cannot manage'
        6  = 'Boot configuration for the device conflicts with other devices'
        7  = 'Cannot filter'
        8  = 'Driver loader for the device is missing'
        9  = 'Device is not working properly  - controlling firmware may be wrong'
        10 = 'Device cannot start'
        11 = 'Device failed'
        12 = 'Device cannot find enough free resources'
        13 = 'Windows cannot verify the device''s resources'
        14 = 'Device cannot work properly until you restart the computer'
        15 = 'Device is not working properly  - possible IRQ conflict'
        16 = 'Windows cannot identify all the resources the device uses'
        17 = 'Device is requesting an unknown resource type'
        18 = 'Reinstall the drivers for this device'
        19 = 'Failure using the VxD loader'
        20 = 'Registry might be corrupted'
        21 = 'System failure: try changing the driver; if that does not work see the hardware documentation'
        22 = 'Device is disabled'
        23 = 'System failure: try changing the driver; if that does not work see the hardware documentation'
        24 = 'Device is not present, not working properly, or does not have all the drivers installed'
        25 = 'Windows is still setting up the device'
        26 = 'Windows is still setting up the device'
        27 = 'Device does not have valid log configuration'
        28 = 'The drivers for this device are not installed'
        29 = 'Device is disabled because the firmware did not provide the required resources'
        30 = 'Device is using an IRQ resource that another device is using'
        31 = 'Device is not working properly because Windows cannot load the required drivers'
        43 = 'Windows has stopped this device because it has reported problems'
    }

    Write-Host "`n  -- Device Manager Status ---------------------------" -ForegroundColor Yellow
    $devices = Get-CimInstance Win32_PnPEntity |
               Select-Object Name, ConfigManagerErrorCode, DeviceID
    $devices | ForEach-Object {
        $code   = $_.ConfigManagerErrorCode
        $status = if ($statusMap.ContainsKey([int]$code)) { $statusMap[[int]$code] } else { "Code $code" }
        [PSCustomObject]@{
            Device    = $_.Name
            ErrorCode = $code
            Status    = $status
        }
    } | Sort-Object ErrorCode -Descending | Format-Table -AutoSize -Wrap
}

# -----------------------------------------------------------------------------
#  SECTION 8  - MEMORY
# -----------------------------------------------------------------------------

function Get-MemoryDetails {
    <#
    .SYNOPSIS  Reads detailed info about each installed RAM module.
    #>
    Write-Host "`n  -- Memory Modules ----------------------------------" -ForegroundColor Yellow
    $slots = Get-CimInstance Win32_PhysicalMemory
    if (-not $slots) {
        Write-Host "  Memory data not available."
        return
    }
    $slots | ForEach-Object {
        $mt = switch ($_.MemoryType) {
            20 { 'DDR' }
            21 { 'DDR2' }
            24 { 'DDR3' }
            26 { 'DDR4' }
            34 { 'DDR5' }
            default { "Type $($_.MemoryType)" }
        }
        [PSCustomObject]@{
            Slot         = $_.DeviceLocator
            Manufacturer = $_.Manufacturer
            PartNumber   = $_.PartNumber.Trim()
            SerialNumber = $_.SerialNumber
            CapacityGB   = [math]::Round($_.Capacity / 1GB, 0)
            SpeedMHz     = $_.Speed
            MemoryType   = $mt
        }
    } | Format-Table -AutoSize
    return $slots
}

# -----------------------------------------------------------------------------
#  SECTION 8b - STORAGE HEALTH & SMART DATA
# -----------------------------------------------------------------------------

function Get-SmartAttribute {
    <#
    .SYNOPSIS  Parses one SMART attribute from an MSStorageDriver_ATAPISmartData
               VendorSpecific byte array.  Returns $null if not found.
               Structure: 2-byte header, then 30 x 12-byte attribute entries.
               Each entry: [0] ID, [1-2] flags, [3] normalized, [4] worst,
               [5-10] raw value (48-bit little-endian), [11] reserved.
    #>
    param([byte[]]$VendorSpecific, [byte]$AttributeId)
    if (-not $VendorSpecific -or $VendorSpecific.Count -lt 14) { return $null }
    for ($i = 2; ($i + 11) -lt $VendorSpecific.Count -and $i -lt 362; $i += 12) {
        if ($VendorSpecific[$i] -eq $AttributeId) {
            $raw = [long]$VendorSpecific[$i + 5]              +
                   ([long]$VendorSpecific[$i + 6]  -shl  8)  +
                   ([long]$VendorSpecific[$i + 7]  -shl 16)  +
                   ([long]$VendorSpecific[$i + 8]  -shl 24)  +
                   ([long]$VendorSpecific[$i + 9]  -shl 32)  +
                   ([long]$VendorSpecific[$i + 10] -shl 40)
            return [PSCustomObject]@{
                Raw        = $raw
                Normalized = [int]$VendorSpecific[$i + 3]
                Worst      = [int]$VendorSpecific[$i + 4]
            }
        }
    }
    return $null
}

function Format-LbaBytes {
    <#
    .SYNOPSIS  Converts a raw LBA count (512-byte sectors) to a readable string.
               Returns '-' for zero or negligible values.
    #>
    param([long]$LbaCount)
    $bytes = $LbaCount * 512
    if     ($bytes -ge 1TB) { return "$([math]::Round($bytes / 1TB, 2)) TB" }
    elseif ($bytes -ge 1GB) { return "$([math]::Round($bytes / 1GB,  1)) GB" }
    else                    { return '-' }
}

function Get-DiskSmartData {
    <#
    .SYNOPSIS
        Reports physical disk health and extended SMART data for all drives.
        Combines two built-in Windows sources - no external tools required:
          - Get-StorageReliabilityCounter : temp, power-on hours, error counts
          - MSStorageDriver_ATAPISmartData (WMI, ATA/SATA only) : total data
            written/read, reallocated/pending/uncorrectable sector counts
        Wear detection tries three sources in order:
          1. Get-StorageReliabilityCounter.Wear  (works when drivers expose it)
          2. Raw SMART normalized value for attrs E9/E7/CA/A9/D1  (SATA SSDs)
          3. Clearly labels NVMe drives where this data path does not apply
    #>
    Write-Host "`n  -- Disk Health & SMART Data ------------------------" -ForegroundColor Yellow
    $disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
    if (-not $disks) {
        Write-Host "  No physical disks found."
        return
    }

    # Load raw SMART WMI data once (ATA/SATA only - NVMe not exposed here)
    $allSmartWmi = Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_ATAPISmartData -ErrorAction SilentlyContinue

    $results = foreach ($disk in $disks) {
        $rel = $disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue

        # -- Resolve ATA/SATA SMART entry for this disk --------------------------
        # InstanceName ends with _N where N matches DeviceId (disk number)
        $vs         = $null
        $smartEntry = $null
        if ($allSmartWmi) {
            $diskNum    = [int]$disk.DeviceId
            $smartEntry = $allSmartWmi |
                          Where-Object { $_.InstanceName -match "_${diskNum}$" } |
                          Select-Object -First 1
            if ($smartEntry) { $vs = $smartEntry.VendorSpecific }
        }

        # -- Wear / health -------------------------------------------------------
        # Priority 1: Get-StorageReliabilityCounter.Wear (% worn, 0=new, 100=dead)
        #             Many drivers return 0 even on used drives; treat 0 as absent.
        # Priority 2: SMART normalized value (100=new, lower=more worn) for SATA:
        #   E9 (233) Media Wearout Indicator  - Intel, SanDisk, many OEM
        #   E7 (231) SSD Life Left            - Intel, Crucial
        #   CA (202) % Lifetime Remaining     - various
        #   A9 (169) Remaining Life           - SanDisk, some WD
        #   D1 (209) Remaining Life %         - Samsung (older)
        # NVMe: health log requires NVMe log page 0x02 which is not exposed
        #       through the Windows ATA SMART path and Wear is driver-dependent.
        $wearStr = 'N/A'
        if ($disk.MediaType -eq 'SSD') {
            if ($rel -and $rel.Wear -gt 0) {
                $worn    = [int]$rel.Wear
                $wearStr = "$(100 - $worn)% remaining  ($worn% worn)"
            } elseif ($disk.BusType -ne 'NVMe' -and $vs) {
                foreach ($wid in @(0xE9, 0xE7, 0xCA, 0xA9, 0xD1)) {
                    $wa = Get-SmartAttribute -VendorSpecific $vs -AttributeId $wid
                    if ($wa -and $wa.Normalized -gt 0 -and $wa.Normalized -le 100) {
                        $worn    = 100 - $wa.Normalized
                        $wearStr = "$($wa.Normalized)% remaining  ($worn% worn)"
                        break
                    }
                }
            }
            if ($wearStr -eq 'N/A' -and $disk.BusType -eq 'NVMe') {
                $wearStr = 'N/A (NVMe)'
            }
        }

        # -- Raw SMART sector / byte counters (ATA/SATA only) --------------------
        # Attrs 241/242 (Total LBAs Written/Read) are supported by many SSDs but
        # not all  -  vendor SSDs (WD Blue, etc.) often omit them.
        # NVMe drives do not use ATA SMART; their totals require NVMe log pages
        # which are not accessible via this WMI class.
        $tbWritten = '-'; $tbRead = '-'
        $reallocated = '-'; $pending = '-'; $uncorrect = '-'

        if ($vs) {
            $a5   = Get-SmartAttribute -VendorSpecific $vs -AttributeId 5
            $a197 = Get-SmartAttribute -VendorSpecific $vs -AttributeId 197
            $a198 = Get-SmartAttribute -VendorSpecific $vs -AttributeId 198
            $a241 = Get-SmartAttribute -VendorSpecific $vs -AttributeId 241
            $a242 = Get-SmartAttribute -VendorSpecific $vs -AttributeId 242

            if ($a5)                        { $reallocated = $a5.Raw }
            if ($a197)                      { $pending     = $a197.Raw }
            if ($a198)                      { $uncorrect   = $a198.Raw }
            if ($a241 -and $a241.Raw -gt 0) { $tbWritten   = Format-LbaBytes $a241.Raw }
            if ($a242 -and $a242.Raw -gt 0) { $tbRead      = Format-LbaBytes $a242.Raw }
        } elseif ($disk.BusType -eq 'NVMe') {
            $tbWritten = 'N/A (NVMe)'
            $tbRead    = 'N/A (NVMe)'
        }

        [PSCustomObject]@{
            Drive           = $disk.FriendlyName
            Type            = $disk.MediaType
            'Size GB'       = [math]::Round($disk.Size / 1GB, 1)
            Health          = $disk.HealthStatus
            Bus             = $disk.BusType
            'Wear'          = $wearStr
            'Temp C'        = if ($rel -and $rel.Temperature)                { $rel.Temperature }   else { '-' }
            'Power-On Hrs'  = if ($rel -and $rel.PowerOnHours)               { $rel.PowerOnHours }  else { '-' }
            'Total Written' = $tbWritten
            'Total Read'    = $tbRead
            'Reallocated'   = $reallocated
            'Pending Sect'  = $pending
            'Uncorrectable' = $uncorrect
            'Read Errors'   = if ($rel -and $null -ne $rel.ReadErrorsTotal)  { $rel.ReadErrorsTotal }  else { '-' }
            'Write Errors'  = if ($rel -and $null -ne $rel.WriteErrorsTotal) { $rel.WriteErrorsTotal } else { '-' }
        }
    }

    # Split output into two tables so columns are readable
    Write-Host ""
    $results | Select-Object Drive, Type, 'Size GB', Health, Bus, Wear, 'Temp C', 'Power-On Hrs' |
        Format-Table -AutoSize
    $results | Select-Object Drive, 'Total Written', 'Total Read', Reallocated, 'Pending Sect', Uncorrectable, 'Read Errors', 'Write Errors' |
        Format-Table -AutoSize
    return $results
}

# -----------------------------------------------------------------------------
#  SECTION 9  - DISPLAY & GRAPHICS
# -----------------------------------------------------------------------------

function Get-DisplayScale {
    <#
    .SYNOPSIS  Reads the current Windows DPI / display scaling level.
    #>
    $applied = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name LogPixels -ErrorAction SilentlyContinue).LogPixels
    if (-not $applied) {
        $applied = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontDPI' -Name LogPixels -ErrorAction SilentlyContinue).LogPixels
    }
    $label = switch ($applied) {
        96  { 'Small (100%)' }
        120 { 'Medium (125%)' }
        144 { 'Large (150%)' }
        192 { 'Larger (200%)' }
        $null { 'Default (100%  - registry key absent)' }
        default { "Custom ($applied DPI)" }
    }
    Write-Host "  Display Scale: $label"
    return $label
}

function Get-DSCStatus {
    <#
    .SYNOPSIS  Checks Display Stream Compression status (Intel and AMD).
    #>
    $procFamily = ProcDetect

    if ($procFamily -eq 'Intel') {
        $key  = 'HKLM:\SOFTWARE\Intel\GMM'
        $dsc  = (Get-ItemProperty $key -Name 'DSCEnable' -ErrorAction SilentlyContinue).DSCEnable
        $msg  = if ($dsc -eq 1) { 'Enabled' } elseif ($dsc -eq 0) { 'Disabled' } else { 'Not configured / key absent' }
        Write-Host "  Intel DSC: $msg"
    }
    elseif ($procFamily -eq 'AMD') {
        $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000'
        $dsc = (Get-ItemProperty $key -Name 'DSCEnabled' -ErrorAction SilentlyContinue).DSCEnabled
        $msg = if ($dsc -eq 1) { 'Enabled' } elseif ($dsc -eq 0) { 'Disabled' } else { 'Not configured / key absent' }
        Write-Host "  AMD DSC: $msg"
    }
    else {
        Write-Host "  DSC: Not applicable for detected processor family ($procFamily)."
    }
}

# -----------------------------------------------------------------------------
#  SECTION 10  - APPLICATION DETECTION
# -----------------------------------------------------------------------------

function Get-TeamsVersion {
    <# Detects Microsoft Teams (classic and new) and returns the version. #>
    # New Teams (MSIX / AppX)
    $newTeams = Get-AppxPackage -AllUsers -Name 'MSTeams' -ErrorAction SilentlyContinue |
                Select-Object -First 1
    if ($newTeams) {
        Write-Host "  Microsoft Teams (New): $($newTeams.Version)"
        return $newTeams.Version
    }
    # Classic Teams settings.json
    $settingsPath = "$env:APPDATA\Microsoft\Teams\settings.json"
    if (Test-Path $settingsPath) {
        $json = Get-Content $settingsPath | ConvertFrom-Json -ErrorAction SilentlyContinue
        $ver  = $json.version
        if ($ver) {
            Write-Host "  Microsoft Teams (Classic): $ver"
            return $ver
        }
    }
    Write-Host "  Microsoft Teams: Not installed."
    return $null
}

function Get-OfficeVersion {
    <# Detects Microsoft Office Click-to-Run and its version. #>
    $c2rKey  = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $c2rKey2 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration'
    foreach ($key in @($c2rKey, $c2rKey2)) {
        if (Test-Path $key) {
            $ver    = (Get-ItemProperty $key).VersionToReport
            $channel = (Get-ItemProperty $key).CDNBaseUrl -replace '.*/',''
            if ($ver) {
                Write-Host "  Microsoft Office (C2R): $ver  Channel: $channel"
                return $ver
            }
        }
    }
    # Fallback: registry uninstall entry
    $officeReg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
                 Where-Object { $_.DisplayName -like 'Microsoft Office*' -or $_.DisplayName -like 'Microsoft 365*' } |
                 Select-Object -First 1
    if ($officeReg) {
        Write-Host "  Microsoft Office: $($officeReg.DisplayName)  $($officeReg.DisplayVersion)"
        return $officeReg.DisplayVersion
    }
    Write-Host "  Microsoft Office: Not installed."
    return $null
}

function Get-ZoomVersion {
    <# Detects Zoom and its version via WMI or registry. #>
    $zoom = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                             'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                             'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' |
            Where-Object { $_.DisplayName -like '*Zoom*' } |
            Select-Object -First 1
    if ($zoom) {
        Write-Host "  Zoom: $($zoom.DisplayName)  $($zoom.DisplayVersion)"
        return $zoom.DisplayVersion
    }
    Write-Host "  Zoom: Not installed."
    return $null
}

# -----------------------------------------------------------------------------
#  SECTION 11  - SYSTEM EVENTS & HISTORY
# -----------------------------------------------------------------------------

function Get-RebootHistory {
    <#
    .SYNOPSIS  Retrieves the recent system shutdown / restart history.
    .PARAMETER Days  How many days of history to retrieve (default 30).
    #>
    param([int]$Days = 30)
    Write-Host "`n  -- Reboot / Shutdown History (last $Days days) -----" -ForegroundColor Yellow

    $since = (Get-Date).AddDays(-$Days)
    # Event IDs: 1074 = user-initiated shutdown/restart, 6006 = clean shutdown, 6008 = unexpected shutdown
    $events = Get-WinEvent -FilterHashtable @{
        LogName   = 'System'
        Id        = @(1074, 6006, 6008, 41)
        StartTime = $since
    } -ErrorAction SilentlyContinue

    if (-not $events) {
        Write-Host "  No shutdown events found in the last $Days days."
        return
    }

    $events | ForEach-Object {
        $type = switch ($_.Id) {
            1074 { 'User-initiated shutdown/restart' }
            6006 { 'Clean shutdown (Event Log stopped)' }
            6008 { 'Unexpected / dirty shutdown' }
            41   { 'Kernel power  - system restarted without clean shutdown' }
            default { "Event $($_.Id)" }
        }
        [PSCustomObject]@{
            Time    = $_.TimeCreated
            EventId = $_.Id
            Type    = $type
            Message = ($_.Message -split "`n")[0]
        }
    } | Sort-Object Time | Format-Table -AutoSize -Wrap
}

function Get-UnexpectedShutdownCount {
    <#
    .SYNOPSIS  Counts dirty / unexpected shutdowns since Windows installation.
    #>
    $count = (Get-WinEvent -FilterHashtable @{ LogName='System'; Id=@(6008,41) } -ErrorAction SilentlyContinue).Count
    Write-Host "  Unexpected / dirty shutdowns recorded: $count"
    return $count
}

function Get-WEREvents {
    <#
    .SYNOPSIS  Collects Windows Error Reporting fault-bucket events.
    .PARAMETER OutFile  Path to write the log.  If omitted, writes to console.
    #>
    param([string]$OutFile)
    $events = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'
        Id      = @(1001, 1000, 1002)
    } -MaxEvents 200 -ErrorAction SilentlyContinue

    $lines = $events | ForEach-Object {
        "{0}  ID:{1}  {2}" -f $_.TimeCreated, $_.Id, ($_.Message -split "`n")[0]
    }

    if ($OutFile) {
        $lines | Set-Content $OutFile -Encoding UTF8
        Write-Host "  WER events written to: $OutFile"
    } else {
        $lines | Format-List
    }
}

# -----------------------------------------------------------------------------
#  SECTION 12  - SYSTEM HEALTH & UPDATES
# -----------------------------------------------------------------------------

function Invoke-KnownIssuesScan {
    <#
    .SYNOPSIS
        Broad health sweep: Device Manager errors, battery health, thermal
        throttling events, pending reboots, Secure Boot, and firewall state.
    .PARAMETER OutFile  If supplied, writes a log file instead of console output.
    #>
    param([string]$OutFile)
    $issues = [System.Collections.Generic.List[string]]::new()
    $issues.Add("SysPulse Known Issues Scan  - $(Get-Date)")
    $issues.Add("=" * 60)

    # 1. Device Manager errors
    $errDevices = Get-CimInstance Win32_PnPEntity |
                  Where-Object { $_.ConfigManagerErrorCode -ne 0 }
    if ($errDevices) {
        $issues.Add("`n[!] Device Manager  - $($errDevices.Count) device(s) with errors:")
        $errDevices | ForEach-Object {
            $issues.Add("    Code $($_.ConfigManagerErrorCode)  - $($_.Name)")
        }
    } else {
        $issues.Add("[OK] Device Manager  - all devices working properly.")
    }

    # 2. Battery health
    $full   = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue).FullChargedCapacity
    $design = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue).DesignedCapacity
    if ($full -and $design -and $design -gt 0) {
        $health = [math]::Round(($full / $design) * 100, 1)
        $flag   = if ($health -lt 60) { '[!]' } else { '[OK]' }
        $issues.Add("$flag Battery health: $health% (Full=$full mWh, Design=$design mWh)")
    } else {
        $issues.Add("[--] Battery health: No battery or data unavailable.")
    }

    # 3. Thermal throttling in event log (last 7 days)
    $thermalEvents = Get-WinEvent -FilterHashtable @{
        LogName   = 'System'
        Id        = 37          # Kernel-Processor-Power: processor throttled
        StartTime = (Get-Date).AddDays(-7)
    } -ErrorAction SilentlyContinue
    if ($thermalEvents) {
        $issues.Add("[!] Thermal throttling detected: $($thermalEvents.Count) event(s) in the last 7 days.")
    } else {
        $issues.Add("[OK] No thermal throttling events in the last 7 days.")
    }

    # 4. Unexpected shutdowns (last 30 days)
    $dirtyShutdowns = (Get-WinEvent -FilterHashtable @{
        LogName   = 'System'
        Id        = @(6008, 41)
        StartTime = (Get-Date).AddDays(-30)
    } -ErrorAction SilentlyContinue).Count
    if ($dirtyShutdowns -gt 0) {
        $issues.Add("[!] Unexpected / dirty shutdowns in last 30 days: $dirtyShutdowns")
    } else {
        $issues.Add("[OK] No unexpected shutdowns in last 30 days.")
    }

    # 5. Pending reboot flag
    $pendingReboot = $false
    $pendingPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations'
    )
    foreach ($p in $pendingPaths) {
        if (Test-Path $p) { $pendingReboot = $true; break }
    }
    $issues.Add($(if ($pendingReboot) { "[!] Pending reboot detected." } else { "[OK] No pending reboot." }))

    # 6. Secure Boot
    $sb = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
    $issues.Add($(if ($sb) { "[OK] Secure Boot: Enabled." } else { "[!] Secure Boot: Disabled or unavailable." }))

    # 7. Windows Defender / Antivirus
    $av = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
    if ($av) {
        foreach ($product in $av) {
            $issues.Add("[OK] Antivirus: $($product.displayName)  State: $($product.productState)")
        }
    } else {
        $issues.Add("[!] No antivirus product registered with Security Center.")
    }

    # 8. Low disk space (< 10 GB free on system drive)
    $sysDrive = Get-PSDrive -Name ($env:SystemDrive -replace ':','') -ErrorAction SilentlyContinue
    if ($sysDrive) {
        $freeGB = [math]::Round($sysDrive.Free / 1GB, 1)
        $flag   = if ($freeGB -lt 10) { '[!]' } else { '[OK]' }
        $issues.Add("$flag System drive free space: $freeGB GB")
    }

    $output = $issues -join "`n"
    if ($OutFile) {
        $output | Set-Content $OutFile -Encoding UTF8
        Write-Host "  Known Issues scan written to: $OutFile"
    } else {
        Write-Host $output
    }
}

function Get-MissingWindowsUpdates {
    <#
    .SYNOPSIS  Queries the Windows Update Agent for updates not yet installed.
    #>
    Write-Host "  Checking for missing Windows updates (this may take a moment)..."
    try {
        $session  = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $result   = $searcher.Search("IsInstalled=0 and IsHidden=0")
        if ($result.Updates.Count -eq 0) {
            Write-Host "  All Windows updates are installed."
            return
        }
        Write-Host "  Missing updates ($($result.Updates.Count)):" -ForegroundColor Yellow
        $result.Updates | ForEach-Object {
            [PSCustomObject]@{
                Title          = $_.Title
                Classification = $_.Categories.Item(0).Name
                SizeMB         = [math]::Round($_.MaxDownloadSize / 1MB, 1)
            }
        } | Format-Table -AutoSize -Wrap
    } catch {
        Write-Warning "Could not query Windows Update: $_"
    }
}

# -----------------------------------------------------------------------------
#  SECTION 13  - SECURITY & FIREWALL
# -----------------------------------------------------------------------------

function Get-ActiveFirewall {
    <#
    .SYNOPSIS  Returns the name of the active third-party firewall product (if any).
    #>
    $fw = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName FirewallProduct -ErrorAction SilentlyContinue
    if ($fw) {
        foreach ($product in $fw) {
            Write-Host "  Active Firewall: $($product.displayName)  State: $($product.productState)"
        }
    } else {
        # Fall back to Windows Firewall status
        $wf = Get-NetFirewallProfile -ErrorAction SilentlyContinue
        $wf | ForEach-Object {
            Write-Host ("  Windows Firewall [{0}]: {1}" -f $_.Name, $(if ($_.Enabled) {'Enabled'} else {'Disabled'}))
        }
    }
}

# -----------------------------------------------------------------------------
#  SECTION 14  - DATA COLLECTION
# -----------------------------------------------------------------------------

function Invoke-QuickData {
    <#
    .SYNOPSIS
        Collects a comprehensive system snapshot into a single log file.
    #>
    param([string]$OutFolder = $Script:OutRoot)
    if (-not $OutFolder) { $OutFolder = New-OutputFolder }
    $logFile = Join-Path $OutFolder 'QuickData.log'
    $sb = [System.Text.StringBuilder]::new()

    $append = { param($s) [void]$sb.AppendLine($s) }

    & $append "SysPulse Quick Data Snapshot  - $(Get-Date)"
    & $append ("=" * 60)

    # OS
    $os  = Get-CimInstance Win32_OperatingSystem
    $cs  = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $bios = Get-CimInstance Win32_BIOS

    & $append "`n--- Operating System ---"
    & $append "Caption     : $($os.Caption)"
    & $append "Version     : $($os.Version)"
    & $append "Build       : $($os.BuildNumber)"
    & $append "Architecture: $($os.OSArchitecture)"
    & $append "Install Date: $($os.InstallDate)"
    & $append "Last Boot   : $($os.LastBootUpTime)"
    & $append "Locale      : $($os.Locale)"
    & $append "System Drive: $($os.SystemDrive)"

    & $append "`n--- Computer System ---"
    & $append "Manufacturer : $($cs.Manufacturer)"
    & $append "Model        : $($cs.Model)"
    & $append "Total RAM    : $([math]::Round($cs.TotalPhysicalMemory / 1GB, 2)) GB"
    & $append "Domain       : $($cs.Domain)"
    & $append "Workgroup    : $($cs.Workgroup)"
    & $append "User         : $($cs.UserName)"

    & $append "`n--- Processor ---"
    & $append "Name         : $($cpu.Name)"
    & $append "Manufacturer : $($cpu.Manufacturer)"
    & $append "Cores        : $($cpu.NumberOfCores)"
    & $append "Logical Procs: $($cpu.NumberOfLogicalProcessors)"
    & $append "Max Speed MHz: $($cpu.MaxClockSpeed)"
    & $append "Socket       : $($cpu.SocketDesignation)"

    & $append "`n--- BIOS ---"
    & $append "Manufacturer : $($bios.Manufacturer)"
    & $append "Version      : $($bios.SMBIOSBIOSVersion)"
    & $append "Release Date : $($bios.ReleaseDate)"
    & $append "Serial Number: $($bios.SerialNumber)"

    # Drives
    & $append "`n--- Storage Drives ---"
    Get-PhysicalDisk | ForEach-Object {
        & $append ("  {0,-30} {1,8} GB  {2}  {3}" -f $_.FriendlyName, [math]::Round($_.Size/1GB,1), $_.MediaType, $_.HealthStatus)
    }

    # Network adapters
    & $append "`n--- Network Adapters ---"
    Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
        $ip = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
        & $append ("  {0,-35} {1,-18} MAC: {2}" -f $_.Name, ($ip -join ','), $_.MacAddress)
    }

    # Drivers
    & $append "`n--- Installed Signed Drivers ---"
    Get-WindowsDriver -Online -ErrorAction SilentlyContinue | ForEach-Object {
        & $append ("  {0,-45} {1}  {2}" -f $_.OriginalFileName, $_.Version, $_.Date)
    }

    # Processes
    & $append "`n--- Running Processes ---"
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 40 | ForEach-Object {
        & $append ("  {0,-35} PID:{1,-6} CPU:{2,-8}" -f $_.Name, $_.Id, $_.CPU)
    }

    # Power scheme
    & $append "`n--- Active Power Scheme ---"
    powercfg /getactivescheme | ForEach-Object { & $append "  $_" }

    # Security
    & $append "`n--- Security ---"
    $sb_boot = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
    $sbText = if ($sb_boot) { 'Enabled' } else { 'Disabled or N/A' }
    & $append "  Secure Boot: $sbText"
    $tpm = Get-Tpm -ErrorAction SilentlyContinue
    if ($tpm) {
        & $append "  TPM Present : $($tpm.TpmPresent)"
        & $append "  TPM Enabled : $($tpm.TpmEnabled)"
        & $append "  TPM Ready   : $($tpm.TpmReady)"
    }

    $sb.ToString() | Set-Content $logFile -Encoding UTF8
    Write-Host "  QuickData written to: $logFile" -ForegroundColor Green
    return $logFile
}

function Invoke-PowerBattery {
    <#
    .SYNOPSIS
        Runs powercfg sleep-study and battery report; exports power config.
    #>
    param([string]$OutFolder = $Script:OutRoot)
    if (-not $OutFolder) { $OutFolder = New-OutputFolder }
    $sub = New-Item -ItemType Directory -Force -Path (Join-Path $OutFolder 'Power_Battery')

    Write-Host "  Generating battery report..."
    powercfg /batteryreport /output (Join-Path $sub 'BatteryReport.html') | Out-Null

    Write-Host "  Generating sleep study..."
    powercfg /sleepstudy     /output (Join-Path $sub 'SleepStudy.html')   | Out-Null

    Write-Host "  Exporting power schemes..."
    powercfg /list | Set-Content (Join-Path $sub 'PowerSchemes.log') -Encoding UTF8
    powercfg /query | Set-Content (Join-Path $sub 'ActiveSchemeDetail.log') -Encoding UTF8
    powercfg /energy /output (Join-Path $sub 'EnergyReport.html') | Out-Null

    # Battery data via WMI
    $batInfo = [System.Text.StringBuilder]::new()
    Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue | ForEach-Object {
        [void]$batInfo.AppendLine("Design Capacity : $($_.DesignedCapacity) mWh")
        [void]$batInfo.AppendLine("Device Name     : $($_.DeviceName)")
        [void]$batInfo.AppendLine("Manufacturer    : $($_.ManufactureName)")
        [void]$batInfo.AppendLine("Manufacture Date: $($_.ManufactureDate)")
    }
    Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | ForEach-Object {
        [void]$batInfo.AppendLine("Full Charge Cap : $($_.FullChargedCapacity) mWh")
    }
    Get-CimInstance -Namespace root\wmi -ClassName BatteryCycleCount -ErrorAction SilentlyContinue | ForEach-Object {
        [void]$batInfo.AppendLine("Cycle Count     : $($_.CycleCount)")
    }
    $batInfo.ToString() | Set-Content (Join-Path $sub 'BatteryWMI.log') -Encoding UTF8

    Write-Host "  Power/Battery data written to: $sub" -ForegroundColor Green
}

function Invoke-NetworkWAN {
    <#
    .SYNOPSIS
        Collects wireless, mobile-broadband, and Bluetooth diagnostic data.
    #>
    param([string]$OutFolder = $Script:OutRoot)
    if (-not $OutFolder) { $OutFolder = New-OutputFolder }
    $sub = New-Item -ItemType Directory -Force -Path (Join-Path $OutFolder 'Network_WAN')

    Write-Host "  Running netsh wlan diagnostics..."
    netsh wlan show all | Set-Content (Join-Path $sub 'WLAN_All.log') -Encoding UTF8
    netsh wlan show drivers | Set-Content (Join-Path $sub 'WLAN_Drivers.log') -Encoding UTF8
    netsh wlan show profiles | Set-Content (Join-Path $sub 'WLAN_Profiles.log') -Encoding UTF8

    Write-Host "  Collecting network adapter details..."
    Get-NetAdapter | Select-Object * | Format-List |
        Out-String | Set-Content (Join-Path $sub 'NetAdapters.log') -Encoding UTF8

    Get-NetIPConfiguration | Out-String |
        Set-Content (Join-Path $sub 'IPConfig.log') -Encoding UTF8

    # Mobile Broadband
    $mbDevices = Get-PnpDevice -Class 'Net' -ErrorAction SilentlyContinue |
                 Where-Object { $_.FriendlyName -match 'Mobile|LTE|WWAN|Modem|Cellular' }
    $mbDevices | Format-List | Out-String |
        Set-Content (Join-Path $sub 'WWAN_Devices.log') -Encoding UTF8

    # Bluetooth
    $btOutput = Get-BluetoothInfo 6>&1 | Out-String
    $btOutput | Set-Content (Join-Path $sub 'Bluetooth.log') -Encoding UTF8

    Write-Host "  Network/WAN data written to: $sub" -ForegroundColor Green
}

function Invoke-BootSecurity {
    <#
    .SYNOPSIS
        Collects boot config, TPM, and BitLocker information.
    #>
    param([string]$OutFolder = $Script:OutRoot)
    if (-not $OutFolder) { $OutFolder = New-OutputFolder }
    $sub = New-Item -ItemType Directory -Force -Path (Join-Path $OutFolder 'Boot_Security')

    Write-Host "  Collecting boot configuration..."
    bcdedit /enum all | Set-Content (Join-Path $sub 'BCDEdit.log') -Encoding UTF8

    Write-Host "  Collecting TPM status..."
    $tpm = Get-Tpm -ErrorAction SilentlyContinue
    if ($tpm) {
        $tpm | Format-List | Out-String | Set-Content (Join-Path $sub 'TPM.log') -Encoding UTF8
    }
    Get-CimInstance -Namespace root\cimv2\security\microsofttpm -ClassName Win32_Tpm -ErrorAction SilentlyContinue |
        Format-List | Out-String | Add-Content (Join-Path $sub 'TPM.log') -Encoding UTF8

    Write-Host "  Collecting BitLocker status..."
    manage-bde -status | Set-Content (Join-Path $sub 'BitLocker.log') -Encoding UTF8

    Write-Host "  Collecting Secure Boot state..."
    @"
Secure Boot : $(Confirm-SecureBootUEFI -ErrorAction SilentlyContinue)
"@ | Set-Content (Join-Path $sub 'SecureBoot.log') -Encoding UTF8
    Confirm-SecureBootUEFI -Verbose 2>&1 | Add-Content (Join-Path $sub 'SecureBoot.log') -Encoding UTF8

    Write-Host "  Boot/Security data written to: $sub" -ForegroundColor Green
}

function Invoke-HWDDriver {
    <#
    .SYNOPSIS
        Collects hardware inventory and driver details.
    #>
    param([string]$OutFolder = $Script:OutRoot)
    if (-not $OutFolder) { $OutFolder = New-OutputFolder }
    $sub = New-Item -ItemType Directory -Force -Path (Join-Path $OutFolder 'Hardware_Drivers')

    Write-Host "  Collecting system information..."
    systeminfo | Set-Content (Join-Path $sub 'SystemInfo.txt') -Encoding UTF8

    Write-Host "  Collecting all PnP devices..."
    Get-PnpDevice | Select-Object Class, FriendlyName, Status, InstanceId |
        Format-Table -AutoSize | Out-String |
        Set-Content (Join-Path $sub 'PnPDevices.log') -Encoding UTF8

    Write-Host "  Collecting driver information..."
    driverquery /fo CSV /v | Set-Content (Join-Path $sub 'DriverQuery.csv') -Encoding UTF8

    Get-WindowsDriver -Online -ErrorAction SilentlyContinue |
        Select-Object OriginalFileName, Version, Date, ProviderName, ClassName |
        Export-Csv (Join-Path $sub 'InstalledDrivers.csv') -NoTypeInformation -Encoding UTF8

    Write-Host "  Collecting GPU information..."
    Get-CimInstance Win32_VideoController |
        Select-Object Name, DriverVersion, DriverDate, VideoProcessor, AdapterRAM, CurrentRefreshRate |
        Format-List | Out-String |
        Set-Content (Join-Path $sub 'GPU.log') -Encoding UTF8

    Write-Host "  Collecting storage info..."
    Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus, Size, BusType |
        Format-Table -AutoSize | Out-String |
        Set-Content (Join-Path $sub 'PhysicalDisks.log') -Encoding UTF8
    Get-Disk | Select-Object * | Format-List | Out-String |
        Add-Content (Join-Path $sub 'PhysicalDisks.log') -Encoding UTF8

    Write-Host "  Collecting disk SMART / reliability data..."
    Get-DiskSmartData 6>&1 | Out-String |
        Add-Content (Join-Path $sub 'PhysicalDisks.log') -Encoding UTF8

    Write-Host "  Hardware/Driver data written to: $sub" -ForegroundColor Green
}

function Invoke-WINEvtDump {
    <#
    .SYNOPSIS
        Exports System, Application, and Security event logs; copies minidumps.
    #>
    param([string]$OutFolder = $Script:OutRoot)
    if (-not $OutFolder) { $OutFolder = New-OutputFolder }
    $sub = New-Item -ItemType Directory -Force -Path (Join-Path $OutFolder 'EventLogs_Dumps')

    foreach ($log in @('System','Application','Security')) {
        $evtPath = Join-Path $sub "$log.evtx"
        Write-Host "  Exporting $log event log..."
        wevtutil epl $log $evtPath 2>$null
    }

    # Minidumps
    $miniDumpDir = "$env:SystemRoot\Minidump"
    if (Test-Path $miniDumpDir) {
        $dmpDest = Join-Path $sub 'Minidumps'
        New-Item -ItemType Directory -Force -Path $dmpDest | Out-Null
        Get-ChildItem $miniDumpDir -Filter '*.dmp' | Copy-Item -Destination $dmpDest
        Write-Host "  Minidumps copied to: $dmpDest"
    }

    Write-Host "  Event logs written to: $sub" -ForegroundColor Green
}

function Invoke-WINPreload {
    <#
    .SYNOPSIS
        Collects Windows OS details (version, edition, activation status).
    #>
    param([string]$OutFolder = $Script:OutRoot)
    if (-not $OutFolder) { $OutFolder = New-OutputFolder }
    $sub = New-Item -ItemType Directory -Force -Path (Join-Path $OutFolder 'Windows_OS')

    Write-Host "  Collecting OS version details..."
    $os  = Get-CimInstance Win32_OperatingSystem
    $regOS = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

    $info = @"
OS Name         : $($os.Caption)
Version         : $($os.Version)
Build           : $($regOS.CurrentBuild).$($regOS.UBR)
Display Version : $($regOS.DisplayVersion)
Edition         : $($os.OperatingSystemSKU)
Architecture    : $($os.OSArchitecture)
Install Date    : $($os.InstallDate)
Last Boot       : $($os.LastBootUpTime)
Registered Owner: $($regOS.RegisteredOwner)
Registered Org  : $($regOS.RegisteredOrganization)
Product ID      : $($regOS.ProductId)
"@
    $info | Set-Content (Join-Path $sub 'WindowsVersion.log') -Encoding UTF8

    Write-Host "  Checking Windows activation status..."
    cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /dli |
        Set-Content (Join-Path $sub 'Activation.log') -Encoding UTF8

    Write-Host "  Windows OS data written to: $sub" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
#  SECTION 15  - CRASH DUMP DISCOVERY
# -----------------------------------------------------------------------------

function Find-KernelDumps {
    <#
    .SYNOPSIS  Lists full kernel memory dump files on the system drive.
    #>
    Write-Host "`n  -- Kernel Dump Files -------------------------------" -ForegroundColor Yellow
    $patterns = @(
        "$env:SystemRoot\MEMORY.DMP",
        "$env:SystemRoot\MEMORY*.DMP",
        "$env:SystemDrive\MEMORY.DMP"
    )
    $found = $false
    foreach ($p in $patterns) {
        foreach ($file in (Get-ChildItem $p -ErrorAction SilentlyContinue)) {
            Write-Host ("  {0,-55} {1,10} MB  {2}" -f $file.FullName, [math]::Round($file.Length/1MB,1), $file.LastWriteTime)
            $found = $true
        }
    }
    if (-not $found) { Write-Host "  No kernel dump files found." }
}

function Get-MiniDumps {
    <#
    .SYNOPSIS  Lists all minidump crash files.
    #>
    Write-Host "`n  -- Minidump Files ----------------------------------" -ForegroundColor Yellow
    $dir = "$env:SystemRoot\Minidump"
    if (-not (Test-Path $dir)) {
        Write-Host "  Minidump directory not found."
        return
    }
    $files = Get-ChildItem $dir -Filter '*.dmp' | Sort-Object LastWriteTime -Descending
    if (-not $files) {
        Write-Host "  No minidump files found."
        return
    }
    $files | ForEach-Object {
        [PSCustomObject]@{
            File     = $_.Name
            SizeKB   = [math]::Round($_.Length / 1KB, 1)
            Modified = $_.LastWriteTime
        }
    } | Format-Table -AutoSize
}

# -----------------------------------------------------------------------------
#  SECTION 16  - IDLE / USAGE ANALYSIS
# -----------------------------------------------------------------------------

# ---- Internal event-classification helpers ----

function isSleepEntry         { param($e) $e.Id -eq 506 -and $e.ProviderName -match 'Microsoft-Windows-Kernel-Power' }
function isSleepExit          { param($e) $e.Id -eq 507 -and $e.ProviderName -match 'Microsoft-Windows-Kernel-Power' }
function isShutdownEntry      { param($e) $e.Id -eq 13 }
function isShutdownExit       { param($e) $e.Id -eq 12 }
function isModernStandbyEntry { param($e) $e.Id -eq 811 }
function isModernStandbyExit  { param($e) $e.Id -eq 812 }
function isCriticalEvent      { param($e) $e.Level -le 2 }  # Critical or Error

function Get-NumberOfDays {
    param([datetime]$Start, [datetime]$End)
    return [math]::Ceiling(($End - $Start).TotalDays)
}

function findTimeZoneAfter {
    param([System.Collections.Generic.List[object]]$Events, [datetime]$After)
    $match = $Events | Where-Object { $_.TimeCreated -gt $After } |
             Sort-Object TimeCreated | Select-Object -First 1
    return if ($match) { $match.TimeCreated.Kind } else { [System.DateTimeKind]::Local }
}

function Invoke-IdleAnalysis {
    <#
    .SYNOPSIS
        Analyses power-state transitions in the event log to produce daily
        active / sleep / shutdown summaries, then generates an HTML chart.
    .PARAMETER Days     How many days of history to analyse (default 30).
    .PARAMETER OutFile  Path for the HTML output.  Defaults to Desktop.
    #>
    param(
        [int]$Days = 30,
        [string]$OutFile
    )
    if (-not $OutFile) {
        $OutFile = "$env:USERPROFILE\Desktop\SysPulse_IdleAnalysis_$(Get-Date -f 'yyyyMMdd').html"
    }

    Write-Host "  Analysing power states for the last $Days days..."
    $since = (Get-Date).AddDays(-$Days)

    $events = Get-WinEvent -FilterHashtable @{
        LogName   = 'System'
        Id        = @(12, 13, 41, 42, 506, 507, 811, 812, 1, 6008)
        StartTime = $since
    } -ErrorAction SilentlyContinue | Sort-Object TimeCreated

    # Build daily buckets
    $dailyData = [ordered]@{}
    for ($d = $Days; $d -ge 0; $d--) {
        $key = (Get-Date).AddDays(-$d).ToString('yyyy-MM-dd')
        $dailyData[$key] = @{ Active=0; Sleep=0; ModernStandby=0; Shutdown=0 }
    }

    $stateStart = $since
    $currentState = 'Active'

    foreach ($ev in $events) {
        $stateEnd = $ev.TimeCreated
        $day      = $stateStart.ToString('yyyy-MM-dd')

        if ($dailyData.Contains($day)) {
            $duration = ($stateEnd - $stateStart).TotalMinutes
            if ($duration -gt 0) {
                $dailyData[$day][$currentState] += [math]::Round($duration)
            }
        }

        $currentState = if     (isSleepEntry         $ev) { 'Sleep'         }
                        elseif (isSleepExit           $ev) { 'Active'        }
                        elseif (isModernStandbyEntry  $ev) { 'ModernStandby' }
                        elseif (isModernStandbyExit   $ev) { 'Active'        }
                        elseif (isShutdownEntry       $ev) { 'Shutdown'      }
                        elseif (isShutdownExit        $ev) { 'Active'        }
                        else                               { $currentState   }

        $stateStart = $stateEnd
    }

    # Build as a proper diagnostic data structure so New-HtmlReport renders it correctly
    $tableRows = @($dailyData.GetEnumerator() | ForEach-Object {
        ,@($_.Key,
           "$($_.Value.Active) min",
           "$($_.Value.Sleep) min",
           "$($_.Value.ModernStandby) min",
           "$($_.Value.Shutdown) min")
    })

    $section = [PSCustomObject]@{
        id      = 'idle'
        title   = "Power State by Day (last $Days days)"
        type    = 'table'
        headers = @('Date','Active','Sleep','Modern Standby','Shutdown')
        rows    = $tableRows
    }

    $diagData = [PSCustomObject]@{
        meta = [PSCustomObject]@{
            hostname  = $env:COMPUTERNAME
            os        = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
            user      = $env:USERNAME
            generated = (Get-Date -Format 'yyyy-MM-dd HH:mm')
        }
        sections = @($section)
    }

    $json = $diagData | ConvertTo-Json -Depth 10
    New-HtmlReport -JsonData $json -OutFile $OutFile -Title "SysPulse Idle Analysis ($Days days)"
    Write-Host "  Idle analysis report: $OutFile" -ForegroundColor Green
}

function ConvertTo-HtmlReport {
    <#
    .SYNOPSIS  Kept for backwards-compatibility  - wraps New-HtmlReport.
    #>
    param([string]$JsonData, [string]$OutFile, [string]$Title = 'SysPulse Report')
    New-HtmlReport -JsonData $JsonData -OutFile $OutFile -Title $Title
}

# -----------------------------------------------------------------------------
#  SECTION 17  - DRIVER INFORMATION
# -----------------------------------------------------------------------------

function Get-DriverDates {
    <#
    .SYNOPSIS  Reports installation dates of all signed device drivers.
    #>
    Write-Host "`n  -- Driver Dates ------------------------------------" -ForegroundColor Yellow
    Get-WindowsDriver -Online -ErrorAction SilentlyContinue |
        Select-Object OriginalFileName, Version, @{N='Date';E={$_.Date.ToString('yyyy-MM-dd')}}, ClassName, ProviderName |
        Sort-Object Date -Descending |
        Format-Table -AutoSize -Wrap
}

# -----------------------------------------------------------------------------
#  SECTION 18  - STRUCTURED DATA EXPORT  (JSON + HTML report)
# -----------------------------------------------------------------------------

function Get-AllDiagnosticData {
    <#
    .SYNOPSIS
        Silently collects all diagnostic data and returns a structured object
        ready for ConvertTo-Json / HTML rendering.  No console output.
    #>

    # Helper: build a key-value section object
    function _kv { param($id,$title,$pairs)
        [PSCustomObject]@{
            id=$id; title=$title; type='kv'
            rows = @($pairs.GetEnumerator() | ForEach-Object { ,@("$($_.Key)", "$($_.Value)") })
        }
    }
    # Helper: build a table section object
    function _tbl { param($id,$title,$headers,$rows)
        [PSCustomObject]@{
            id=$id; title=$title; type='table'
            headers = $headers
            rows    = @($rows)
        }
    }

    $sections = [System.Collections.Generic.List[object]]::new()

    # -- System --------------------------------------------------------------
    $cs   = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $os   = Get-CimInstance Win32_OperatingSystem
    $regOS = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue

    $sections.Add((_kv 'system' 'System' ([ordered]@{
        Manufacturer    = $cs.Manufacturer
        Model           = $cs.Model
        'Total RAM (GB)'= [math]::Round($cs.TotalPhysicalMemory/1GB,2)
        Domain          = $cs.Domain
        Workgroup       = $cs.Workgroup
        CurrentUser     = $cs.UserName
        Hostname        = $env:COMPUTERNAME
    })))

    # -- BIOS ----------------------------------------------------------------
    $sections.Add((_kv 'bios' 'BIOS / Firmware' ([ordered]@{
        Manufacturer    = $bios.Manufacturer
        Version         = $bios.SMBIOSBIOSVersion
        'Release Date'  = $bios.ReleaseDate
        'Serial Number' = $bios.SerialNumber
    })))

    # -- Processor -----------------------------------------------------------
    $sections.Add((_kv 'processor' 'Processor' ([ordered]@{
        Name                = $cpu.Name
        Manufacturer        = $cpu.Manufacturer
        Cores               = $cpu.NumberOfCores
        'Logical Processors'= $cpu.NumberOfLogicalProcessors
        'Max Speed (MHz)'   = $cpu.MaxClockSpeed
        Socket              = $cpu.SocketDesignation
        Architecture        = $cpu.Architecture
    })))

    # -- Operating System ----------------------------------------------------
    $sections.Add((_kv 'os' 'Operating System' ([ordered]@{
        Caption           = $os.Caption
        Version           = $os.Version
        'Build (Full)'    = "$($regOS.CurrentBuild).$($regOS.UBR)"
        'Display Version' = $regOS.DisplayVersion
        Architecture      = $os.OSArchitecture
        'Install Date'    = $os.InstallDate
        'Last Boot'       = $os.LastBootUpTime
        'System Drive'    = $os.SystemDrive
        'Registered Owner'= $regOS.RegisteredOwner
    })))

    # -- Memory Modules ------------------------------------------------------
    $memRows = @(Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
        $mt = switch ($_.MemoryType) {
            20 { 'DDR' }
            21 { 'DDR2' }
            24 { 'DDR3' }
            26 { 'DDR4' }
            34 { 'DDR5' }
            default { "Type $($_.MemoryType)" }
        }
        ,@(
            $_.DeviceLocator,
            $_.Manufacturer,
            $_.PartNumber.Trim(),
            $_.SerialNumber,
            "$([math]::Round($_.Capacity/1GB,0)) GB",
            "$($_.Speed) MHz",
            $mt
        )
    })
    $sections.Add((_tbl 'memory' 'Memory Modules' @('Slot','Manufacturer','Part Number','Serial','Capacity','Speed','Type') $memRows))

    # -- Storage -------------------------------------------------------------
    $allSmartWmiReport = Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_ATAPISmartData -ErrorAction SilentlyContinue
    $storageData = @(Get-PhysicalDisk -ErrorAction SilentlyContinue | ForEach-Object {
        $rel     = $_ | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        $diskNum = [int]$_.DeviceId
        $vs      = $null
        if ($allSmartWmiReport) {
            $se = $allSmartWmiReport | Where-Object { $_.InstanceName -match "_${diskNum}$" } | Select-Object -First 1
            if ($se) { $vs = $se.VendorSpecific }
        }

        # Wear: try reliability counter, then SMART attr fallbacks, then label NVMe
        $wearStr = 'N/A'
        if ($_.MediaType -eq 'SSD') {
            if ($rel -and $rel.Wear -gt 0) {
                $worn    = [int]$rel.Wear
                $wearStr = "$(100 - $worn)% remaining ($worn% worn)"
            } elseif ($_.BusType -ne 'NVMe' -and $vs) {
                foreach ($wid in @(0xE9, 0xE7, 0xCA, 0xA9, 0xD1)) {
                    $wa = Get-SmartAttribute -VendorSpecific $vs -AttributeId $wid
                    if ($wa -and $wa.Normalized -gt 0 -and $wa.Normalized -le 100) {
                        $worn    = 100 - $wa.Normalized
                        $wearStr = "$($wa.Normalized)% remaining ($worn% worn)"
                        break
                    }
                }
            }
            if ($wearStr -eq 'N/A' -and $_.BusType -eq 'NVMe') { $wearStr = 'N/A (NVMe)' }
        }

        $tbWritten = '-'; $tbRead = '-'; $reallocated = '-'; $pending = '-'; $uncorrect = '-'
        if ($vs) {
            $a5   = Get-SmartAttribute -VendorSpecific $vs -AttributeId 5
            $a197 = Get-SmartAttribute -VendorSpecific $vs -AttributeId 197
            $a198 = Get-SmartAttribute -VendorSpecific $vs -AttributeId 198
            $a241 = Get-SmartAttribute -VendorSpecific $vs -AttributeId 241
            $a242 = Get-SmartAttribute -VendorSpecific $vs -AttributeId 242
            if ($a5)                        { $reallocated = $a5.Raw }
            if ($a197)                      { $pending     = $a197.Raw }
            if ($a198)                      { $uncorrect   = $a198.Raw }
            if ($a241 -and $a241.Raw -gt 0) { $tbWritten   = Format-LbaBytes $a241.Raw }
            if ($a242 -and $a242.Raw -gt 0) { $tbRead      = Format-LbaBytes $a242.Raw }
        } elseif ($_.BusType -eq 'NVMe') {
            $tbWritten = 'N/A (NVMe)'; $tbRead = 'N/A (NVMe)'
        }

        [PSCustomObject]@{
            Name          = $_.FriendlyName
            Type          = $_.MediaType
            Size          = "$([math]::Round($_.Size/1GB,1)) GB"
            Health        = $_.HealthStatus
            Bus           = $_.BusType
            Wear          = $wearStr
            TempC         = if ($rel -and $rel.Temperature)                { $rel.Temperature }   else { '-' }
            PowerOnHrs    = if ($rel -and $rel.PowerOnHours)               { $rel.PowerOnHours }  else { '-' }
            TotalWritten  = $tbWritten
            TotalRead     = $tbRead
            Reallocated   = $reallocated
            PendingSect   = $pending
            Uncorrectable = $uncorrect
            ReadErrors    = if ($rel -and $null -ne $rel.ReadErrorsTotal)  { $rel.ReadErrorsTotal }  else { '-' }
            WriteErrors   = if ($rel -and $null -ne $rel.WriteErrorsTotal) { $rel.WriteErrorsTotal } else { '-' }
        }
    })

    # Section 1: basic overview (8 columns - readable width)
    $sections.Add((_tbl 'storage' 'Storage Drives' @('Drive','Type','Size','Health','Bus','Wear','Temp C','Power-On Hrs') @(
        $storageData | ForEach-Object { ,@($_.Name, $_.Type, $_.Size, $_.Health, $_.Bus, $_.Wear, $_.TempC, $_.PowerOnHrs) }
    )))
    # Section 2: SMART detail (8 columns)
    $sections.Add((_tbl 'storage_smart' 'Storage SMART Detail' @('Drive','Total Written','Total Read','Reallocated','Pending Sect','Uncorrectable','Read Errors','Write Errors') @(
        $storageData | ForEach-Object { ,@($_.Name, $_.TotalWritten, $_.TotalRead, $_.Reallocated, $_.PendingSect, $_.Uncorrectable, $_.ReadErrors, $_.WriteErrors) }
    )))

    # -- Battery -------------------------------------------------------------
    $batStatic = Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData    -ErrorAction SilentlyContinue | Select-Object -First 1
    $batFull   = Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | Select-Object -First 1
    $batCycle  = Get-CimInstance -Namespace root\wmi -ClassName BatteryCycleCount    -ErrorAction SilentlyContinue | Select-Object -First 1
    $batWmi    = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($batWmi) {
        $health = if ($batFull -and $batStatic -and $batStatic.DesignedCapacity) {
            "$([math]::Round(($batFull.FullChargedCapacity/$batStatic.DesignedCapacity)*100,1))%"
        } else { 'N/A' }
        $sections.Add((_kv 'battery' 'Battery' ([ordered]@{
            'Charge Remaining' = "$($batWmi.EstimatedChargeRemaining)%"
            'Status'           = $batWmi.BatteryStatus
            'Wear / Health'    = $health
            'Design Capacity'  = if($batStatic){"$($batStatic.DesignedCapacity) mWh"}else{'N/A'}
            'Full Charge Cap'  = if($batFull)  {"$($batFull.FullChargedCapacity) mWh"}  else{'N/A'}
            'Cycle Count'      = if($batCycle) {$batCycle.CycleCount}else{'N/A'}
            Manufacturer       = $batStatic.ManufactureName
            'Device Name'      = $batStatic.DeviceName
        })))
    } else {
        $sections.Add((_kv 'battery' 'Battery' ([ordered]@{ Status = 'No battery detected (desktop system)' })))
    }

    # -- Thermal Zones -------------------------------------------------------
    $thermalRows = @(
        Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue |
        ForEach-Object {
            $c = [math]::Round(($_.CurrentTemperature/10)-273.15,1)
            ,@($_.InstanceName, "$c  degC", "$([math]::Round($c*9/5+32,1))  degF")
        }
    )
    if ($thermalRows.Count) {
        $sections.Add((_tbl 'thermal' 'Thermal Zones' @('Zone','Celsius','Fahrenheit') $thermalRows))
    }

    # -- Network Adapters ----------------------------------------------------
    $netRows = @(Get-NetAdapter | ForEach-Object {
        $ip = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress -join ', '
        ,@($_.Name, $_.Status, $_.MacAddress, $ip, $_.LinkSpeed, $_.InterfaceDescription)
    })
    $sections.Add((_tbl 'network' 'Network Adapters' @('Name','Status','MAC','IPv4','Speed','Description') $netRows))

    # -- Security ------------------------------------------------------------
    $tpm  = Get-Tpm -ErrorAction SilentlyContinue
    $av   = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
    $fw   = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName FirewallProduct  -ErrorAction SilentlyContinue
    $sb   = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
    $bl   = (manage-bde -status 2>$null | Select-String 'Protection Status') -replace '.*:\s*',''
    $sections.Add((_kv 'security' 'Security' ([ordered]@{
        'Secure Boot'   = if($sb){'Enabled'}else{'Disabled or N/A'}
        'TPM Present'   = if($tpm){$tpm.TpmPresent}else{'N/A'}
        'TPM Enabled'   = if($tpm){$tpm.TpmEnabled}else{'N/A'}
        'TPM Ready'     = if($tpm){$tpm.TpmReady}  else{'N/A'}
        BitLocker       = ($bl -join '; ')
        Antivirus       = ($av | ForEach-Object { $_.displayName }) -join ', '
        Firewall        = ($fw | ForEach-Object { $_.displayName }) -join ', '
    })))

    # -- Power Settings -------------------------------------------------------
    $activeGuid = (powercfg /getactivescheme) -replace '.*GUID: ([a-f0-9-]+).*','$1'
    $overlay = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' `
                -Name ActiveOverlayAcPowerScheme -ErrorAction SilentlyContinue).ActiveOverlayAcPowerScheme
    $sliderLabel = if ($overlay) {
        switch ($overlay) {
            '{961cc777-2547-4f9d-8174-7d86181b8a7a}' { 'Best Battery Life' }
            '{00000000-0000-0000-0000-000000000000}' { 'Balanced' }
            '{ded574b5-45a0-4f42-8737-46345c09c238}' { 'Best Performance' }
            default { "Custom ($overlay)" }
        }
    } else { switch ($activeGuid) {
        'a1841308-3541-4fab-bc81-f71556f20b4a' { 'Best Battery Life' }
        '381b4222-f694-41f0-9685-ff5bb260df2e' { 'Balanced' }
        '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' { 'Best Performance' }
        default { "Custom ($activeGuid)" }
    }}
    $sections.Add((_kv 'power' 'Power Settings' ([ordered]@{
        'Power Slider'       = $sliderLabel
        'Active Scheme GUID' = $activeGuid
    })))

    # -- Display -------------------------------------------------------------
    $dpi = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name LogPixels -ErrorAction SilentlyContinue).LogPixels
    $dpiLabel = switch ($dpi) {
        96      { 'Small (100%)' }
        120     { 'Medium (125%)' }
        144     { 'Large (150%)' }
        192     { 'Larger (200%)' }
        $null   { 'Default (100%)' }
        default { "Custom ($dpi DPI)" }
    }
    $gpu = Get-CimInstance Win32_VideoController | ForEach-Object { "$($_.Name)  - driver $($_.DriverVersion)" }
    $sections.Add((_kv 'display' 'Display & Graphics' ([ordered]@{
        'DPI Scale'    = $dpiLabel
        'GPU(s)'       = $gpu -join ' | '
        'Resolution'   = (Get-CimInstance Win32_VideoController | Select-Object -First 1 |
                          ForEach-Object { "$($_.CurrentHorizontalResolution) x $($_.CurrentVerticalResolution)" })
        'Refresh Rate' = (Get-CimInstance Win32_VideoController | Select-Object -First 1).CurrentRefreshRate
    })))

    # -- Applications --------------------------------------------------------
    $teamsVer  = (Get-AppxPackage -AllUsers -Name 'MSTeams'   -ErrorAction SilentlyContinue | Select-Object -First 1).Version
    if (-not $teamsVer) {
        $tj = "$env:APPDATA\Microsoft\Teams\settings.json"
        if (Test-Path $tj) { $teamsVer = (Get-Content $tj | ConvertFrom-Json -ErrorAction SilentlyContinue).version }
    }
    $officeVer = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue).VersionToReport
    $zoomVer   = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                   'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
                  Where-Object { $_.DisplayName -like '*Zoom*' } | Select-Object -First 1).DisplayVersion
    $sections.Add((_kv 'apps' 'Key Applications' ([ordered]@{
        'Microsoft Teams' = if($teamsVer){$teamsVer}else{'Not installed'}
        'Microsoft Office'= if($officeVer){$officeVer}else{'Not installed'}
        Zoom              = if($zoomVer){$zoomVer}else{'Not installed'}
    })))

    # -- Device Manager (error devices only) ---------------------------------
    $errCodes = @{
        1='Not configured';2='Driver load failed';10='Cannot start';22='Disabled';
        28='Driver not installed';43='Reported problems';default_='Error'
    }
    $devRows = @(Get-CimInstance Win32_PnPEntity |
        ForEach-Object {
            $code = [int]$_.ConfigManagerErrorCode
            $stat = if ($code -eq 0) { 'OK' } elseif ($errCodes.ContainsKey($code)) { $errCodes[$code] } else { "Error $code" }
            ,@($_.Name, $stat, $code, $_.DeviceID)
        })
    $sections.Add((_tbl 'devices' 'All Devices (Device Manager)' @('Device','Status','Code','Instance ID') $devRows))

    # -- Reboot History (last 30 days) ----------------------------------------
    $evtRows = @(Get-WinEvent -FilterHashtable @{
        LogName='System'; Id=@(1074,6006,6008,41)
        StartTime=(Get-Date).AddDays(-30)
    } -ErrorAction SilentlyContinue | Sort-Object TimeCreated | ForEach-Object {
        $type = switch ($_.Id) {
            1074    { 'User-initiated shutdown/restart' }
            6006    { 'Clean shutdown' }
            6008    { 'Unexpected / dirty shutdown' }
            41      { 'Kernel power - no clean shutdown' }
            default { "Event $($_.Id)" }
        }
        ,@($_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), $_.Id, $type, ($_.Message -split "`n")[0])
    })
    $sections.Add((_tbl 'reboots' 'Reboot / Shutdown History (30 days)' @('Time','Event ID','Type','Message') $evtRows))

    # -- Known Issues --------------------------------------------------------
    $issueRows = [System.Collections.Generic.List[object]]::new()

    $errDevCount = (Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 }).Count
    $devVal    = if ($errDevCount) { "$errDevCount device(s) with errors" } else { 'All OK' }
    $devStatus = if ($errDevCount) { 'Warning' } else { 'OK' }
    $issueRows.Add(@('Device Manager', $devVal, $devStatus))

    $full2   = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue).FullChargedCapacity
    $design2 = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData          -ErrorAction SilentlyContinue).DesignedCapacity
    if ($full2 -and $design2 -and $design2 -gt 0) {
        $h         = [math]::Round(($full2 / $design2) * 100, 1)
        $batStatus = if ($h -lt 60) { 'Warning' } else { 'OK' }
        $issueRows.Add(@('Battery Health', "$h%", $batStatus))
    }

    $dirtyCount   = (Get-WinEvent -FilterHashtable @{ LogName='System'; Id=@(6008,41); StartTime=(Get-Date).AddDays(-30) } -ErrorAction SilentlyContinue).Count
    $dirtyStatus  = if ($dirtyCount -gt 0) { 'Warning' } else { 'OK' }
    $issueRows.Add(@('Unexpected Shutdowns (30d)', $dirtyCount, $dirtyStatus))

    $pendingReboot = ($null -ne (Get-Item 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'              -ErrorAction SilentlyContinue)) -or
                     ($null -ne (Get-Item 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' -ErrorAction SilentlyContinue))
    $rebootVal    = if ($pendingReboot) { 'Yes' }     else { 'No' }
    $rebootStatus = if ($pendingReboot) { 'Warning' } else { 'OK' }
    $issueRows.Add(@('Pending Reboot', $rebootVal, $rebootStatus))

    $sbVal    = if ($sb) { 'Enabled' }  else { 'Disabled' }
    $sbStatus = if ($sb) { 'OK' }       else { 'Warning' }
    $issueRows.Add(@('Secure Boot', $sbVal, $sbStatus))

    $freeGB      = [math]::Round((Get-PSDrive ($env:SystemDrive -replace ':', '')).Free / 1GB, 1)
    $diskStatus  = if ($freeGB -lt 10) { 'Warning' } else { 'OK' }
    $issueRows.Add(@('Free Disk Space (C:)', "$freeGB GB", $diskStatus))
    $sections.Add((_tbl 'issues' 'Known Issues Scan' @('Check','Value','Status') @($issueRows)))

    # -- Installed Drivers ----------------------------------------------------
    $drvRows = @(Get-WindowsDriver -Online -ErrorAction SilentlyContinue |
        Select-Object -First 200 |
        ForEach-Object {
            ,@($_.ClassName, $_.ProviderName, $_.Version, $_.Date.ToString('yyyy-MM-dd'), [System.IO.Path]::GetFileName($_.OriginalFileName))
        })
    $sections.Add((_tbl 'drivers' 'Installed Drivers (first 200)' @('Class','Provider','Version','Date','File') $drvRows))

    # -- Installed Software ---------------------------------------------------
    # Normalise InstallDate: registry stores yyyyMMdd, but some installers write
    # a full date string.  Always output yyyy-MM-dd or empty.
    function _fmtDate { param([string]$raw)
        if (-not $raw) { return '' }
        if ($raw -match '^\d{8}$') {
            return "$($raw.Substring(0,4))-$($raw.Substring(4,2))-$($raw.Substring(6,2))"
        }
        $dt = $null
        if ([datetime]::TryParse($raw, [ref]$dt)) { return $dt.ToString('yyyy-MM-dd') }
        return $raw
    }

    # Also query the interactive user's hive via HKU so user-installed apps
    # (e.g. Steam) show up even when the script is running elevated as a
    # different admin account.
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    # Find the SID of the profile that owns $env:USERPROFILE and add its HKU path
    $profileList = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*' -ErrorAction SilentlyContinue
    $userSid = ($profileList | Where-Object { $_.ProfileImagePath -eq $env:USERPROFILE } | Select-Object -First 1).PSChildName
    if ($userSid -and $userSid -ne '') {
        $regPaths += "Registry::HKEY_USERS\$userSid\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        $regPaths += "Registry::HKEY_USERS\$userSid\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    }

    $swRows = @(
        Get-ItemProperty $regPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Sort-Object DisplayName -Unique |
        ForEach-Object { ,@($_.DisplayName, $_.DisplayVersion, $_.Publisher, (_fmtDate $_.InstallDate)) }
    )
    $sections.Add((_tbl 'software' 'Installed Software' @('Name','Version','Publisher','Install Date') $swRows))

    # -- Running Processes (top 40 by CPU) ------------------------------------
    $procRows = @(Get-Process | Sort-Object CPU -Descending | Select-Object -First 40 | ForEach-Object {
        ,@($_.Name, $_.Id, [math]::Round($_.CPU, 1), "$([math]::Round($_.WorkingSet64/1MB,1)) MB", $_.Path)
    })
    $sections.Add((_tbl 'processes' 'Running Processes (top 40 CPU)' @('Name','PID','CPU (s)','Memory','Path') $procRows))

    # -- Services (non-running) -----------------------------------------------
    $svcRows = @(Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' } | ForEach-Object {
        ,@($_.DisplayName, $_.Name, $_.Status, $_.StartType)
    })
    $sections.Add((_tbl 'services' 'Auto-Start Services Not Running' @('Display Name','Service Name','Status','Start Type') $svcRows))

    # -- Startup Programs -----------------------------------------------------
    $startupPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    )
    $startRows = @(foreach ($p in $startupPaths) {
        if (Test-Path $p) {
            $hive = if ($p -like 'HKLM*') { 'HKLM' } else { 'HKCU' }
            Get-ItemProperty $p | ForEach-Object {
                $_.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
                    ,@($_.Name, $_.Value, $hive)
                }
            }
        }
    })
    $sections.Add((_tbl 'startup' 'Startup Programs (Registry)' @('Name','Command','Hive') $startRows))

    # -- Local Users ----------------------------------------------------------
    $userRows = @(Get-LocalUser -ErrorAction SilentlyContinue | ForEach-Object {
        ,@($_.Name, $_.FullName, $_.Enabled, $_.LastLogon, $_.PasswordLastSet, $_.Description)
    })
    $sections.Add((_tbl 'localusers' 'Local User Accounts' @('Username','Full Name','Enabled','Last Logon','Password Set','Description') $userRows))

    # -- Local Groups ---------------------------------------------------------
    $grpRows = @(Get-LocalGroup -ErrorAction SilentlyContinue | ForEach-Object {
        $members = (Get-LocalGroupMember $_.Name -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ', '
        ,@($_.Name, $members, $_.Description)
    })
    $sections.Add((_tbl 'localgroups' 'Local Groups' @('Group','Members','Description') $grpRows))

    # -- Network Connections --------------------------------------------------
    $connRows = @(Get-NetTCPConnection -State Established,Listen -ErrorAction SilentlyContinue | ForEach-Object {
        $proc = (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name
        ,@($_.State, $_.LocalAddress, $_.LocalPort, $_.RemoteAddress, $_.RemotePort, $proc, $_.OwningProcess)
    })
    $sections.Add((_tbl 'netconn' 'Network Connections (TCP)' @('State','Local Addr','Local Port','Remote Addr','Remote Port','Process','PID') $connRows))

    # -- Windows Update History -----------------------------------------------
    $wuRows = @(Get-WuaHistory | Select-Object -First 50 | ForEach-Object {
        ,@($_.Date, $_.Title, $_.Result)
    })
    $sections.Add((_tbl 'wuhistory' 'Windows Update History (last 50)' @('Date','Title','Result') $wuRows))

    # -- Recent System Errors (last 50) ---------------------------------------
    $evtErrRows = @(Get-WinEvent -FilterHashtable @{
        LogName   = 'System'
        Level     = @(1, 2)
        StartTime = (Get-Date).AddDays(-14)
    } -MaxEvents 50 -ErrorAction SilentlyContinue | ForEach-Object {
        ,@($_.TimeCreated.ToString('yyyy-MM-dd HH:mm'), $_.Id, $_.LevelDisplayName, $_.ProviderName, ($_.Message -split "`n")[0])
    })
    $sections.Add((_tbl 'sysevterr' 'Recent System Errors / Criticals (14 days)' @('Time','Event ID','Level','Source','Message') $evtErrRows))

    # -- Shares ---------------------------------------------------------------
    $shareRows = @(Get-SmbShare -ErrorAction SilentlyContinue | ForEach-Object {
        ,@($_.Name, $_.Path, $_.Description, $_.ShareType)
    })
    $sections.Add((_tbl 'shares' 'SMB Shares' @('Name','Path','Description','Type') $shareRows))

    # -- Boot Configuration (BCDEdit) - raw -----------------------------------
    $bcdRaw = (bcdedit /enum all 2>$null) -join "`n"
    $sections.Add([PSCustomObject]@{ id='bcd'; title='Boot Configuration (BCDEdit)'; type='raw'; content=$bcdRaw })

    # -- BitLocker Detail - raw -----------------------------------------------
    $blRaw = (manage-bde -status 2>$null) -join "`n"
    $sections.Add([PSCustomObject]@{ id='bitlocker'; title='BitLocker Detail'; type='raw'; content=$blRaw })

    # -- Environment Variables (System) - raw ---------------------------------
    $envRaw = ([System.Environment]::GetEnvironmentVariables('Machine').GetEnumerator() |
               Sort-Object Name | ForEach-Object { "$($_.Key) = $($_.Value)" }) -join "`n"
    $sections.Add([PSCustomObject]@{ id='envvars'; title='System Environment Variables'; type='raw'; content=$envRaw })

    return [PSCustomObject]@{
        meta = [PSCustomObject]@{
            tool      = "SysPulse $($Script:VERSION)"
            generated = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            hostname  = $env:COMPUTERNAME
            user      = $env:USERNAME
            os        = $os.Caption
        }
        sections = @($sections)
    }
}

function New-HtmlReport {
    <#
    .SYNOPSIS
        Generates a fully offline, searchable HTML report from a JSON string.
        No external dependencies  - everything is embedded inline.
    .PARAMETER JsonData  JSON string to embed (output of Get-AllDiagnosticData | ConvertTo-Json -Depth 10).
    .PARAMETER OutFile   Destination HTML file path.
    .PARAMETER Title     Page / browser tab title.
    #>
    param(
        [string]$JsonData,
        [string]$OutFile,
        [string]$Title = 'SysPulse Diagnostic Report'
    )

    # Escape any backtick that PS might expand  - the JSON goes inside a JS const,
    # so we just need to make sure </script> never appears in the data.
    $safeJson = $JsonData -replace '</script>','<\/script>'

    $html = @"
<!DOCTYPE html>
<html lang="en" data-theme="nord">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$Title</title>
<style>
/* --- Nord (default dark) theme --- */
:root,[data-theme="nord"]{
  --bg:#1a1b26;--surface:#1f2335;--surface2:#24283b;
  --hdr-bg:#16161e;--border:#2a2b3d;--border2:#2a2b3d;
  --text:#c0caf5;--muted:#565f89;--accent:#7aa2f7;
  --th-bg:#16161e;--th-text:#9aa5ce;
  --td-border:#1a1b26;--row-hover:#24283b;
  --kv-key:#9aa5ce;
  --badge-ok:#9ece6a;--badge-warn:#e0af68;--badge-err:#f7768e;
  --mark-bg:#3d4166;--mark-text:#c0caf5;
  --toggle-label:"Switch to Pinku";
}
/* --- OverPinku (light) theme --- */
[data-theme="pinku"]{
  --bg:#fff0f5;--surface:#fff8fa;--surface2:#ffe4ee;
  --hdr-bg:#ffe4ee;--border:rgba(255,20,147,.2);--border2:rgba(255,20,147,.25);
  --text:#5c1a3a;--muted:#b05070;--accent:#e91e8c;
  --th-bg:#ffe4ee;--th-text:#7a1040;
  --td-border:rgba(255,20,147,.1);--row-hover:#ffe4ee;
  --kv-key:#7a1040;
  --badge-ok:#2e7d32;--badge-warn:#e65100;--badge-err:#c62828;
  --mark-bg:rgba(233,30,140,.18);--mark-text:#5c1a3a;
  --toggle-label:"Switch to Nord";
}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',Arial,sans-serif;background:var(--bg);color:var(--text);font-size:14px;line-height:1.5;transition:background .25s,color .25s}
header{background:var(--hdr-bg);border-bottom:1px solid var(--border2);padding:18px 24px;position:sticky;top:0;z-index:100;display:flex;align-items:center;gap:16px;flex-wrap:wrap}
header h1{font-size:1.25rem;color:var(--accent);white-space:nowrap}
header .meta{font-size:.8rem;color:var(--muted);flex:1}
#searchbox{padding:7px 12px;border-radius:6px;border:1px solid var(--border2);background:var(--surface);color:var(--text);font-size:13px;width:260px;outline:none;transition:border .2s,background .25s}
#searchbox:focus{border-color:var(--accent)}
#clearbtn,#themebtn{background:none;border:none;color:var(--muted);cursor:pointer;font-size:1rem;padding:0 4px;line-height:1}
#clearbtn:hover,#themebtn:hover{color:var(--text)}
#themebtn{font-size:.75rem;padding:4px 8px;border:1px solid var(--border2);border-radius:4px;white-space:nowrap}
main{max-width:1200px;margin:24px auto;padding:0 16px;display:flex;flex-direction:column;gap:20px}
.section{background:var(--surface);border-radius:10px;border:1px solid var(--border);overflow:hidden;transition:background .25s}
.section-header{display:flex;justify-content:space-between;align-items:center;padding:12px 18px;cursor:pointer;user-select:none;background:var(--surface);transition:background .15s}
.section-header:hover{background:var(--surface2)}
.section-header h2{font-size:.95rem;color:var(--accent);font-weight:600}
.chevron{color:var(--muted);font-size:.8rem;transition:transform .2s}
.section.collapsed .chevron{transform:rotate(-90deg)}
.section-body{overflow-x:auto}
.section.collapsed .section-body{display:none}
table{width:100%;border-collapse:collapse;font-size:13px}
th{background:var(--th-bg);color:var(--th-text);font-weight:600;padding:8px 12px;text-align:left;border-bottom:1px solid var(--border2);position:sticky;top:0;white-space:nowrap}
td{padding:7px 12px;border-bottom:1px solid var(--td-border);vertical-align:top;word-break:break-all}
tr:last-child td{border-bottom:none}
tr:hover td{background:var(--row-hover)}
.kv-key{color:var(--kv-key);width:220px;white-space:nowrap;font-weight:500}
.badge-ok{color:var(--badge-ok);font-weight:600}.badge-warn{color:var(--badge-warn);font-weight:600}.badge-error{color:var(--badge-err);font-weight:600}
.hidden{display:none!important}
mark{background:var(--mark-bg);color:var(--mark-text);border-radius:2px;padding:0 1px}
#no-results{text-align:center;padding:40px;color:var(--muted);display:none}
#toc{background:var(--hdr-bg);border-bottom:1px solid var(--border2);padding:8px 16px;font-size:.78rem;display:flex;flex-wrap:wrap;gap:6px 12px}
#toc a{color:var(--muted);text-decoration:none;transition:color .15s}
#toc a:hover{color:var(--accent)}
.match-count{font-size:.75rem;color:var(--muted);margin-left:6px}
</style>
</head>
<body>
<header>
  <h1>&#128268; SysPulse</h1>
  <span class="meta" id="header-meta">Loading...</span>
  <input id="searchbox" type="search" placeholder="Search all data..." autocomplete="off" spellcheck="false">
  <button id="clearbtn" title="Clear search">&#x2715;</button>
  <button id="themebtn" title="Toggle colour theme">&#127912; Theme</button>
</header>
<nav id="toc"></nav>
<main id="main">
  <div id="no-results">No matching results for your search.</div>
</main>
<script>
const DATA = $safeJson;

// -- Render ----------------------------------------------------------------
const main = document.getElementById('main');
const toc  = document.getElementById('toc');

// Header meta
const m = DATA.meta;
document.getElementById('header-meta').textContent =
  m.hostname + ' \u2022 ' + m.os + ' \u2022 ' + m.user + ' \u2022 Generated: ' + m.generated;
document.title = 'SysPulse \u2014 ' + m.hostname;

function esc(s){ return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;') }

function statusBadge(val){
  const v = String(val).toLowerCase();
  if(v==='ok'||v==='true'||v==='enabled'||v==='yes') return '<span class="badge-ok">'+esc(val)+'</span>';
  if(v==='warning'||v==='warn') return '<span class="badge-warn">&#9888; Warning</span>';
  if(v==='error'||v==='false'||v==='disabled'||v==='no') return '<span class="badge-error">'+esc(val)+'</span>';
  return esc(val);
}

function buildSection(sec){
  const div = document.createElement('div');
  div.className = 'section';
  div.id = 'sec-' + sec.id;

  const hdr = document.createElement('div');
  hdr.className = 'section-header';
  hdr.innerHTML = '<h2>' + esc(sec.title) + '<span class="match-count" id="mc-'+sec.id+'"></span></h2>'
                + '<span class="chevron">&#9660;</span>';
  hdr.addEventListener('click', () => {
    div.classList.toggle('collapsed');
  });

  const body = document.createElement('div');
  body.className = 'section-body';

  if(sec.type === 'raw'){
    body.innerHTML = '<pre style="padding:12px 18px;font-size:12px;line-height:1.5;color:var(--text);white-space:pre-wrap;word-break:break-word;overflow-x:auto" data-row>' + esc(sec.content||'') + '</pre>';
  } else {
    let tableHtml = '<table>';
    if(sec.type === 'kv'){
      (sec.rows||[]).forEach(r => {
        tableHtml += '<tr data-row><td class="kv-key">'+esc(r[0])+'</td><td>'+statusBadge(r[1])+'</td></tr>';
      });
    } else {
      tableHtml += '<thead><tr>' + (sec.headers||[]).map(h=>'<th>'+esc(h)+'</th>').join('') + '</tr></thead><tbody>';
      (sec.rows||[]).forEach(r => {
        const cells = Array.isArray(r) ? r : Object.values(r);
        tableHtml += '<tr data-row>' + cells.map((c,i) => {
          const hdr = (sec.headers||[])[i]||'';
          const val = (hdr==='Status'||hdr==='Code') ? statusBadge(c) : esc(c);
          return '<td>' + val + '</td>';
        }).join('') + '</tr>';
      });
      tableHtml += '</tbody>';
    }
    tableHtml += '</table>';
    body.innerHTML = tableHtml;
  }
  div.appendChild(hdr);
  div.appendChild(body);
  return div;
}

DATA.sections.forEach(sec => {
  main.appendChild(buildSection(sec));
  const a = document.createElement('a');
  a.href = '#sec-'+sec.id;
  a.textContent = sec.title;
  toc.appendChild(a);
});

// -- Search ----------------------------------------------------------------
const searchbox = document.getElementById('searchbox');
const clearbtn  = document.getElementById('clearbtn');
const noResults = document.getElementById('no-results');

function clearHighlights(el){
  el.querySelectorAll('mark').forEach(m => {
    m.replaceWith(document.createTextNode(m.textContent));
  });
  el.normalize();
}

function highlight(el, term){
  if(!term) return;
  const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, null, false);
  const nodes = [];
  while(walker.nextNode()) nodes.push(walker.currentNode);
  nodes.forEach(node => {
    const idx = node.textContent.toLowerCase().indexOf(term);
    if(idx === -1) return;
    const mark = document.createElement('mark');
    const after = node.splitText(idx);
    after.splitText(term.length);
    mark.appendChild(after.cloneNode(true));
    after.replaceWith(mark);
  });
}

function doSearch(){
  const q = searchbox.value.trim().toLowerCase();
  let totalVisible = 0;

  document.querySelectorAll('.section').forEach(sec => {
    const id = sec.id.replace('sec-','');
    const rows = sec.querySelectorAll('tr[data-row]');
    clearHighlights(sec);
    let visibleRows = 0;

    rows.forEach(row => {
      if(!q){ row.classList.remove('hidden'); visibleRows++; return; }
      const text = row.textContent.toLowerCase();
      if(text.includes(q)){
        row.classList.remove('hidden');
        highlight(row, q);
        visibleRows++;
      } else {
        row.classList.add('hidden');
      }
    });

    const mc = document.getElementById('mc-'+id);
    if(q && mc){ mc.textContent = visibleRows ? ' ('+visibleRows+' match'+(visibleRows>1?'es':'')+')' : ''; }
    else if(mc){ mc.textContent = ''; }

    // Expand sections that have matches; collapse empty ones when searching
    if(q){
      if(visibleRows > 0){ sec.classList.remove('collapsed'); totalVisible += visibleRows; }
      else { sec.classList.add('collapsed'); }
    } else {
      sec.classList.remove('collapsed');
      totalVisible += rows.length;
    }
  });

  noResults.style.display = (q && totalVisible===0) ? 'block' : 'none';
}

searchbox.addEventListener('input', doSearch);
clearbtn.addEventListener('click', () => { searchbox.value=''; doSearch(); searchbox.focus(); });

// -- Theme toggle -----------------------------------------------------------
const root = document.documentElement;
const themebtn = document.getElementById('themebtn');
const savedTheme = localStorage.getItem('syspulse-theme') || 'nord';
root.setAttribute('data-theme', savedTheme);

themebtn.addEventListener('click', () => {
  const next = root.getAttribute('data-theme') === 'nord' ? 'pinku' : 'nord';
  root.setAttribute('data-theme', next);
  localStorage.setItem('syspulse-theme', next);
});
</script>
</body>
</html>
"@
    $html | Set-Content $OutFile -Encoding UTF8
}

function Export-DiagnosticReport {
    <#
    .SYNOPSIS
        Collects all diagnostic data, saves data.json, and generates report.html.
        Both files are fully self-contained and work offline.
    .PARAMETER OutFolder  Output folder.  Defaults to the current $Script:OutRoot or creates one.
    #>
    param([string]$OutFolder = $Script:OutRoot)
    if (-not $OutFolder) { $OutFolder = New-OutputFolder }

    Write-Host "  Collecting diagnostic data..." -ForegroundColor Cyan
    $data = Get-AllDiagnosticData

    # Save raw JSON
    $jsonPath = Join-Path $OutFolder 'data.json'
    $json     = $data | ConvertTo-Json -Depth 10 -Compress:$false
    $json | Set-Content $jsonPath -Encoding UTF8
    Write-Host "  data.json written to: $jsonPath" -ForegroundColor Green

    # Build HTML report (JSON embedded inline)
    $htmlPath  = Join-Path $OutFolder 'report.html'
    $title     = "SysPulse  - $($data.meta.hostname)  - $($data.meta.generated)"
    New-HtmlReport -JsonData $json -OutFile $htmlPath -Title $title
    Write-Host "  report.html written to: $htmlPath" -ForegroundColor Green

    return $htmlPath
}

# -----------------------------------------------------------------------------
#  SECTION 19  - MASTER COLLECTION  (Invoke-All)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
#  SMTP  -- encrypted credential storage and report delivery
# -----------------------------------------------------------------------------

function Get-SmtpConfigPath {
    return Join-Path (Split-Path $PSCommandPath -Parent) 'SysPulse_smtp.cfg'
}

function Invoke-PackageSmtp {
    <#
    .SYNOPSIS
        Encrypts SMTP credentials with AES-256 and writes them directly into
        this script file so clients never need to configure anything.
        Run this once on your own machine, then distribute the script.
    #>
    Write-Host "`n  -- Package SMTP Credentials into Script ----------------" -ForegroundColor Cyan
    Write-Host   "  The password will be AES-256 encrypted and embedded in"
    Write-Host   "  the script. Clients will never see or enter credentials.`n"

    Write-Host   "  Leave recipient blank to ask on the client at send-time.`n"
    $server = Read-Host "  SMTP server  (e.g. smtp.gmail.com)"
    $port   = [int](Read-Host "  SMTP port    (e.g. 587)")
    $ssl    = ((Read-Host "  Use SSL/TLS? [Y/n]").Trim().ToUpper() -ne 'N')
    $from   = Read-Host "  From address"
    $to     = (Read-Host "  Recipient address (leave blank to ask on client)").Trim()
    $user   = Read-Host "  SMTP username"
    $secPwd = Read-Host "  SMTP password" -AsSecureString

    # Extract plain text from SecureString only long enough to encrypt it
    $bstr    = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPwd)
    $plain   = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    # AES-256 encrypt
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256
    $aes.GenerateKey()
    $aes.GenerateIV()
    $enc       = $aes.CreateEncryptor()
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($plain)
    $cipher    = $enc.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
    $combined  = $aes.IV + $cipher          # IV prepended so we can extract it later
    $ePwd      = [Convert]::ToBase64String($combined)
    $key       = [Convert]::ToBase64String($aes.Key)
    $plain     = $null                      # clear plain text from memory

    # Build replacement block
    $sslStr  = if ($ssl) { '$true' } else { '$false' }
    $newBlock = @"
`$Script:_SmtpServer = '$server'
`$Script:_SmtpPort   = $port
`$Script:_SmtpSSL    = $sslStr
`$Script:_SmtpFrom   = '$from'
`$Script:_SmtpTo     = '$to'
`$Script:_SmtpUser   = '$user'
`$Script:_SmtpEPwd   = '$ePwd'
`$Script:_SmtpKey    = '$key'
"@

    # Write packaged copy to a new file (<name>_pkg.ps1) - original stays clean
    $srcPath  = $PSCommandPath
    $srcDir   = Split-Path $srcPath -Parent
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($srcPath)
    $pkgPath  = Join-Path $srcDir ($baseName + '_pkg.ps1')

    $content     = Get-Content $srcPath -Raw
    $pattern     = '(?s)(# =SMTP-BEGIN=\r?\n).*?(# =SMTP-END=)'
    $replacement = "# =SMTP-BEGIN=`n$newBlock# =SMTP-END="
    $updated     = [regex]::Replace($content, $pattern, $replacement)

    if ($updated -eq $content) {
        Write-Host "  ERROR: Could not locate the SMTP config block in the script." -ForegroundColor Red
        return
    }

    Set-Content $pkgPath $updated -Encoding UTF8 -NoNewline:$false
    Write-Host "`n  Packaged script written to:" -ForegroundColor Green
    Write-Host "  $pkgPath" -ForegroundColor White
    Write-Host   ""
    Write-Host   "  Distribute '$($baseName)_pkg.ps1' to clients."
    Write-Host   "  The original '$baseName.ps1' is unchanged."
    Write-Host   "  On successful send the packaged script will delete itself."
}

function Clear-EmbeddedSmtp {
    <# Strips embedded credentials from this script file (resets the block to blank defaults). #>
    $scriptPath = $PSCommandPath
    $content    = Get-Content $scriptPath -Raw
    $blank = @"
`$Script:_SmtpServer = ''
`$Script:_SmtpPort   = 587
`$Script:_SmtpSSL    = `$true
`$Script:_SmtpFrom   = ''
`$Script:_SmtpTo     = ''
`$Script:_SmtpUser   = ''
`$Script:_SmtpEPwd   = ''
`$Script:_SmtpKey    = ''
"@
    $pattern  = '(?s)(# =SMTP-BEGIN=\r?\n).*?(# =SMTP-END=)'
    $replacement = "# =SMTP-BEGIN=`n$blank# =SMTP-END="
    $updated  = [regex]::Replace($content, $pattern, $replacement)
    Set-Content $scriptPath $updated -Encoding UTF8 -NoNewline:$false
    Write-Host "  Embedded SMTP credentials cleared from script." -ForegroundColor Green
}

function Set-SmtpConfig {
    <#
    .SYNOPSIS
        Prompts for SMTP settings, encrypts the password with Windows DPAPI
        (tied to this user account on this machine), and saves to SysPulse_smtp.cfg.
        The password is never stored in plain text.
    #>
    Write-Host "`n  -- SMTP Configuration ----------------------------------" -ForegroundColor Cyan
    Write-Host   "  Password is encrypted with your Windows login (DPAPI)."
    Write-Host   "  It can only be decrypted by the same user on this machine.`n"

    $cfg = [ordered]@{
        SmtpServer = (Read-Host "  SMTP server (e.g. smtp.gmail.com)")
        SmtpPort   = [int](Read-Host "  SMTP port   (e.g. 587)")
        UseSSL     = ((Read-Host "  Use SSL/TLS? [Y/n]").Trim().ToUpper() -ne 'N')
        From       = (Read-Host "  From address")
        To         = (Read-Host "  To address  (report recipient)")
        Username   = (Read-Host "  SMTP username (usually same as From)")
    }
    $securePass        = Read-Host "  SMTP password" -AsSecureString
    $cfg['EncryptedPassword'] = ConvertFrom-SecureString $securePass

    $cfg | ConvertTo-Json | Set-Content (Get-SmtpConfigPath) -Encoding UTF8
    Write-Host "`n  SMTP settings saved to: $(Get-SmtpConfigPath)" -ForegroundColor Green
}

function Get-SmtpConfig {
    <#
    .SYNOPSIS  Reads and returns the saved SMTP config, or $null if not configured.
    #>
    $path = Get-SmtpConfigPath
    if (-not (Test-Path $path)) { return $null }
    $cfg = Get-Content $path -Raw | ConvertFrom-Json
    return $cfg
}

function Send-DiagnosticReport {
    <#
    .SYNOPSIS
        Emails the report.html (and optionally data.json) from the last collection.
        Prefers embedded AES-256 credentials (set via [P]) over the local DPAPI file.
        When running with embedded creds the script self-deletes after a successful send.
    .PARAMETER OutFolder  Folder containing report.html.  Uses $Script:OutRoot if omitted.
    #>
    param([string]$OutFolder = $Script:OutRoot)

    if (-not $OutFolder -or -not (Test-Path $OutFolder)) {
        Write-Host "  No output folder found. Run a collection first (option [A] or [29])." -ForegroundColor Yellow
        return
    }

    $reportFile = Join-Path $OutFolder 'report.html'
    if (-not (Test-Path $reportFile)) {
        Write-Host "  report.html not found in $OutFolder. Run option [29] to generate it." -ForegroundColor Yellow
        return
    }

    # -------------------------------------------------------------------------
    # Resolve credentials: embedded AES-256 block takes priority over DPAPI file
    # -------------------------------------------------------------------------
    $smtpServer  = $null
    $smtpPort    = 587
    $smtpSSL     = $true
    $smtpFrom    = $null
    $smtpTo      = $null
    $credential  = $null
    $usingEmbedded = $false

    if ($Script:_SmtpServer -ne '') {
        # Embedded credentials - decrypt AES-256
        try {
            $key        = [Convert]::FromBase64String($Script:_SmtpKey)
            $combined   = [Convert]::FromBase64String($Script:_SmtpEPwd)
            $iv         = $combined[0..15]
            $cipher     = $combined[16..($combined.Length - 1)]
            $aes        = [System.Security.Cryptography.Aes]::Create()
            $aes.Key    = $key
            $aes.IV     = $iv
            $plainBytes = $aes.CreateDecryptor().TransformFinalBlock($cipher, 0, $cipher.Length)
            $plain      = [System.Text.Encoding]::UTF8.GetString($plainBytes)
            $securePwd  = ConvertTo-SecureString $plain -AsPlainText -Force
            $plain      = $null
            $credential    = New-Object System.Management.Automation.PSCredential($Script:_SmtpUser, $securePwd)
            $smtpServer    = $Script:_SmtpServer
            $smtpPort      = $Script:_SmtpPort
            $smtpSSL       = [bool]$Script:_SmtpSSL
            $smtpFrom      = $Script:_SmtpFrom
            $usingEmbedded = $true
        } catch {
            Write-Host "  Failed to decrypt embedded credentials: $_" -ForegroundColor Red
            return
        }

        # Recipient: use embedded To if set, otherwise always ask
        if ($Script:_SmtpTo -ne '') {
            $smtpTo = $Script:_SmtpTo
        } else {
            $smtpTo = (Read-Host "  Enter recipient email address").Trim()
            if (-not $smtpTo) {
                Write-Host "  No recipient entered. Aborting send." -ForegroundColor Yellow
                return
            }
        }
    } else {
        # Fall back to DPAPI config file
        $cfg = Get-SmtpConfig
        if (-not $cfg) {
            Write-Host "  No SMTP credentials found." -ForegroundColor Yellow
            Write-Host "  Use [S] to configure per-machine credentials, or [P] to embed them in the script." -ForegroundColor Yellow
            return
        }
        try {
            $securePass = ConvertTo-SecureString $cfg.EncryptedPassword
            $credential = New-Object System.Management.Automation.PSCredential($cfg.Username, $securePass)
        } catch {
            Write-Host "  Failed to decrypt password. Re-run option [S] to re-enter credentials." -ForegroundColor Red
            return
        }
        $smtpServer = $cfg.SmtpServer
        $smtpPort   = $cfg.SmtpPort
        $smtpSSL    = [bool]$cfg.UseSSL
        $smtpFrom   = $cfg.From
        $smtpTo     = $cfg.To
    }

    $subject     = "SysPulse Report - $env:COMPUTERNAME - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $body        = "SysPulse diagnostic report attached from $env:COMPUTERNAME.`nGenerated: $(Get-Date)"
    $attachments = @($reportFile)
    $jsonFile   = Join-Path $OutFolder 'data.json'
    $idleFile   = Join-Path $OutFolder 'IdleAnalysis.html'
    if (Test-Path $jsonFile)  { $attachments += $jsonFile }
    if (Test-Path $idleFile)  { $attachments += $idleFile }

    Write-Host "  Sending report to $smtpTo via ${smtpServer}:${smtpPort}..." -ForegroundColor Cyan
    $sent = $false
    try {
        Send-MailMessage `
            -From        $smtpFrom `
            -To          $smtpTo `
            -Subject     $subject `
            -Body        $body `
            -Attachments $attachments `
            -SmtpServer  $smtpServer `
            -Port        $smtpPort `
            -Credential  $credential `
            -UseSsl:$smtpSSL `
            -ErrorAction Stop
        Write-Host "  Report sent successfully." -ForegroundColor Green
        $sent = $true
    } catch {
        Write-Host "  Failed to send email: $_" -ForegroundColor Red
    }

    # Self-delete when distributed with embedded credentials and send succeeded
    if ($sent -and $usingEmbedded -and $PSCommandPath) {
        Write-Host "  Self-deleting script as configured for client distribution..." -ForegroundColor DarkGray
        $target = $PSCommandPath
        # Launch a detached process that waits briefly then removes the file
        $cmd = "Start-Sleep -Milliseconds 800; Remove-Item -LiteralPath '$target' -Force"
        Start-Process powershell.exe -ArgumentList "-NoProfile -NonInteractive -WindowStyle Hidden -Command $cmd"
        Write-Host "  Done. Exiting." -ForegroundColor DarkGray
        exit
    }
}

function Remove-SmtpConfig {
    <# Deletes the saved SMTP configuration. #>
    $path = Get-SmtpConfigPath
    if (Test-Path $path) {
        Remove-Item $path -Force
        Write-Host "  SMTP configuration removed." -ForegroundColor Green
    } else {
        Write-Host "  No SMTP configuration file found." -ForegroundColor Yellow
    }
}

# -----------------------------------------------------------------------------

function Invoke-All {
    <#
    .SYNOPSIS
        Runs the complete SysPulse diagnostic suite and packages everything
        into a single timestamped output folder.
    #>
    Write-Host "`n  +======================================================+" -ForegroundColor Cyan
    Write-Host   "  |   SysPulse  - Full Diagnostic Collection Starting ...  |" -ForegroundColor Cyan
    Write-Host   "  +======================================================+`n" -ForegroundColor Cyan

    $folder = New-OutputFolder

    $steps = @(
        { Invoke-QuickData    -OutFolder $folder },
        { Invoke-PowerBattery -OutFolder $folder },
        { Invoke-NetworkWAN   -OutFolder $folder },
        { Invoke-BootSecurity -OutFolder $folder },
        { Invoke-HWDDriver    -OutFolder $folder },
        { Invoke-WINEvtDump   -OutFolder $folder },
        { Invoke-WINPreload   -OutFolder $folder }
    )

    $total = $steps.Count
    for ($i = 0; $i -lt $total; $i++) {
        Write-Host ("  [{0}/{1}] " -f ($i+1), $total) -NoNewline -ForegroundColor Yellow
        & $steps[$i]
    }

    # Known Issues scan
    Write-Host "  Generating known-issues scan..."
    Invoke-KnownIssuesScan -OutFile (Join-Path $folder 'KnownIssues.log')

    # WER events
    Write-Host "  Collecting WER events..."
    Get-WEREvents -OutFile (Join-Path $folder 'WER_Events.log')

    # Idle analysis
    Write-Host "  Running idle analysis..."
    Invoke-IdleAnalysis -Days 30 -OutFile (Join-Path $folder 'IdleAnalysis.html')

    # Structured JSON + searchable HTML report
    Write-Host "  Building searchable HTML report..."
    Export-DiagnosticReport -OutFolder $folder | Out-Null

    Write-Host "`n  ========================================================" -ForegroundColor Cyan
    Write-Host   "  Collection complete.  Output folder:" -ForegroundColor Cyan
    Write-Host   "  $folder" -ForegroundColor White
    Write-Host   "  Open report.html in any browser to view results." -ForegroundColor Green
    Write-Host   "  ========================================================`n" -ForegroundColor Cyan

    # Auto-send if embedded SMTP credentials are present
    if ($Script:_SmtpServer -ne '') {
        Write-Host "  Embedded SMTP detected. Sending report automatically..." -ForegroundColor Cyan
        Send-DiagnosticReport -OutFolder $folder
    }

    return $folder
}

# -----------------------------------------------------------------------------
#  SECTION 19  - INTERACTIVE MENU
# -----------------------------------------------------------------------------

function Show-Menu {
    Write-Host ""
    Write-Host   "  -- Quick Info --------------------------------------"
    Write-Host   "   [1]  Processor family detection"
    Write-Host   "   [2]  BIOS / firmware info"
    Write-Host   "   [3]  Battery charge & health"
    Write-Host   "   [4]  CPU temperatures"
    Write-Host   "   [5]  Memory modules"
    Write-Host   "   [6]  Bluetooth devices"
    Write-Host   "   [7]  Device Manager status"
    Write-Host   "   [8]  Display scale & DSC"
    Write-Host   "   [9]  Installed apps (Teams / Office / Zoom)"
    Write-Host   "  [10]  Power button & lid close actions"
    Write-Host   "  [11]  Power slider"
    Write-Host   "  [12]  Active firewall"
    Write-Host   "  [30]  Disk health & SMART data"
    Write-Host   ""
    Write-Host   "  -- History & Health --------------------------------"
    Write-Host   "  [13]  Reboot history (last 30 days)"
    Write-Host   "  [14]  Unexpected shutdown count"
    Write-Host   "  [15]  Windows Error Reporting events"
    Write-Host   "  [16]  Driver dates"
    Write-Host   "  [17]  Known issues scan"
    Write-Host   "  [18]  Missing Windows updates"
    Write-Host   "  [19]  Kernel dumps"
    Write-Host   "  [20]  Minidump files"
    Write-Host   ""
    Write-Host   "  -- Data Collection ---------------------------------"
    Write-Host   "  [21]  Quick snapshot log"
    Write-Host   "  [22]  Power & battery reports"
    Write-Host   "  [23]  Network & wireless data"
    Write-Host   "  [24]  Boot & security data"
    Write-Host   "  [25]  Hardware & driver inventory"
    Write-Host   "  [26]  Event log dump + minidumps"
    Write-Host   "  [27]  Windows OS info"
    Write-Host   "  [28]  Idle usage analysis (HTML)"
    Write-Host   "  [29]  Export searchable report (data.json + report.html)"
    Write-Host   ""
    Write-Host   "  -- Email -------------------------------------------"
    if ($Script:_SmtpServer -ne '') {
        Write-Host   "  [E]   Send report by email"
    } else {
        Write-Host   "  [S]   Configure SMTP credentials (per-machine, DPAPI)"
        Write-Host   "  [E]   Send last report by email"
        Write-Host   "  [X]   Remove saved SMTP credentials (DPAPI file)"
        Write-Host   "  [P]   Package SMTP credentials into script (for client distribution)"
        Write-Host   "  [C]   Clear embedded SMTP credentials from script"
    }
    Write-Host   ""
    Write-Host   "  [A]   RUN FULL COLLECTION (all of the above)"
    Write-Host   "  [H]   Help / changelog"
    Write-Host   "  [Q]   Quit"
    Write-Host   ""
}

function Invoke-SysPulseMenu {
    Show-VersionBanner
    while ($true) {
        Show-Menu
        $choice = (Read-Host "  Select").Trim().ToUpper()
        switch ($choice) {
            '1'  { ProcDetect }
            '2'  { Show-BiosInfo }
            '3'  { Get-ChargePercent }
            '4'  { Get-Temperature }
            '5'  { Get-MemoryDetails }
            '6'  { Get-BluetoothInfo }
            '7'  { Show-DeviceManagerStatus }
            '8'  { Get-DisplayScale; Get-DSCStatus }
            '9'  { Get-TeamsVersion; Get-OfficeVersion; Get-ZoomVersion }
            '10' { Show-PowerButtonActions; Show-LidCloseActions; Show-CriticalBatteryActions }
            '11' { Show-PowerSlider }
            '12' { Get-ActiveFirewall }
            '30' { Get-DiskSmartData }
            '13' { Get-RebootHistory }
            '14' { Get-UnexpectedShutdownCount }
            '15' { Get-WEREvents }
            '16' { Get-DriverDates }
            '17' { Invoke-KnownIssuesScan }
            '18' { Get-MissingWindowsUpdates }
            '19' { Find-KernelDumps }
            '20' { Get-MiniDumps }
            '21' { Invoke-QuickData }
            '22' { Invoke-PowerBattery }
            '23' { Invoke-NetworkWAN }
            '24' { Invoke-BootSecurity }
            '25' { Invoke-HWDDriver }
            '26' { Invoke-WINEvtDump }
            '27' { Invoke-WINPreload }
            '28' { Invoke-IdleAnalysis }
            '29' { Export-DiagnosticReport }
            'S'  { Set-SmtpConfig }
            'E'  { Send-DiagnosticReport }
            'X'  { Remove-SmtpConfig }
            'P'  { Invoke-PackageSmtp }
            'C'  { Clear-EmbeddedSmtp }
            'A'  { Invoke-All }
            'H'  { SysPulseHelp }
            'Q'  { Write-Host "  Goodbye.`n"; return }
            default { Write-Host "  Invalid choice. Please try again." -ForegroundColor Red }
        }
        Write-Host "`n  Press Enter to return to menu..." -NoNewline
        Read-Host | Out-Null
    }
}

# -----------------------------------------------------------------------------
#  ENTRY POINT
#  Run the menu automatically when the script is executed directly.
#  When dot-sourced, all functions are available but the menu does not run.
# -----------------------------------------------------------------------------

if ($MyInvocation.InvocationName -ne '.') {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                   [Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "`n  Relaunching as Administrator..." -ForegroundColor Cyan
        $psArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        try {
            Start-Process powershell.exe -ArgumentList $psArgs -Verb RunAs
        } catch {
            # User cancelled the UAC prompt — fall through and run without elevation
            Write-Host "  UAC prompt cancelled. Running without administrator privileges." -ForegroundColor Yellow
            Write-Host "  Some diagnostics may be unavailable.`n" -ForegroundColor Yellow
            Invoke-SysPulseMenu
        }
        exit
    }

    Invoke-SysPulseMenu
}
