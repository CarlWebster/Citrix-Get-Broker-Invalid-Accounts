#Requires -Version 3.0

<#
.SYNOPSIS
	Creates a CVS file of invalid computer and user accounts for a Citrix 7.x/18xx/19xx 
	Site.
.DESCRIPTION
	Creates a CSV file of invalid computer and user accounts for a Citrix 7.x/18xx/19xx 
	Site.

	Creates a CSV file named SiteName_InvalidAccounts.csv
	The CSV file contains a list of all invalid accounts found (User, Group, and 
	Computer).
	If no invalid accounts are found, the following line is written to the CSV file:
	"There were 0 invalid accounts found on $(Get-Date)"
	
	This script does not require an elevated PowerShell session.

	This script can be run by a Read-Only Site Administrator.

	This script requires PowerShell version 3 or later.
	
	This script is designed to help find the account(s) causing Event ID 505 caused by 
	the Citrix ConfigSync Service in the Application event log.
	
	The Citrix Config Sync Service failed an import. 
 
	Error details: 
	Error importing configuration data into secondary Broker.
	 : 
	At C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Temp\
	e3fefc3b-dc5e-41dc-9099-b3f7c85ff935\ImportBrokerConfiguration.ps1:1265 char:5
	+     throw $_.Exception
	+     ~~~~~~~~~~~~~~~~~~
		+ Message               : Security identifier does not represent a Windows 
		account
		+ CategoryInfo          : OperationStopped: (:) [], SdkOperationException
		+ FullyQualifiedErrorId : Security identifier does not represent a Windows 
		account

.PARAMETER AdminAddress
	Specifies the address of a CVAD controller the PowerShell snapins will connect 
	to. 
	This can be provided as a hostname or an IP address. 
	This parameter defaults to Localhost.
	This parameter has an alias of AA.
.PARAMETER Folder
	Specifies the optional output folder to save the output report. 
.EXAMPLE
	PS C:\PSScript > .\Get-BrokerInvalidAccounts.ps1
	
	Uses LocalHost for the delivery controller name and places the CSV file in
	the same folder where the script is run.
.EXAMPLE
	PS C:\PSScript > .\Get-BrokerInvalidAccounts.ps1 -AdminAddress DDC01
	
	Uses DDC01 for the delivery controller name and places the CSV file in
	the same folder where the script is run.
.EXAMPLE
	PS C:\PSScript > .\Get-BrokerInvalidAccounts.ps1 -Folder \\ServerName\Share
	
	Uses LocalHost for the delivery controller name and places the CSV file in
	the Share folder on the server ServerName.
.EXAMPLE
	PS C:\PSScript > .\Get-BrokerInvalidAccounts.ps1 -AA DDC01 -Folder 
	\\ServerName\Share
	
	Uses DDC01 for the delivery controller name and places the CSV file in
	the Share folder on the server ServerName.
.INPUTS
	None.  You cannot pipe objects to this script.
.OUTPUTS
	No objects are output from this script.  This script creates a CSV file.
.NOTES
	NAME: Get-BrokerInvalidAccounts.ps1
	VERSION: 1.00
	AUTHOR: Carl Webster, Sr. Solutions Architect at Choice Solutions and a lot of code from Michael B. Smith
	LASTEDIT: May 14, 2019
#>

[CmdletBinding(SupportsShouldProcess = $False, ConfirmImpact = "None", DefaultParameterSetName = "") ]

Param(
	[parameter(Mandatory=$False)] 
	[ValidateNotNullOrEmpty()]
	[Alias("AA")]
	[string]$AdminAddress="Localhost",

	[parameter(Mandatory=$False)] 
	[string]$Folder=""

	)

#region script change log	
#webster@carlwebster.com
#@carlwebster on Twitter
#http://www.CarlWebster.com
#Created on May 2, 2019
#
#V1.00 
#	Initial release to the community on 14-May-2019
#endregion

#region initial variable testing and setup
Set-StrictMode -Version Latest

#force on
$PSDefaultParameterValues = @{"*:Verbose"=$True}

If($Folder -ne "")
{
	Write-Verbose "$(Get-Date): Testing folder path"
	#does it exist
	If(Test-Path $Folder -EA 0)
	{
		#it exists, now check to see if it is a folder and not a file
		If(Test-Path $Folder -pathType Container -EA 0)
		{
			#it exists and it is a folder
			Write-Verbose "$(Get-Date): Folder path $Folder exists and is a folder"
		}
		Else
		{
			#it exists but it is a file not a folder
			Write-Error "Folder $Folder is a file, not a folder.  Script cannot continue"
			Exit
		}
	}
	Else
	{
		#does not exist
		Write-Error "Folder $Folder does not exist.  Script cannot continue"
		Exit
	}
}

