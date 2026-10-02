[CmdletBinding()]
param(
    [switch]$WhatIfMode,
    [string]$Action,
    [string]$UserName,
    [string]$GroupName,
    [string]$Password
)

$ErrorActionPreference = 'Stop'
$DryRun = [bool]$WhatIfMode

function Initialize-ConsoleTheme {
    try {
        $rawUi = $Host.UI.RawUI
        $rawUi.BackgroundColor = 'Black'
        $rawUi.WindowTitle = 'ECTS WIN 11 Terminal'
        Clear-Host
    }
    catch {
        Write-Host 'theme skipped' -ForegroundColor Red
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

    foreach ($line in ($logo -split "`r?`n")) {
        Write-Host $line -ForegroundColor Magenta
    }


    Write-Host '=================================================================================' -ForegroundColor Magenta
    Write-Host ''
}

function Get-CountAsInt {
    param(
        [AllowNull()]
        [object]$Value,
        [int]$Default = 0
    )

    if ($null -eq $Value) { return $Default }
    return [int]@($Value).Count
}

function Write-Log {
    param([string]$Message)

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] [ERROR] $Message"

    Write-Host $entry -ForegroundColor Red
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
                IsAdmin  = ($currentGroup -eq 'Admin')
            }
        }
    }

    return $result
}

function Set-RegistryDword {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value
    )

    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force
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
        New-Item -Path $Path -Force
    }

    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force
}

