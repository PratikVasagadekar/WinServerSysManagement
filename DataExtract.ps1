# DataExtraction.ps1

# Define the base output location on the D:\ drive
$baseOutputPath = "D:\"

# Retrieve the hostname of the current system
$hostname = $env:COMPUTERNAME

# Generate a timestamp for the file name in the format ddMMyyyyHHmmss (e.g., 25022025143000)
$fileTimestamp = (Get-Date).ToString("ddMMyyyyHHmmss")

# Define the output JSON file name and full path
$outputFileName = "${hostname}_${fileTimestamp}.json"
$outputFilePath = Join-Path $baseOutputPath $outputFileName

# Dot source the system hardware extraction script (assumes GetSystemHW.ps1 is in the System folder)
. "$PSScriptRoot\System\GetSystemHW.ps1"

# Call the Get-SystemHW function to retrieve system/hardware data
$data = Get-SystemHW

# Convert the result to JSON (adjust -Depth as necessary to include nested objects)
$jsonOutput = $data | ConvertTo-Json -Depth 5

# Save the JSON output to the file using UTF8 encoding
$jsonOutput | Out-File -FilePath $outputFilePath -Encoding UTF8

# Inform the user that the file has been saved
Write-Host "Data extraction completed. JSON output saved to $outputFilePath"
