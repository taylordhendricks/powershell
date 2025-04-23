#Trimmed down version of https://www.powershellgallery.com/packages/WindowsLocationServices/1.0.3/Content/Get-WindowsLocation.psm1 as I didnt need all the features

function Get-WindowsLocation {
    [CmdletBinding()]
    param (
        [string]$RemoteFile,
        [ValidateSet('None', 'Windows', 'Azure', 'Basic', 'Key')]
        [string]$AuthType = 'None',
        [string]$Username,
        [PSCredential]$Credential,
        [string]$Key,
        [switch]$Continuous,
        [int]$IntervalSeconds = 300,
        [ValidateSet('Google','Bing')]
        [string]$Maps = 'Bing'
    )

    Add-Type -AssemblyName System.Device
    $watcher = New-Object System.Device.Location.GeoCoordinateWatcher
    $watcher.Start()
    Start-Sleep -Seconds 2

    $coord = $watcher.Position.Location
    if ($coord.IsUnknown) {
        Write-Error "Unable to determine location."
        if (-not $Continuous) { return }
        else { Start-Sleep -Seconds $IntervalSeconds; continue }
    }   
    $latitude = $coord.Latitude
    $longitude = $coord.Longitude
    $timestamp = (Get-Date).ToString("o")
    $accuracy = $coord.HorizontalAccuracy   
    # Choose Maps provider
    switch ($Maps) {
        'Google' { $mapsLink = "https://www.google.com/maps/search/?api=1&query=$latitude,$longitude" }
        'Bing'   { $mapsLink = "https://www.bing.com/maps?q=$latitude,$longitude" }
    }   
    $locationData = [PSCustomObject]@{
        Username     = $env:USERNAME
        ComputerName = $env:COMPUTERNAME
        Latitude     = $latitude
        Longitude    = $longitude
        Timestamp    = $timestamp
        Accuracy     = $accuracy
        MapsLink     = $mapsLink
    }   
    Write-Output $locationData
}

Get-WindowsLocation
