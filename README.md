# Get-Broker-Invalid-Accounts
Get Broker Invalid Accounts

Creates a CSV file of invalid computer and user accounts for a Citrix
7.x/18xx/19xx Site.

Creates a CSV file named SiteName_InvalidAccounts.csv

The CSV file contains a list of all invalid accounts found (User, Group, and
Computer).

If no invalid accounts are found, the following line is written to the CSV file:
"There were 0 invalid accounts found on $(Get-Date)"

This script does not require an elevated PowerShell session.

This script can be run by a Read-Only Site Administrator to find invalid accounts only.
Removing invalid accounts requires a Full Site Administrator.

This script supports -Confirm and -WhatIf to make it safer for removing invalid
accounts.

This script requires PowerShell version 3 or later.

This script is designed to help find the account(s) causing Event ID 505 caused by the Citrix ConfigSync Service in the Application event log.

The Citrix Config Sync Service failed an import.

Error details:
Error importing configuration data into secondary Broker.
:
At C:WindowsServiceProfilesNetworkServiceAppDataLocalTemp
e3fefc3b-dc5e-41dc-9099-b3f7c85ff935ImportBrokerConfiguration.ps1:1265 char:5
+ throw $_.Exception
+ ~~~~~~~~~~~~~~~~~~
+ Message : Security identifier does not represent a Windows
account
+ CategoryInfo : OperationStopped: (:) [], SdkOperationException
+ FullyQualifiedErrorId : Security identifier does not represent a Windows
account