function Get-DefaultScanRoot {
    $root = $env:SystemDrive
    if ([string]::IsNullOrWhiteSpace($root)) { $root = $env:USERPROFILE }
    if ([string]::IsNullOrWhiteSpace($root)) { $root = 'C:\' }

    if (-not (Test-Path -LiteralPath $root)) {
        $fallback = $env:USERPROFILE
        if (-not [string]::IsNullOrWhiteSpace($fallback) -and (Test-Path -LiteralPath $fallback)) {
            return $fallback
        }
        return 'C:\'
    }

    return $root
}

function Enable-WindowsSecurityBaseline {
    $firewallProfiles = @('Domain', 'Public', 'Private')
    foreach ($profile in $firewallProfiles) {
        try {
            Get-NetFirewallProfile -Name $profile -ErrorAction Stop
            Set-NetFirewallProfile -Name $profile -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Allow -NotifyOnListen True -LogFileName "$env:SystemRoot\System32\LogFiles\Firewall\pfirewall.log" -LogMaxSizeKilobytes 4096 -LogBlocked True -LogAllowed False -ErrorAction Stop
        }
        catch {
            Write-Log "firewall profile '$profile' failed: $($_.Exception.Message)"
        }
    }

    foreach ($serviceName in @('MpsSvc', 'WinDefend', 'wscsvc')) {
        try {
            $svc = Get-Service -Name $serviceName -ErrorAction Stop
            if ($svc.StartType -ne 'Automatic') {
                Set-Service -Name $serviceName -StartupType Automatic -ErrorAction Stop
            }
            if ($svc.Status -ne 'Running') {
                Start-Service -Name $serviceName -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Log "service '$serviceName' failed: $($_.Exception.Message)"
        }
    }

    $securityRegistry = @(
        @{Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableRealtimeMonitoring'; Value = 0 },
        @{Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableBehaviorMonitoring'; Value = 0 },
        @{Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableOnAccessProtection'; Value = 0 },
        @{Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableScanOnRealtimeEnable'; Value = 0 },
        @{Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'EnableLUA'; Value = 1 },
        @{Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'ConsentPromptBehaviorAdmin'; Value = 5 },
        @{Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'PromptOnSecureDesktop'; Value = 1 },
        @{Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'; Name = 'EnableScriptBlockLogging'; Value = 1 }
    )

    foreach ($entry in $securityRegistry) {
        try {
            Set-RegistryDword -Path $entry.Path -Name $entry.Name -Value $entry.Value
        }
        catch {
            Write-Log "setting failed: $($entry.Path)\$($entry.Name): $($_.Exception.Message)"
        }
    }

    try {
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
        Set-MpPreference -PUAProtection 1 -ErrorAction Stop
        Set-MpPreference -ScanAvgCPULoadFactor 5 -ErrorAction Stop
        Set-MpPreference -MAPSReporting 1 -ErrorAction Stop
    }
    catch {
        Write-Log 'Defender settings failed'
    }
}

function Disable-ServiceSafely {
    param([string]$ServiceName)

    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) { return }

    try {
        if ($svc.Status -ne 'Stopped') {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        }
        Set-Service -Name $ServiceName -StartupType Disabled
        Write-Host "Disabled service: $ServiceName"
    }
    catch {
        Write-Log "service '$ServiceName' unavailable: $($_.Exception.Message)"
    }
}

function Disable-OptionalFeatureSafely {
    param([string]$FeatureName)

    try {
        if (Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop) {
            Disable-WindowsOptionalFeature -Online -FeatureName $FeatureName -NoRestart -ErrorAction Stop
        }
    }
    catch {
        Write-Log "feature '$FeatureName' failed"
    }
}

function Ensure-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log 'admin rights required'
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
        return $existingGroup
    }

    if ($DryRun) {
        return $null
    }

    $group = New-LocalGroup -Name $Name -Description $Description
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
        return $existingUser
    }

    if ([string]::IsNullOrWhiteSpace($Password)) {
        $Password = Read-Host "Enter password for user '$UserName'"
    }

    if ($DryRun) {
        return $null
    }

    $newUser = New-LocalUser -Name $UserName -Password (ConvertTo-SecureString -String $Password -AsPlainText -Force) -FullName $FullName -Description $Description
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
        New-CyberGroup -Name $GroupName
    }

    $alreadyMember = Get-LocalGroupMember -Group $GroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "\\$UserName$|^$UserName$" }
    if ($alreadyMember) {
        return
    }

    if ($DryRun) {
        return
    }

    Add-LocalGroupMember -Group $GroupName -Member $UserName -ErrorAction Stop
}

function Add-CyberUserToRdpGroup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName
    )

    $rdpGroup = 'Remote Desktop Users'
    $group = Get-LocalGroup -Name $rdpGroup -ErrorAction SilentlyContinue
    if (-not $group) {
        return
    }

    Add-CyberUserToGroup -UserName $UserName -GroupName $rdpGroup
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
        return
    }

    $member = Get-LocalGroupMember -Group $GroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "\\$UserName$|^$UserName$" }
    if (-not $member) {
        return
    }

    if ($DryRun) {
        return
    }

    Remove-LocalGroupMember -Group $GroupName -Member $UserName -ErrorAction Stop
}

function Show-CyberMenu {
    Write-Host ''
    Write-Host 'Menu'
    Write-Host '1: harden'
    Write-Host '2: new group'
    Write-Host '3: new user'
    Write-Host '4: add to group'
    Write-Host '5: add to RDP'
    Write-Host '6: remove from group'
    Write-Host '7: list users'
    Write-Host '8: list groups'
    Write-Host '9: scan'
    Write-Host ''
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
                Name   = $prop.Name
                Value  = $prop.Value
                Type   = 'RegistryRunKey'
            }
        }
    }

    $startupFolder = [System.Environment]::GetFolderPath('CommonStartup')
    if ($startupFolder -and (Test-Path $startupFolder)) {
        Get-ChildItem -Path $startupFolder -File -ErrorAction SilentlyContinue | ForEach-Object {
            $items += [PSCustomObject]@{
                Source = $startupFolder
                Name   = $_.Name
                Value  = $_.FullName
                Type   = 'StartupFolder'
            }
        }
    }

    try {
        Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
            $items += [PSCustomObject]@{
                Source = 'ScheduledTask'
                Name   = $_.TaskName
                Value  = $_.Actions.Execute
                Type   = 'ScheduledTask'
            }
        }
    }
    catch {
    }

    return $items | Sort-Object Type, Name
}

