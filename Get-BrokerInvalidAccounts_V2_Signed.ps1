#Requires -Version 3.0

<#
.SYNOPSIS
	Creates a CVS file of invalid computer and user accounts for a Citrix 
	7.x/18xx/19xx Site.
.DESCRIPTION
	Creates a CSV file of invalid computer and user accounts for a Citrix 
	7.x/18xx/19xx Site.

	Creates a CSV file named SiteName_InvalidAccounts.csv
	
	The CSV file contains a list of all invalid accounts found (User, Group, and 
	Computer).
	
	If no invalid accounts are found, the following line is written to the CSV file:
	"There were 0 invalid accounts found on $(Get-Date)"
	
	This script does not require an elevated PowerShell session.

	This script can be run by a Read-Only Site Administrator to find invalid accounts 
	only.
	Removing invalid accounts requires a Full Site Administrator.
	
	This script supports -Confirm and -WhatIf to make it safer for removing invalid 
	accounts.

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

	Citrix Virtual Apps and Desktops version 7.15 CU4 and 1906 no longer produce the 
	505 error.
.PARAMETER AdminAddress
	Specifies the address of a CVAD controller the PowerShell snapins will connect 
	to. 
	This can be provided as a hostname or an IP address. 
	This parameter defaults to Localhost.
	This parameter has an alias of AA.
.PARAMETER Folder
	Specifies the optional output folder to save the output report. 
.PARAMETER RemoveInvalidAccounts
	Specifies that any invalid account(s) found should be removed.
	
	This parameter defaults to False.
	This parameter has an alis of RIA.
.PARAMETER UpdateNameCache
	Specifies that the Machine and User Broker name caches are updated.
	
	Runs the following cmdlet:
		Update-BrokerNameCache -Machines -Users
		
	Triggers an immediate asynchronous refresh of the name cache.

    The Broker Service maintains a cache of the names of users/groups and 
	machines in use by the site. By default, name information is obtained 
	periodically from Active Directory and the cache refreshed automatically.

    Triggering a cache refresh with this cmdlet ensures up-to-date name 
	information is present in the cache after user/group or machine accounts 
	are known to have changed and you need to see those changes immediately 
	instead of waiting for the periodic automatic refresh.
	
	Using this parameter will turn recently deleted AD accounts into a SID.
	
	The script sleeps for 30 seconds after running Update-BrokerNameCache.

	This parameter defaults to False.
	This parameter has an alias of UNC.
.EXAMPLE
	PS C:\PSScript > .\Get-BrokerInvalidAccounts_V2.ps1
	
	Uses LocalHost for the delivery controller name and places the CSV file in
	the same folder where the script is run.
.EXAMPLE
	PS C:\PSScript > .\Get-BrokerInvalidAccounts_V2.ps1 -AdminAddress DDC01
	
	Uses DDC01 for the delivery controller name and places the CSV file in
	the same folder where the script is run.
.EXAMPLE
	PS C:\PSScript > .\Get-BrokerInvalidAccounts_V2.ps1 -Folder \\ServerName\Share
	
	Uses LocalHost for the delivery controller name and places the CSV file in
	the Share folder on the server ServerName.
.EXAMPLE
	PS C:\PSScript > .\Get-BrokerInvalidAccounts_V2.ps1 -AA DDC01 -Folder 
	\\ServerName\Share
	
	Uses DDC01 for the delivery controller name and places the CSV file in
	the Share folder on the server ServerName.
.EXAMPLE
	PS C:\PSScript > .\Get-BrokerInvalidAccounts_V2.ps1 -UpdateNameCache
	
	Uses LocalHost for the delivery controller name and places the CSV file in
	the same folder where the script is run.

	The Machine and User Broker name caches are updated.
	
	Triggers an immediate asynchronous refresh of the name cache.

	The script sleeps for 30 seconds after running Update-BrokerNameCache.
.EXAMPLE
	PS C:\PSScript > .\Get-BrokerInvalidAccounts_V2.ps1 -AdminAddress DDC01 
	-RemoveInvalidAccounts
	
	Uses DDC01 for the delivery controller name and places the CSV file in
	the same folder where the script is run.
	
	The script will attempt to remove all invalid accounts.
.EXAMPLE
	PS C:\PSScript > .\Get-BrokerInvalidAccounts_V2.ps1 -UpdateNameCache 
	-RemoveInvalidAccounts
	
	Uses LocalHost for the delivery controller name and places the CSV file in
	the same folder where the script is run.

	The Machine and User Broker name caches are updated.
	
	Triggers an immediate asynchronous refresh of the name cache.

	The script sleeps for 30 seconds after running Update-BrokerNameCache.

	After the 30 second wait, the script will attempt to remove all invalid accounts.
.EXAMPLE
	PS C:\PSScript > .\Get-BrokerInvalidAccounts_V2.ps1 -RemoveInvalidAccounts -WhatIf
	
	Uses LocalHost for the delivery controller name.
	
	The script will show what it would have attempted to do if -WhatIf had not been 
	used.
.EXAMPLE
	PS C:\PSScript > .\Get-BrokerInvalidAccounts_V2.ps1 -RemoveInvalidAccounts -Confirm
	
	Uses LocalHost for the delivery controller name and places the CSV file in
	the same folder where the script is run if you answer Yes to the Confirmation 
	prompt.
	
	The script will ask for confirmation before attempting to remove invalid accounts.
.INPUTS
	None.  You cannot pipe objects to this script.
.OUTPUTS
	No objects are output from this script.  This script creates a CSV file.
.NOTES
	NAME: Get-BrokerInvalidAccounts_V2.ps1
	VERSION: 2.00
	AUTHOR: Carl Webster and a lot of code from Michael B. Smith
	LASTEDIT: June 18, 2019
#>

[CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = "Medium", DefaultParameterSetName = "") ]

Param(
	[parameter(Mandatory=$False)] 
	[ValidateNotNullOrEmpty()]
	[Alias("AA")]
	[string]$AdminAddress="Localhost",

	[parameter(Mandatory=$False)] 
	[string]$Folder="",

	[parameter(Mandatory=$False)] 
	[Alias("RIA")]
	[switch]$RemoveInvalidAccounts=$False,

	[parameter(Mandatory=$False)] 
	[Alias("UNC")]
	[switch]$UpdateNameCache=$False

	)

#region script change log	
#webster@carlwebster.com
#@carlwebster on Twitter
#http://www.CarlWebster.com
#Created on May 2, 2019
#
#V2.00 18-Jun-2019
#	Add support for -WhatIf and -Confirm
#	Add switch -RemoveInvalidAccounts
#	Add switch -UpdateNameCache with a 30 second wait
#	At the end of the script, show:
#		Count of unique number of SIDs and account names
#		Count of accounts removed
#		Count of accounts not removed
#
#V1.10 8-Jun-2019
#	Added a line to the final output that shows the number of unique orphaned SIDs or invalid account names found
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
If(!(Check-NeededPSSnapins "Citrix.Broker.Admin.V2",
"Citrix.ConfigurationLogging.Admin.V1"))
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

#get product version
If($AdminAddress -eq "LocalHost")
{
	#changed 18-dec-2016 to allow 32-bit PoSH to get the data in the 64-bit registry location
	#initial idea from WC at Citrix and also from http://stackoverflow.com/questions/630382/how-to-access-the-64-bit-registry-from-a-32-bit-powershell-instance reply from SergVro
	$key = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
	$subKey =  $key.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Citrix Desktop Delivery Controller")
}
Else
{
	$subKey = $Null
}

#if subkey is Null, then check the -AdminAddress computer for the key
If($Null -eq $subkey)
{
	$key = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $AdminAddress)
	$subKey =  $key.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Citrix Desktop Delivery Controller")
	
	If($Null -eq $subkey)
	{
		#something is really wrong
		Write-Verbose "$(Get-Date): Could not find the version information on $($AdminAddress),`n`nScript cannot continue`n "
		Exit
	}
}
Else
{
	Write-Verbose "$(Get-Date): Found the version information on $($env:ComputerName)"
}

$value = $subKey.GetValue("DisplayVersion")
$XDSiteVersion = $value
$tmp = $XDSiteVersion.Split(".")
[int]$MajorVersion = $tmp[0]
[int]$MinorVersion = $tmp[1]
[int]$RevisionVersion = $tmp[2]
[int]$BuildVersion = $tmp[3]

Write-Verbose "$(Get-Date): "
Write-Verbose "$(Get-Date): You are running version $value"
Write-Verbose "$(Get-Date): Major version: $MajorVersion"
Write-Verbose "$(Get-Date): Minor version: $MinorVersion"
Write-Verbose "$(Get-Date): Revision     : $RevisionVersion"
Write-Verbose "$(Get-Date): Build        : $BuildVersion"
Write-Verbose "$(Get-Date): "

#first check to make sure this is a 7.x Site or 1906+ Site
$Display505Msg = $True

If($MajorVersion -ge 1906)
{
	#version 1906 or later
	$Display505Msg = $False
}
ElseIf($MajorVersion -eq 7)
{
	#running CU4 or later?
	If($RevisionVersion -ge 4000)
	{
		$Display505Msg = $False
	}
}

#check if name cache should be updated
If($UpdateNameCache)
{
	Write-Verbose "$(Get-Date): Updating the Machine and User name cache"
	
	Update-BrokerNameCache -Machines -Users @CVADParams2
	
	If(!($?))
	{
		#this is not a problem
		Write-Warning "$(Get-Date): Machine and User name cache could not be updated"
	}
	ElseIf($?)
	{
		Write-Verbose "$(Get-Date): Machine and User name cache successfully updated. Waiting 30 seconds."
		
		Start-Sleep -Seconds 30
	}
}

