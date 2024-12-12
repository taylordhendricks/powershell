<#
.SYNOPSIS
This script manages Azure resource tags by allowing users to export existing tags to a CSV file, modify them, and re-import the updated tags.

.DESCRIPTION
The script contains two primary functions:

1. `Export-AzureResourceTags`: Queries Azure resources in a subscription or resource group, retrieves their existing tags, and exports the data to a CSV file. The exported CSV includes columns for resource metadata and individual tag keys.

2. `Import-AzureResourceTags`: Reads the updated CSV file and applies the tags to the corresponding Azure resources. It updates the tags based on whats listed in the CSV and skipping tags with empty values.

.PARAMETER Export-AzureResourceTags
- `SubscriptionId`: The ID of the Azure subscription to query.
- `ResourceGroupName` (optional): The name of the resource group to limit the query to.
- `OutputPath`: The file path where the CSV will be saved (default: `AzureResourceTags.csv`).
- The output CSV will contain columns necessary for the Import-AzureResourceTags function to identify a resource and any existing tags, if new tags are need add a new column with the tag as a header.
EXAMPLE CSV
Name,Location,ResourceId,ResourceType,business:EnvironmentType,business:BusinessUnit,business:CostCenter,business:Department,business:Owner,business:Platform,business:Product,technical:AVDHostpool
AzureVM1,eastus,/subscriptions/<REDACTED>/providers/Microsoft.Compute/virtualMachines/AzureVM1,Microsoft.Compute/virtualMachines,Prod,InformationSystems,CC1234,Infrastructure,taylor.hendricks@email.com,Azure,AVD,hp-pooledavd-usea

.PARAMETER Import-AzureResourceTags
- `InputPath`: The file path of the CSV file to import and apply tags from.

.EXAMPLE
Export resource tags:
```powershell
Export-AzureResourceTags -SubscriptionId "<YourSubscriptionId>" -OutputPath "ResourceTags.csv"
```

Modify `ResourceTags.csv` to add or update tags and then apply them:
```powershell
Import-AzureResourceTags -InputPath "ResourceTags.csv"
```

.NOTES
- Requires the Azure PowerShell Az module.
- Maintains existing tags not listed in the CSV.
- Skips applying tags with empty values in the CSV
#>

function Export-AzureResourceTags {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [string]$SubscriptionId,
        
        [Parameter()]
        [string]$ResourceGroupName,
        
        [Parameter()]
        [string]$OutputPath = ".\AzureResourceTags.csv"
    )
    Import-Module Az.Accounts
    Import-Module Az.Resources

    # Connect to Azure and set the subscription context
    #Connect-AzAccount
    Set-AzContext -SubscriptionId $SubscriptionId

    # Fetch resources
    $resources = if ($ResourceGroupName) {
        Get-AzResource -ResourceGroupName $ResourceGroupName
    } else {
        Get-AzResource
    }

    # Collect all tag keys
    $allTagKeys = @{}
    foreach ($resource in $resources) {
        if ($resource.Tags) {
            $resource.Tags.GetEnumerator() | ForEach-Object {
                $allTagKeys[$_.Key] = $true
            }
        }
    }

    # Sort the tag keys for consistent column order
    $sortedTagKeys = $allTagKeys.Keys | Sort-Object

    # Prepare the output for CSV
    $resourceData = @()
    foreach ($resource in $resources) {
        $tagProperties = @{}
        foreach ($key in $sortedTagKeys) {
            $tagProperties[$key] = if ($resource.Tags -and $resource.Tags[$key]) {
                $resource.Tags[$key]
            } else {
                $null
            }
        }

        $resourceData += New-Object PSObject -Property (@{
            Name         = $resource.Name
            Location     = $resource.Location
            ResourceId   = $resource.ResourceId
            ResourceType = $resource.ResourceType
        } + $tagProperties)
    }

    # Export to CSV
    $resourceData | Export-Csv -Path $OutputPath -NoTypeInformation -Force
    Write-Host "Resource tags exported to $OutputPath with individual tag columns and consistent column order."
}

function Import-AzureResourceTags {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [string]$InputPath
    )
    Import-Module Az.Accounts
    Import-Module Az.Resources

    # Connect to Azure
    #Connect-AzAccount

    # Read the CSV
    $resourcesToTag = Import-Csv -Path $InputPath

    # Apply tags
    foreach ($resource in $resourcesToTag) {
        $resourceId = $resource.ResourceId
        
        # Fetch existing tags
        $existingResource = Get-AzResource -ResourceId $resourceId
        $existingTags = $existingResource.Tags

        # Convert new tags to a dictionary
        $newTags = @{}
        foreach ($column in $resource.PSObject.Properties.Name) {
            if ($column -notin @("ResourceId", "Name", "ResourceType", "Location") -and $resource.$column -ne "") {
                $newTags[$column] = $resource.$column
            }
        }

        # Merge tags
        $mergedTags = @{}
        if ($existingTags) {
            $existingTags.GetEnumerator() | ForEach-Object {
                $mergedTags[$_.Key] = $_.Value
            }
        }
        if ($newTags) {
            $newTags.GetEnumerator() | ForEach-Object {
                $mergedTags[$_.Key] = $_.Value
            }
        }

        # Apply merged tags
        Set-AzResource -ResourceId $resourceId -Tag $mergedTags -Force
        Write-Host "Applied merged tags to $($resource.Name)"
    }
}

Export-ModuleMember -Function Export-AzureResourceTags, Import-AzureResourceTags
