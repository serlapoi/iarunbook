<# 
.SYNOPSIS  
    The purpose of this runbook is to demonstrate how to restore a database to a new database using an Azure Automation workflow.
 
.DESCRIPTION 
    WARNING: This runbook deletes a database. The database which you will be restoring to will be deleted upon the next run of this runbook.
    
    This runbook is designed to restore a single database to a test database. It will first try to delete the old test database. Then it will create a new one with data from 24 hours ago.

    
.PARAMETER SourceServerName
    This is the name of the server where the source database is located
    
.PARAMETER SourceDatabaseName
    This is the name of the database being restored from
    
.PARAMETER ActiveDirectoryUser
    This is the name of the Active Directory User used to authenticate with. 
    Example: MyActiveDirectoryUser@LiveIDEmail.onmicrosoft.com
 
 .PARAMETER SubscriptionName
    This is the name of the subscription where the database is on.
    
 .PARAMETER HoursBack
    This is how many hours back you want the copy of the database to be restored too.
    
.NOTES 
    AUTHOR: Eli Fisher
    LASTEDIT: March 11, 2015
#> 
 
    param([Parameter(Mandatory=$False)] 
      [ValidateNotNullOrEmpty()] 
      [String]$SourceServerName = 'iadbsl',
      [Parameter(Mandatory=$False)]  
      [ValidateNotNullOrEmpty()] 
      [String]$SourceDatabaseName = 'IACDSitecore_Master',
      [Parameter(Mandatory=$False)]  
      [ValidateNotNullOrEmpty()] 
      [String]$ActiveDirectoryUser = 'serge',
      [Parameter(Mandatory=$False)]  
      [ValidateNotNullOrEmpty()] 
      [String]$DatabaseCredentialName = 'dba',
      [Parameter(Mandatory=$False)]  
      [ValidateNotNullOrEmpty()] 
      [String]$SubscriptionName = 'Microsoft AE IA',
      [Parameter(Mandatory=$False)]  
      [ValidateNotNullOrEmpty()] 
      [int]$HoursBack = 2
      )
    
# Log function helper
function Log([Parameter(ValueFromPipeline=$true)]$Message, $LogColor = "Cyan")
{
    Write-Host $Message -ForegroundColor $LogColor
}

# Helper function to combine the server and database names together into a key
# that can be used within a hash table
function GetServerDatabaseHashMapKey
{
    param (
        [Parameter(Mandatory=$true)][string]$ServerName,
        [Parameter(Mandatory=$true)][string]$DatabaseName
    )

    return [String]::Format("{0}:{1}", $ServerName, $DatabaseName)
}

# Function to obtain the databases to use within a custom collection
# Currently, this function returns all databases within a server.  The 
# function could be updated to return a different set of databases.
function GetDatabasesForCustomCollection
{
    param (
        [Parameter(Mandatory=$true)][string]$ServerName
    )

    # This function returns all the databases in the server
    # However, this function could be modified to return a different set of databases for your scenario, for example all databases in a pool.
    # For all DBs in a pool, simply replace Get-AzureSqlDatabase with Get-AzureSqlElasticPoolDatabase and 
    # provide the value the -ElasticPoolName parameter in addition to the -ResourceGroupName and -ServerName parameters
    $azureSqlDatabases = @{}
    Log ("Getting the Azure SQL Databases in Azure SQL Server: " + $ServerName)
    foreach($azureSqlDatabase in Get-AzureSqlDatabase -ServerName $ServerName)
    {
        if($azureSqlDatabase.Name -ne "master") 
        {
            Log ("Identified Azure SQL Database: " + $azureSqlDatabase.Name)
            $key = GetServerDatabaseHashMapKey  -ServerName $ServerName `
                                                -DatabaseName $azureSqlDatabase.Name
            $azureSqlDatabases.add($key, $true)

			$BlobName = $azureSqlDatabase.Name + ".bacpac"
			$Blob = Get-AzureStorageBlob -Blob $BlobName -Container $ContainerName -Context $StorageCtx -ErrorAction SilentlyContinue
			if ($Blob) {
				Remove-AzureStorageBlob -Blob $BlobName -Container $ContainerName -Context $StorageCtx
			}
			$exportRequest = Start-AzureSqlDatabaseExport -SqlConnectionContext $SqlCtx -StorageContext $StorageCtx -StorageContainerName $ContainerName -DatabaseName $azureSqlDatabase.Name -BlobName $BlobName  -ErrorAction SilentlyContinue;
        }
    } 
    return $azureSqlDatabases
}
	$StorageName = "iadbstorage"
	$ContainerName = "sqlbackups"
	$StorageKey = "7zkbrwaNhyh0/OU0Im4wxn8PD0MjgmyL5+v7EeBySJa999OKMDkADvHMRNKgUrliTMLjDu+ZStc0I7vqP97J/g=="
	
    #Configure PowerShell credentials and connection context
    $Cred = Get-AutomationPSCredential -Name $ActiveDirectoryUser #Replace this with the account used for Azure Automation authentication with Azure Active Directory
    if(!$Cred) {
        Throw "Could not find an Automation Credential Asset named '${ActiveDirectoryUser}'. Make sure you have created one in this Automation Account."
    }
	
    #Configure PowerShell credentials and connection context
    $credential = Get-AutomationPSCredential -Name $DatabaseCredentialName #Replace this with the account used for Azure Automation authentication with Azure Active Directory
    if(!$credential) {
        Throw "Could not find an Automation Credential Asset named '${DatabaseCredentialName}'. Make sure you have created one in this Automation Account."
    }
	
    Add-AzureAccount -Credential $Cred
 	Select-AzureSubscription -SubscriptionName $SubscriptionName #Replace this with your subscription name
    
    #Set the point in time to restore too and the target database
    
	#Write-Output $sqlCtx.Name

	$SqlCtx = New-AzureSqlDatabaseServerContext -ServerName $SourceServerName -Credential $credential;

	$StorageCtx = New-AzureStorageContext -StorageAccountName $StorageName -StorageAccountKey $StorageKey;
	
    if(!$StorageCtx) {
        Throw "Could not connect to '${StorageName}'. Make sure you have created one in this Automation Account."
    }
	
	$Container = Get-AzureStorageContainer -Name $ContainerName -Context $StorageCtx; 
	
    if(!$Container) {
        Throw "Could not connect to '${ContainerName}'. Something went wrong!."
    }

	Log "Get the Azure SQL Databases to target for the custom group of databases"
	$azureSqlDatabasesForCollection = GetDatabasesForCustomCollection -ServerName $SourceServerName
																  
    #$PointInTime = (Get-Date).AddHours(-$HoursBack) #This gets the point in time for the database restore
    #$TargetDatabaseName = 'Copy_' + $SourceDatabaseName  #Replace this with the name of the database you want to restore to
    
    #Write-Output "Deleting the old $TargetDatabaseName"
    #Delete the old database copy
    #Remove-AzureSqlDatabase -ServerName $SourceServerName -DatabaseName $TargetDatabaseName -Force #Delete the day old copy database.
    
    #Write-Output "Creating new $TargetDatabaseName with data at time $PointInTime"
    #Start the database restore to refresh the data
    #Start-AzureSqlDatabaseRestore -SourceServerName $SourceServerName -SourceDatabaseName $SourceDatabaseName -TargetDatabaseName $TargetDatabaseName -PointInTime $PointInTime