If($Folder -eq "")
{
	$pwdpath = $pwd.Path
}
Else
{
	$pwdpath = $Folder
}

If($pwdpath.EndsWith("\"))
{
	#remove the trailing \
	$pwdpath = $pwdpath.SubString(0, ($pwdpath.Length - 1))
}
#endregion

#region Michael B Smith functions
$global:__rootDSE = $null

function getRootDSE
{
	if( $null -eq $global:__rootDSE )
	{
		$global:__rootDSE = [ADSI] 'LDAP://RootDSE'
	}

	$global:__rootDSE
}

$global:__defaultNC = $null
$global:__schemaNC  = $null
$global:__configNC  = $null
$global:__rootNC    = $null

function getDefaultNC
{
	if( $null -eq $global:__defaultNC )
	{
		$rootDSE = getRootDSE
		$global:__defaultNC = $rootDSE.Properties[ 'defaultNamingContext' ].Value
	}

	$global:__defaultNC
}

function getSchemaNC
{
	if( $null -eq $global:__schemaNC )
	{
		$rootDSE = getRootDSE
		$global:__schemaNC = $rootDSE.Properties[ 'schemaNamingContext' ].Value
	}

	$global:__schemaNC
}

function getConfigNC
{
	if( $null -eq $global:__configNC )
	{
		$rootDSE = getRootDSE
		$global:__configNC = $rootDSE.Properties[ 'configurationNamingContext' ].Value
	}

	$global:__configNC
}

function getRootNC
{
	if( $null -eq $global:__rootNC )
	{
		$rootDSE = getRootDSE
		$global:__rootNC = $rootDSE.Properties[ 'rootDomainNamingContext' ].Value
	}

	$global:__rootNC
}

function Test-ValidUserOrGroup( [string] $user )
{
	$adSearcher = [adsisearcher] "(&(|(objectClass=user)(objectClass=group))(samaccountname=$user))"
	$adSearcher.SearchRoot = [adsi] ( 'LDAP://' + ( getdefaultNC ) )

	[Bool] $success = $false
	try
	{
		$results = $adSearcher.FindAll()
		## Write-Host $results.GetType().FullName
		if( $results )
		{
			foreach( $r in $results )
			{
				## Write-Host $r.Properties[ 'distinguishedName' ][ 0 ]
				$success = $true
				break
			}
		}
	}
	catch
	{
	}

	$success
}

function Test-ValidComputer( [string] $computer )
{
	if( -not $computer.EndsWith( '$' ) )
	{
		$computer += '$' ## suffix a "$"
	}

	$adSearcher = [adsisearcher] "(&(objectClass=computer)(samaccountname=$computer))"
	$adSearcher.SearchRoot = [adsi] ( 'LDAP://' + ( getdefaultNC ) )

	[Bool] $success = $false
	try
	{
		$results = $adSearcher.FindAll()
		## Write-Host $results.GetType().FullName
		if( $results )
		{
			foreach( $r in $results )
			{
				## Write-Host $r.Properties[ 'distinguishedName' ][ 0 ]
				$success = $true
				break
			}
		}
	}
	catch
	{
	}

	$success
}
#endregion

#region validation functions
Function Check-NeededPSSnapins
{
	Param([parameter(Mandatory = $True)][alias("Snapin")][string[]]$Snapins)

	#Function specifics
	$MissingSnapins = @()
	[bool]$FoundMissingSnapin = $False
	$LoadedSnapins = @()
	$RegisteredSnapins = @()

	#Creates arrays of strings, rather than objects, we're passing strings so this will be more robust.
	$loadedSnapins += Get-PSSnapin | ForEach-Object {$_.name}
	$registeredSnapins += Get-PSSnapin -Registered | ForEach-Object {$_.name}

	ForEach($Snapin in $Snapins)
	{
		#check if the snapin is loaded
		If(!($LoadedSnapins -like $snapin))
		{
			#Check if the snapin is missing
			If(!($RegisteredSnapins -like $Snapin))
			{
				#set the flag if it's not already
				If(!($FoundMissingSnapin))
				{
					$FoundMissingSnapin = $True
				}
				#add the entry to the list
				$MissingSnapins += $Snapin
			}
			Else
			{
				#Snapin is registered, but not loaded, loading it now:
				Add-PSSnapin -Name $snapin -EA 0 *>$Null
			}
		}
	}

	If($FoundMissingSnapin)
	{
		Write-Warning "Missing Windows PowerShell snap-ins Detected:"
		$missingSnapins | ForEach-Object {Write-Warning "($_)"}
		Return $False
	}
	Else
	{
		Return $True
	}
}
#endregion

$StartTime = Get-Date

#check for required Citrix snapin
If(!(Check-NeededPSSnapins "Citrix.Broker.Admin.V2"))
{
	#We're missing Citrix Snapins that we need
	Write-Error "`nMissing Citrix PowerShell Snap-ins Detected, check the console above for more information. 
	`nAre you sure you are running this script against a XenDesktop 7.0 or later Delivery Controller or VDA? 
	`nIf running on a VDA, make sure the Broker_PowerShell_SnapIn_x64 is installed.
	`n`nScript will now close."
	Exit
}

#set value for MaxRecordCount
$MaxRecordCount = [int]::MaxValue 
[int]$InvalidAccounts = 0

$CVADParams1 = @{
adminaddress = $AdminAddress; 
EA = 0;
MaxRecordCount = $MaxRecordCount;
}

$CVADParams2 = @{
adminaddress = $AdminAddress; 
EA = 0;
}

#get Site name
$CVADSiteName = "Unable to determine"

$CVADSiteName = (Get-BrokerSite @CVADParams2).Name

If( !($?) -or $Null -eq $CVADSiteName)
{
	Write-Warning "CVAD Site information could not be retrieved.  Script cannot continue"
	Write-Error "cmdlet failed $($error[ 0 ].ToString())"
	Exit
}

Write-Verbose "$(Get-Date): Site name is $CVADSiteName"

$InvalidAccountData = New-Object System.Collections.ArrayList
$OutputFile = "$($pwdpath)\$($CVADSiteName)_InvalidAccounts.csv"

Write-Verbose "$(Get-Date): Gathering invalid account data and saving to $OutputFile"

Write-Verbose "$(Get-Date): Processing Get-BrokerAccessPolicyRule"
$results = Get-BrokerAccessPolicyRule @CVADParams1

If(!$?)
{
	Write-Error "$(Get-Date): Processing Get-BrokerAccessPolicyRule"
}
ElseIf($? -and $Null -ne $Results)
{
	ForEach($result in $results)
	{
		If($result.ExcludedUsers.Count -gt 0)
		{
			$tmpusers = $result.ExcludedUsers
			ForEach($tmpuser in $tmpusers)
			{
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerAccessPolicyRule"
						Account             = $testuser
						AccountType         = "Unknown User or Group: SID"
						cmdletPropertyName  = "ExcludedUsers"
						Location            = "Broker Assignment Policy Rule: $($result.Name)"
					}
					$null = $InvalidAccountData.Add($obj)
				}
				Else
				{
					$tmparray = $tmpuser.Name.Split("\")
					$testuser = $tmparray[1]
					If(!(Test-ValidUserOrGroup $testuser))
					{
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerAccessPolicyRule"
							Account             = $testuser
							AccountType         = "UserOrGroup"
							cmdletPropertyName  = "ExcludedUsers"
							Location            = "Broker Assignment Policy Rule: $($result.Name)"
						}
						$null = $InvalidAccountData.Add($obj)
					}
				}
			}
		}

		If($result.IncludedUsers.Count -gt 0)
		{
			$tmpusers = $result.IncludedUsers
			ForEach($tmpuser in $tmpusers)
			{
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerAccessPolicyRule"
						Account             = $testuser
						AccountType         = "Unknown User or Group: SID"
						cmdletPropertyName  = "IncludedUsers"
						Location            = "Broker Assignment Policy Rule: $($result.Name)"
					}
					$null = $InvalidAccountData.Add($obj)
				}
				Else
				{
					$tmparray = $tmpuser.Name.Split("\")
					$testuser = $tmparray[1]
					If(!(Test-ValidUserOrGroup $testuser))
					{
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerAccessPolicyRule"
							Account             = $testuser
							AccountType         = "UserOrGroup"
							cmdletPropertyName  = "IncludedUsers"
							Location            = "Broker Assignment Policy Rule: $($result.Name)"
						}
						$null = $InvalidAccountData.Add($obj)
					}
				}
			}
		}
	}
}