[int]$InvalidAccounts = 0
[int]$RemovedAccounts = 0
[int]$NotRemovedAccounts = 0
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
				$LogArguments = @{
					Text = "Set-BrokerAccessPolicyRule `-Name $($result.Name) `-RemoveExcludedUsers $($tmpuser.Name)"
					Source = "Get-BrokerInvalidAccounts_V2 Script"
					OperationType = "ConfigurationChange"
					TargetTypes = "AccessPolicyRule"
					AdminAddress = $AdminAddress
				}
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					
					If($RemoveInvalidAccounts)
					{
						$AccountStatus = "Not Removed"
						If($PSCmdlet.ShouldProcess("Set-BrokerAccessPolicyRule -Name $($result.Name)","Remove orphaned SID $($tmpuser.Name)"))
						{
							Try
							{
								$Succeeded = $False #will indicate if the high-level operation was successful

								# Log high-level operation start.
								$HighLevelOp = Start-LogHighLevelOperation @LogArguments
								
								Set-BrokerAccessPolicyRule -Name $result.Name -RemoveExcludedUsers $testuser -LoggingId $HighLevelOp.Id -EA 0		
								
								If($?)
								{
									$Succeeded = $True
									$RemovedAccounts++
									$AccountStatus = "Removed"
									Write-Verbose "$(Get-Date): Removed orphaned SID $($testuser) from BrokerAccessPolicyRule $($result.name)"
								}
							}
							
							Catch
							{
								$NotRemovedAccounts++
								Write-Warning "Unable to remove orphaned SID $($testuser) from BrokerAccessPolicyRule $($result.name)"
							}
							
							Finally
							{
								# Log high-level operation stop, and indicate its success
								Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
							}
						}
					}
					Else
					{
						$AccountStatus = "Not removed"
					}
					
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerAccessPolicyRule"
						Account             = $testuser
						AccountStatus       = $AccountStatus
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
					
						If($RemoveInvalidAccounts)
						{
							$AccountStatus = "Not Removed"
							If($PSCmdlet.ShouldProcess("Set-BrokerAccessPolicyRule -Name $($result.Name)","Remove invalid account $($tmpuser.Name)"))
							{
								Try
								{
									$Succeeded = $False #will indicate if the high-level operation was successful

									# Log high-level operation start.
									$HighLevelOp = Start-LogHighLevelOperation @LogArguments
									
									Set-BrokerAccessPolicyRule -Name $result.Name -RemoveExcludedUsers $tmpuser.Name -LoggingId $HighLevelOp.Id -EA 0		
									
									If($?)
									{
										$Succeeded = $True
										$RemovedAccounts++
										$AccountStatus = "Removed"
										Write-Verbose "$(Get-Date): Removed invalid account $($tmpuser.Name) from BrokerAccessPolicyRule $($result.name)"
									}
								}
								
								Catch
								{
									$NotRemovedAccounts++
									Write-Warning "Unable to remove invalid account $($tmpuser.Name) from BrokerAccessPolicyRule $($result.name)"
								}
								
								Finally
								{
									# Log high-level operation stop, and indicate its success
									Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
								}
							}
						}
						Else
						{
							$AccountStatus = "Not removed"
						}
						
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerAccessPolicyRule"
							Account             = $testuser
							AccountStatus       = $AccountStatus
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
				$LogArguments = @{
					Text = "Set-BrokerAccessPolicyRule `-Name $($result.Name) `-RemoveIncludedUsers $($tmpuser.Name)"
					Source = "Get-BrokerInvalidAccounts_V2 Script"
					OperationType = "ConfigurationChange"
					TargetTypes = "AccessPolicyRule"
					AdminAddress = $AdminAddress
				}
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					
					If($RemoveInvalidAccounts)
					{
						$AccountStatus = "Not removed"
						If($PSCmdlet.ShouldProcess("Set-BrokerAccessPolicyRule -Name $($result.Name)","Remove orphaned SID $($tmpuser.Name)"))
						{
							Try
							{
								$Succeeded = $False #will indicate if the high-level operation was successful

								# Log high-level operation start.
								$HighLevelOp = Start-LogHighLevelOperation @LogArguments
								
								Set-BrokerAccessPolicyRule -Name $result.Name -RemoveIncludedUsers $testuser -LoggingId $HighLevelOp.Id -EA 0		
								
								If($?)
								{
									$Succeeded = $True
									$RemovedAccounts++
									$AccountStatus = "Removed"
									Write-Verbose "$(Get-Date): Removed orphaned SID $($testuser) from BrokerAccessPolicyRule $($result.name)"
								}
							}
							
							Catch
							{
								$NotRemovedAccounts++
								Write-Warning "Unable to remove orphaned SID $($testuser) from BrokerAccessPolicyRule $($result.name)"
							}
							
							Finally
							{
								# Log high-level operation stop, and indicate its success
								Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
							}
						}
					}
					Else
					{
						$AccountStatus = "Not removed"
					}
					
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerAccessPolicyRule"
						Account             = $testuser
						AccountStatus       = $AccountStatus
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
					
						If($RemoveInvalidAccounts)
						{
							$AccountStatus = "Not removed"
							If($PSCmdlet.ShouldProcess("Set-BrokerAccessPolicyRule -Name $($result.Name)","Remove invalid account $($tmpuser.Name)"))
							{
								Try
								{
									$Succeeded = $False #will indicate if the high-level operation was successful

									# Log high-level operation start.
									$HighLevelOp = Start-LogHighLevelOperation @LogArguments
									
									Set-BrokerAccessPolicyRule -Name $result.Name -RemoveIncludedUsers $tmpuser.Name -LoggingId $HighLevelOp.Id -EA 0		
									
									If($?)
									{
										$Succeeded = $True
										$RemovedAccounts++
										$AccountStatus = "Removed"
										Write-Verbose "$(Get-Date): Removed invalid account $($tmpuser.Name) from BrokerAccessPolicyRule $($result.name)"
									}
								}
								
								Catch
								{
									$NotRemovedAccounts++
									Write-Warning "Unable to remove invalid account $($tmpuser.Name) from BrokerAccessPolicyRule $($result.name)"
								}
								
								Finally
								{
									# Log high-level operation stop, and indicate its success
									Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
								}
							}
						}
						Else
						{
							$AccountStatus = "Not removed"
						}
						
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerAccessPolicyRule"
							Account             = $testuser
							AccountStatus       = $AccountStatus
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

