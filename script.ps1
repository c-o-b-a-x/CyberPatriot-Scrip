[CmdletBinding()]
param(
    [switch]$WhatIfMode,
    [string]$Action,
    [string]$UserName,
    [string]$GroupName,
    [string]$Password,
    [string[]]$AppNames
)

$ErrorActionPreference = 'Stop'
$DryRun = [bool]$WhatIfMode

function Initialize-ConsoleTheme {
    try {
        $rawUi = $Host.UI.RawUI
        $rawUi.BackgroundColor = 'Black'
        $rawUi.ForegroundColor = 'White'
        $rawUi.WindowTitle = 'Cyber Hardening Toolkit'
        Clear-Host
    }
    catch {
        Write-Host 'Console theme override not supported in this host; continuing normally.' -ForegroundColor Yellow
    }
}

function Show-AsciiLogo {
    $logo = @'
                                                                                             
                                 .####.                                                     
                                ##.  ##                                                     
                                ##  ##                                                       
                               ##    ##                                                      
                               #     ##                                                      
                              .#     #.                                                      
                              .#     .#.#####..####                                          
                              ##      ###         ##                                        
                               #.     ##          ###                                        
                               ##        ##         .##                                      
                               ##      .##  .##      ##                                      
                               ##        ##  ##      .##                                    
                              .#         ##.   #      ##                                   
                               ####        #####     ###                                    
                                  ##.              ###                                       
                                   ##             ###                                       
                           ..       ###      . ####    ########                             
                        ##.  .#####   #######     ###         ##                            
                     .###          ###          .##            ###                           
                     #.              ##        ##               ##.                          
                    ##      .####     ###    .##    #####.       #####                      
                  .##       .#  ##      ##  .##     ##   ##.        ##                      
                  .#      ##.  .#.       #.  ##      ..# .##        #                        
                   #.     .#..###       ##   ###      ##   ##.      .#                       
                   ##      ####        ###   ###         .##  .     #.                       
                    .##      #.       ##       ###           ##     .##                     
                      ######         ##          ##         ###     ###                     
                       ###           ###          #####..###..##    ##.                     
                    .###         .#####                       ##     .#                     
                  ##.         ####                            ##    .#.                     
              #####        .###                               ##.   ##                      
              ##         ####                                  ##  ##                       
               #######.#.                                     ##  ###                       
                                                               #####                        
                                                                                              
'@

    $logo = $logo -split "`r?`n"

    Write-Host ''
    foreach ($line in $logo) {
        Write-Host $line -ForegroundColor Magenta
    }

    Write-Host '=================================================================' -ForegroundColor DarkCyan
    Write-Host '  CYBER HARDENING TOOLKIT' -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host '  Local Security, User Management, and System Review Utility' -ForegroundColor Green
    Write-Host '=================================================================' -ForegroundColor DarkCyan
    Write-Host ''
}

function Get-CountAsInt {
    param(
        [AllowNull()]
        [object]$Value,
        [int]$Default = 0
    )

    if ($null -eq $Value) { return $Default }
    if ($Value -is [System.Array]) { return [int]@($Value).Count }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return $Default }
        try { return [int]$Value } catch { return $Default }
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        try { return [int]@($Value).Count } catch { return $Default }
    }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [short] -or $Value -is [byte]) {
        return [int]$Value
    }
    try { return [int]$Value } catch { return $Default }
}

function Get-CollectionCount {
    param(
        [AllowNull()]
        [object]$Value,
        [int]$Default = 0
    )

    return Get-CountAsInt -Value $Value -Default $Default
}



$logDir = Join-Path $env:TEMP 'CyberHardening'
$logPath = Join-Path $logDir 'CyberHardening.log'
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
Set-Content -Path $logPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Starting Cyber Hardening log.`r`n" -Encoding UTF8

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] [$Level] $Message"
    $color = 'Gray'

    switch ($Level) {
        'SUCCESS' { $color = 'Green' }
        'WARN' { $color = 'Yellow' }
        'ERROR' { $color = 'Red' }
    }

    Write-Host $entry -ForegroundColor $color
    Add-Content -Path $logPath -Value $entry -Encoding UTF8
}

function Parse-FormattedUserList {
    param([string]$Text)

    $result = @()
    $currentGroup = $null

    foreach ($line in ($Text -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        if ($trimmed -match '^(Authorized\s+Administrators\s*:\s*)$') {
            $currentGroup = 'Admin'
            continue
        }

        if ($trimmed -match '^(Authorized\s+Users\s*:\s*)$') {
            $currentGroup = 'User'
            continue
        }

        if ($trimmed -match '^(password|pass)\s*:\s*') {
            continue
        }

        $normalized = $trimmed
        if ($normalized -match '^(?<Name>[^()]+?)(?:\s*\([^)]*\))?$') {
            $normalized = $matches['Name'].Trim()
        }

        if (-not [string]::IsNullOrWhiteSpace($normalized)) {
            $result += [PSCustomObject]@{
                UserName = $normalized
                IsAdmin = ($currentGroup -eq 'Admin')
            }
        }
    }

    return $result
}

function Write-Section {
    param([string]$Name)
    Write-Log "`n=== $Name ===" -Level 'INFO'
    Write-Host "" 
    Write-Host ('=' * 80) -ForegroundColor DarkCyan
    Write-Host "  $Name" -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host ('=' * 80) -ForegroundColor DarkCyan
}

function Set-RegistryDword {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value
    )

    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force
}

function Set-RegistryString {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Value
    )

    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force
}

function Disable-ServiceSafely {
    param([string]$ServiceName)

    try {
        $svc = Get-Service -Name $ServiceName -ErrorAction Stop
        if ($svc.Status -ne 'Stopped') {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        }
        Set-Service -Name $ServiceName -StartupType Disabled
        Write-Host "Disabled service: $ServiceName" -ForegroundColor Green
    }
    catch {
        Write-Warning "Service '$ServiceName' not found or unavailable; skipping."
    }
}

