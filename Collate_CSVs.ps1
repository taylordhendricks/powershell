# Reads a folder of CSVs, combines them and then moves them to a '.\Processed\$DATE folder

# Define the directory where the CSV files are located
$sourceDirectory = ".\Downloads\CSV TestFolder"
$processedFolder = "Processed"

# Create a date-stamped subfolder in the Processed directory
$date = Get-Date -Format "yyyy-MM-dd"
$destinationSubfolder = Join-Path -Path $sourceDirectory -ChildPath $processedFolder -AdditionalChildPath $date
if (-Not (Test-Path -Path $destinationSubfolder)) {
    New-Item -ItemType Directory -Path $destinationSubfolder
}

# Get all CSV files in the source directory, excluding any under the Processed folder
$csvFiles = Get-ChildItem -Path $sourceDirectory -Filter *.csv | Where-Object { $_.DirectoryName -notmatch "$processedFolder" }

# Define the name and path for the collated CSV file
$collatedCsvFileName = "$($date)_CollatedCSV.csv"
$collatedCsvPath = Join-Path -Path $sourceDirectory -ChildPath $collatedCsvFileName

# Initialize a flag to track if the header has been added to the collated CSV
$headerAdded = $false

# Combine all CSV files into one
foreach ($file in $csvFiles) {
    $csvContent = Get-Content -Path $file.FullName
    
    # Check if the header should be added or not
    if (-Not $headerAdded) {
        # Write the header from the first file
        $csvContent | Out-File -FilePath $collatedCsvPath -Encoding UTF8
        $headerAdded = $true
    } else {
        # Exclude the header and append the rest
        $csvContent | Select-Object -Skip 1 | Add-Content -Path $collatedCsvPath
    }
}

# Move individual CSV files to the dated subfolder
foreach ($file in $csvFiles) {
    Move-Item -Path $file.FullName -Destination $destinationSubfolder
}