If(!($?))
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
				$LogArguments = @{
					Text = "Set-BrokerAppAssignmentPolicyRule `-Name $($result.Name) `-RemoveExcludedUsers $($tmpuser.Name)"
					Source = "Get-BrokerInvalidAccounts_V2 Script"
					OperationType = "ConfigurationChange"
					TargetTypes = "AccessPolicyRule"
					AdminAddress = $AdminAddress
				}
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					
					If($RemoveInvalidAccounts)
					{
						$AccountStatus = "Not removed"
						If($PSCmdlet.ShouldProcess("Set-BrokerAppAssignmentPolicyRule -Name $($result.Name)","Remove orphaned SID $($tmpuser.Name)"))
						{
							Try
							{
								$Succeeded = $False #will indicate if the high-level operation was successful

								# Log high-level operation start.
								$HighLevelOp = Start-LogHighLevelOperation @LogArguments
								
								Set-BrokerAppAssignmentPolicyRule -Name $result.Name -RemoveExcludedUsers $testuser -LoggingId $HighLevelOp.Id -EA 0		
								
								If($?)
								{
									$Succeeded = $True
									$RemovedAccounts++
									$AccountStatus = "Removed"
									Write-Verbose "$(Get-Date): Removed orphaned SID $($testuser) from BrokerAppAssignmentPolicyRule $($result.name)"
								}
							}
							
							Catch
							{
								$NotRemovedAccounts++
								Write-Warning "Unable to remove orphaned SID $($testuser) from BrokerAppAssignmentPolicyRule $($result.name)"
							}
							
							Finally
							{
								# Log high-level operation stop, and indicate its success
								Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
							}
						}
					}
					Else
					{
						$AccountStatus = "Not removed"
					}
					
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerAppAssignmentPolicyRule"
						Account             = $testuser
						AccountStatus       = $AccountStatus
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
					
						If($RemoveInvalidAccounts)
						{
							$AccountStatus = "Not removed"
							If($PSCmdlet.ShouldProcess("Set-BrokerAppAssignmentPolicyRule -Name $($result.Name)","Remove invalid account $($tmpuser.Name)"))
							{
								Try
								{
									$Succeeded = $False #will indicate if the high-level operation was successful
							
									# Log high-level operation start.
									$HighLevelOp = Start-LogHighLevelOperation @LogArguments
									
									Set-BrokerAppAssignmentPolicyRule -Name $result.Name -RemoveExcludedUsers $tmpuser.Name -LoggingId $HighLevelOp.Id -EA 0		
									
									If($?)
									{
										$Succeeded = $True
										$RemovedAccounts++
										$AccountStatus = "Removed"
										Write-Verbose "$(Get-Date): Removed invalid account $($tmpuser.Name) from BrokerAppAssignmentPolicyRule $($result.name)"
									}
								}
								
								Catch
								{
									$NotRemovedAccounts++
									Write-Warning "Unable to remove invalid account $($tmpuser.Name) from BrokerAppAssignmentPolicyRule $($result.name)"
								}
								
								Finally
								{
									# Log high-level operation stop, and indicate its success
									Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
								}
							}
						}
						Else
						{
							$AccountStatus = "Not removed"
						}
						
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerAppAssignmentPolicyRule"
							Account             = $testuser
							AccountStatus       = $AccountStatus
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
				$LogArguments = @{
					Text = "Set-BrokerAppAssignmentPolicyRule `-Name $($result.Name) `-RemoveIncludedUsers $($tmpuser.Name)"
					Source = "Get-BrokerInvalidAccounts_V2 Script"
					OperationType = "ConfigurationChange"
					TargetTypes = "AccessPolicyRule"
					AdminAddress = $AdminAddress
				}
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					
					If($RemoveInvalidAccounts)
					{
						$AccountStatus = "Not removed"
						If($PSCmdlet.ShouldProcess("Set-BrokerAppAssignmentPolicyRule -Name $($result.Name)","Remove orphaned SID $($tmpuser.Name)"))
						{
							Try
							{
								$Succeeded = $False #will indicate if the high-level operation was successful

								# Log high-level operation start.
								$HighLevelOp = Start-LogHighLevelOperation @LogArguments
								
								Set-BrokerAppAssignmentPolicyRule -Name $result.Name -RemoveIncludedUsers $testuser -LoggingId $HighLevelOp.Id -EA 0		
								
								If($?)
								{
									$Succeeded = $True
									$RemovedAccounts++
									$AccountStatus = "Removed"
									Write-Verbose "$(Get-Date): Removed orphaned SID $($testuser) from BrokerAppAssignmentPolicyRule $($result.name)"
								}
							}
							
							Catch
							{
								$NotRemovedAccounts++
								Write-Warning "Unable to remove orphaned SID $($testuser) from BrokerAppAssignmentPolicyRule $($result.name)"
							}
							
							Finally
							{
								# Log high-level operation stop, and indicate its success
								Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
							}
						}
					}
					Else
					{
						$AccountStatus = "Not removed"
					}
					
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerAppAssignmentPolicyRule"
						Account             = $testuser
						AccountStatus       = $AccountStatus
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
					
						If($RemoveInvalidAccounts)
						{
							$AccountStatus = "Not removed"
							If($PSCmdlet.ShouldProcess("Set-BrokerAppAssignmentPolicyRule -Name $($result.Name)","Remove invalid account $($tmpuser.Name)"))
							{
								Try
								{
									$Succeeded = $False #will indicate if the high-level operation was successful
							
									# Log high-level operation start.
									$HighLevelOp = Start-LogHighLevelOperation @LogArguments
									
									Set-BrokerAppAssignmentPolicyRule -Name $result.Name -RemoveIncludedUsers $tmpuser.Name -LoggingId $HighLevelOp.Id -EA 0		
									
									If($?)
									{
										$Succeeded = $True
										$RemovedAccounts++
										$AccountStatus = "Removed"
										Write-Verbose "$(Get-Date): Removed invalid account $($tmpuser.Name) from BrokerAppAssignmentPolicyRule $($result.name)"
									}
								}
								
								Catch
								{
									$NotRemovedAccounts++
									Write-Warning "Unable to remove invalid account $($tmpuser.Name) from BrokerAppAssignmentPolicyRule $($result.name)"
								}
								
								Finally
								{
									# Log high-level operation stop, and indicate its success
									Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
								}
							}
						}
						Else
						{
							$AccountStatus = "Not removed"
						}
						
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerAppAssignmentPolicyRule"
							Account             = $testuser
							AccountStatus       = $AccountStatus
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
				$LogArguments = @{
					Text = "Set-BrokerAppEntitlementPolicyRule `-Name $($result.Name) `-RemoveExcludedUsers $($tmpuser.Name)"
					Source = "Get-BrokerInvalidAccounts_V2 Script"
					OperationType = "ConfigurationChange"
					TargetTypes = "AccessPolicyRule"
					AdminAddress = $AdminAddress
				}
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					
					If($RemoveInvalidAccounts)
					{
						$AccountStatus = "Not removed"
						If($PSCmdlet.ShouldProcess("Set-BrokerAppEntitlementPolicyRule -Name $($result.Name)","Remove orphaned SID $($tmpuser.Name)"))
						{
							Try
							{
								$Succeeded = $False #will indicate if the high-level operation was successful

								# Log high-level operation start.
								$HighLevelOp = Start-LogHighLevelOperation @LogArguments
								
								Set-BrokerAppEntitlementPolicyRule -Name $result.Name -RemoveExcludedUsers $testuser -LoggingId $HighLevelOp.Id -EA 0		
								
								If($?)
								{
									$Succeeded = $True
									$RemovedAccounts++
									$AccountStatus = "Removed"
									Write-Verbose "$(Get-Date): Removed orphaned SID $($testuser) from BrokerAppEntitlementPolicyRule $($result.name)"
								}
							}
							
							Catch
							{
								$NotRemovedAccounts++
								Write-Warning "Unable to remove orphaned SID $($testuser) from BrokerAppEntitlementPolicyRule $($result.name)"
							}
							
							Finally
							{
								# Log high-level operation stop, and indicate its success
								Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
							}
						}
					}
					Else
					{
						$AccountStatus = "Not removed"
					}
					
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerAppEntitlementPolicyRule"
						Account             = $testuser
						AccountStatus       = $AccountStatus
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
					
						If($RemoveInvalidAccounts)
						{
							$AccountStatus = "Not removed"
							If($PSCmdlet.ShouldProcess("Set-BrokerAppEntitlementPolicyRule -Name $($result.Name)","Remove invalid account $($tmpuser.Name)"))
							{
								Try
								{
									$Succeeded = $False #will indicate if the high-level operation was successful

									# Log high-level operation start.
									$HighLevelOp = Start-LogHighLevelOperation @LogArguments
									
									Set-BrokerAppEntitlementPolicyRule -Name $result.Name -RemoveExcludedUsers $tmpuser.Name -LoggingId $HighLevelOp.Id -EA 0		
									
									If($?)
									{
										$Succeeded = $True
										$RemovedAccounts++
										$AccountStatus = "Removed"
										Write-Verbose "$(Get-Date): Removed invalid account $($tmpuser.Name) from BrokerAppEntitlementPolicyRule $($result.name)"
									}
								}
								
								Catch
								{
									$NotRemovedAccounts++
									Write-Warning "Unable to remove invalid account $($tmpuser.Name) from BrokerAppEntitlementPolicyRule $($result.name)"
								}
								
								Finally
								{
									# Log high-level operation stop, and indicate its success
									Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
								}
							}
						}
						Else
						{
							$AccountStatus = "Not removed"
						}
						
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerAppEntitlementPolicyRule"
							Account             = $testuser
							AccountStatus       = $AccountStatus
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
				$LogArguments = @{
					Text = "Set-BrokerAppEntitlementPolicyRule `-Name $($result.Name) `-RemoveIncludedUsers $($tmpuser.Name)"
					Source = "Get-BrokerInvalidAccounts_V2 Script"
					OperationType = "ConfigurationChange"
					TargetTypes = "AccessPolicyRule"
					AdminAddress = $AdminAddress
				}
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					
					If($RemoveInvalidAccounts)
					{
						$AccountStatus = "Not removed"
						If($PSCmdlet.ShouldProcess("Set-BrokerAppEntitlementPolicyRule -Name $($result.Name)","Remove orphaned SID $($tmpuser.Name)"))
						{
							Try
							{
								$Succeeded = $False #will indicate if the high-level operation was successful

								# Log high-level operation start.
								$HighLevelOp = Start-LogHighLevelOperation @LogArguments
								
								Set-BrokerAppEntitlementPolicyRule -Name $result.Name -RemoveIncludedUsers $testuser -LoggingId $HighLevelOp.Id -EA 0		
								
								If($?)
								{
									$Succeeded = $True
									$RemovedAccounts++
									$AccountStatus = "Removed"
									Write-Verbose "$(Get-Date): Removed orphaned SID $($testuser) from BrokerAppEntitlementPolicyRule $($result.name)"
								}
							}
							
							Catch
							{
								$NotRemovedAccounts++
								Write-Warning "Unable to remove orphaned SID $($testuser) from BrokerAppEntitlementPolicyRule $($result.name)"
							}
							
							Finally
							{
								# Log high-level operation stop, and indicate its success
								Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
							}
						}
					}
					Else
					{
						$AccountStatus = "Not removed"
					}
					
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerAppEntitlementPolicyRule"
						Account             = $testuser
						AccountStatus       = $AccountStatus
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
					
						If($RemoveInvalidAccounts)
						{
							$AccountStatus = "Not removed"
							If($PSCmdlet.ShouldProcess("Set-BrokerAppEntitlementPolicyRule -Name $($result.Name)","Remove invalid account $($tmpuser.Name)"))
							{
								Try
								{
									$Succeeded = $False #will indicate if the high-level operation was successful

									# Log high-level operation start.
									$HighLevelOp = Start-LogHighLevelOperation @LogArguments
									
									Set-BrokerAppEntitlementPolicyRule -Name $result.Name -RemoveIncludedUsers $tmpuser.Name -LoggingId $HighLevelOp.Id -EA 0		
									
									If($?)
									{
										$Succeeded = $True
										$RemovedAccounts++
										$AccountStatus = "Removed"
										Write-Verbose "$(Get-Date): Removed invalid account $($tmpuser.Name) from BrokerAppEntitlementPolicyRule $($result.name)"
									}
								}
								
								Catch
								{
									$NotRemovedAccounts++
									Write-Warning "Unable to remove invalid account $($tmpuser.Name) from BrokerAppEntitlementPolicyRule $($result.name)"
								}
								
								Finally
								{
									# Log high-level operation stop, and indicate its success
									Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
								}
							}
						}
						Else
						{
							$AccountStatus = "Not removed"
						}
						
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerAppEntitlementPolicyRule"
							Account             = $testuser
							AccountStatus       = $AccountStatus
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
					
					$LogArguments = @{
						Text = "Remove-BrokerUser `-Name $($tmpuser) `-Application $($result.name)"
						Source = "Get-BrokerInvalidAccounts_V2 Script"
						OperationType = "ConfigurationChange"
						TargetTypes = "BrokerUser"
						AdminAddress = $AdminAddress
					}
					
					If($RemoveInvalidAccounts)
					{
						$AccountStatus = "Not removed"
						If($PSCmdlet.ShouldProcess("Remove-BrokerUser -Application $($result.Name)","Remove orphaned SID $($tmpuser)"))
						{
							Try
							{
								$Succeeded = $False #will indicate if the high-level operation was successful

								# Log high-level operation start.
								$HighLevelOp = Start-LogHighLevelOperation @LogArguments
								
								Remove-BrokerUser -Application $result.Uid -Name $tmpuser -LoggingId $HighLevelOp.Id -EA 0		
								
								If($?)
								{
									$Succeeded = $True
									$RemovedAccounts++
									$AccountStatus = "Removed"
									Write-Verbose "$(Get-Date): Removed orphaned SID $($testuser) from BrokerApplication $($result.name)"
								}
							}
							
							Catch
							{
								$NotRemovedAccounts++
								Write-Warning "Unable to remove orphaned SID $($testuser) from Application $($result.Name)"
							}
							
							Finally
							{
								# Log high-level operation stop, and indicate its success
								Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
							}
						}
					}
					Else
					{
						$AccountStatus = "Not removed"
					}
					
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerApplication"
						Account             = $testuser
						AccountStatus       = $AccountStatus
						AccountType         = "Unknown User or Group: SID"
						cmdletPropertyName  = "Name"
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
					
						$LogArguments = @{
							Text = "Remove-BrokerUser `-Name $($tmpuser) `-Application $($result.name)"
							Source = "Get-BrokerInvalidAccounts_V2 Script"
							OperationType = "ConfigurationChange"
							TargetTypes = "BrokerUser"
							AdminAddress = $AdminAddress
						}
					
						If($RemoveInvalidAccounts)
						{
							$AccountStatus = "Not removed"
							If($PSCmdlet.ShouldProcess("Remove-BrokerUser -Application $($result.Name)","Remove invalid account $($tmpuser)"))
							{
								Try
								{
									$Succeeded = $False #will indicate if the high-level operation was successful

									# Log high-level operation start.
									$HighLevelOp = Start-LogHighLevelOperation @LogArguments
									
									Remove-BrokerUser -Application $result.Uid -Name $tmpuser -LoggingId $HighLevelOp.Id -EA 0		
									
									If($?)
									{
										$Succeeded = $True
										$RemovedAccounts++
										$AccountStatus = "Removed"
										Write-Verbose "$(Get-Date): Removed invalid account $($tmpuser) from BrokerApplication $($result.name)"
									}
								}
								
								Catch
								{
									$NotRemovedAccounts++
									Write-Warning "Unable to remove invalid account $($tmpuser) from Application $($result.Name)"
								}
								
								Finally
								{
									# Log high-level operation stop, and indicate its success
									Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
								}
							}
						}
						Else
						{
							$AccountStatus = "Not removed"
						}
						
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerApplication"
							Account             = $testuser
							AccountStatus       = $AccountStatus
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
					
					$LogArguments = @{
						Text = "Remove-BrokerUser `-Name $($tmpuser) `-ApplicationGroup $($result.Name)"
						Source = "Get-BrokerInvalidAccounts_V2 Script"
						OperationType = "ConfigurationChange"
						TargetTypes = "BrokerUser"
						AdminAddress = $AdminAddress
					}
					
					If($RemoveInvalidAccounts)
					{
						$AccountStatus = "Not removed"
						If($PSCmdlet.ShouldProcess("Remove-BrokerUser -ApplicationGroupo $($result.Name)","Remove orphaned SID $($tmpuser)"))
						{
							Try
							{
								$Succeeded = $False #will indicate if the high-level operation was successful

								# Log high-level operation start.
								$HighLevelOp = Start-LogHighLevelOperation @LogArguments
								
								Remove-BrokerUser -ApplicationGroup $result.Uid -Name $tmpuser -LoggingId $HighLevelOp.Id -EA 0		
								
								If($?)
								{
									$Succeeded = $True
									$RemovedAccounts++
									$AccountStatus = "Removed"
									Write-Verbose "$(Get-Date): Removed orphaned SID $($testuser) from BrokerApplicationGroup $($result.name)"
								}
							}
							
							Catch
							{
								$NotRemovedAccounts++
								Write-Warning "Unable to remove orphaned SID $($testuser) from ApplicationGroup $($result.Name)"
							}
							
							Finally
							{
								# Log high-level operation stop, and indicate its success
								Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
							}
						}
					}
					Else
					{
						$AccountStatus = "Not removed"
					}
					
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerApplicationGroup"
						Account             = $testuser
						AccountStatus       = $AccountStatus
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
					
						$LogArguments = @{
							Text = "Remove-BrokerUser `-Name $($tmpuser) `-ApplicationGroup $($result.Name)"
							Source = "Get-BrokerInvalidAccounts_V2 Script"
							OperationType = "ConfigurationChange"
							TargetTypes = "BrokerUser"
							AdminAddress = $AdminAddress
						}
					
						If($RemoveInvalidAccounts)
						{
							$AccountStatus = "Not removed"
							If($PSCmdlet.ShouldProcess("Remove-BrokerUser -ApplicationGroup $($result.Name)","Remove invalid account $($tmpuser)"))
							{
								Try
								{
									$Succeeded = $False #will indicate if the high-level operation was successful

									# Log high-level operation start.
									$HighLevelOp = Start-LogHighLevelOperation @LogArguments
									
									Remove-BrokerUser -ApplicationGroup $result.Uid -Name $tmpuser -LoggingId $HighLevelOp.Id -EA 0		
									
									If($?)
									{
										$Succeeded = $True
										$RemovedAccounts++
										$AccountStatus = "Removed"
										Write-Verbose "$(Get-Date): Removed invalid account $($tmpuser) from BrokerApplicationGroup $($result.name)"
									}
								}
								
								Catch
								{
									$NotRemovedAccounts++
									Write-Warning "Unable to remove invalid account $($tmpuser) from ApplicationGroup $($result.Name)"
								}
								
								Finally
								{
									# Log high-level operation stop, and indicate its success
									Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
								}
							}
						}
						Else
						{
							$AccountStatus = "Not removed"
						}
						
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerApplicationGroup"
							Account             = $testuser
							AccountStatus       = $AccountStatus
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
				$LogArguments = @{
					Text = "Set-BrokerAssignmentPolicyRule `-Name $($result.Name) `-RemoveExcludedUsers $($tmpuser.Name)"
					Source = "Get-BrokerInvalidAccounts_V2 Script"
					OperationType = "ConfigurationChange"
					TargetTypes = "AccessPolicyRule"
					AdminAddress = $AdminAddress
				}
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					
					If($RemoveInvalidAccounts)
					{
						$AccountStatus = "Not removed"
						If($PSCmdlet.ShouldProcess("Set-BrokerAssignmentPolicyRule -Name $($result.Name)","Remove orphaned SID $($tmpuser.Name)"))
						{
							Try
							{
								$Succeeded = $False #will indicate if the high-level operation was successful

								# Log high-level operation start.
								$HighLevelOp = Start-LogHighLevelOperation @LogArguments
								
								Set-BrokerAssignmentPolicyRule -Name $result.Name -RemoveExcludedUsers $testuser -LoggingId $HighLevelOp.Id -EA 0		
								
								If($?)
								{
									$Succeeded = $True
									$RemovedAccounts++
									$AccountStatus = "Removed"
									Write-Verbose "$(Get-Date): Removed orphaned SID $($testuser) from BrokerAssignmentPolicyRule $($result.name)"
								}
							}
							
							Catch
							{
								$NotRemovedAccounts++
								Write-Warning "Unable to remove orphaned SID $($testuser) from BrokerAssignmentPolicyRule $($result.name)"
							}
							
							Finally
							{
								# Log high-level operation stop, and indicate its success
								Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
							}
						}
					}
					Else
					{
						$AccountStatus = "Not removed"
					}
					
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerAssignmentPolicyRule"
						Account             = $testuser
						AccountStatus       = $AccountStatus
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
					
						If($RemoveInvalidAccounts)
						{
							$AccountStatus = "Not removed"
							If($PSCmdlet.ShouldProcess("Set-BrokerAssignmentPolicyRule -Name $($result.Name)","Remove invalid account $($tmpuser.Name)"))
							{
								Try
								{
									$Succeeded = $False #will indicate if the high-level operation was successful

									# Log high-level operation start.
									$HighLevelOp = Start-LogHighLevelOperation @LogArguments
									
									Set-BrokerAssignmentPolicyRule -Name $result.Name -RemoveExcludedUsers $tmpuser.Name -LoggingId $HighLevelOp.Id -EA 0		
									
									If($?)
									{
										$Succeeded = $True
										$RemovedAccounts++
										$AccountStatus = "Removed"
										Write-Verbose "$(Get-Date): Removed invalid account $($tmpuser.Name) from BrokerAssignmentPolicyRule $($result.name)"
									}
								}
								
								Catch
								{
									$NotRemovedAccounts++
									Write-Warning "Unable to remove invalid account $($tmpuser.Name) from BrokerAssignmentPolicyRule $($result.name)"
								}
								
								Finally
								{
									# Log high-level operation stop, and indicate its success
									Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
								}
							}
						}
						Else
						{
							$AccountStatus = "Not removed"
						}
						
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerAssignmentPolicyRule"
							Account             = $testuser
							AccountStatus       = $AccountStatus
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
				$LogArguments = @{
					Text = "Set-BrokerAssignmentPolicyRule `-Name $($result.Name) `-RemoveIncludedUsers $($tmpuser.Name)"
					Source = "Get-BrokerInvalidAccounts_V2 Script"
					OperationType = "ConfigurationChange"
					TargetTypes = "AccessPolicyRule"
					AdminAddress = $AdminAddress
				}
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					
					If($RemoveInvalidAccounts)
					{
						$AccountStatus = "Not removed"
						If($PSCmdlet.ShouldProcess("Set-BrokerAssignmentPolicyRule -Name $($result.Name)","Remove orphaned SID $($tmpuser.Name)"))
						{
							Try
							{
								$Succeeded = $False #will indicate if the high-level operation was successful

								# Log high-level operation start.
								$HighLevelOp = Start-LogHighLevelOperation @LogArguments
								
								Set-BrokerAssignmentPolicyRule -Name $result.Name -RemoveIncludedUsers $testuser -LoggingId $HighLevelOp.Id -EA 0		
								
								If($?)
								{
									$Succeeded = $True
									$RemovedAccounts++
									$AccountStatus = "Removed"
									Write-Verbose "$(Get-Date): Removed orphaned SID $($testuser) from BrokerAssignmentPolicyRule $($result.name)"
								}
							}
							
							Catch
							{
								$NotRemovedAccounts++
								Write-Warning "Unable to remove orphaned SID $($testuser) from BrokerAssignmentPolicyRule $($result.name)"
							}
							
							Finally
							{
								# Log high-level operation stop, and indicate its success
								Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
							}
						}
					}
					Else
					{
						$AccountStatus = "Not removed"
					}
					
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerAssignmentPolicyRule"
						Account             = $testuser
						AccountStatus       = $AccountStatus
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
					
						If($RemoveInvalidAccounts)
						{
							$AccountStatus = "Not removed"
							If($PSCmdlet.ShouldProcess("Set-BrokerAssignmentPolicyRule -Name $($result.Name)","Remove invalid account $($tmpuser.Name)"))
							{
								Try
								{
									$Succeeded = $False #will indicate if the high-level operation was successful

									# Log high-level operation start.
									$HighLevelOp = Start-LogHighLevelOperation @LogArguments
									
									Set-BrokerAssignmentPolicyRule -Name $result.Name -RemoveIncludedUsers $tmpuser.Name -LoggingId $HighLevelOp.Id -EA 0		
									
									If($?)
									{
										$Succeeded = $True
										$RemovedAccounts++
										$AccountStatus = "Removed"
										Write-Verbose "$(Get-Date): Removed invalid account $($tmpuser.Name) from BrokerAssignmentPolicyRule $($result.name)"
									}
								}
								
								Catch
								{
									$NotRemovedAccounts++
									Write-Warning "Unable to remove invalid account $($tmpuser.Name) from BrokerAssignmentPolicyRule $($result.name)"
								}
								
								Finally
								{
									# Log high-level operation stop, and indicate its success
									Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
								}
							}
						}
						Else
						{
							$AccountStatus = "Not removed"
						}
						
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerAssignmentPolicyRule"
							Account             = $testuser
							AccountStatus       = $AccountStatus
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
				$LogArguments = @{
					Text = "Set-BrokerEntitlementPolicyRule `-Name $($result.Name) `-RemoveExcludedUsers $($tmpuser.Name)"
					Source = "Get-BrokerInvalidAccounts_V2 Script"
					OperationType = "ConfigurationChange"
					TargetTypes = "AccessPolicyRule"
					AdminAddress = $AdminAddress
				}
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					
					If($RemoveInvalidAccounts)
					{
						$AccountStatus = "Not removed"
						If($PSCmdlet.ShouldProcess("Set-BrokerEntitlementPolicyRule -Name $($result.Name)","Remove orphaned SID $($tmpuser.Name)"))
						{
							Try
							{
								$Succeeded = $False #will indicate if the high-level operation was successful

								# Log high-level operation start.
								$HighLevelOp = Start-LogHighLevelOperation @LogArguments
								
								Set-BrokerEntitlementPolicyRule -Name $result.Name -RemoveExcludedUsers $testuser -LoggingId $HighLevelOp.Id -EA 0		
								
								If($?)
								{
									$Succeeded = $True
									$RemovedAccounts++
									$AccountStatus = "Removed"
									Write-Verbose "$(Get-Date): Removed orphaned SID $($testuser) from BrokerEntitlementPolicyRule $($result.name)"
								}
							}
							
							Catch
							{
								$NotRemovedAccounts++
								Write-Warning "Unable to remove orphaned SID $($testuser) from BrokerEntitlementPolicyRule $($result.name)"
							}
							
							Finally
							{
								# Log high-level operation stop, and indicate its success
								Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
							}
						}
					}
					Else
					{
						$AccountStatus = "Not removed"
					}
					
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerEntitlementPolicyRule"
						Account             = $testuser
						AccountStatus       = $AccountStatus
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
					
						If($RemoveInvalidAccounts)
						{
							$AccountStatus = "Not removed"
							If($PSCmdlet.ShouldProcess("Set-BrokerEntitlementPolicyRule -Name $($result.Name)","Remove invalid account $($tmpuser.Name)"))
							{
								Try
								{
									$Succeeded = $False #will indicate if the high-level operation was successful

									# Log high-level operation start.
									$HighLevelOp = Start-LogHighLevelOperation @LogArguments
									
									Set-BrokerEntitlementPolicyRule -Name $result.Name -RemoveExcludedUsers $tmpuser.Name -LoggingId $HighLevelOp.Id -EA 0		
									
									If($?)
									{
										$Succeeded = $True
										$RemovedAccounts++
										$AccountStatus = "Removed"
										Write-Verbose "$(Get-Date): Removed invalid account $($tmpuser.Name) from BrokerEntitlementPolicyRule $($result.name)"
									}
								}
								
								Catch
								{
									$NotRemovedAccounts++
									Write-Warning "Unable to remove invalid account $($tmpuser.Name) from BrokerEntitlementPolicyRule $($result.name)"
								}
								
								Finally
								{
									# Log high-level operation stop, and indicate its success
									Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
								}
							}
						}
						Else
						{
							$AccountStatus = "Not removed"
						}
						
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerEntitlementPolicyRule"
							Account             = $testuser
							AccountStatus       = $AccountStatus
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
				$LogArguments = @{
					Text = "Set-BrokerEntitlementPolicyRule `-Name $($result.Name) `-RemoveIncludedUsers $($tmpuser.Name)"
					Source = "Get-BrokerInvalidAccounts_V2 Script"
					OperationType = "ConfigurationChange"
					TargetTypes = "AccessPolicyRule"
					AdminAddress = $AdminAddress
				}
				If($tmpuser.Name -like "*S-1-*")
				{
					$InvalidAccounts++
					$testuser = $tmpuser.Name
					
					If($RemoveInvalidAccounts)
					{
						$AccountStatus = "Not removed"
						If($PSCmdlet.ShouldProcess("Set-BrokerEntitlementPolicyRule -Name $($result.Name)","Remove orphaned SID $($tmpuser.Name)"))
						{
							Try
							{
								$Succeeded = $False #will indicate if the high-level operation was successful

								# Log high-level operation start.
								$HighLevelOp = Start-LogHighLevelOperation @LogArguments
								
								Set-BrokerEntitlementPolicyRule -Name $result.Name -RemoveIncludedUsers $testuser -LoggingId $HighLevelOp.Id -EA 0		
								
								If($?)
								{
									$Succeeded = $True
									$RemovedAccounts++
									$AccountStatus = "Removed"
									Write-Verbose "$(Get-Date): Removed orphaned SID $($testuser) from BrokerEntitlementPolicyRule $($result.name)"
								}
							}
							
							Catch
							{
								$NotRemovedAccounts++
								Write-Warning "Unable to remove orphaned SID $($testuser) from BrokerEntitlementPolicyRule $($result.name)"
							}
							
							Finally
							{
								# Log high-level operation stop, and indicate its success
								Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
							}
						}
					}
					Else
					{
						$AccountStatus = "Not removed"
					}
					
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerEntitlementPolicyRule"
						Account             = $testuser
						AccountStatus       = $AccountStatus
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
					
						If($RemoveInvalidAccounts)
						{
							$AccountStatus = "Not removed"
							If($PSCmdlet.ShouldProcess("Set-BrokerEntitlementPolicyRule -Name $($result.Name)","Remove invalid account $($tmpuser.Name)"))
							{
								Try
								{
									$Succeeded = $False #will indicate if the high-level operation was successful

									# Log high-level operation start.
									$HighLevelOp = Start-LogHighLevelOperation @LogArguments
									
									Set-BrokerEntitlementPolicyRule -Name $result.Name -RemoveIncludedUsers $tmpuser.Name -LoggingId $HighLevelOp.Id -EA 0		
									
									If($?)
									{
										$Succeeded = $True
										$RemovedAccounts++
										$AccountStatus = "Removed"
										Write-Verbose "$(Get-Date): Removed invalid account $($tmpuser.Name) from BrokerEntitlementPolicyRule $($result.name)"
									}
								}
								
								Catch
								{
									$NotRemovedAccounts++
									Write-Warning "Unable to remove invalid account $($tmpuser.Name) from BrokerEntitlementPolicyRule $($result.name)"
								}
								
								Finally
								{
									# Log high-level operation stop, and indicate its success
									Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
								}
							}
						}
						Else
						{
							$AccountStatus = "Not removed"
						}
						
						$InvalidAccounts++
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerEntitlementPolicyRule"
							Account             = $testuser
							AccountStatus       = $AccountStatus
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
					
					$LogArguments = @{
						Text = "Remove-BrokerUser `-Name $($tmpuser) `-Machine $($result.MachineName)"
						Source = "Get-BrokerInvalidAccounts_V2 Script"
						OperationType = "ConfigurationChange"
						TargetTypes = "BrokerUser"
						AdminAddress = $AdminAddress
					}
					
					If($RemoveInvalidAccounts)
					{
						$AccountStatus = "Not removed"
						If($PSCmdlet.ShouldProcess("Remove-BrokerUser -Machine $($result.MachineName)","Remove orphaned SID $($tmpuser)"))
						{
							Try
							{
								$Succeeded = $False #will indicate if the high-level operation was successful

								# Log high-level operation start.
								$HighLevelOp = Start-LogHighLevelOperation @LogArguments
								
								Remove-BrokerUser -Machine $result.Uid -Name $tmpuser -LoggingId $HighLevelOp.Id -EA 0		
								
								If($?)
								{
									$Succeeded = $True
									$RemovedAccounts++
									$AccountStatus = "Removed"
									Write-Verbose "$(Get-Date): Removed orphaned SID $($testuser) from Machine $($result.MachineName)"
								}
							}
							
							Catch
							{
								$NotRemovedAccounts++
								Write-Warning "Unable to remove orphaned SID $($testuser) from Machine $($result.MachineName)"
							}
							
							Finally
							{
								# Log high-level operation stop, and indicate its success
								Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
							}
						}
					}
					Else
					{
						$AccountStatus = "Not removed"
					}
					
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerMachine"
						Account             = $testuser
						AccountStatus       = $AccountStatus
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
					
						$LogArguments = @{
							Text = "Remove-BrokerUser `-Name $($tmpuser) `-Machine $($result.MachineName)"
							Source = "Get-BrokerInvalidAccounts_V2 Script"
							OperationType = "ConfigurationChange"
							TargetTypes = "BrokerUser"
							AdminAddress = $AdminAddress
						}
					
						If($RemoveInvalidAccounts)
						{
							$AccountStatus = "Not removed"
							If($PSCmdlet.ShouldProcess("Remove-BrokerUser -Machine $($result.MachineName)","Remove invalid account $($tmpuser)"))
							{
								Try
								{
									$Succeeded = $False #will indicate if the high-level operation was successful

									# Log high-level operation start.
									$HighLevelOp = Start-LogHighLevelOperation @LogArguments
									
									Remove-BrokerUser -Machine $result.Uid -Name $tmpuser -LoggingId $HighLevelOp.Id -EA 0		
									
									If($?)
									{
										$Succeeded = $True
										$RemovedAccounts++
										$AccountStatus = "Removed"
										Write-Verbose "$(Get-Date): Removed invalid account $($tmpuser) from Machine $($result.MachineName)"
									}
								}
								
								Catch
								{
									$NotRemovedAccounts++
									Write-Warning "Unable to remove invalid account $($tmpuser) from Machine $($result.MachineName)"
								}
								
								Finally
								{
									# Log high-level operation stop, and indicate its success
									Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
								}
							}
						}
						Else
						{
							$AccountStatus = "Not removed"
						}
						
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerMachine"
							Account             = $testuser
							AccountStatus       = $AccountStatus
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
		$LogArguments = @{
			Text = "Remove-BrokerMachine `-MachineName $($result.MachineName)"
			Source = "Get-BrokerInvalidAccounts_V2 Script"
			OperationType = "ConfigurationChange"
			TargetTypes = "AccessPolicyRule"
			AdminAddress = $AdminAddress
		}
		If($result.MachineName -like "*S-1-*")
		{
			$InvalidAccounts++
			$testcomputer = $result.MachineName
					
			If($RemoveInvalidAccounts)
			{
				If(![String]::IsNullOrEmpty($result.DesktopGroupName))
				{
					$AccountStatus = "Not removed"
					If($PSCmdlet.ShouldProcess("Remove-BrokerMachine -Name $($result.MachineName) -DesktopGroup $($result.DesktopGroupName)","Remove orphaned SID $($result.MachineName)"))
					{
						Try
						{
							$Succeeded = $False #will indicate if the high-level operation was successful

							# Log high-level operation start.
							$HighLevelOp = Start-LogHighLevelOperation @LogArguments
							
							Remove-BrokerMachine -MachineName $result.MachineName -DesktopGroup $result.DesktopGroupName -LoggingId $HighLevelOp.Id -EA 0		
							
							If($?)
							{
								$Succeeded = $True
								$RemovedAccounts++
								$AccountStatus = "Removed"
								Write-Verbose "$(Get-Date): Removed orphaned SID $($result.MachineName) from Remove-BrokerMachine $($result.MachineName) and DesktopGroup $($result.DesktopGroupName)"
							}
						}
						
						Catch
						{
							$NotRemovedAccounts++
							Write-Warning "Unable to remove orphaned SID $($result.MachineName) from Remove-BrokerMachine $($result.MachineName) and DesktopGroup $($result.DesktopGroupName)"
						}
						
						Finally
						{
							# Log high-level operation stop, and indicate its success
							Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
						}
					}
				}
				Else
				{
					$AccountStatus = "Not removed"
					If($PSCmdlet.ShouldProcess("Remove-BrokerMachine -Name $($result.MachineName)","Remove orphaned SID $($result.MachineName)"))
					{
						Try
						{
							$Succeeded = $False #will indicate if the high-level operation was successful

							# Log high-level operation start.
							$HighLevelOp = Start-LogHighLevelOperation @LogArguments
							
							Remove-BrokerMachine -MachineName $result.MachineName -LoggingId $HighLevelOp.Id -EA 0		
							
							If($?)
							{
								$Succeeded = $True
								$RemovedAccounts++
								$AccountStatus = "Removed"
								Write-Verbose "$(Get-Date): Removed orphaned SID $($result.MachineName) from Remove-BrokerMachine $($result.MachineName)"
							}
						}
						
						Catch
						{
							$NotRemovedAccounts++
							Write-Warning "Unable to remove orphaned SID $($result.MachineName) from Remove-BrokerMachine $($result.MachineName)"
						}
						
						Finally
						{
							# Log high-level operation stop, and indicate its success
							Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
						}
					}
				}
			}
			Else
			{
				$AccountStatus = "Not removed"
			}
			
			$obj = [PSCustomObject] @{
				cmdletName          = "Get-BrokerMachine"
				Account             = $testcomputer
				AccountStatus       = $AccountStatus
				AccountType         = "Unknown Computer: SID"
				cmdletPropertyName  = "MachineName"
				Location            = "Machine Name: $($result.MachineName) - Delivery Group Name: $($result.DesktopGroupName) - Machine Catalog Name: $($result.CatalogName)"
			}
			$null = $InvalidAccountData.Add($obj)
		}
		Else
		{
			$tmparray = $result.MachineName.Split("\")
			$testcomputer = $tmparray[1]
			If(!(Test-ValidComputer $testcomputer))
			{
				If($RemoveInvalidAccounts)
				{
					If(![String]::IsNullOrEmpty($result.DesktopGroupName))
					{
						$AccountStatus = "Not removed"
						If($PSCmdlet.ShouldProcess("Remove-BrokerMachine -Name $($result.MachineName) -DesktopGroup $($result.DesktopGroupName)","Remove invalid account $($result.MachineName)"))
						{
							Try
							{
								$Succeeded = $False #will indicate if the high-level operation was successful

								# Log high-level operation start.
								$HighLevelOp = Start-LogHighLevelOperation @LogArguments
								
								Remove-BrokerMachine -MachineName $result.MachineName -DesktopGroup $result.DesktopGroupName -LoggingId $HighLevelOp.Id -EA 0		
								
								If($?)
								{
									$Succeeded = $True
									$RemovedAccounts++
									$AccountStatus = "Removed"
									Write-Verbose "$(Get-Date): Removed invalid account $($result.MachineName) from Remove-BrokerMachine $($result.MachineName) and DesktopGroup $($result.DesktopGroupName)"
								}
							}
							
							Catch
							{
								$NotRemovedAccounts++
								Write-Warning "Unable to remove invalid account $($result.MachineName) from Remove-BrokerMachine $($result.MachineName) and DesktopGroup $($result.DesktopGroupName)"
							}
							
							Finally
							{
								# Log high-level operation stop, and indicate its success
								Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
							}
						}
					}
					Else
					{
						$AccountStatus = "Not removed"
						If($PSCmdlet.ShouldProcess("Remove-BrokerMachine -Name $($result.MachineName)","Remove invalid account $($result.MachineName)"))
						{
							Try
							{
								$Succeeded = $False #will indicate if the high-level operation was successful

								# Log high-level operation start.
								$HighLevelOp = Start-LogHighLevelOperation @LogArguments
								
								Remove-BrokerMachine -MachineName $result.MachineName -LoggingId $HighLevelOp.Id -EA 0		
								
								If($?)
								{
									$Succeeded = $True
									$RemovedAccounts++
									$AccountStatus = "Removed"
									Write-Verbose "$(Get-Date): Removed invalid account $($result.MachineName) from Remove-BrokerMachine $($result.MachineName)"
								}
							}
							
							Catch
							{
								$NotRemovedAccounts++
								Write-Warning "Unable to remove invalid account $($result.MachineName) from Remove-BrokerMachine $($result.MachineName)"
							}
							
							Finally
							{
								# Log high-level operation stop, and indicate its success
								Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
							}
						}
					}
				}
				Else
				{
					$AccountStatus = "Not removed"
				}
				
				$InvalidAccounts++
				$obj = [PSCustomObject] @{
					cmdletName          = "Get-BrokerMachine"
					Account             = $testcomputer
					AccountStatus       = $AccountStatus
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
					
					$LogArguments = @{
						Text = "Remove-BrokerUser `-Name $($tmpuser) `-SessionLinger $($result.DesktopGroupName)"
						Source = "Get-BrokerInvalidAccounts_V2 Script"
						OperationType = "ConfigurationChange"
						TargetTypes = "BrokerUser"
						AdminAddress = $AdminAddress
					}
					
					If($RemoveInvalidAccounts)
					{
						$AccountStatus = "Not removed"
						If($PSCmdlet.ShouldProcess("Remove-BrokerUser -SessionLinger $($result.DesktopGroupName)","Remove orphaned SID $($tmpuser)"))
						{
							Try
							{
								$Succeeded = $False #will indicate if the high-level operation was successful

								# Log high-level operation start.
								$HighLevelOp = Start-LogHighLevelOperation @LogArguments
								
								Remove-BrokerUser -SessionLinger $result.DesktopGroupUid -Name $tmpuser -LoggingId $HighLevelOp.Id -EA 0		
								
								If($?)
								{
									$Succeeded = $True
									$RemovedAccounts++
									$AccountStatus = "Removed"
									Write-Verbose "$(Get-Date): Removed orphaned SID $($testuser) from SessionLinger $($result.DesktopGroupName)"
								}
							}
							
							Catch
							{
								$NotRemovedAccounts++
								Write-Warning "Unable to remove orphaned SID $($testuser) from SessionLinger $($result.DesktopGroupName)"
							}
							
							Finally
							{
								# Log high-level operation stop, and indicate its success
								Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
							}
						}
					}
					Else
					{
						$AccountStatus = "Not removed"
					}
					
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerSessionLinger"
						Account             = $testuser
						AccountStatus       = $AccountStatus
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
					
						$LogArguments = @{
							Text = "Remove-BrokerUser `-Name $($tmpuser) `-SessionLinger $($result.DesktopGroupName)"
							Source = "Get-BrokerInvalidAccounts_V2 Script"
							OperationType = "ConfigurationChange"
							TargetTypes = "BrokerUser"
							AdminAddress = $AdminAddress
						}
						
						If($RemoveInvalidAccounts)
						{
							$AccountStatus = "Not removed"
							If($PSCmdlet.ShouldProcess("Remove-BrokerUser -SessionLinger $($result.DesktopGroupName)","Remove invalid account $($tmpuser)"))
							{
								Try
								{
									$Succeeded = $False #will indicate if the high-level operation was successful

									# Log high-level operation start.
									$HighLevelOp = Start-LogHighLevelOperation @LogArguments
									
									Remove-BrokerUser -SessionLinger $result.DesktopGroupUid -Name $tmpuser -LoggingId $HighLevelOp.Id -EA 0		
									
									If($?)
									{
										$Succeeded = $True
										$RemovedAccounts++
										$AccountStatus = "Removed"
										Write-Verbose "$(Get-Date): Removed invalid account $($tmpuser) from SessionLinger $($result.DesktopGroupName)"
									}
								}
								
								Catch
								{
									$NotRemovedAccounts++
									Write-Warning "Unable to remove invalid account $($tmpuser) from SessionLinger $($result.DesktopGroupName)"
								}
								
								Finally
								{
									# Log high-level operation stop, and indicate its success
									Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
								}
							}
						}
						Else
						{
							$AccountStatus = "Not removed"
						}
					
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerSessionLinger"
							Account             = $testuser
							AccountStatus       = $AccountStatus
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
					
					$LogArguments = @{
						Text = "Remove-BrokerUser `-Name $($tmpuser) `-SessionPrelaunch $($result.DesktopGroupName)"
						Source = "Get-BrokerInvalidAccounts_V2 Script"
						OperationType = "ConfigurationChange"
						TargetTypes = "BrokerUser"
						AdminAddress = $AdminAddress
					}
					
					If($RemoveInvalidAccounts)
					{
						$AccountStatus = "Not removed"
						If($PSCmdlet.ShouldProcess("Remove-BrokerUser -SessionPrelaunch $($result.DesktopGroupName)","Remove orphaned SID $($tmpuser)"))
						{
							Try
							{
								$Succeeded = $False #will indicate if the high-level operation was successful

								# Log high-level operation start.
								$HighLevelOp = Start-LogHighLevelOperation @LogArguments
								
								Remove-BrokerUser -SessionPrelaunch $result.DesktopGroupUid -Name $tmpuser -LoggingId $HighLevelOp.Id -EA 0		
								
								If($?)
								{
									$Succeeded = $True
									$RemovedAccounts++
									$AccountStatus = "Removed"
									Write-Verbose "$(Get-Date): Removed orphaned SID $($testuser) from SessionPrelaunch $($result.DesktopGroupName)"
								}
							}
							
							Catch
							{
								$NotRemovedAccounts++
								Write-Warning "Unable to remove orphaned SID $($testuser) from SessionPrelaunch $($result.DesktopGroupName)"
							}
							
							Finally
							{
								# Log high-level operation stop, and indicate its success
								Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
							}
						}
					}
					Else
					{
						$AccountStatus = "Not removed"
					}
					
					$obj = [PSCustomObject] @{
						cmdletName          = "Get-BrokerSessionPreLaunch"
						Account             = $testuser
						AccountStatus       = $AccountStatus
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
					
						$LogArguments = @{
							Text = "Remove-BrokerUser `-Name $($tmpuser) `-SessionPrelaunch $($result.DesktopGroupName)"
							Source = "Get-BrokerInvalidAccounts_V2 Script"
							OperationType = "ConfigurationChange"
							TargetTypes = "BrokerUser"
							AdminAddress = $AdminAddress
						}
						
						If($RemoveInvalidAccounts)
						{
							$AccountStatus = "Not removed"
							If($PSCmdlet.ShouldProcess("Remove-BrokerUser -SessionPrelaunch $($result.DesktopGroupName)","Remove invalid account $($tmpuser)"))
							{
								Try
								{
									$Succeeded = $False #will indicate if the high-level operation was successful

									# Log high-level operation start.
									$HighLevelOp = Start-LogHighLevelOperation @LogArguments
									
									Remove-BrokerUser -SessionPrelaunch $result.DesktopGroupUid -Name $tmpuser -LoggingId $HighLevelOp.Id -EA 0		
									
									If($?)
									{
										$Succeeded = $True
										$RemovedAccounts++
										$AccountStatus = "Removed"
										Write-Verbose "$(Get-Date): Removed invalid account $($tmpuser) from SessionPrelaunch $($result.DesktopGroupName)"
									}
								}
								
								Catch
								{
									$NotRemovedAccounts++
									Write-Warning "Unable to remove invalid account $($tmpuser) from SessionPrelaunch $($result.DesktopGroupName)"
								}
								
								Finally
								{
									# Log high-level operation stop, and indicate its success
									Stop-LogHighLevelOperation -HighLevelOperationId $HighLevelOp.Id -IsSuccessful $Succeeded
								}
							}
						}
						Else
						{
							$AccountStatus = "Not removed"
						}
					
						$obj = [PSCustomObject] @{
							cmdletName          = "Get-BrokerSessionPreLaunch"
							Account             = $testuser
							AccountStatus       = $AccountStatus
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

#if $RemoveInvalidAccounts was used, there should be no accounts found here
If($RemoveInvalidAccounts)
{
	[int]$BrokerUserInvalidAccounts = 0
}

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
			If($RemoveInvalidAccounts)
			{
				$BrokerUserInvalidAccounts++
			}
			$InvalidAccounts++
			$testuser = $result.name
			$obj = [PSCustomObject] @{
				cmdletName          = "Get-BrokerUser"
				Account             = $testuser
				AccountStatus       = $AccountStatus
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
				If($RemoveInvalidAccounts)
				{
					$BrokerUserInvalidAccounts++
				}
				$InvalidAccounts++
				$obj = [PSCustomObject] @{
					cmdletName          = "Get-BrokerUser"
					Account             = $testuser
					AccountStatus       = $AccountStatus
					AccountType         = "UserOrGroup"
					cmdletPropertyName  = "Name"
					Location            = "Name: $($result.Name)"
				}
				$null = $InvalidAccountData.Add($obj)
			}
		}
	}
}

If($RemoveInvalidAccounts -and $BrokerUserInvalidAccounts -gt 0)
{
	#we should not be here
	#as the script removed accounts from all the various locations; the "BrokerUser" accounts should have also been removed
	Write-Verbose "$(Get-Date): "
	Write-Verbose "$(Get-Date): OOPS, something wrong has happened. You shouldn't see this message."
	Write-Verbose "$(Get-Date): There are still $BrokerUserInvalidAccounts invalid Get-BrokerUser accounts found."
	Write-Verbose "$(Get-Date): "
	Write-Verbose "$(Get-Date): Try rerunning the script with the UpdateNameCache switch."
	Write-Verbose "$(Get-Date): "
}

Write-Verbose "$(Get-Date): "
Write-Verbose "$(Get-Date): There were $InvalidAccounts invalid accounts found"
Write-Verbose "$(Get-Date): "
If($InvalidAccounts -gt 0)
{
	$UniqueInvalidAccounts = $InvalidAccountData | Sort-Object Account -Unique
	
	$UniqueInvalidAccountsCnt = $UniqueInvalidAccounts.Count
	
	Write-Verbose "$(Get-Date): There were $UniqueInvalidAccountsCnt unique orphaned SIDs or invalid account names found"
	Write-Verbose "$(Get-Date): "
	Write-Verbose "$(Get-Date): There were $RemovedAccounts invalid accounts removed"
	Write-Verbose "$(Get-Date): "
	Write-Verbose "$(Get-Date): There were $NotRemovedAccounts invalid accounts not removed"
	Write-Verbose "$(Get-Date): "
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

If($Display505Msg)
{
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
}

$InvalidAccountData = $Null

# SIG # Begin signature block
# MIIf8QYJKoZIhvcNAQcCoIIf4jCCH94CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUl9lrXbEPNz4RPKKk6LzOcSeS
# 9JSgghtYMIIDtzCCAp+gAwIBAgIQDOfg5RfYRv6P5WD8G/AwOTANBgkqhkiG9w0B
# AQUFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVk
# IElEIFJvb3QgQ0EwHhcNMDYxMTEwMDAwMDAwWhcNMzExMTEwMDAwMDAwWjBlMQsw
# CQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cu
# ZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3Qg
# Q0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCtDhXO5EOAXLGH87dg
# +XESpa7cJpSIqvTO9SA5KFhgDPiA2qkVlTJhPLWxKISKityfCgyDF3qPkKyK53lT
# XDGEKvYPmDI2dsze3Tyoou9q+yHyUmHfnyDXH+Kx2f4YZNISW1/5WBg1vEfNoTb5
# a3/UsDg+wRvDjDPZ2C8Y/igPs6eD1sNuRMBhNZYW/lmci3Zt1/GiSw0r/wty2p5g
# 0I6QNcZ4VYcgoc/lbQrISXwxmDNsIumH0DJaoroTghHtORedmTpyoeb6pNnVFzF1
# roV9Iq4/AUaG9ih5yLHa5FcXxH4cDrC0kqZWs72yl+2qp/C3xag/lRbQ/6GW6whf
# GHdPAgMBAAGjYzBhMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB0G
# A1UdDgQWBBRF66Kv9JLLgjEtUYunpyGd823IDzAfBgNVHSMEGDAWgBRF66Kv9JLL
# gjEtUYunpyGd823IDzANBgkqhkiG9w0BAQUFAAOCAQEAog683+Lt8ONyc3pklL/3
# cmbYMuRCdWKuh+vy1dneVrOfzM4UKLkNl2BcEkxY5NM9g0lFWJc1aRqoR+pWxnmr
# EthngYTffwk8lOa4JiwgvT2zKIn3X/8i4peEH+ll74fg38FnSbNd67IJKusm7Xi+
# fT8r87cmNW1fiQG2SVufAQWbqz0lwcy2f8Lxb4bG+mRo64EtlOtCt/qMHt1i8b5Q
# Z7dsvfPxH2sMNgcWfzd8qVttevESRmCD1ycEvkvOl77DZypoEd+A5wwzZr8TDRRu
# 838fYxAe+o0bJW1sj6W3YQGx0qMmoRBxna3iw/nDmVG3KwcIzi7mULKn+gpFL6Lw
# 8jCCBSYwggQOoAMCAQICEAZY+tvHeDVvdG/HsafuSKwwDQYJKoZIhvcNAQELBQAw
# cjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQ
# d3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVk
# IElEIENvZGUgU2lnbmluZyBDQTAeFw0xOTEwMTUwMDAwMDBaFw0yMDEyMDQxMjAw
# MDBaMGMxCzAJBgNVBAYTAlVTMRIwEAYDVQQIEwlUZW5uZXNzZWUxEjAQBgNVBAcT
# CVR1bGxhaG9tYTEVMBMGA1UEChMMQ2FybCBXZWJzdGVyMRUwEwYDVQQDEwxDYXJs
# IFdlYnN0ZXIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDCib5DeGTG
# 3J70a2CA8i9n+dPsDklvWpkUTAuZesMTdgYYYKJTsaaNY/UEAHlJukWzaoFQUJc8
# cf5mUa48zGHKjIsFRJtv1YjaeoJzdLBWiqSaI6m3Ttkj8YqvAVj7U3wDNc30gWgU
# eJwPQs2+Ge6tVHRx7/Knzu12RkJ/fEUwoqwHyL5ezfBHfIf3AiukAxRMKrsqGMPI
# 20y/mc8oiwTuyCG9vieR9+V+iq+ATGgxxb+TOzRoxyFsYOcqnGv3iHqNr74y+rfC
# /HfkieCRmkwh0ss4EVnKIJMefWIlkH3HPirYn+4wmeTKQZmtIq0oEbJlXsSryOXW
# i/NjGfe2xXENAgMBAAGjggHFMIIBwTAfBgNVHSMEGDAWgBRaxLl7KgqjpepxA8Bg
# +S32ZXUOWDAdBgNVHQ4EFgQUqRd4UyWyhbxwBUPJhcJf/q5IdaQwDgYDVR0PAQH/
# BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMHcGA1UdHwRwMG4wNaAzoDGGL2h0
# dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9zaGEyLWFzc3VyZWQtY3MtZzEuY3JsMDWg
# M6Axhi9odHRwOi8vY3JsNC5kaWdpY2VydC5jb20vc2hhMi1hc3N1cmVkLWNzLWcx
# LmNybDBMBgNVHSAERTBDMDcGCWCGSAGG/WwDATAqMCgGCCsGAQUFBwIBFhxodHRw
# czovL3d3dy5kaWdpY2VydC5jb20vQ1BTMAgGBmeBDAEEATCBhAYIKwYBBQUHAQEE
# eDB2MCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wTgYIKwYB
# BQUHMAKGQmh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFNIQTJB
# c3N1cmVkSURDb2RlU2lnbmluZ0NBLmNydDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3
# DQEBCwUAA4IBAQBMkLEdY3RRV97ghwUHUZlBdZ9dFFjBx6WB3rAGTeS2UaGlZuwj
# 2zigbOf8TAJGXiT4pBIZ17X01rpbopIeGGW6pNEUIQQlqaXHQUsY8kbjwVVSdQki
# c1ZwNJoGdgsE50yxPYq687+LR1rgViKuhkTN79ffM5kuqofxoGByxgbinRbC3PQp
# H3U6c1UhBRYAku/l7ev0dFvibUlRgV4B6RjQBylZ09+rcXeT+GKib13Ma6bjcKTq
# qsf9PgQ6P5/JNnWdy19r10SFlsReHElnnSJeRLAptk9P7CRU5/cMkI7CYAR0GWdn
# e1/Kdz6FwvSJl0DYr1p0utdyLRVpgHKG30bTMIIFMDCCBBigAwIBAgIQBAkYG1/V
# u2Z1U0O1b5VQCDANBgkqhkiG9w0BAQsFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UE
# ChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYD
# VQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMTMxMDIyMTIwMDAw
# WhcNMjgxMDIyMTIwMDAwWjByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNl
# cnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdp
# Q2VydCBTSEEyIEFzc3VyZWQgSUQgQ29kZSBTaWduaW5nIENBMIIBIjANBgkqhkiG
# 9w0BAQEFAAOCAQ8AMIIBCgKCAQEA+NOzHH8OEa9ndwfTCzFJGc/Q+0WZsTrbRPV/
# 5aid2zLXcep2nQUut4/6kkPApfmJ1DcZ17aq8JyGpdglrA55KDp+6dFn08b7KSfH
# 03sjlOSRI5aQd4L5oYQjZhJUM1B0sSgmuyRpwsJS8hRniolF1C2ho+mILCCVrhxK
# hwjfDPXiTWAYvqrEsq5wMWYzcT6scKKrzn/pfMuSoeU7MRzP6vIK5Fe7SrXpdOYr
# /mzLfnQ5Ng2Q7+S1TqSp6moKq4TzrGdOtcT3jNEgJSPrCGQ+UpbB8g8S9MWOD8Gi
# 6CxR93O8vYWxYoNzQYIH5DiLanMg0A9kczyen6Yzqf0Z3yWT0QIDAQABo4IBzTCC
# AckwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAww
# CgYIKwYBBQUHAwMweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8v
# b2NzcC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRp
# Z2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwgYEGA1UdHwR6
# MHgwOqA4oDaGNGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3Vy
# ZWRJRFJvb3RDQS5jcmwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9E
# aWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwTwYDVR0gBEgwRjA4BgpghkgBhv1s
# AAIEMCowKAYIKwYBBQUHAgEWHGh0dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMw
# CgYIYIZIAYb9bAMwHQYDVR0OBBYEFFrEuXsqCqOl6nEDwGD5LfZldQ5YMB8GA1Ud
# IwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgPMA0GCSqGSIb3DQEBCwUAA4IBAQA+
# 7A1aJLPzItEVyCx8JSl2qB1dHC06GsTvMGHXfgtg/cM9D8Svi/3vKt8gVTew4fbR
# knUPUbRupY5a4l4kgU4QpO4/cY5jDhNLrddfRHnzNhQGivecRk5c/5CxGwcOkRX7
# uq+1UcKNJK4kxscnKqEpKBo6cSgCPC6Ro8AlEeKcFEehemhor5unXCBc2XGxDI+7
# qPjFEmifz0DLQESlE/DmZAwlCEIysjaKJAL+L3J+HNdJRZboWR3p+nRka7LrZkPa
# s7CM1ekN3fYBIM6ZMWM9CBoYs4GbT8aTEAb8B4H6i9r5gkn3Ym6hU/oSlBiFLpKR
# 6mhsRDKyZqHnGKSaZFHvMIIGajCCBVKgAwIBAgIQAwGaAjr/WLFr1tXq5hfwZjAN
# BgkqhkiG9w0BAQUFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQg
# SW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2Vy
# dCBBc3N1cmVkIElEIENBLTEwHhcNMTQxMDIyMDAwMDAwWhcNMjQxMDIyMDAwMDAw
# WjBHMQswCQYDVQQGEwJVUzERMA8GA1UEChMIRGlnaUNlcnQxJTAjBgNVBAMTHERp
# Z2lDZXJ0IFRpbWVzdGFtcCBSZXNwb25kZXIwggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQCjZF38fLPggjXg4PbGKuZJdTvMbuBTqZ8fZFnmfGt/a4ydVfiS
# 457VWmNbAklQ2YPOb2bu3cuF6V+l+dSHdIhEOxnJ5fWRn8YUOawk6qhLLJGJzF4o
# 9GS2ULf1ErNzlgpno75hn67z/RJ4dQ6mWxT9RSOOhkRVfRiGBYxVh3lIRvfKDo2n
# 3k5f4qi2LVkCYYhhchhoubh87ubnNC8xd4EwH7s2AY3vJ+P3mvBMMWSN4+v6GYeo
# fs/sjAw2W3rBerh4x8kGLkYQyI3oBGDbvHN0+k7Y/qpA8bLOcEaD6dpAoVk62RUJ
# V5lWMJPzyWHM0AjMa+xiQpGsAsDvpPCJEY93AgMBAAGjggM1MIIDMTAOBgNVHQ8B
# Af8EBAMCB4AwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDCC
# Ab8GA1UdIASCAbYwggGyMIIBoQYJYIZIAYb9bAcBMIIBkjAoBggrBgEFBQcCARYc
# aHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzCCAWQGCCsGAQUFBwICMIIBVh6C
# AVIAQQBuAHkAIAB1AHMAZQAgAG8AZgAgAHQAaABpAHMAIABDAGUAcgB0AGkAZgBp
# AGMAYQB0AGUAIABjAG8AbgBzAHQAaQB0AHUAdABlAHMAIABhAGMAYwBlAHAAdABh
# AG4AYwBlACAAbwBmACAAdABoAGUAIABEAGkAZwBpAEMAZQByAHQAIABDAFAALwBD
# AFAAUwAgAGEAbgBkACAAdABoAGUAIABSAGUAbAB5AGkAbgBnACAAUABhAHIAdAB5
# ACAAQQBnAHIAZQBlAG0AZQBuAHQAIAB3AGgAaQBjAGgAIABsAGkAbQBpAHQAIABs
# AGkAYQBiAGkAbABpAHQAeQAgAGEAbgBkACAAYQByAGUAIABpAG4AYwBvAHIAcABv
# AHIAYQB0AGUAZAAgAGgAZQByAGUAaQBuACAAYgB5ACAAcgBlAGYAZQByAGUAbgBj
# AGUALjALBglghkgBhv1sAxUwHwYDVR0jBBgwFoAUFQASKxOYspkH7R7for5XDStn
# As0wHQYDVR0OBBYEFGFaTSS2STKdSip5GoNL9B6Jwcp9MH0GA1UdHwR2MHQwOKA2
# oDSGMmh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRENB
# LTEuY3JsMDigNqA0hjJodHRwOi8vY3JsNC5kaWdpY2VydC5jb20vRGlnaUNlcnRB
# c3N1cmVkSURDQS0xLmNybDB3BggrBgEFBQcBAQRrMGkwJAYIKwYBBQUHMAGGGGh0
# dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0cDovL2NhY2Vy
# dHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEQ0EtMS5jcnQwDQYJKoZI
# hvcNAQEFBQADggEBAJ0lfhszTbImgVybhs4jIA+Ah+WI//+x1GosMe06FxlxF82p
# G7xaFjkAneNshORaQPveBgGMN/qbsZ0kfv4gpFetW7easGAm6mlXIV00Lx9xsIOU
# GQVrNZAQoHuXx/Y/5+IRQaa9YtnwJz04HShvOlIJ8OxwYtNiS7Dgc6aSwNOOMdgv
# 420XEwbu5AO2FKvzj0OncZ0h3RTKFV2SQdr5D4HRmXQNJsQOfxu19aDxxncGKBXp
# 2JPlVRbwuwqrHNtcSCdmyKOLChzlldquxC5ZoGHd2vNtomHpigtt7BIYvfdVVEAD
# kitrwlHCCkivsNRu4PQUCjob4489yq9qjXvc2EQwggbNMIIFtaADAgECAhAG/fkD
# lgOt6gAK6z8nu7obMA0GCSqGSIb3DQEBBQUAMGUxCzAJBgNVBAYTAlVTMRUwEwYD
# VQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAi
# BgNVBAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0wNjExMTAwMDAw
# MDBaFw0yMTExMTAwMDAwMDBaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdp
# Q2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERp
# Z2lDZXJ0IEFzc3VyZWQgSUQgQ0EtMTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
# AQoCggEBAOiCLZn5ysJClaWAc0Bw0p5WVFypxNJBBo/JM/xNRZFcgZ/tLJz4Flnf
# nrUkFcKYubR3SdyJxArar8tea+2tsHEx6886QAxGTZPsi3o2CAOrDDT+GEmC/sfH
# MUiAfB6iD5IOUMnGh+s2P9gww/+m9/uizW9zI/6sVgWQ8DIhFonGcIj5BZd9o8dD
# 3QLoOz3tsUGj7T++25VIxO4es/K8DCuZ0MZdEkKB4YNugnM/JksUkK5ZZgrEjb7S
# zgaurYRvSISbT0C58Uzyr5j79s5AXVz2qPEvr+yJIvJrGGWxwXOt1/HYzx4KdFxC
# uGh+t9V3CidWfA9ipD8yFGCV/QcEogkCAwEAAaOCA3owggN2MA4GA1UdDwEB/wQE
# AwIBhjA7BgNVHSUENDAyBggrBgEFBQcDAQYIKwYBBQUHAwIGCCsGAQUFBwMDBggr
# BgEFBQcDBAYIKwYBBQUHAwgwggHSBgNVHSAEggHJMIIBxTCCAbQGCmCGSAGG/WwA
# AQQwggGkMDoGCCsGAQUFBwIBFi5odHRwOi8vd3d3LmRpZ2ljZXJ0LmNvbS9zc2wt
# Y3BzLXJlcG9zaXRvcnkuaHRtMIIBZAYIKwYBBQUHAgIwggFWHoIBUgBBAG4AeQAg
# AHUAcwBlACAAbwBmACAAdABoAGkAcwAgAEMAZQByAHQAaQBmAGkAYwBhAHQAZQAg
# AGMAbwBuAHMAdABpAHQAdQB0AGUAcwAgAGEAYwBjAGUAcAB0AGEAbgBjAGUAIABv
# AGYAIAB0AGgAZQAgAEQAaQBnAGkAQwBlAHIAdAAgAEMAUAAvAEMAUABTACAAYQBu
# AGQAIAB0AGgAZQAgAFIAZQBsAHkAaQBuAGcAIABQAGEAcgB0AHkAIABBAGcAcgBl
# AGUAbQBlAG4AdAAgAHcAaABpAGMAaAAgAGwAaQBtAGkAdAAgAGwAaQBhAGIAaQBs
# AGkAdAB5ACAAYQBuAGQAIABhAHIAZQAgAGkAbgBjAG8AcgBwAG8AcgBhAHQAZQBk
# ACAAaABlAHIAZQBpAG4AIABiAHkAIAByAGUAZgBlAHIAZQBuAGMAZQAuMAsGCWCG
# SAGG/WwDFTASBgNVHRMBAf8ECDAGAQH/AgEAMHkGCCsGAQUFBwEBBG0wazAkBggr
# BgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdo
# dHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290
# Q0EuY3J0MIGBBgNVHR8EejB4MDqgOKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5j
# b20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMDqgOKA2hjRodHRwOi8vY3Js
# NC5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMB0GA1Ud
# DgQWBBQVABIrE5iymQftHt+ivlcNK2cCzTAfBgNVHSMEGDAWgBRF66Kv9JLLgjEt
# UYunpyGd823IDzANBgkqhkiG9w0BAQUFAAOCAQEARlA+ybcoJKc4HbZbKa9Sz1Lp
# MUerVlx71Q0LQbPv7HUfdDjyslxhopyVw1Dkgrkj0bo6hnKtOHisdV0XFzRyR4WU
# VtHruzaEd8wkpfMEGVWp5+Pnq2LN+4stkMLA0rWUvV5PsQXSDj0aqRRbpoYxYqio
# M+SbOafE9c4deHaUJXPkKqvPnHZL7V/CSxbkS3BMAIke/MV5vEwSV/5f4R68Al2o
# /vsHOE8Nxl2RuQ9nRc3Wg+3nkg2NsWmMT/tZ4CMP0qquAHzunEIOz5HXJ7cW7g/D
# vXwKoO4sCFWFIrjrGBpN/CohrUkxg0eVd3HcsRtLSxwQnHcUwZ1PL1qVCCkQJjGC
# BAMwggP/AgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0
# IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0ECEAZY+tvHeDVvdG/Hsafu
# SKwwCQYFKw4DAhoFAKBAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMCMGCSqG
# SIb3DQEJBDEWBBTMwNunNinr3TQvWsqJWtsRlCEpiDANBgkqhkiG9w0BAQEFAASC
# AQAL02cVQIUlhFBPuTauU3KPzy55j04Jkob9gIThCL6quJDzD6dSAHXmg3Tadydb
# 87enePy6Zp+WTha4igJWXc1sAaWNOtc+Vkutj392dIUOd+DEI+/75h+mVjKO+MkU
# rjfdn1BF4jDcuDG3EZ40zBgFj+GmQX5Dv4EDWoRaPf+XfJsSqWaMceKqueVYEyUe
# 5kLQyYgabEQjrmSHxX0CYQRh7/xOUr/iKu+Rguv5yd4MOa4FuYgV1uj14IY/RSuD
# WzQmbJODFPxGT/vZacIXqi7uZ06f0iN+hkjv+zDri6dSKZdxWrEgtaf7pcO/4xhm
# 9Tm8tJMSV6zv0m4vOfV9CHu4oYICDzCCAgsGCSqGSIb3DQEJBjGCAfwwggH4AgEB
# MHYwYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UE
# CxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQgQXNzdXJlZCBJ
# RCBDQS0xAhADAZoCOv9YsWvW1ermF/BmMAkGBSsOAwIaBQCgXTAYBgkqhkiG9w0B
# CQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yMDEwMzExMjQ3MzNaMCMG
# CSqGSIb3DQEJBDEWBBT65phngt0NnPC386ilyoFtfwa7pjANBgkqhkiG9w0BAQEF
# AASCAQBQDZXp7HVKaYbfELlYmdce1b7NxltZyFy0uLX1+3CUKq1WncxziKKFCE8P
# UQG9e1L2wE6s8BNpaBgmdJATf+5JE2eXEWGn+yQvI2K2R6auTaf5AFVFAjc/8Hgt
# aLk6PSibNGLAXRHrp2y0jSa2/Rd/674p3kYwoWK156lMlm+1wZT3eZen6L7Upjg2
# I38PGHVNuT3jhny52Qh2yII9bWR6b0/lXrD5J1QflidgNUZnYpUILyEJRRYZmYWp
# X7rEBVDztnyvf1grVgMtb2DRoCeOZxI0ad8kfbFfttUvCGkjdnDSdCR+2VKy44rA
# maeFPd5lZK9YcoaGNGX+jSUgMaRy
# SIG # End signature block
