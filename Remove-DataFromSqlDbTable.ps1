<#
.SYNOPSIS
    Truncate a SQL table if the database is within a specified threshold of its maximum capacity

.DESCRIPTION
    This runbook provides an example of how Azure Automation can be used to accomplish common SQL Agent tasks in the cloud.  The runbook first queries a master DB to obtain the list of databases associated to that particular logical server as well as each database's current size.  Next, the runbook queries each of the individual databases, obtains the databases maximum size, and then, if the current database size is within a specified threshold of the maximum DB size, the script will truncate a specified table ([dbo].[ExampleTable]).

    For this runbook to execute successfully, the Azure DB logical server must allow incoming connections from Azure services. This configuration can be achieved in the Microsoft Azure portal by selecting the server, clicking on the "Configure" tab and, under allowed services, selecting 'YES' for Windows Azure Services.

    As prerequisite, please create an Azure Automation credential asset that contains the username and password for the target Azure SQL DB logical server ($SqlServerName).  Additionally, for this runbook to execute correctly, the [dbo].[ExampleTable] table must exist on each of the database associated to $SqlServerName.
	
.EXAMPLE
    Remove-DataFromSqlDbTable
	
.NOTES
    AUTHOR: Joseph Idziorek
    LAST EDIT: June 23, 2014 
#>

workflow Remove-DataFromSqlDbTable 
{
    param
    (
        # Fully-qualified name of the Azure DB server 
        [parameter(Mandatory=$true)] 
        [string] $SqlServerName,
		
		# Credentials for $SqlServerName stored as an Azure Automation credential asset
		# When using in the Azure Automation UI, please enter the name of the credential asset for the "Credential" parameter
        [parameter(Mandatory=$true)] 
        [PSCredential] $Credential
    )
    
    inlinescript{
        
        # Setup credentials   
        $ServerName = $Using:SqlServerName
        $UserId = $Using:Credential.UserName
        $Password = ($Using:Credential).GetNetworkCredential().Password
        
        # Setup threshold for % of maximum DB size
        $Threshold = 0.8
        
        # Create connection to Master DB
        $MasterDatabaseConnection = New-Object System.Data.SqlClient.SqlConnection
        $MasterDatabaseConnection.ConnectionString = "Server = $ServerName; Database = Master; User ID = $UserId; Password = $Password;"
        $MasterDatabaseConnection.Open();
        
        # Create command to query the current size of active databases in $ServerName
        $MasterDatabaseCommand = New-Object System.Data.SqlClient.SqlCommand
        $MasterDatabaseCommand.Connection = $MasterDatabaseConnection
        $MasterDatabaseCommand.CommandText = 
            "
                SELECT 
                       database_name,
                       storage_in_megabytes [SizeMB]
                FROM 
                       [sys].[databases] as db
                INNER JOIN
                       [sys].[resource_usage] as rs
                ON
                       rs.database_name = db.name
                WHERE
                       [time] = (SELECT Max([time]) FROM [sys].[resource_usage] WHERE database_name = db.name)
                GROUP BY 
                       database_name, storage_in_megabytes
            "
        # Execute reader and return tuples of results <database_name, SizeMB>
        $MasterDbResult = $MasterDatabaseCommand.ExecuteReader()
        
        # Proceed if there is at least one database
        if ($MasterDbResult.HasRows)
        {
            # Create connection for each individual database
            $DatabaseConnection = New-Object System.Data.SqlClient.SqlConnection
            $DatabaseCommand = New-Object System.Data.SqlClient.SqlCommand
        
            # Iterate through each database under $ServerName
            while($MasterDbResult.Read())
            {
                $DbName = $MasterDbResult[0]
                $DbSize = $MasterDbResult[1]
                
                # Apply conditions for user databases (i.e., not master DB)
                if($DbName -ne "Master")
                {
                    # Setup connection string for $DbName
                    $DatabaseConnection.ConnectionString = "Server=$ServerName; Database=$DbName; User ID=$UserId; Password=$Password;"
                    $DatabaseConnection.Open();
        
                    # Create command for a specific database $DBName
                    $DatabaseCommand.Connection = $DatabaseConnection
                    $DatabaseCommand.CommandText = "SELECT DATABASEPROPERTYEX ('$DbName','MaxSizeInBytes')"
        
                    # Execute query and return single scalar result 
                    $DbResultBytes = $DatabaseCommand.ExecuteScalar()
                    $MaxDbSizeMB = $DbResultBytes/(1Mb)
        
                    # Calculate $TargetDbSize
                    $TargetDbSize = $MaxDbSizeMB * $Threshold
        
                    # When the current $DbSize is greater than a percentage ($Threshold) of the $MaxDbSizeMB
                    # then perform a certain action, in this example, truncate a table on that database
                    if($DbSize -gt $TargetDbSize) 
                    {
                        Write-Output "Perform action on $DbName ($DbSize MB > $TargetDbSize MB)"

						# ExampleTable is a place holder for a table that holds a large volume of less important and expendable data
						# that can be truncated to save space on the database.

                        $DatabaseCommand.CommandText = "TRUNCATE TABLE [dbo].[ExampleTable]"
                        $NonQueryResult = $DatabaseCommand.ExecuteNonQuery()
                    }
                    else
                    {
                        Write-Output "Do not perform action on $DbName ($DbSize MB <= $TargetDbSize MB)"
                    }
                    
                    # Close connection to $DbName
                    $DatabaseConnection.Close()
        
                }
            }
        } 
        
        # Close connection to Master DB
        $MasterDatabaseConnection.Close() 
    }    
}
