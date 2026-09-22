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

## What the Original Checklist This Script Does Not Fully Cover
This script is a practical automation subset, not a complete replacement for every item in the original hardening checklist. Some areas are intentionally left for manual review or require environment-specific validation.

The script does not fully automate the following items by default:
- browser plug-ins, toolbars, and third-party add-ons review
- Java, Flash, and Adobe plugin verification
- manual validation of scheduled tasks and startup items
- review of all Windows services not explicitly covered by the script
- domain-specific or organization-specific policy exceptions
- custom network firewall rules beyond the built-in baseline changes
- full auditing of every registry key, GPO, or local policy drift scenario
- any checklist item that depends on live user judgment or operational context
- deep validation of every installed application, browser extension, or user profile setting

In other words, the script automates the common local admin, security, and cleanup tasks, but it still expects an operator to manually confirm the parts of the checklist that are environment-sensitive, policy-specific, or not safe to automate broadly.