function New-VulnerabilityFinding {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [int]$Score,
        [Parameter(Mandatory = $true)]
        [string]$Evidence,
        [Parameter(Mandatory = $true)]
        [string]$Recommendation
    )

    [PSCustomObject]@{
        Category       = $Category
        Title          = $Title
        Score          = $Score
        Evidence       = $Evidence
        Recommendation = $Recommendation
    }
}

function Get-SuspiciousNamedFiles {
    $baseRoot = Get-DefaultScanRoot
    $patterns = @(
        'mimikatz', 'psexec', 'nc.exe', 'netcat', 'metasploit', 'r57', 'rat', 'rootkit', 'backdoor', 'keylogger', 'passwordstealer', 'credential', 'token', 'samdump', 'lsass', 'dump', 'revshell', 'reverse', 'payload', 'exploit', 'loader', 'dropper', 'beacon', 'agent', 'stealer', 'inject', 'hacktool', 'crack', 'bypass', 'runner', 'evil', 'malware', 'shell', 'pwnd', 'pwn', 'adminpass', 'pass.txt', 'passw', 'accountdump', 'wmic', 'cmd.exe', 'powershell.exe'
    )

    $fileResults = @()
    try {
        $files = Get-ChildItem -Path $baseRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -and $_.Extension -match '\.(exe|dll|bat|cmd|ps1|vbs|js|jar|com|scr|hta|lnk)$|\.(zip|rar|7z)$'
        }

        foreach ($file in $files) {
            $name = $file.Name.ToLowerInvariant()
            foreach ($pattern in $patterns) {
                if ($name.Contains($pattern)) {
                    $fileResults += [PSCustomObject]@{
                        FullName = $file.FullName
                        Name     = $file.Name
                        Pattern  = $pattern
                    }
                    break
                }
            }
        }
    }
    catch {
    }

    return $fileResults | Sort-Object FullName -Unique
}

