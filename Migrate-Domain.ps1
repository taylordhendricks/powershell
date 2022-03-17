<#Domain Migration Script v0.1
Created by: Taylor Hendricks (taylor.hendricks@hyland.com)
This command moves a list of comma separated servers in a CSV file from a current Domain to $NewDomain.
https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/add-computer?view=powershell-5.1
Example Command: Add-Computer -ComputerName Server01, Server02, localhost -DomainName Domain02 -LocalCredential Domain01\User01 -UnjoinDomainCredential Domain01\Admin01 -Credential Domain02\Admin01 -OUPath "OU=testOU,DC=domain,DC=Domain,DC=com" -Restart
#>

#region Log File Generation/Cleanup
##Source: https://itluke.online/2018/10/25/how-to-create-a-log-file-for-your-powershell-scripts/ ##
$CurrentPath = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$LogPath = Join-Path -Path $CurrentPath -ChildPath 'Migrate-Domain Logs'
$LogRootName = (Split-Path -Path $MyInvocation.MyCommand.Path -Leaf) -replace '\.ps1'
$TimeStamp = Get-Date -Format yyyyMMdd_HHmmss
$LogFileName = '{0}_{1}.log' -f $LogRootName, $TimeStamp
$LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName
 
#Change this value to how many log files you want to keep
$NumberOfLogsToKeep = 2
 
If(Test-Path -Path $LogPath)
    {
    #Make some cleanup and keep only the most recent ones
    $Filter = '{0}_????????_??????.log' -f (Join-Path -Path $LogPath -ChildPath $LogRootName)
     
    Get-ChildItem -Path $Filter |
    Sort-Object -Property LastWriteTime -Descending |
    Select-Object -Skip $NumberOfLogsToKeep |
    Remove-Item -Verbose
    }
Else
    {
    #No logs to clean but create the Logs folder
    New-Item -Path $LogPath -ItemType Directory -Verbose
    }
#endregion

#region Global Variables and Credentials
$NewDomain = "<NEW Domain>"
$CurrentDomain = "<Current Domain>"
$ListOfComputers = "PathToListofComputers.csv"
#Fetching/Checking Credentials
if ($CurrentDomainCreds -eq $null)
    {
    $CurrentDomainCreds = Get-Credential -Message "PVI Domain Admin Credentials required" -UserName "$CurrentDomain\$env:username"
    $NewDomainCreds = Get-Credential -Message "HylandQA Domain Admin Credentials required" -UserName "$NewDomain\$env:username"
    }
else {Write-Host "`n`rCredentials Found`n`rUsing existing credentials`n`rIf new credentials need to be entered use close and re-open PowerShell ISE or set the variables to Null"}
#endregion

#region Migrate-Domain
<#Migrate-Domain Comments
    This is the meat of the script
    Tried to use comma separated entries as defined in the documentation but ran into issues where it was parsing the comma separated values as just one PC, having it loop foreach instead.
    If we were to go the route of dividing all machines into their various OUs this can also be employed and is actually better via the foreach loop.
    This assumes the CSV you are loading is formatted as such: column 1 'ServerList', column 2 'OUPath' as headers
    eg. ServerList,OUPath
    eg. Hostname,OU=General Computer,DC=NewDomain,DC=net
    If the OU ends up being defined in the CSV comment out line 62 and uncomment 63, otherise this uses 'General Computer' OU as the default
    #>
Function Migrate-Domain
{       
    $ServerList = import-csv -Path $ListOfComputers | foreach-object {
        $Server = $($_.ServerList)
        $NewOUPath = "OU=General Computer,DC=DomainName,DC=net"
        #$NewOUPath = $($_.OUPath)
        Write-Host "`n`rAttempting to migrate $Server to $NewDomain, OU Path is: $NewOUPath"
        #Testing to see if the machine is even online to migrate
        if((Test-Connection -ComputerName $Server -count 1 -ErrorAction 0))
            {
            Write-Host "`t$Server is ONLINE" -ForegroundColor Green
            try{
                Add-Computer -ComputerName $Server -DomainName $NewDomain -LocalCredential $CurrentDomainCreds -UnjoinDomainCredential $CurrentDomainCreds -Credential $NewDomainCreds -OUPath $NewOUPath -Verbose
                ##Rebooting from the Add-Computer function fails due to permissions, likely as a result of migrating using this instead
                Restart-Computer $Server -Credential $NewDomainCreds
                ##Cleanup the ADObject that gets left behind
                Remove-ADComputer -Identity $Server -Confirm:$False -verbose
            }
            catch{
                Write-Host "$Server is Online, but Domain Migration failed" -ForegroundColor Yellow
            }
            } 
        else 
            {Write-Host "`t$Server is OFFLINE" -ForegroundColor Red
            }
    }
}
#endregion

Start-Transcript -Append -Path $LogFile

Migrate-Domain

Stop-Transcript
Write-Host "`n`rLogs can be found in the directory above`n`rCheck output for errors"
