# Cyber Hardening Toolkit

This is a small PowerShell tool for basic Windows hardening and account cleanup. It gives you a menu for common tasks, so you do not have to remember every command by hand.

It can change real system settings. Read through the script first and do not run it on an important machine without knowing what each option does.

## Before you start

You will need:

- a Windows computer
- PowerShell
- an Administrator PowerShell window

## Running it

Open PowerShell as Administrator, move to the folder containing the script, and run:

```powershell
.\script.ps1
```

If Windows blocks local scripts, you may need to adjust the execution policy first:

```powershell
Set-ExecutionPolicy Unrestricted -Scope LocalMachine
```

Only change that setting if you understand the risk, and change it back when you are finished if needed.

## What the menu does

The menu lets you:

- create local users and groups
- add or remove users from groups
- add a user to Remote Desktop Users
- list local users and groups
- run the hardening routine
- run a quick security scan

The hardening routine asks for the approved users first. It then checks local accounts, applies password and audit settings, enables security features, turns off several older services and features, and adjusts common network and login settings.

## Important warning

Some choices make immediate changes to Windows. The script can disable accounts, change group membership, change firewall and Defender settings, and disable services or Windows features. Test it in a virtual machine first when possible.

The `-WhatIfMode` switch is available for paths that support a dry run:

```powershell
.\script.ps1 -WhatIfMode
```

## Still check these yourself

This tool is not a replacement for a full security review. You should still manually check:

- browser extensions, toolbars, Java, and Adobe software
- every service and startup item
- organization-specific rules and exceptions
- firewall rules that are unique to the machine
- user profiles, installed applications, and registry settings
- anything on your official hardening checklist that needs human judgment