function Get-VulnerabilityFindings {
    $findings = @()

    $guestUser = Get-CimInstance Win32_UserAccount -Filter "LocalAccount='True' AND Name='Guest'" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($guestUser -and -not $guestUser.Disabled) {
        $findings += New-VulnerabilityFinding -Category 'Accounts' -Title 'Guest account is enabled' -Score 25 -Evidence "Guest account status: enabled" -Recommendation 'Disable the Guest account and review local account policy.'
    }

    try {
        $autoAdminSetting = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoAdminLogon' -ErrorAction Stop).AutoAdminLogon
        if ($autoAdminSetting -eq 1) {
            $findings += New-VulnerabilityFinding -Category 'Logon' -Title 'Automatic admin logon enabled' -Score 35 -Evidence 'AutoAdminLogon is set to 1.' -Recommendation 'Set AutoAdminLogon to 0 and require user authentication.'
        }
    }
    catch {
    }

    try {
        $uacValue = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA' -ErrorAction Stop).EnableLUA
        if ($uacValue -ne 1) {
            $findings += New-VulnerabilityFinding -Category 'Security Controls' -Title 'User Account Control is disabled or reduced' -Score 30 -Evidence "EnableLUA is $uacValue" -Recommendation 'Set EnableLUA to 1 and enforce secure consent prompts.'
        }
    }
    catch {
    }

    try {
        $profiles = Get-NetFirewallProfile -ErrorAction Stop
        foreach ($profile in $profiles) {
            if (-not $profile.Enabled) {
                $findings += New-VulnerabilityFinding -Category 'Firewall' -Title "Firewall profile disabled: $($profile.Name)" -Score 30 -Evidence "Firewall profile '$($profile.Name)' is disabled." -Recommendation 'Enable the profile and block unauthorized inbound traffic.'
            }
        }
    }
    catch {
    }

    $defenderSvc = Get-Service -Name 'WinDefend' -ErrorAction SilentlyContinue
    if ($defenderSvc -and $defenderSvc.Status -ne 'Running') {
        $findings += New-VulnerabilityFinding -Category 'Endpoint Protection' -Title 'Windows Defender is not actively running' -Score 40 -Evidence "WinDefend service status: $($defenderSvc.Status)" -Recommendation 'Start and configure Windows Defender to protect the endpoint.'
    }

    try {
        $smb1 = Get-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -ErrorAction Stop
        if ($smb1.State -eq 'Enabled') {
            $findings += New-VulnerabilityFinding -Category 'Protocols' -Title 'SMB1 is enabled' -Score 20 -Evidence 'SMB1 optional feature is enabled.' -Recommendation 'Disable SMB1 and require modern SMB versions.'
        }
    }
    catch {
    }

    foreach ($legacyService in @('Telnet', 'SNMPTRAP', 'RemoteRegistry', 'Fax')) {
        $svc = Get-Service -Name $legacyService -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            $findings += New-VulnerabilityFinding -Category 'Services' -Title "Legacy service is running: $legacyService" -Score 15 -Evidence "Service '$legacyService' is currently running." -Recommendation 'Disable unnecessary legacy services and review service baselines.'
        }
    }

    $startupItems = Get-StartupItems
    if ((Get-CountAsInt $startupItems) -gt 12) {
        $findings += New-VulnerabilityFinding -Category 'Startup' -Title 'Large number of startup items present' -Score 20 -Evidence "Found $((Get-CountAsInt $startupItems)) startup items." -Recommendation 'Review auto-run entries and remove unauthorized startup programs.'
    }

    $suspiciousNamedFiles = Get-SuspiciousNamedFiles
    if ((Get-CountAsInt $suspiciousNamedFiles) -gt 0) {
        $score = 50
        $sampleNames = ($suspiciousNamedFiles | Select-Object -ExpandProperty Name | Select-Object -First 5) -join ', '
        $findings += New-VulnerabilityFinding -Category 'Files' -Title 'Suspicious file names detected' -Score $score -Evidence "Suspicious file names found: $sampleNames" -Recommendation 'Review these files manually for malicious content, persistence, or unauthorized payloads.'
    }

    $localUsers = Get-LocalUser -ErrorAction SilentlyContinue
    $knownSafeUsers = @('Administrator', 'Guest', 'DefaultAccount', 'WDAGUtilityAccount')
    $unknownLocalUsers = @($localUsers | Where-Object { $_.Name -notin $knownSafeUsers })
    if ((Get-CountAsInt $unknownLocalUsers) -gt 0) {
        $sampleNames = ($unknownLocalUsers | Select-Object -ExpandProperty Name | Select-Object -First 5) -join ', '
        $findings += New-VulnerabilityFinding -Category 'Accounts' -Title 'Unreviewed local user accounts exist' -Score 25 -Evidence "Local accounts found: $sampleNames" -Recommendation 'Review local user accounts against the approved list and disable any unapproved accounts.'
    }

    if ($findings.Count -eq 0) {
        $findings += New-VulnerabilityFinding -Category 'Baseline' -Title 'No obvious manual-review gaps detected' -Score 0 -Evidence 'No high-confidence vulnerabilities were detected in the standard local baseline scan.' -Recommendation 'Continue manual validation for environment-specific policies and app-specific risk.'
    }

    return $findings | Sort-Object Score -Descending
}

function Invoke-VulnerabilityScan {
    $findings = Get-VulnerabilityFindings
    $totalScore = (($findings | Measure-Object -Property Score -Sum).Sum)

    if ($findings.Count -eq 0) {
        Write-Host 'No findings recorded.'
        return
    }

    $findings | Select-Object Category, Title, Score, Evidence, Recommendation | Format-Table -AutoSize
    Write-Host "`nTotal likely vulnerability score: $totalScore"
}