function Disable-OptionalFeatureSafely {
    param([string]$FeatureName)

    try {
        if (Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop) {
            Disable-WindowsOptionalFeature -Online -FeatureName $FeatureName -NoRestart -ErrorAction Stop | Out-Null
            Write-Host "Disabled optional feature: $FeatureName" -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "Optional feature '$FeatureName' not found or cannot be disabled; skipping."
    }
}

function Ensure-PolicyValue {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value
    )

    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        $current = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
        if ($null -eq $current -or $current -ne $Value) {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force
        }
    }
    catch {
        Write-Warning "Could not set $Path\$Name to $Value"
    }
}

function Ensure-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log 'This operation requires administrator rights.' -Level 'ERROR'
        throw 'This script must be run as Administrator.'
    }
}

function New-CyberGroup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$Description = ''
    )

    Ensure-Administrator

    $existingGroup = Get-LocalGroup -Name $Name -ErrorAction SilentlyContinue
    if ($existingGroup) {
        Write-Log "Local group '$Name' already exists." -Level 'WARN'
        return $existingGroup
    }

    if ($DryRun) {
        Write-Log "Dry run: would create local group '$Name'." -Level 'INFO'
        return $null
    }

    $group = New-LocalGroup -Name $Name -Description $Description
    Write-Log "Created local group '$Name'." -Level 'SUCCESS'
    return $group
}

function New-CyberUser {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName,
        [string]$Password = '',
        [string]$FullName = '',
        [string]$Description = ''
    )

    Ensure-Administrator

    $existingUser = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    if ($existingUser) {
        Write-Log "Local user '$UserName' already exists." -Level 'WARN'
        return $existingUser
    }

    if ([string]::IsNullOrWhiteSpace($Password)) {
        $Password = Read-Host "Enter password for user '$UserName'"
    }

    if ($DryRun) {
        Write-Log "Dry run: would create local user '$UserName'." -Level 'INFO'
        return $null
    }

    $newUser = New-LocalUser -Name $UserName -Password (ConvertTo-SecureString -String $Password -AsPlainText -Force) -FullName $FullName -Description $Description
    Write-Log "Created local user '$UserName'." -Level 'SUCCESS'
    return $newUser
}

function Add-CyberUserToGroup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName,
        [Parameter(Mandatory = $true)]
        [string]$GroupName
    )

    Ensure-Administrator

    $user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    $group = Get-LocalGroup -Name $GroupName -ErrorAction SilentlyContinue

    if (-not $user) {
        throw "User '$UserName' does not exist."
    }

    if (-not $group) {
        $group = New-CyberGroup -Name $GroupName
    }

    $alreadyMember = Get-LocalGroupMember -Group $GroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "\\$UserName$|^$UserName$" }
    if ($alreadyMember) {
        Write-Log "User '$UserName' is already a member of group '$GroupName'." -Level 'WARN'
        return
    }

    if ($DryRun) {
        Write-Log "Dry run: would add user '$UserName' to group '$GroupName'." -Level 'INFO'
        return
    }

    Add-LocalGroupMember -Group $GroupName -Member $UserName -ErrorAction Stop
    Write-Log "Added user '$UserName' to group '$GroupName'." -Level 'SUCCESS'
}

function Remove-CyberUserFromGroup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName,
        [Parameter(Mandatory = $true)]
        [string]$GroupName
    )

    Ensure-Administrator

    $group = Get-LocalGroup -Name $GroupName -ErrorAction SilentlyContinue
    if (-not $group) {
        Write-Log "Group '$GroupName' does not exist." -Level 'WARN'
        return
    }

    $member = Get-LocalGroupMember -Group $GroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "\\$UserName$|^$UserName$" }
    if (-not $member) {
        Write-Log "User '$UserName' is not a member of '$GroupName'." -Level 'WARN'
        return
    }

    if ($DryRun) {
        Write-Log "Dry run: would remove user '$UserName' from group '$GroupName'." -Level 'INFO'
        return
    }

    Remove-LocalGroupMember -Group $GroupName -Member $UserName -ErrorAction Stop
    Write-Log "Removed user '$UserName' from group '$GroupName'." -Level 'SUCCESS'
}

function Show-CyberMenu {
    Write-Host ''
    Write-Host '=================================================================' -ForegroundColor DarkYellow
    Write-Host '                         CYBER TOOL MENU' -ForegroundColor Yellow
    Write-Host '=================================================================' -ForegroundColor DarkYellow
    Write-Host '1.  Create local group' -ForegroundColor Magenta
    Write-Host '2.  Create local user' -ForegroundColor Magenta
    Write-Host '3.  Add user to group' -ForegroundColor Magenta
    Write-Host '4.  Remove user from group' -ForegroundColor Magenta
    Write-Host '5.  List local users' -ForegroundColor Magenta
    Write-Host '6.  List local groups' -ForegroundColor Magenta
    Write-Host '7.  Run hardening checklist' -ForegroundColor Magenta
    Write-Host '8.  Uninstall application list' -ForegroundColor Magenta
    Write-Host '9.  Search file types' -ForegroundColor Magenta
    Write-Host '10. System audit & report' -ForegroundColor Magenta
    Write-Host '11. Exit' -ForegroundColor Red
    Write-Host '=================================================================' -ForegroundColor DarkYellow
}

function Get-InstalledApplications {
    $software = @()

    try {
        $software += Get-CimInstance Win32_Product -ErrorAction SilentlyContinue | Select-Object Name, Vendor, Version, InstallLocation
    }
    catch {
        Write-Log 'Could not enumerate Win32_Product entries; falling back to registry uninstall data.' -Level 'WARN'
    }

    $registryPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($path in $registryPaths) {
        if (-not (Test-Path $path)) { continue }

        $items = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            $props = Get-ItemProperty -Path $item.PSPath -ErrorAction SilentlyContinue
            if (-not $props) { continue }

            $displayName = $props.DisplayName
            if ([string]::IsNullOrWhiteSpace($displayName)) { continue }

            $software += [PSCustomObject]@{
                Name = $displayName
                Vendor = $props.Publisher
                Version = $props.DisplayVersion
                InstallLocation = $props.InstallLocation
            }
        }
    }

    return $software | Sort-Object Name -Unique
}