Write-Verbose "$(Get-Date): Processing Get-BrokerAppAssignmentPolicyRule"
$results = Get-BrokerAppAssignmentPolicyRule @CVADParams1

If(!$?)
{
	Write-Error "$(Get-Date): Processing Get-BrokerAppAssignmentPolicyRule"
}
ElseIf($? -and $Null -ne $Results)
{
	ForEach($result in $results)
	{
		If($result.ExcludedUsers.Count -gt 0)
		{
			$tmpusers = $result.ExcludedUsers
			ForEach($tmpuser in $tmpusers)
			{
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerAppAssignmentPolicyRule"
						Account             = $testuser
						AccountType         = "Unknown User or Group: SID"
						cmdletPropertyName  = "ExcludedUsers"
						Location            = "Broker App Assignment Policy Rule: $($result.Name)"
					}
					$null = $InvalidAccountData.Add($obj)
				}
				Else
				{
					$tmparray = $tmpuser.Name.Split("\")
					$testuser = $tmparray[1]
					If(!(Test-ValidUserOrGroup $testuser))
					{
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerAppAssignmentPolicyRule"
							Account             = $testuser
							AccountType         = "UserOrGroup"
							cmdletPropertyName  = "ExcludedUsers"
							Location            = "Broker App Assignment Policy Rule: $($result.Name)"
						}
						$null = $InvalidAccountData.Add($obj)
					}
				}
			}
		}

		If($result.IncludedUsers.Count -gt 0)
		{
			$tmpusers = $result.IncludedUsers
			ForEach($tmpuser in $tmpusers)
			{
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerAppAssignmentPolicyRule"
						Account             = $testuser
						AccountType         = "Unknown User or Group: SID"
						cmdletPropertyName  = "IncludedUsers"
						Location            = "Broker App Assignment Policy Rule: $($result.Name)"
					}
					$null = $InvalidAccountData.Add($obj)
				}
				Else
				{
					$tmparray = $tmpuser.Name.Split("\")
					$testuser = $tmparray[1]
					If(!(Test-ValidUserOrGroup $testuser))
					{
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerAppAssignmentPolicyRule"
							Account             = $testuser
							AccountType         = "UserOrGroup"
							cmdletPropertyName  = "IncludedUsers"
							Location            = "Broker App Assignment Policy Rule: $($result.Name)"
						}
						$null = $InvalidAccountData.Add($obj)
					}
				}
			}
		}
	}
}

