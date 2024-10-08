#Uses a 'do/while' loop to return to start for multiple searches
#Prompts user for an AD Username
do {$LoginID = Read-Host "Enter the username to search: "
                # Initially searches specifically for lockout status
                $UserLock = Get-ADUser -identity $LoginID -property lockedout | Select-Object LockedOut
                # Then searches for a formatted lost of properties
                Get-ADUser -identity $LoginID -property * | Format-List -property name, mailnickname, mail, TelephoneNumber, lockedout, passwordexpired, enabled, passwordlastset, physicaldeliveryofficename 
                    # If a user is locked prompts if you would like to unlock
                    If ($UserLock.lockedout -eq $True)
                        {Write-Host "User is locked."
                        Write-Host ""
                        $UnlockChoice = Read-Host "Would you like to Unlock $LoginID? Enter Y/N"
                        Write-Host ""
                            If ($UnlockChoice -eq "Y")
                                {Unlock-ADAccount -Identity $LoginID
                                Write-Host "User has been unlocked"
                                }
                            ElseIF ($UnlockChoice -eq "N")
                                {Write-Host "User will remain locked"
                                }             
                            Else
                                {"Incorrect Choice Please Try Again"
                                }
                        }
                    ElseIf ($UserLock.lockedout -eq $False)
                            {Write-Host "User is NOT locked"
                            Write-Host ""
                            }
                    ElseIf ($UserLock.passwordexpired -eq $True)
                            {Write-Host "User pswd EXPIRED"
                            Write-Host ""
                            }
                    ElseIf ($UserLock.enabled -eq $False)
                            {Write-Host "User account DISABLED"
                            Write-Host ""
                            }
                    Else
                            {
                            }

                $again = read-host "Search another user? Enter Y/N"
                }
            while ($again -eq "Y")
