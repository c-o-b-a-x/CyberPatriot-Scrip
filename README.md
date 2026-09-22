# Cyber Hardening Toolkit

This project provides a Windows local hardening and administration script for creating users, managing groups, reviewing local accounts, uninstalling applications, and applying baseline security settings.

## Prerequisites
- Windows machine with PowerShell
- Administrator privileges
- Execution policy can be adjusted if needed for local script use

## Quick Setup
1. Open PowerShell as Administrator.
2. Run:
   ```powershell
   Set-ExecutionPolicy Unrestricted -Scope LocalMachine
   ```
3. Download the script:
   ```powershell
   curl -L -O https://raw.githubusercontent.com/c-o-b-a-x/CyberPatriot-Scrip/refs/heads/main/CyberHardening.ps1
   ```
4. Locate the downloaded file in your current directory or in the system folders, then sort by date modified if needed.
5. Run the script:
   ```powershell
   .\CyberHardening.ps1
   ```

## Notes
- The script is intended for local Windows administration and hardening tasks.
- Some actions require elevated administrator rights and may affect local system security settings.
- Review the script before running it in production or on managed systems.
- Use caution when creating or removing users, changing group membership, or uninstalling software.

## Included Features
- local user creation and management
- local group creation and membership control
- application uninstallation helper
- hardening checklist and baseline policy actions
- file-type search utilities
- console-based menu interface