Write-Verbose "$(Get-Date): Processing Get-BrokerAppEntitlementPolicyRule"
$results = Get-BrokerAppEntitlementPolicyRule @CVADParams1

If(!$?)
{
	Write-Error "$(Get-Date): Processing Get-BrokerAppEntitlementPolicyRule"
}
ElseIf($? -and $Null -ne $Results)
{
	ForEach($result in $results)
	{
		If($result.ExcludedUsers.Count -gt 0)
		{
			$tmpusers = $result.ExcludedUsers
			ForEach($tmpuser in $tmpusers)
			{
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerAppEntitlementPolicyRule"
						Account             = $testuser
						AccountType         = "Unknown User or Group: SID"
						cmdletPropertyName  = "ExcludedUsers"
						Location            = "Broker App Entitlement Policy Rule: $($result.Name)"
					}
					$null = $InvalidAccountData.Add($obj)
				}
				Else
				{
					$tmparray = $tmpuser.Name.Split("\")
					$testuser = $tmparray[1]
					If(!(Test-ValidUserOrGroup $testuser))
					{
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerAppEntitlementPolicyRule"
							Account             = $testuser
							AccountType         = "UserOrGroup"
							cmdletPropertyName  = "ExcludedUsers"
							Location            = "Broker App Entitlement Policy Rule: $($result.Name)"
						}
						$null = $InvalidAccountData.Add($obj)
					}
				}
			}
		}

		If($result.IncludedUsers.Count -gt 0)
		{
			$tmpusers = $result.IncludedUsers
			ForEach($tmpuser in $tmpusers)
			{
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerAppEntitlementPolicyRule"
						Account             = $testuser
						AccountType         = "Unknown User or Group: SID"
						cmdletPropertyName  = "IncludedUsers"
						Location            = "Broker App Entitlement Policy Rule: $($result.Name)"
					}
					$null = $InvalidAccountData.Add($obj)
				}
				Else
				{
					$tmparray = $tmpuser.Name.Split("\")
					$testuser = $tmparray[1]
					If(!(Test-ValidUserOrGroup $testuser))
					{
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerAppEntitlementPolicyRule"
							Account             = $testuser
							AccountType         = "UserOrGroup"
							cmdletPropertyName  = "IncludedUsers"
							Location            = "Broker App Entitlement Policy Rule: $($result.Name)"
						}
						$null = $InvalidAccountData.Add($obj)
					}
				}
			}
		}
	}
}

