#Script to resolve Certificate and Auth. Errors that came about as a result of the Admin users' SID changing when the VM was exported

# Ensure the WebAdministration module is imported
try {
    Import-Module WebAdministration -ErrorAction Stop
    Write-Host "WebAdministration module imported successfully."
} catch {
    Write-Host "Failed to import WebAdministration module: $_"
    exit 1
}

# Step 1: Create a new self-signed certificate with CSP provider
Write-Host "Creating a new self-signed certificate..."
try {
    $cert = New-SelfSignedCertificate -DnsName "localhost" `
        -CertStoreLocation "cert:\LocalMachine\My" `
        -NotAfter (Get-Date).AddYears(50) `
        -KeyExportPolicy Exportable `
        -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider" -ErrorAction Stop
        # Using this as other providers do not allow us to modify permissions to add the IIS_IUSRS group with read access.
        #-Provider "Microsoft RSA SChannel Cryptographic Provider" -ErrorAction Stop
        #-Provider "Microsoft Enhanced RSA and AES Cryptographic Provider" -ErrorAction Stop

    $certThumbprint = $cert.Thumbprint
    Write-Host "Certificate created successfully. Thumbprint: $certThumbprint"
} catch {
    Write-Host "Failed to create a self-signed certificate: $_"
    exit 1
}

# Step 2: Add the certificate to the Trusted Root Certification Authorities store
Write-Host "Adding the certificate to the Trusted Root Certification Authorities store..."
try {
    $rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
    $rootStore.Open("ReadWrite")
    $rootStore.Add($cert)
    $rootStore.Close()
    Write-Host "Certificate added to the Trusted Root store successfully."
} catch {
    Write-Host "Failed to add the certificate to the Trusted Root store: $_"
    exit 1
}

# Step 3: Grant IIS_IUSRS read permission to the certificate's private key
Write-Host "Granting IIS_IUSRS read permission to the certificate's private key..."
try {
    $account = "IIS_IUSRS"

    # Fetch the certificate from the store
    $cert = Get-ChildItem -Path "Cert:\LocalMachine\My\$certThumbprint"

    # Get the private key file path
    if ($cert.HasPrivateKey) {
        $keyFileName = $cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
        $keyFilePath = "$env:ProgramData\Microsoft\Crypto\RSA\MachineKeys\$keyFileName"

        # Grant read permissions to IIS_IUSRS
        icacls $keyFilePath /grant "IIS_IUSRS:(R)" | Out-Null
        Write-Host "Granted IIS_IUSRS read permission to the certificate's private key."
    } else {
        Write-Host "Certificate does not have a private key."
    }
} catch {
    Write-Host "Failed to grant read permission to the certificate's private key: $_"
    exit 1
}

# Step 4: Bind the certificate to the "Default Web Site" in IIS
Write-Host "Binding the certificate to the 'Default Web Site' in IIS..."
$certThumbprint = $cert.Thumbprint
$siteName = "Default Web Site"

# Remove any existing HTTPS bindings (optional, but ensures no duplicate bindings)
Remove-WebBinding -Name $siteName -Protocol "https" -ErrorAction SilentlyContinue

# Bind the new certificate to the Default Web Site on port 443
New-WebBinding -Name $siteName -Protocol "https" -Port 443

# Assign the certificate to the HTTPS binding using the Thumbprint
$binding = Get-WebBinding -Name $siteName -Protocol "https"
$binding.AddSslCertificate($certThumbprint, "My")

# Step 5: Replace the thumbprint string in the appsettings.json file
Write-Host "Updating the thumbprint in the appsettings.json file..."
try {
    $jsonFilePath = "C:\Program Files\Hyland\identityprovider\config\appsettings.json"

    # Read the file content as text
    $jsonContent = Get-Content $jsonFilePath -Raw

    # Replace the thumbprint
    $pattern = '"Thumbprint":\s*"[A-Fa-f0-9]{40}"'
    $replacement = '"Thumbprint": "' + $certThumbprint + '"'
    $jsonContent = $jsonContent -replace $pattern, $replacement

    # Write the updated content back to the file
    Set-Content -Path $jsonFilePath -Value $jsonContent
    Write-Host "Thumbprint updated in appsettings.json file."
} catch {
    Write-Host "Failed to update the thumbprint in appsettings.json: $_"
    exit 1
}

# List of application pools to process
$appPools = @(
    "identityproviderAppPool",
    "EVM API Pool",
    "EVM UI Pool",
    "ApiServerAppPool",
    "OnBaseAdminPortalAppPool"
)

# Directory to store backups
try {
    $backupDir = "C:\Backup\AppPools"
    New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    Write-Host "Backup directory created at $backupDir."
} catch {
    Write-Host "Failed to create backup directory: $_"
    exit 1
}