function Get-StartupItems {
    $items = @()

    $runLocations = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    )

    foreach ($path in $runLocations) {
        if (-not (Test-Path $path)) { continue }

        $props = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
        if (-not $props) { continue }

        foreach ($prop in $props.PSObject.Properties) {
            if ($prop.Name -match 'PSPath|PSParentPath|PSChildName|PSDrive|PSProvider') { continue }
            $items += [PSCustomObject]@{
                Source = $path
                Name = $prop.Name
                Value = $prop.Value
                Type = 'RegistryRunKey'
            }
        }
    }

    $startupFolder = [System.Environment]::GetFolderPath('CommonStartup')
    if ($startupFolder -and (Test-Path $startupFolder)) {
        Get-ChildItem -Path $startupFolder -File -ErrorAction SilentlyContinue | ForEach-Object {
            $items += [PSCustomObject]@{
                Source = $startupFolder
                Name = $_.Name
                Value = $_.FullName
                Type = 'StartupFolder'
            }
        }
    }

    try {
        Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
            $items += [PSCustomObject]@{
                Source = 'ScheduledTask'
                Name = $_.TaskName
                Value = $_.Actions.Execute
                Type = 'ScheduledTask'
            }
        }
    }
    catch {
        Write-Log 'Scheduled tasks are not available for inspection on this system.' -Level 'WARN'
    }

    return $items | Sort-Object Type, Name
}

function Get-SuspiciousFiles {
    param(
        [string]$RootPath = $env:USERPROFILE,
        [string[]]$Extensions = @('exe', 'dll', 'bat', 'cmd', 'ps1', 'vbs', 'js', 'jar', 'com', 'scr', 'hta')
    )

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        $RootPath = $env:USERPROFILE
    }

    $root = $RootPath.Trim()
    if (-not (Test-Path -LiteralPath $root)) {
        throw "Path '$root' does not exist."
    }

    $extList = @()
    foreach ($ext in $Extensions) {
        if (-not [string]::IsNullOrWhiteSpace($ext)) {
            $extList += $ext.Trim().TrimStart('.').ToLowerInvariant()
        }
    }

    $results = Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $ext = $_.Extension.TrimStart('.').ToLowerInvariant()
            $extList -contains $ext
        } |
        Select-Object FullName, Extension, Length, LastWriteTime

    return $results | Sort-Object FullName
}

function Export-ComplianceReport {
    param(
        [string]$OutputPath = (Join-Path $env:TEMP 'CyberHardening_Report.txt')
    )

    $apps = Get-InstalledApplications
    $startup = Get-StartupItems
    $suspicious = @()

    try {
        $suspicious = Get-SuspiciousFiles -RootPath $env:USERPROFILE
    }
    catch {
        Write-Log 'Could not generate suspicious file report for the user profile.' -Level 'WARN'
        $suspicious = @()
    }

    $report = @(
        'Cyber Hardening Compliance Report',
        "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        '',
        'Installed Applications:',
        ($apps | ForEach-Object { "- $($_.Name) [$($_.Version)] [$($_.Vendor)]" }) -join "`r`n",
        '',
        'Startup / AutoRun Items:',
        ($startup | ForEach-Object { "- $($_.Type): $($_.Name) -> $($_.Value)" }) -join "`r`n",
        '',
        'Suspicious Files:',
        ($suspicious | ForEach-Object { "- $($_.FullName) [$($_.Extension)]" }) -join "`r`n",
        '',
        'Summary:',
        "Installed software count: $((Get-CountAsInt $apps))",
        "Startup item count: $((Get-CountAsInt $startup))",
        "Suspicious file count: $((Get-CountAsInt $suspicious))"
    )

    $reportText = $report -join "`r`n"
    $reportText | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Log "Compliance report written to '$OutputPath'." -Level 'SUCCESS'
    return $OutputPath
}

function Invoke-AssessmentMenu {
    do {
        Write-Section 'System Audit'
        Write-Host '1. List installed software' -ForegroundColor Magenta
        Write-Host '2. List startup and autorun items' -ForegroundColor Magenta
        Write-Host '3. Scan suspicious files in user profile' -ForegroundColor Magenta
        Write-Host '4. Generate compliance report' -ForegroundColor Magenta
        Write-Host '5. Back to main menu' -ForegroundColor Magenta
        $auditChoice = Read-Host 'Select an audit option'

        switch ($auditChoice) {
            '1' {
                Write-Section 'Installed Software'
                $apps = Get-InstalledApplications
                if ((Get-CountAsInt $apps) -eq 0) {
                    Write-Host 'No installed software was found.' -ForegroundColor Yellow
                }
                else {
                    $apps | Select-Object Name, Vendor, Version, InstallLocation | Format-Table -AutoSize
                }
            }
            '2' {
                Write-Section 'Startup / Autorun Items'
                $startup = Get-StartupItems
                if ((Get-CountAsInt $startup) -eq 0) {
                    Write-Host 'No startup items were found.' -ForegroundColor Yellow
                }
                else {
                    $startup | Select-Object Type, Name, Value, Source | Format-Table -AutoSize
                }
            }
            '3' {
                $scanRoot = Read-Host 'Enter the folder to scan (default: user profile)'
                if ([string]::IsNullOrWhiteSpace($scanRoot)) { $scanRoot = $env:USERPROFILE }
                $suspicious = Get-SuspiciousFiles -RootPath $scanRoot
                if ((Get-CountAsInt $suspicious) -eq 0) {
                    Write-Host "No suspicious files found under '$scanRoot'." -ForegroundColor Yellow
                }
                else {
                    $suspicious | Select-Object FullName, Extension, Length, LastWriteTime | Format-Table -AutoSize
                }
            }
            '4' {
                $output = Read-Host 'Enter report output path (default: TEMP\CyberHardening_Report.txt)'
                if ([string]::IsNullOrWhiteSpace($output)) { $output = (Join-Path $env:TEMP 'CyberHardening_Report.txt') }
                Export-ComplianceReport -OutputPath $output
            }
            '5' {
                return
            }
            default {
                Write-Log 'Invalid audit option selected.' -Level 'WARN'
            }
        }

        Write-Host ''
    } while ($true)
}

