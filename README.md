# Cyber Hardening Toolkit

This script is basically a local Windows cleanup and hardening helper. It can create users, manage groups, check local accounts, uninstall software, apply common security changes, and help you review a machine for obvious problem areas.

Think of it as a practical tool for someone who wants a faster starting point without blindly changing everything on a system.

## What you need
- Windows machine
- PowerShell
- Administrator rights
- A willingness to review anything risky before you let it run

## Quick start
1. Open PowerShell as Administrator.
2. If needed, allow local scripts to run:
   ```powershell
   Set-ExecutionPolicy Unrestricted -Scope LocalMachine
   ```
3. Download the script:
   ```powershell
   curl -L -O https://raw.githubusercontent.com/c-o-b-a-x/CyberPatriot-Scrip/refs/heads/main/CyberHardening.ps1
   ```
4. Find the file and run it:
   ```powershell
   .\CyberHardening.ps1
   ```

## A few important notes
- This is meant for local Windows administration and hardening tasks.
- Some actions need elevated privileges and can affect security settings.
- Always review the script before running it on a production machine or anything important.
- Be careful with user creation, group membership changes, and uninstalling software.

## What it can do
- create local users
- create local groups
- add or remove users from groups
- review approved vs. unapproved local accounts
- disable unwanted accounts with a confirmation step
- uninstall a list of applications
- apply common hardening settings
- search for files by type, such as media, archives, executables, and documents
- scan installed software, startup items, and suspicious files
- export a simple compliance report for review
- give you a simple console menu instead of a GUI

## The menu
When you launch it, you get a menu with options like:
- create a local group
- create a local user
- add a user to a group
- remove a user from a group
- list local users
- list local groups
- run the hardening checklist
- uninstall applications
- search for file types
- open the system audit and reporting menu
- exit the tool

## Audit and reporting
The audit section is there to help you spot things that are easy to miss:
- what software is installed
- what is launching at startup
- what suspicious files are sitting around in a folder
- a simple report you can save for documentation or review

This part is meant to support investigation, not silently change things without human review.

## What this does not cover completely
This is a useful automation tool, but it is not a full replacement for every item on a real hardening checklist. Some parts are left for manual review because they depend on the environment, business rules, or how a machine is actually being used.

Things it does not fully automate by default include:
- browser plugins, toolbars, and browser add-ons
- Java, Flash, and Adobe plugin checks
- deep review of every service or startup entry
- domain-specific or org-specific policy exceptions
- custom firewall rules beyond the built-in baseline changes
- full auditing of every registry key, GPO, or policy drift issue
- any checklist item that needs human judgment in context
- detailed validation of every installed app or user profile setting
- advanced incident-response cleanup beyond what is safe and useful for a local review tool

So the script handles the common admin and cleanup work, but it still expects a person to check the sensitive or environment-specific parts before finalizing anything.