function Invoke-CyberToolMenu {
    Initialize-ConsoleTheme
    Show-AsciiLogo
    do {
        Show-CyberMenu
        $choice = Read-Host 'Select an option'

        switch ($choice) {
            '1' {
                Invoke-CyberHardening
            }
            '2' {
                $groupName = Read-Host 'Enter group name'
                $description = Read-Host 'Enter group description (optional)'
                New-CyberGroup -Name $groupName -Description $description
            }
            '3' {
                $userName = Read-Host 'Enter username'
                $password = Read-Host 'Enter password'
                $fullName = Read-Host 'Enter full name (optional)'
                $description = Read-Host 'Enter description (optional)'
                New-CyberUser -UserName $userName -Password $password -FullName $fullName -Description $description
            }
            '4' {
                $userName = Read-Host 'Enter username to add'
                $groupName = Read-Host 'Enter group name'
                Add-CyberUserToGroup -UserName $userName -GroupName $groupName
            }
            '5' {
                $userName = Read-Host 'Enter username to add to Remote Desktop Users'
                Add-CyberUserToRdpGroup -UserName $userName
            }
            '6' {
                $userName = Read-Host 'Enter username to remove'
                $groupName = Read-Host 'Enter group name'
                Remove-CyberUserFromGroup -UserName $userName -GroupName $groupName
            }
            '7' {
                Get-LocalUser | Select-Object Name, Enabled, PrincipalSource | Format-Table -AutoSize
            }
            '8' {
                Get-LocalGroup | Select-Object Name, Description | Format-Table -AutoSize
            }
            '9' {
                Invoke-VulnerabilityScan
            }
        }

        Write-Host ''
    } while ($true)
}