function Search-FilesByType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,
        [Parameter(Mandatory = $true)]
        [string[]]$Extensions,
        [string]$CategoryName = 'Files'
    )

    $validatedRoot = $RootPath.Trim()
    if ([string]::IsNullOrWhiteSpace($validatedRoot)) {
        throw 'A valid root path is required.'
    }

    if (-not (Test-Path -LiteralPath $validatedRoot)) {
        throw "Path '$validatedRoot' does not exist."
    }

    $normalizedExts = @()
    foreach ($ext in $Extensions) {
        if ([string]::IsNullOrWhiteSpace($ext)) { continue }
        $normalizedExts += $ext.Trim().TrimStart('.').ToLowerInvariant()
    }

    $normalizedExts = $normalizedExts | Sort-Object -Unique
    if ((Get-CountAsInt $normalizedExts) -eq 0) {
        throw 'No file extensions were provided for the search.'
    }

    $items = Get-ChildItem -Path $validatedRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $ext = $_.Extension.TrimStart('.').ToLowerInvariant()
            $normalizedExts -contains $ext
        } |
        Sort-Object -Property FullName

    if ((Get-CountAsInt $items) -eq 0) {
        Write-Log "No $CategoryName files found under '$validatedRoot'." -Level 'WARN'
        return @()
    }

    Write-Section "$CategoryName file search"
    Write-Log "Searching '$validatedRoot' for $CategoryName files. Extensions: $($normalizedExts -join ', ')" -Level 'INFO'
    $items | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
    return $items
}

function Show-FileSearchMenu {
    Write-Section 'File Type Search'
    Write-Host '1. Media files (.mp3, .mp4, .jpg, .png, .avi, .mov, .wav)' -ForegroundColor Magenta
    Write-Host '2. Archive files (.zip, .rar, .7z, .tar, .gz, .iso)' -ForegroundColor Magenta
    Write-Host '3. Executables and installers (.exe, .msi, .dll, .bat, .cmd, .ps1)' -ForegroundColor Magenta
    Write-Host '4. Documents (.pdf, .doc, .docx, .xls, .xlsx, .ppt, .pptx, .txt)' -ForegroundColor Magenta
    Write-Host '5. Custom extension list' -ForegroundColor Magenta
    Write-Host '6. Back to main menu' -ForegroundColor Magenta
}