Write-Verbose "$(Get-Date): Processing Get-BrokerApplication"
$results = Get-BrokerApplication @CVADParams1

If(!$?)
{
	Write-Error "$(Get-Date): Processing Get-BrokerApplication"
}
ElseIf($? -and $Null -ne $Results)
{
	ForEach($result in $results)
	{
		If($result.AssociatedUserNames.Count -gt 0)
		{
			$tmpusers = $result.AssociatedUserNames
			ForEach($tmpuser in $tmpusers)
			{
				If($tmpuser -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerApplication"
						Account             = $testuser
						AccountType         = "Unknown User or Group: SID"
						cmdletPropertyName  = "AssociatedUserNames"
						Location            = "Application: $($result.name)"
					}
					$null = $InvalidAccountData.Add($obj)
				}
				Else
				{
					$tmparray = $tmpuser.Split("\")
					$testuser = $tmparray[1]
					If(!(Test-ValidUserOrGroup $testuser))
					{
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerApplication"
							Account             = $testuser
							AccountType         = "UserOrGroup"
							cmdletPropertyName  = "AssociatedUserNames"
							Location            = "Application: $($result.name)"
						}
						$null = $InvalidAccountData.Add($obj)
					}
				}
			}
		}
	}
}

Write-Verbose "$(Get-Date): Processing Get-BrokerApplicationGroup"
$results = Get-BrokerApplicationGroup @CVADParams1

If(!$?)
{
	Write-Error "$(Get-Date): Processing Get-BrokerApplicationGroup"
}
ElseIf($? -and $Null -ne $Results)
{
	ForEach($result in $results)
	{
		If($result.AssociatedUserNames.Count -gt 0)
		{
			$tmpusers = $result.AssociatedUserNames
			ForEach($tmpuser in $tmpusers)
			{
				If($tmpuser -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerApplicationGroup"
						Account             = $testuser
						AccountType         = "Unknown User or Group: SID"
						cmdletPropertyName  = "AssociatedUserNames"
						Location            = "Application Group: $($result.name)"
					}
					$null = $InvalidAccountData.Add($obj)
				}
				Else
				{
					$tmparray = $tmpuser.Split("\")
					$testuser = $tmparray[1]
					If(!(Test-ValidUserOrGroup $testuser))
					{
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerApplicationGroup"
							Account             = $testuser
							AccountType         = "UserOrGroup"
							cmdletPropertyName  = "AssociatedUserNames"
							Location            = "Application Group: $($result.name)"
						}
						$null = $InvalidAccountData.Add($obj)
					}
				}
			}
		}
	}
}

Write-Verbose "$(Get-Date): Processing Get-BrokerAssignmentPolicyRule"
$results = Get-BrokerAssignmentPolicyRule @CVADParams1