function Invoke-CyberHardening {

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log 'Script is not running with administrator rights.'
        throw 'This script must be run as Administrator.'
    }

    $authorizedUsers = @()
    $formattedText = Read-Host 'Paste the full formatted list, including "Authorized Administrators:" and "Authorized Users:" headings'
    $parsedUsers = Parse-FormattedUserList -Text $formattedText
    foreach ($entry in $parsedUsers) {
        $authorizedUsers += [PSCustomObject]@{
            UserName = $entry.UserName
            IsAdmin  = $entry.IsAdmin
        }
    }

    Write-Host ''
    Write-Host 'Authorized Administrators:'
    foreach ($adminUser in ($parsedUsers | Where-Object { $_.IsAdmin } | Select-Object -ExpandProperty UserName)) {
        Write-Host "  - $adminUser"
    }

    foreach ($standardUser in ($parsedUsers | Where-Object { -not $_.IsAdmin } | Select-Object -ExpandProperty UserName)) {
        Write-Host "  - $standardUser"
    }

    $builtInExcludedUsers = @('Administrator', 'Guest', 'DefaultAccount', 'WDAGUtilityAccount')
    $allLocalUsers = Get-LocalUser | Where-Object { $_.Name -notin $builtInExcludedUsers }
    $approvedSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $authorizedUsers) {
        $null = $approvedSet.Add($entry.UserName)
    }

    foreach ($localUser in $allLocalUsers) {
        if ($approvedSet.Contains($localUser.Name)) {
            continue
        }

        $removeChoice = Read-Host "User '$($localUser.Name)' is not in the approved list. Remove/disable this account? [Y/N]"
        if ($removeChoice -match '^(Y|YES|Yes)$') {
            if ($DryRun) {
                continue
            }

            try {
                Disable-LocalUser -Name $localUser.Name -ErrorAction Stop
            }
            catch {
                Write-Log "Could not disable '$($localUser.Name)'. Review manually. Error: $($_.Exception.Message)"
            }
        }
    }

    net accounts /minpwlen:12
    net accounts /maxpwage:60
    net accounts /minpwage:1
    net accounts /uniquepw:24

    net accounts /lockoutthreshold:10
    net accounts /lockoutduration:30
    net accounts /lockoutwindow:30

    # More rules go in the template below.

    $tempDir = Join-Path $env:TEMP 'CyberHardening'
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force
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

    secedit /configure /db $env:windir\security\database\securepc.sdb /cfg $infPath /areas SECURITYPOLICY /quiet

    auditpol /set /category:* /success:enable /failure:enable

    foreach ($user in $authorizedUsers) {
        $localUser = Get-LocalUser -Name $user.UserName -ErrorAction SilentlyContinue
        if (-not $localUser) {
            continue
        }

        $adminGroup = 'Administrators'
        $userGroup = 'Users'

        $isAdminMember = (Get-LocalGroupMember -Group $adminGroup -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "\\$($user.UserName)$|^$($user.UserName)$" }).Count -gt 0

        if ($user.IsAdmin) {
            if (-not $isAdminMember -and -not $DryRun) {
                Add-LocalGroupMember -Group $adminGroup -Member $user.UserName -ErrorAction Stop
            }
        }
        else {
            if ($isAdminMember -and -not $DryRun) {
                Remove-LocalGroupMember -Group $adminGroup -Member $user.UserName -ErrorAction SilentlyContinue
            }

            $isUserMember = (Get-LocalGroupMember -Group $userGroup -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "\\$($user.UserName)$|^$($user.UserName)$" }).Count -gt 0
            if (-not $isUserMember -and -not $DryRun) {
                Add-LocalGroupMember -Group $userGroup -Member $user.UserName -ErrorAction SilentlyContinue
            }
        }
    }

    $tempAdminName = (Get-CimInstance Win32_UserAccount -Filter "LocalAccount='True' AND SID LIKE 'S-1-5-21-%-500'" | Select-Object -First 1).Name
    if ($tempAdminName -and -not $DryRun) {
        try {
            net user $tempAdminName /active:no
        }
        catch {
            Write-Log 'Could not disable local Administrator account. Review manually.'
        }
    }

    $guest = Get-CimInstance Win32_UserAccount -Filter "LocalAccount='True' AND Name='Guest'" | Select-Object -First 1
    if ($guest -and -not $DryRun) {
        try {
            net user Guest /active:no
        }
        catch {
            Write-Log 'Could not disable Guest account. Review manually.'
        }
    }

    $allLocalAccounts = Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @('Administrator', 'Guest', 'DefaultAccount', 'WDAGUtilityAccount') }
    foreach ($localAccount in $allLocalAccounts) {
        if ($DryRun) { continue }
        try {
            net user "$($localAccount.Name)" /PASSWORDREQ:YES
        }
        catch {
        }
    }

    $uacKeys = @(
        @{Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'EnableLUA'; Value = 1 },
        @{Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'ConsentPromptBehaviorAdmin'; Value = 5 },
        @{Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'ConsentPromptBehaviorUser'; Value = 3 },
        @{Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'PromptOnSecureDesktop'; Value = 1 },
        @{Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'EnableInstallerDetection'; Value = 1 },
        @{Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'ValidateAdminCodeSignatures'; Value = 0 },
        @{Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'EnableVirtualization'; Value = 1 },
        @{Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'EnableSecureUIAPaths'; Value = 1 }
    )
    foreach ($entry in $uacKeys) {
        Set-RegistryDword -Path $entry.Path -Name $entry.Name -Value $entry.Value
    }

    Set-RegistryDword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers' -Name 'DisableAutoplay' -Value 1

    Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'DontDisplayLastUserName' -Value 1

    Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'ShutdownWithoutLogon' -Value 0

    Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'DisableAutomaticAdminLogon' -Value 1

    Set-RegistryDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'NoDataCollection' -Value 1

    Enable-WindowsSecurityBaseline

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

    # Keep event collection on
    try {
        $svc = Get-Service -Name 'Wecsvc' -ErrorAction Stop
        if ($svc.StartType -ne 'Automatic') {
            Set-Service -Name 'Wecsvc' -StartupType Automatic
        }
        if ($svc.Status -ne 'Running') {
            Start-Service -Name 'Wecsvc' -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Host 'Wecsvc Error' -ForegroundColor Red
    }

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
        Disable-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -NoRestart -ErrorAction Stop
    }
    catch {
        Write-Host 'SMB1 Error' -ForegroundColor Red
    }

    Get-NetAdapter | ForEach-Object {
        try {
            Disable-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6 -ErrorAction Stop
            Write-Host "Disabled IPv6 binding on adapter: $($_.Name)"
        }
        catch {
            Write-Host "Could not disable IPv6 on adapter $($_.Name)"
        }
    }

    Get-DnsClient | ForEach-Object {
        try {
            Set-DnsClient -InterfaceIndex $_.InterfaceIndex -RegisterThisConnectionsAddress $false -ErrorAction Stop
        }
        catch {
            Write-Host "Could not update DNS client registration on interface $($_.InterfaceIndex)"
        }
    }

    $upnpPath = 'HKLM:\Software\Microsoft\DirectplayNATHelp\DPNHUPnP'
    if (-not (Test-Path $upnpPath)) {
        New-Item -Path $upnpPath -Force
    }
    Set-RegistryDword -Path $upnpPath -Name 'UPnPMode' -Value 2

    $wifiSenseRoot = 'HKLM:\Software\Microsoft\WlanSvc\Features'
    if (Test-Path $wifiSenseRoot) {
        Set-RegistryDword -Path $wifiSenseRoot -Name 'AutoConnectAllowed' -Value 0
    }

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
            Write-Host "Disabled firewall rule: $rule"
        }
        catch {
            Write-Host "Firewall rule '$rule' not found; skipping."
        }
    }

    Set-RegistryDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0' -Name 'NtlmMinClientSec' -Value 537395200
    Set-RegistryDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0' -Name 'NtlmMinServerSec' -Value 537395200

    # Remove extra shares, keep the defaults
    $defaultShares = @('ADMIN$', 'C$', 'IPC$')
    $shares = Get-SmbShare | Where-Object { $_.Name -notin $defaultShares }
    foreach ($share in $shares) {
        try {
            Remove-SmbShare -Name $share.Name -Force
            Write-Host "Removed unauthorized share: $($share.Name)"
        }
        catch {
            Write-Host "Could not remove share $($share.Name)"
        }
    }

    # Browser cleanup is manual
    Write-Host 'Review browsers and third-party toolbars manually. Update Flash/Reader/Java plugins and remove unauthorized toolbars.'

    $oneDrive = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if (Test-Path $oneDrive) {
        Remove-ItemProperty -Path $oneDrive -Name 'OneDrive' -ErrorAction SilentlyContinue
    }

    Set-RegistryDword -Path 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaveTimeOut' -Value 600
    Set-RegistryString -Path 'HKCU:\Control Panel\Desktop' -Name 'SCRNSAVE.EXE' -Value 'logon.scr'
    Set-RegistryDword -Path 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaverIsSecure' -Value 1
    Set-RegistryDword -Path 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaveActive' -Value 1
    Set-RegistryString -Path 'HKCU:\Control Panel\Desktop' -Name 'UserPreferencesMask' -Value '90 12 0 0 0 0 0 0'

    Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoAdminLogon' -Value 0
    Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'ForceAutoLogon' -Value 0
    Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoLogonCount' -Value 0

    Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'HideFastUserSwitching' -Value 1

    Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA' -Value 1
    Set-RegistryDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -Name 'EnableScriptBlockLogging' -Value 1

    Write-Host 'Hardening finished.'
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
        'add-to-rdp' {
            if (-not $UserName) { throw 'UserName is required when Action is add-to-rdp.' }
            Add-CyberUserToRdpGroup -UserName $UserName
        }
        'harden' {
            Invoke-CyberHardening
        }
        default {
            throw "Unknown action '$Action'. Valid actions: create-group, create-user, add-to-group, remove-from-group, add-to-rdp, harden."
        }
    }
    exit 0
}

Invoke-CyberToolMenu