function Uninstall-ApplicationList {
    param(
        [string[]]$Applications
    )

    Ensure-Administrator

    $targets = @()
    if ((Get-CountAsInt $Applications) -gt 0) {
        $targets = @($Applications)
    }
    else {
        $rawInput = Read-Host 'Paste application names to uninstall, one per line. Press Enter on a blank line to finish.'
        $targets = @()
        while (-not [string]::IsNullOrWhiteSpace($rawInput)) {
            $targets += $rawInput.Trim()
            $rawInput = Read-Host 'Add another app name or press Enter to finish'
        }
    }

    $targets = @($targets | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ((Get-CountAsInt $targets) -eq 0) {
        Write-Log 'No application names were provided for uninstall.' -Level 'WARN'
        return
    }

    Write-Section 'Application Uninstall'
    foreach ($target in $targets) {
        $name = $target.Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        Write-Log "Checking for application: $name" -Level 'INFO'
        $uninstallMatches = @()

        $uninstallMatches += Get-CimInstance Win32_Product -ErrorAction SilentlyContinue | Where-Object { $_.Name -and $_.Name -match [regex]::Escape($name) }
        $uninstallMatches += Get-ChildItem 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
            Get-ItemProperty |
            Where-Object { $_.DisplayName -and $_.DisplayName -match [regex]::Escape($name) }

        $uniqueMatches = $uninstallMatches | Sort-Object -Property Name, DisplayName -Unique

        if (-not $uniqueMatches -or $uniqueMatches.Count -eq 0) {
            Write-Log "No matching application found for '$name'." -Level 'WARN'
            continue
        }

        foreach ($match in $uniqueMatches) {
            $displayName = if ($match.DisplayName) { $match.DisplayName } elseif ($match.Name) { $match.Name } else { $name }
            if ($DryRun) {
                Write-Log "Dry run: would uninstall '$displayName'." -Level 'INFO'
                continue
            }

            try {
                if ($match -is [Microsoft.Management.Infrastructure.CimInstance]) {
                    $match | Invoke-CimMethod -MethodName Uninstall | Out-Null
                }
                else {
                    $uninstallString = $match.UninstallString
                    if (-not $uninstallString) {
                        throw "No uninstall string found for '$displayName'."
                    }
                    Start-Process -FilePath $uninstallString -ArgumentList '/quiet' -Wait -NoNewWindow -ErrorAction Stop
                }

                Write-Log "Uninstalled application '$displayName'." -Level 'SUCCESS'
            }
            catch {
                Write-Log "Failed to uninstall '$displayName'. Review manually. Error: $($_.Exception.Message)" -Level 'ERROR'
            }
        }
    }
}

function Invoke-CyberToolMenu {
    Initialize-ConsoleTheme
    Clear-Host
    Show-AsciiLogo
    Write-Host ' Select the task you want to run.' -ForegroundColor Gray
    Write-Host ''
    do {
        Show-CyberMenu
        $choice = Read-Host 'Select an option'

        switch ($choice) {
            '1' {
                $groupName = Read-Host 'Enter group name'
                $description = Read-Host 'Enter group description (optional)'
                New-CyberGroup -Name $groupName -Description $description
            }
            '2' {
                $userName = Read-Host 'Enter username'
                $password = Read-Host 'Enter password'
                $fullName = Read-Host 'Enter full name (optional)'
                $description = Read-Host 'Enter description (optional)'
                New-CyberUser -UserName $userName -Password $password -FullName $fullName -Description $description
            }
            '3' {
                $userName = Read-Host 'Enter username to add'
                $groupName = Read-Host 'Enter group name'
                Add-CyberUserToGroup -UserName $userName -GroupName $groupName
            }
            '4' {
                $userName = Read-Host 'Enter username to remove'
                $groupName = Read-Host 'Enter group name'
                Remove-CyberUserFromGroup -UserName $userName -GroupName $GroupName
            }
            '5' {
                Get-LocalUser | Select-Object Name, Enabled, PrincipalSource | Format-Table -AutoSize
            }
            '6' {
                Get-LocalGroup | Select-Object Name, Description | Format-Table -AutoSize
            }
            '7' {
                Invoke-CyberHardening
            }
            '8' {
                Uninstall-ApplicationList
            }
            '9' {
                do {
                    Show-FileSearchMenu
                    $fileChoice = Read-Host 'Select a file type search'

                    switch ($fileChoice) {
                        '1' {
                            $root = Read-Host 'Enter the folder path to search for media files'
                            $exts = @('mp3', 'mp4', 'm4a', 'aac', 'wav', 'flac', 'avi', 'mov', 'wmv', 'mkv', 'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp')
                            Search-FilesByType -RootPath $root -Extensions $exts -CategoryName 'Media'
                        }
                        '2' {
                            $root = Read-Host 'Enter the folder path to search for archive files'
                            $exts = @('zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz', 'iso')
                            Search-FilesByType -RootPath $root -Extensions $exts -CategoryName 'Archive'
                        }
                        '3' {
                            $root = Read-Host 'Enter the folder path to search for executables and installers'
                            $exts = @('exe', 'msi', 'dll', 'bat', 'cmd', 'ps1', 'com', 'scr', 'appx', 'msix')
                            Search-FilesByType -RootPath $root -Extensions $exts -CategoryName 'Executable'
                        }
                        '4' {
                            $root = Read-Host 'Enter the folder path to search for documents'
                            $exts = @('pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'rtf')
                            Search-FilesByType -RootPath $root -Extensions $exts -CategoryName 'Document'
                        }
                        '5' {
                            $root = Read-Host 'Enter the folder path to search for custom types'
                            $customInput = Read-Host 'Enter extensions separated by commas (example: exe,zip,pdf,mp4)'
                            $exts = @()
                            if (-not [string]::IsNullOrWhiteSpace($customInput)) {
                                $exts = $customInput.Split(',') | ForEach-Object { $_.Trim() }
                            }
                            Search-FilesByType -RootPath $root -Extensions $exts -CategoryName 'Custom'
                        }
                        '6' {
                            break
                        }
                        default {
                            Write-Log 'Invalid file search option selected.' -Level 'WARN'
                        }
                    }

                    Write-Host ''
                } while ($fileChoice -ne '6')
            }
            '10' {
                Invoke-AssessmentMenu
            }
            '11' {
                Write-Log 'Exiting Cyber tool.' -Level 'INFO'
                return
            }
            default {
                Write-Log 'Invalid option selected.' -Level 'WARN'
            }
        }

        Write-Host ''
    } while ($true)
}

function Invoke-CyberHardening {

Write-Section 'Privilege Check'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log 'Script is not running with administrator rights.' -Level 'ERROR'
    throw 'This script must be run as Administrator.'
}

Write-Log 'Administrator context confirmed.' -Level 'SUCCESS'

Write-Section 'Authorized User Setup'
$authorizedUsers = @()
$formattedText = Read-Host 'Paste the full formatted list, including "Authorized Administrators:" and "Authorized Users:" headings'
$parsedUsers = Parse-FormattedUserList -Text $formattedText
foreach ($entry in $parsedUsers) {
    $authorizedUsers += [PSCustomObject]@{
        UserName = $entry.UserName
        IsAdmin = $entry.IsAdmin
    }
    $groupLabel = if ($entry.IsAdmin) { 'Administrator' } else { 'Standard User' }
    Write-Log "Recorded user: $($entry.UserName) -> $groupLabel" -Level 'SUCCESS'
}

Write-Host ''
Write-Host 'Authorized Administrators:' -ForegroundColor Magenta
foreach ($adminUser in ($parsedUsers | Where-Object { $_.IsAdmin } | Select-Object -ExpandProperty UserName)) {
    Write-Host "  - $adminUser" -ForegroundColor Green
}

Write-Host 'Authorized Users:' -ForegroundColor Magenta
foreach ($standardUser in ($parsedUsers | Where-Object { -not $_.IsAdmin } | Select-Object -ExpandProperty UserName)) {
    Write-Host "  - $standardUser" -ForegroundColor Yellow
}

if ((Get-CountAsInt $authorizedUsers) -eq 0) {
    Write-Log 'No approved users were entered. The script will continue with base hardening only.' -Level 'WARN'
}
else {
    $approvedNames = ($authorizedUsers | ForEach-Object { $_.UserName }) -join ', '
    Write-Log "Approved user list: $approvedNames" -Level 'INFO'
}

$keptUnapprovedUsers = @()
$disabledUnapprovedUsers = @()
$builtInExcludedUsers = @('Administrator', 'Guest', 'DefaultAccount', 'WDAGUtilityAccount')
$allLocalUsers = Get-LocalUser | Where-Object { $_.Name -notin $builtInExcludedUsers }
$approvedSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $authorizedUsers) {
    $null = $approvedSet.Add($entry.UserName)
}

Write-Log 'Scanning local users against the approved list.' -Level 'INFO'
foreach ($localUser in $allLocalUsers) {
    if ($approvedSet.Contains($localUser.Name)) {
        continue
    }

    Write-Log "Found unapproved local user: $($localUser.Name)" -Level 'WARN'
    $removeChoice = Read-Host "User '$($localUser.Name)' is not in the approved list. Remove/disable this account? [Y/N]"
    if ($removeChoice -match '^(Y|YES|Yes)$') {
        if ($DryRun) {
            Write-Log "Dry run: would disable account '$($localUser.Name)'" -Level 'INFO'
            $keptUnapprovedUsers += $localUser.Name
            continue
        }

        try {
            Disable-LocalUser -Name $localUser.Name -ErrorAction Stop
            Write-Log "Disabled unapproved local user: $($localUser.Name)" -Level 'SUCCESS'
            $disabledUnapprovedUsers += $localUser.Name
        }
        catch {
            Write-Log "Could not disable '$($localUser.Name)'. Review manually. Error: $($_.Exception.Message)" -Level 'ERROR'
            $keptUnapprovedUsers += $localUser.Name
        }
    }
    else {
        Write-Log "Kept unapproved account '$($localUser.Name)' because operator chose not to remove it." -Level 'WARN'
        $keptUnapprovedUsers += $localUser.Name
    }
}

Write-Section 'Summary'
$adminUsers = ($authorizedUsers | Where-Object { $_.IsAdmin } | Select-Object -ExpandProperty UserName)
$standardUsers = ($authorizedUsers | Where-Object { -not $_.IsAdmin } | Select-Object -ExpandProperty UserName)
Write-Host 'Approved Admins:' -ForegroundColor Magenta
if ((Get-CountAsInt $adminUsers) -gt 0) {
    foreach ($user in $adminUsers) { Write-Host "  - $user" -ForegroundColor Green }
}
else {
    Write-Host '  - None' -ForegroundColor Yellow
}

Write-Host 'Approved Standard Users:' -ForegroundColor Magenta
if ((Get-CountAsInt $standardUsers) -gt 0) {
    foreach ($user in $standardUsers) { Write-Host "  - $user" -ForegroundColor Yellow }
}
else {
    Write-Host '  - None' -ForegroundColor Yellow
}

Write-Host 'Kept Unapproved Users:' -ForegroundColor Magenta
if ((Get-CountAsInt $keptUnapprovedUsers) -gt 0) {
    foreach ($user in $keptUnapprovedUsers) { Write-Host "  - $user" -ForegroundColor Yellow }
}
else {
    Write-Host '  - None' -ForegroundColor Yellow
}

Write-Host 'Disabled Unapproved Users:' -ForegroundColor Magenta
if ((Get-CountAsInt $disabledUnapprovedUsers) -gt 0) {
    foreach ($user in $disabledUnapprovedUsers) { Write-Host "  - $user" -ForegroundColor Green }
}
else {
    Write-Host '  - None' -ForegroundColor Yellow
}

Write-Section 'Baseline: Password and Lockout Policies'
# Password policy
net accounts /minpwlen:12 | Out-Null
net accounts /maxpwage:60 | Out-Null
net accounts /minpwage:1 | Out-Null
net accounts /uniquepw:24 | Out-Null

# Lockout policy
net accounts /lockoutthreshold:10 | Out-Null
net accounts /lockoutduration:30 | Out-Null
net accounts /lockoutwindow:30 | Out-Null

# NOTE: Some local policy values are not directly configurable with net accounts.
# The script also creates a security template below to apply the remaining standard settings.

Write-Section 'Local Security Policy: Security Template'
$tempDir = Join-Path $env:TEMP 'CyberHardening'
if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}