If(!$?)
{
	Write-Error "$(Get-Date): Processing Get-BrokerAssignmentPolicyRule"
}
ElseIf($? -and $Null -ne $Results)
{
	ForEach($result in $results)
	{
		If($result.ExcludedUsers.Count -gt 0)
		{
			$tmpusers = $result.ExcludedUsers
			ForEach($tmpuser in $tmpusers)
			{
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerAssignmentPolicyRule"
						Account             = $testuser
						AccountType         = "Unknown User or Group: SID"
						cmdletPropertyName  = "ExcludedUsers"
						Location            = "Broker Assignment Policy Rule: $($result.Name)"
					}
					$null = $InvalidAccountData.Add($obj)
				}
				Else
				{
					$tmparray = $tmpuser.Name.Split("\")
					$testuser = $tmparray[1]
					If(!(Test-ValidUserOrGroup $testuser))
					{
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerAssignmentPolicyRule"
							Account             = $testuser
							AccountType         = "UserOrGroup"
							cmdletPropertyName  = "ExcludedUsers"
							Location            = "Broker Assignment Policy Rule: $($result.Name)"
						}
						$null = $InvalidAccountData.Add($obj)
					}
				}
			}
		}

		If($result.IncludedUsers.Count -gt 0)
		{
			$tmpusers = $result.IncludedUsers
			ForEach($tmpuser in $tmpusers)
			{
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerAssignmentPolicyRule"
						Account             = $testuser
						AccountType         = "Unknown User or Group: SID"
						cmdletPropertyName  = "IncludedUsers"
						Location            = "Broker Assignment Policy Rule: $($result.Name)"
					}
					$null = $InvalidAccountData.Add($obj)
				}
				Else
				{
					$tmparray = $tmpuser.Name.Split("\")
					$testuser = $tmparray[1]
					If(!(Test-ValidUserOrGroup $testuser))
					{
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerAssignmentPolicyRule"
							Account             = $testuser
							AccountType         = "UserOrGroup"
							cmdletPropertyName  = "IncludedUsers"
							Location            = "Broker Assignment Policy Rule: $($result.Name)"
						}
						$null = $InvalidAccountData.Add($obj)
					}
				}
			}
		}
	}
}

Write-Verbose "$(Get-Date): Processing Get-BrokerEntitlementPolicyRule"
$results = Get-BrokerEntitlementPolicyRule @CVADParams1

If(!$?)
{
	Write-Error "$(Get-Date): Processing Get-BrokerEntitlementPolicyRule"
}
ElseIf($? -and $Null -ne $Results)
{
	ForEach($result in $results)
	{
		If($result.ExcludedUsers.Count -gt 0)
		{
			$tmpusers = $result.ExcludedUsers
			ForEach($tmpuser in $tmpusers)
			{
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerEntitlementPolicyRule"
						Account             = $testuser
						AccountType         = "Unknown User or Group: SID"
						cmdletPropertyName  = "ExcludedUsers"
						Location            = "Broker Entitlement Policy Rule: $($result.Name)"
					}
					$null = $InvalidAccountData.Add($obj)
				}
				Else
				{
					$tmparray = $tmpuser.Name.Split("\")
					$testuser = $tmparray[1]
					If(!(Test-ValidUserOrGroup $testuser))
					{
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerEntitlementPolicyRule"
							Account             = $testuser
							AccountType         = "UserOrGroup"
							cmdletPropertyName  = "ExcludedUsers"
							Location            = "Broker Entitlement Policy Rule: $($result.Name)"
						}
						$null = $InvalidAccountData.Add($obj)
					}
				}
			}
		}

		If($result.IncludedUsers.Count -gt 0)
		{
			$tmpusers = $result.IncludedUsers
			ForEach($tmpuser in $tmpusers)
			{
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerEntitlementPolicyRule"
						Account             = $testuser
						AccountType         = "Unknown User or Group: SID"
						cmdletPropertyName  = "IncludedUsers"
						Location            = "Broker Entitlement Policy Rule: $($result.Name)"
					}
					$null = $InvalidAccountData.Add($obj)
				}
				Else
				{
					$tmparray = $tmpuser.Name.Split("\")
					$testuser = $tmparray[1]
					If(!(Test-ValidUserOrGroup $testuser))
					{
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerEntitlementPolicyRule"
							Account             = $testuser
							AccountType         = "UserOrGroup"
							cmdletPropertyName  = "IncludedUsers"
							Location            = "Broker Entitlement Policy Rule: $($result.Name)"
						}
						$null = $InvalidAccountData.Add($obj)
					}
				}
			}
		}
	}
}

Write-Verbose "$(Get-Date): Processing Get-BrokerMachine for Users"
$results = Get-BrokerMachine @CVADParams1

If(!$?)
{
	Write-Error "$(Get-Date): Processing Get-BrokerMachine"
}
ElseIf($? -and $Null -ne $Results)
{
	ForEach($result in $results)
	{
		If($result.AssociatedUserNames.Count -gt 0)
		{
			$tmpusers = $result.AssociatedUserNames
			ForEach($tmpuser in $tmpusers)
			{
				If($tmpuser -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerMachine"
						Account             = $testuser
						AccountType         = "Unknown User or Group: SID"
						cmdletPropertyName  = "AssociatedUserNames"
						Location            = "Machine Name: $($result.MachineName) - Delivery Group Name: $($result.DesktopGroupName)"
					}
					$null = $InvalidAccountData.Add($obj)
				}
				Else
				{
					$tmparray = $tmpuser.Split("\")
					$testuser = $tmparray[1]
					If(!((Test-ValidUserOrGroup $testuser)))
					{
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerMachine"
							Account             = $testuser
							AccountType         = "UserOrGroup"
							cmdletPropertyName  = "AssociatedUserNames"
							Location            = "Machine Name: $($result.MachineName) - Delivery Group Name: $($result.DesktopGroupName)"
						}
						$null = $InvalidAccountData.Add($obj)
					}
				}
			}
		}
	}
}

