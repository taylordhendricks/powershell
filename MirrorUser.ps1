# Must Have Active Director Module installed
# Import the Active Directory module in order to be able to use Get-ADuser and Add-AdGroupMember cmdlet
Import-Module ActiveDirectory

# enter login name of the first user
$UserToCopy = Read-host "Enter username to copy FROM: "

# enter login name of the second user
$UserToPaste  = Read-host "Enter username to copy TO: "

# copy-paste process. Get-ADuser membership     | then selecting membership                       | and add it to the second user
get-ADuser -identity $UserToCopy -properties memberof | select-object memberof -expandproperty memberof | Add-AdGroupMember -Members $UserToPaste