$infPath = Join-Path $tempDir 'CyberHardening.inf'
@"
[Unicode]
Unicode=yes

[Version]
signature="$CHICAGO$"
Revision=1

[System Access]
MinimumPasswordAge = 1
MaximumPasswordAge = 60
MinimumPasswordLength = 10
PasswordComplexity = 1
PasswordHistorySize = 24
ClearTextPassword = 0
LockoutBadCount = 10
ResetLockoutCount = 30
LockoutDuration = 1800

[Event Audit]
AuditSystemEvents = 0
AuditLogonEvents = 3
AuditObjectAccess = 0
AuditPrivilegeUse = 0
AuditPolicyChange = 3
AuditAccountManage = 3
AuditProcessTracking = 0
AuditDSAccess = 0
AuditAccountLogon = 3

[Privilege Rights]
SeNetworkLogonRight = *S-1-5-32-544,*S-1-5-32-545,*S-1-5-32-551
SeBatchLogonRight = *S-1-5-32-544
SeServiceLogonRight = 
"@ | Set-Content -Path $infPath -Encoding Unicode

# Apply the template
secedit /configure /db $env:windir\security\database\securepc.sdb /cfg $infPath /areas SECURITYPOLICY /quiet

Write-Host 'Applied security policy template.' -ForegroundColor Green

Write-Section 'Audit Policy'
auditpol /set /category:* /success:enable /failure:enable | Out-Null
Write-Host 'Enabled Success and Failure auditing across standard categories.' -ForegroundColor Green

Write-Section 'Account Hardening'
foreach ($user in $authorizedUsers) {
    $localUser = Get-LocalUser -Name $user.UserName -ErrorAction SilentlyContinue
    if (-not $localUser) {
        Write-Log "User '$($user.UserName)' was not found on this machine. Skipping local group assignment." -Level 'WARN'
        continue
    }

    $adminGroup = 'Administrators'
    $userGroup = 'Users'

    $isAdminMember = (Get-LocalGroupMember -Group $adminGroup -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "\\$($user.UserName)$|^$($user.UserName)$" }).Count -gt 0

    if ($user.IsAdmin) {
        if (-not $isAdminMember) {
            if ($DryRun) {
                Write-Log "Dry run: would add '$($user.UserName)' to Administrators." -Level 'INFO'
            }
            else {
                Add-LocalGroupMember -Group $adminGroup -Member $user.UserName -ErrorAction Stop
                Write-Log "Added '$($user.UserName)' to Administrators." -Level 'SUCCESS'
            }
        }
        else {
            Write-Log "'$($user.UserName)' is already in Administrators." -Level 'INFO'
        }
    }
    else {
        if ($isAdminMember) {
            if ($DryRun) {
                Write-Log "Dry run: would remove '$($user.UserName)' from Administrators." -Level 'INFO'
            }
            else {
                Remove-LocalGroupMember -Group $adminGroup -Member $user.UserName -ErrorAction SilentlyContinue
                Write-Log "Removed '$($user.UserName)' from Administrators." -Level 'SUCCESS'
            }
        }

        $isUserMember = (Get-LocalGroupMember -Group $userGroup -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "\\$($user.UserName)$|^$($user.UserName)$" }).Count -gt 0
        if (-not $isUserMember) {
            if ($DryRun) {
                Write-Log "Dry run: would add '$($user.UserName)' to Users." -Level 'INFO'
            }
            else {
                Add-LocalGroupMember -Group $userGroup -Member $user.UserName -ErrorAction SilentlyContinue
                Write-Log "Added '$($user.UserName)' to Users." -Level 'SUCCESS'
            }
        }
    }
}