Write-Verbose "$(Get-Date): Processing Get-BrokerMachine for Computers"
$results = Get-BrokerMachine @CVADParams1

If(!$?)
{
	Write-Error "$(Get-Date): Processing Get-BrokerMachine"
}
ElseIf($? -and $Null -ne $Results)
{
	ForEach($result in $results)
	{
		If($result.MachineName -like "*S-1-*")
		{
			$InvalidAccounts++
			$testcomputer = $result.MachineName
			$obj = [PSCustomObject] @{
				cmdletName          = "Get-BrokerMachine"
				Account             = $testcomputer
				AccountType         = "Unknown Computer: SID"
				cmdletPropertyName  = "MachineName"
				Location            = "Machine Name: $($result.MachineName)"
			}
			$null = $InvalidAccountData.Add($obj)
		}
		Else
		{
			$tmparray = $result.MachineName.Split("\")
			$testcomputer = $tmparray[1]
			If(!(Test-ValidComputer $testcomputer))
			{
				$InvalidAccounts++
				$obj = [PSCustomObject] @{
					cmdletName          = "Get-BrokerMachine"
					Account             = $testcomputer
					AccountType         = "Computer"
					cmdletPropertyName  = "MachineName"
					Location            = "Machine Name: $($result.MachineName) - Delivery Group Name: $($result.DesktopGroupName) - Machine Catalog Name: $($result.CatalogName)"
				}
				$null = $InvalidAccountData.Add($obj)
			}
		}
	}
}

Write-Verbose "$(Get-Date): Processing Get-BrokerSessionLinger"
$results = Get-BrokerSessionLinger @CVADParams1

If(!$?)
{
	Write-Error "$(Get-Date): Processing Get-BrokerSessionLinger"
}
ElseIf($? -and $Null -ne $Results)
{
	ForEach($result in $results)
	{
		If($result.AssociatedUserNames.Count -gt 0)
		{
			$tmpusers = $result.AssociatedUserNames
			ForEach($tmpuser in $tmpusers)
			{
				If($tmpuser -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerSessionLinger"
						Account             = $testuser
						AccountType         = "Unknown User or Group: SID"
						cmdletPropertyName  = "AssociatedUserNames"
						Location            = "Delivery Group Name: $($result.DesktopGroupName)"
					}
					$null = $InvalidAccountData.Add($obj)
				}
				Else
				{
					$tmparray = $tmpuser.Split("\")
					$testuser = $tmparray[1]
					If(!((Test-ValidUserOrGroup $testuser)))
					{
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerSessionLinger"
							Account             = $testuser
							AccountType         = "UserOrGroup"
							cmdletPropertyName  = "AssociatedUserNames"
							Location            = "Delivery Group Name: $($result.DesktopGroupName)"
						}
						$null = $InvalidAccountData.Add($obj)
					}
				}
			}
		}
	}
}

Write-Verbose "$(Get-Date): Processing Get-BrokerSessionPreLaunch"
$results = Get-BrokerSessionPreLaunch @CVADParams1

If(!$?)
{
	Write-Error "$(Get-Date): Processing Get-BrokerSessionPreLaunch"
}
ElseIf($? -and $Null -ne $Results)
{
	ForEach($result in $results)
	{
		If($result.AssociatedUserNames.Count -gt 0)
		{
			$tmpusers = $result.AssociatedUserNames
			ForEach($tmpuser in $tmpusers)
			{
				If($tmpuser -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerSessionPreLaunch"
						Account             = $testuser
						AccountType         = "Unknown User or Group: SID"
						cmdletPropertyName  = "AssociatedUserNames"
						Location            = "Delivery Group Name: $($result.DesktopGroupName)"
					}
					$null = $InvalidAccountData.Add($obj)
				}
				Else
				{
					$tmparray = $tmpuser.Split("\")
					$testuser = $tmparray[1]
					If(!((Test-ValidUserOrGroup $testuser)))
					{
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerSessionPreLaunch"
							Account             = $testuser
							AccountType         = "UserOrGroup"
							cmdletPropertyName  = "AssociatedUserNames"
							Location            = "Delivery Group Name: $($result.DesktopGroupName)"
						}
						$null = $InvalidAccountData.Add($obj)
					}
				}
			}
		}
	}
}