# Step 6: Capture Application Pool Configurations
Write-Host "Backing up application pool configurations..."
foreach ($appPool in $appPools) {
    try {
        if (Test-Path "IIS:\AppPools\$appPool") {
            # Export application pool configuration to XML
            $backupPath = Join-Path $backupDir "$($appPool).xml"
            $appPoolConfig = Get-WebConfiguration "/system.applicationHost/applicationPools/add[@name='$appPool']"
            $appPoolConfig.ChildElements | Export-Clixml -Path $backupPath

            Write-Host "Configuration for application pool '$appPool' has been backed up to '$backupPath'."
        } else {
            Write-Host "Application pool '$appPool' does not exist."
        }
    } catch {
        Write-Host "Failed to back up application pool '$appPool': $_"
    }
}

# Step 7: Delete the Application Pools
Write-Host "Deleting application pools..."
foreach ($appPool in $appPools) {
    try {
        if (Test-Path "IIS:\AppPools\$appPool") {
            # Stop and remove the application pool
            Stop-WebAppPool -Name $appPool -ErrorAction SilentlyContinue
            Remove-WebAppPool -Name $appPool -ErrorAction Stop
            Write-Host "Application pool '$appPool' has been deleted."
        } else {
            Write-Host "Application pool '$appPool' does not exist or has already been deleted."
        }
    } catch {
        Write-Host "Failed to delete application pool '$appPool': $_"
    }
}

# Step 8: Recreate Application Pools with ApplicationPoolIdentity
Write-Host "Recreating application pools with ApplicationPoolIdentity..."
foreach ($appPool in $appPools) {
    try {
        # Path to the backup file
        $backupPath = Join-Path $backupDir "$($appPool).xml"

        if (Test-Path $backupPath) {
            # Import the configuration
            $appPoolConfig = Import-Clixml -Path $backupPath

            # Create a new application pool
            New-WebAppPool -Name $appPool -ErrorAction Stop
            Write-Host "Application pool '$appPool' created."

            # Set the application pool identity to ApplicationPoolIdentity
            Set-ItemProperty "IIS:\AppPools\$appPool" -Name "processModel.identityType" -Value "ApplicationPoolIdentity" -ErrorAction Stop
            Write-Host "Set application pool '$appPool' identity to 'ApplicationPoolIdentity'."

            # Reapply other settings
            foreach ($element in $appPoolConfig) {
                $propertyName = $element.Name
                $propertyValue = $element.Value

                # Skip identity-related properties
                if ($propertyName -notin @("identityType", "userName", "password")) {
                    try {
                        Set-ItemProperty "IIS:\AppPools\$appPool" -Name $propertyName -Value $propertyValue -ErrorAction Stop
                        Write-Host "Set property '$propertyName' to '$propertyValue' for application pool '$appPool'."
                    } catch {
                        Write-Host "Could not set property '$propertyName' for application pool '$appPool': $_"
                    }
                }
            }

            # Start the application pool
            Start-WebAppPool -Name $appPool -ErrorAction Stop
            Write-Host "Application pool '$appPool' has been recreated with ApplicationPoolIdentity and started."
        } else {
            Write-Host "Backup configuration for application pool '$appPool' not found."
        }
    } catch {
        Write-Host "Failed to recreate application pool '$appPool': $_"
    }
}

# Step 9: Reassign Applications to Application Pools
Write-Host "Reassigning applications to application pools..."
# Map of applications to their application pools
$appAssignments = @{
    "/Default Web Site/identityprovider" = "identityproviderAppPool"
    "/Default Web Site/EVM_API" = "EVM API Pool"
    "/Default Web Site/EVM_UI" = "EVM UI Pool"
    "/Default Web Site/ApiServer" = "ApiServerAppPool"
    "/Default Web Site/OnBaseAdminPortal" = "OnBaseAdminPortalAppPool"
}

foreach ($app in $appAssignments.Keys) {
    try {
        $appPoolName = $appAssignments[$app]
        if (Test-Path "IIS:\Sites$app") {
            Set-ItemProperty "IIS:\Sites$app" -Name "applicationPool" -Value $appPoolName -ErrorAction Stop
            Write-Host "Assigned application '$app' to application pool '$appPoolName'."
        } else {
            Write-Host "Application '$app' does not exist."
        }
    } catch {
        Write-Host "Failed to assign application '$app' to application pool '$appPoolName': $_"
    }
}

Write-Host "All application pools have been recreated and applications reassigned."
Write-Host "Running an IIS Reset to refresh settings and configuration..."

iisreset

Write-Host "IIS Reset, please proceed to testing..."
Write-Host "Script Complete"