# Administrator account status and Guest account status are often best handled manually.
# These are included here as a fast path, but review them before production use.
$tempAdminName = (Get-CimInstance Win32_UserAccount -Filter "LocalAccount='True' AND SID LIKE 'S-1-5-21-%-500'" | Select-Object -First 1).Name
if ($tempAdminName) {
    try {
        if ($DryRun) {
            Write-Log "Dry run: would disable local Administrator account: $tempAdminName" -Level 'INFO'
        }
        else {
            net user $tempAdminName /active:no | Out-Null
            Write-Log "Disabled local Administrator account: $tempAdminName" -Level 'SUCCESS'
        }
    }
    catch {
        Write-Log 'Could not disable local Administrator account. Review manually.' -Level 'ERROR'
    }
}

$guest = Get-CimInstance Win32_UserAccount -Filter "LocalAccount='True' AND Name='Guest'" | Select-Object -First 1
if ($guest) {
    try {
        if ($DryRun) {
            Write-Log 'Dry run: would disable Guest account.' -Level 'INFO'
        }
        else {
            net user Guest /active:no | Out-Null
            Write-Log 'Disabled Guest account.' -Level 'SUCCESS'
        }
    }
    catch {
        Write-Log 'Could not disable Guest account. Review manually.' -Level 'ERROR'
    }
}

Write-Section 'User Account Control and Security Options'
$uacKeys = @(
    @{Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name='EnableLUA'; Value=1},
    @{Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name='ConsentPromptBehaviorAdmin'; Value=5},
    @{Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name='ConsentPromptBehaviorUser'; Value=3},
    @{Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name='PromptOnSecureDesktop'; Value=1},
    @{Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name='EnableInstallerDetection'; Value=1},
    @{Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name='ValidateAdminCodeSignatures'; Value=0},
    @{Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name='EnableVirtualization'; Value=1},
    @{Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name='EnableSecureUIAPaths'; Value=1}
)
foreach ($entry in $uacKeys) {
    Set-RegistryDword -Path $entry.Path -Name $entry.Name -Value $entry.Value
}

# Disable AutoPlay
Set-RegistryDword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers' -Name 'DisableAutoplay' -Value 1

# Disable password reveal / show last user name
Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'DontDisplayLastUserName' -Value 1

# Disable system shutdown without logon
Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'ShutdownWithoutLogon' -Value 0

# Disable automatic administrative logon
Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'DisableAutomaticAdminLogon' -Value 1

# Disable one-click network discovery hints and place controls into standard security posture
Set-RegistryDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'NoDataCollection' -Value 1

Write-Section 'Windows Defender'
try {
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
    Set-MpPreference -ScanAvgCPULoadFactor 5 -ErrorAction Stop
    Set-MpPreference -PUAProtection 1 -ErrorAction Stop
    Write-Host 'Windows Defender settings applied.' -ForegroundColor Green
}
catch {
    Write-Warning 'Windows Defender could not be configured via WMI; review manually.'
}

Write-Section 'Services'
$servicesToDisable = @(
    'upnphost',
    'Telnet',
    'SNMPTRAP',
    'RemoteRegistry',
    'W32Time',
    'Fax'
)
foreach ($svc in $servicesToDisable) {
    Disable-ServiceSafely -ServiceName $svc
}

# Keep Event Collector enabled and Automatic if available
try {
    $svc = Get-Service -Name 'Wecsvc' -ErrorAction Stop
    if ($svc.StartType -ne 'Automatic') {
        Set-Service -Name 'Wecsvc' -StartupType Automatic
    }
    if ($svc.Status -ne 'Running') {
        Start-Service -Name 'Wecsvc' -ErrorAction SilentlyContinue
    }
    Write-Host 'Ensured Windows Event Collector is enabled.' -ForegroundColor Green
}
catch {
    Write-Warning 'Wecsvc not found; review manual service requirements.'
}

Write-Section 'Windows Features'
$featuresToDisable = @(
    'TelnetClient',
    'TelnetServer',
    'SNMP',
    'RIPListener',
    'ClientForNFS',
    'IIS-WebServerRole',
    'IIS-WebServer',
    'MSMQ-Server',
    'WCF-Services45'
)

foreach ($feature in $featuresToDisable) {
    Disable-OptionalFeatureSafely -FeatureName $feature
}

try {
    Disable-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -NoRestart -ErrorAction Stop | Out-Null
    Write-Host 'Disabled SMB1.' -ForegroundColor Green
}
catch {
    Write-Warning 'SMB1 feature not available or already disabled.'
}

Write-Section 'Network Hardening'
# Disable IPv6 on all adapters while leaving IPv4 enabled
Get-NetAdapter | ForEach-Object {
    try {
        Disable-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6 -ErrorAction Stop
        Write-Host "Disabled IPv6 binding on adapter: $($_.Name)" -ForegroundColor Green
    }
    catch {
        Write-Warning "Could not disable IPv6 on adapter $($_.Name)"
    }
}

# Disable NetBIOS and enable DNS registration controls on network interfaces
Get-DnsClient | ForEach-Object {
    try {
        Set-DnsClient -InterfaceIndex $_.InterfaceIndex -RegisterThisConnectionsAddress $false -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not update DNS client registration on interface $($_.InterfaceIndex)"
    }
}

# Disable UPnP out of the registry if present
$upnpPath = 'HKLM:\Software\Microsoft\DirectplayNATHelp\DPNHUPnP'
if (-not (Test-Path $upnpPath)) {
    New-Item -Path $upnpPath -Force | Out-Null
}
Set-RegistryDword -Path $upnpPath -Name 'UPnPMode' -Value 2