Write-Verbose "$(Get-Date): Processing Get-BrokerUser"
$results = Get-BrokerUser @CVADParams1

If(!$?)
{
	Write-Error "$(Get-Date): Processing Get-BrokerUser"
}
ElseIf($? -and $Null -ne $Results)
{
	ForEach($result in $results)
	{
		If($result.name -like "*S-1-*")
		{
			$InvalidAccounts++
			$testuser = $result.name
			$obj = [PSCustomObject] @{
				cmdletName          = "Get-BrokerUser"
				Account             = $testuser
				AccountType         = "Unknown User or Group: SID"
				cmdletPropertyName  = "Name"
				Location            = "Name: $($result.Name)"
			}
			$null = $InvalidAccountData.Add($obj)
		}
		Else
		{
			$tmparray = $result.name.Split("\")
			$testuser = $tmparray[1]
			If(!((Test-ValidUserOrGroup $testuser)))
			{
				$InvalidAccounts++
				$obj = [PSCustomObject] @{
					cmdletName          = "Get-BrokerUser"
					Account             = $testuser
					AccountType         = "UserOrGroup"
					cmdletPropertyName  = "Name"
					Location            = "Name: $($result.Name)"
				}
				$null = $InvalidAccountData.Add($obj)
			}
		}
	}
}

Write-Verbose "$(Get-Date): "
Write-Verbose "$(Get-Date): There were $InvalidAccounts invalid accounts found"
Write-Verbose "$(Get-Date): "
If($InvalidAccounts -gt 0)
{
	Write-Verbose "$(Get-Date): Exporting $InvalidAccounts invalid accounts to $OutputFile"
	Write-Verbose "$(Get-Date): "
	$InvalidAccountData = $InvalidAccountData | Sort-Object cmdletName,Account

	$InvalidAccountData | Export-CSV -Force -Encoding ASCII -NoTypeInformation -Path $OutputFile *> $Null
}
Else
{
	Write-Verbose "$(Get-Date): Exporting $InvalidAccounts invalid accounts to $OutputFile"
	Write-Verbose "$(Get-Date): "

	$obj = [PSCustomObject] @{
		cmdletName          = "There were $InvalidAccounts invalid accounts found on $(Get-Date)"
		Account             = ""
		AccountType         = ""
		cmdletPropertyName  = ""
		Location            = ""
	}
	$null = $InvalidAccountData.Add($obj)
	$InvalidAccountData | Export-CSV -Force -Encoding ASCII -NoTypeInformation -Path $OutputFile *> $Null
}

Write-Verbose "$(Get-Date): Script started: $($StartTime)"
Write-Verbose "$(Get-Date): Script ended: $(Get-Date)"
$runtime = $(Get-Date) - $StartTime
$Str = [string]::format("{0} days, {1} hours, {2} minutes, {3}.{4} seconds",
	$runtime.Days,
	$runtime.Hours,
	$runtime.Minutes,
	$runtime.Seconds,
	$runtime.Milliseconds)
Write-Verbose "$(Get-Date): Elapsed time: $($Str)"

If($InvalidAccounts -eq 0)
{
	Write-Verbose "$(Get-Date): "
	Write-Verbose "$(Get-Date): If you are still getting Event ID 505 from the Citrix ConfigSync Service,"
	Write-Verbose "$(Get-Date): please follow https://support.citrix.com/article/CTX228758 to rebuild the"
	Write-Verbose "$(Get-Date): Local Host Cache database."
	Write-Verbose "$(Get-Date): "
}
Else
{
	Write-Verbose "$(Get-Date): "
	Write-Verbose "$(Get-Date): After removing any invalid accounts found, please check the application event log"
	Write-Verbose "$(Get-Date): on a DDC to see if you are still getting Event ID 505 from the Citrix ConfigSync Service."
	Write-Verbose "$(Get-Date): If you are, please follow https://support.citrix.com/article/CTX228758"
	Write-Verbose "$(Get-Date): to rebuild the Local Host Cache database."
	Write-Verbose "$(Get-Date): "
}

$InvalidAccountData = $Null