# Disable Wi-Fi Sense related settings if present
$wifiSenseRoot = 'HKLM:\Software\Microsoft\WlanSvc\Features'
if (Test-Path $wifiSenseRoot) {
    Set-RegistryDword -Path $wifiSenseRoot -Name 'AutoConnectAllowed' -Value 0
}

# Block MS Edge / Search / known app traffic on the firewall (best effort)
$firewallRules = @(
    'Microsoft Edge',
    'Search',
    'MSN Money',
    'MSN Sports',
    'MSN News',
    'MSN Weather',
    'Microsoft Photos',
    'Xbox'
)
foreach ($rule in $firewallRules) {
    try {
        Get-NetFirewallRule -DisplayName $rule -ErrorAction Stop | Disable-NetFirewallRule
        Write-Host "Disabled firewall rule: $rule" -ForegroundColor Green
    }
    catch {
        Write-Warning "Firewall rule '$rule' not found; skipping."
    }
}

# Disable LAN Manager and SMB signing not always accessible, but keep the config in place.
Set-RegistryDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0' -Name 'NtlmMinClientSec' -Value 537395200
Set-RegistryDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0' -Name 'NtlmMinServerSec' -Value 537395200

Write-Section 'File Shares / Network Access'
# Best effort: remove unauthorized shares. This does not touch ADMIN$, C$, or IPC$ by default.
$defaultShares = @('ADMIN$', 'C$', 'IPC$')
$shares = Get-SmbShare | Where-Object { $_.Name -notin $defaultShares }
foreach ($share in $shares) {
    try {
        Remove-SmbShare -Name $share.Name -Force
        Write-Host "Removed unauthorized share: $($share.Name)" -ForegroundColor Green
    }
    catch {
        Write-Warning "Could not remove share $($share.Name)"
    }
}

Write-Section 'Browser / Adobe / Java Cleanup'
# This is a manual review item because browser/toolbar preferences vary by environment.
Write-Host 'Review browsers and third-party toolbars manually. Update Flash/Reader/Java plugins and remove unauthorized toolbars.' -ForegroundColor Yellow

Write-Section 'Startup / Login Hardening'
# Disable OneDrive startup
$oneDrive = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if (Test-Path $oneDrive) {
    Remove-ItemProperty -Path $oneDrive -Name 'OneDrive' -ErrorAction SilentlyContinue
}

# Disable screen saver lock after 10 minutes and require logon screen on resume
Set-RegistryDword -Path 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaveTimeOut' -Value 600
Set-RegistryString -Path 'HKCU:\Control Panel\Desktop' -Name 'SCRNSAVE.EXE' -Value 'logon.scr'
Set-RegistryDword -Path 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaverIsSecure' -Value 1
Set-RegistryDword -Path 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaveActive' -Value 1
Set-RegistryString -Path 'HKCU:\Control Panel\Desktop' -Name 'UserPreferencesMask' -Value '90 12 0 0 0 0 0 0'

# Confirm autologin is disabled
Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoAdminLogon' -Value 0
Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'ForceAutoLogon' -Value 0
Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoLogonCount' -Value 0

# Hide user switching and disable Fast User Switching
Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'HideFastUserSwitching' -Value 1

Write-Section 'Firewall / Defender / PowerShell Hardening'
# Enable UAC and PowerShell logging best effort
Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA' -Value 1
Set-RegistryDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -Name 'EnableScriptBlockLogging' -Value 1

Write-Section 'Task Scheduler / Cleanup'
# Remove common unauthorized scheduled tasks is not broadly safe; review manually.
Write-Host 'Review scheduled tasks and startup items manually for unauthorized entries.' -ForegroundColor Yellow

Write-Section 'Manual Review Items'
$manualItems = @(
    'Verify the README and authorized user list before changing domain or local admin memberships.',
    'Review all unauthorized users, disabled accounts, and admin group membership.',
    'Validate RDP group membership against the README.',
    'Inspect all Windows Services not covered above and confirm they match the required baseline.',
    'Check Windows Features and any IIS or FTP settings against the README.',
    'Review browser plugins, toolbars, and Java/Flash versions in each browser.',
    'Verify Wi-Fi Sense and network adapter settings on every device profile.',
    'Check interface-specific firewall inbound rules and any startup app exceptions.',
    'Confirm the systems share count matches README requirements and remove any unauthorized shares.',
    'Validate screen lock / screen saver policy applies to all users.',
    'Review registry and GPO exceptions that could impact local policy enforcement.'
)
for ($i = 0; $i -lt $manualItems.Count; $i++) {
    Write-Host ($i + 1).ToString() + '. ' + $manualItems[$i] -ForegroundColor Yellow
}

Write-Host "`nHardening script completed. Review the manual items above before final sign-off." -ForegroundColor Green
}

if ($Action) {
    switch ($Action.ToLowerInvariant()) {
        'create-group' {
            if (-not $GroupName) { throw 'GroupName is required when Action is create-group.' }
            New-CyberGroup -Name $GroupName
        }
        'create-user' {
            if (-not $UserName) { throw 'UserName is required when Action is create-user.' }
            New-CyberUser -UserName $UserName -Password $Password
        }
        'add-to-group' {
            if (-not $UserName -or -not $GroupName) { throw 'UserName and GroupName are required when Action is add-to-group.' }
            Add-CyberUserToGroup -UserName $UserName -GroupName $GroupName
        }
        'remove-from-group' {
            if (-not $UserName -or -not $GroupName) { throw 'UserName and GroupName are required when Action is remove-from-group.' }
            Remove-CyberUserFromGroup -UserName $UserName -GroupName $GroupName
        }
        'harden' {
            Invoke-CyberHardening
        }
        'uninstall-apps' {
            Uninstall-ApplicationList -Applications $AppNames
        }
        default {
            throw "Unknown action '$Action'. Valid actions: create-group, create-user, add-to-group, remove-from-group, harden, uninstall-apps."
        }
    }
    exit 0
}

Invoke-CyberToolMenu

