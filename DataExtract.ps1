# DataExtraction.ps1

# ----------------------------
# 1. Base File Setup
# ----------------------------
# Define the base output location on the D:\ drive
$baseOutputPath = "D:\"

# Retrieve the hostname of the current system
$hostname = $env:COMPUTERNAME

# Generate a timestamp for the file name in the format ddMMyyyyHHmmss (e.g., 25022025143000)
$fileTimestamp = (Get-Date).ToString("ddMMyyyyHHmmss")

# Define the output JSON file name and full path
$outputFileName = "${hostname}_${fileTimestamp}.json"
$outputFilePath = Join-Path $baseOutputPath $outputFileName

# ----------------------------
# 2. Load Local Extraction Scripts
# ----------------------------
# Dot source the system hardware extraction script (assumes GetSystemHW.ps1 is in the System folder)
. "${PSScriptRoot}\System\GetSystemHW.ps1"

# Dot source the domain information extraction script (assumes GetDomainInfo.ps1 is in the Domain folder)
. "${PSScriptRoot}\Domain\GetDomainInfo.ps1"

# ----------------------------
# 3. Extract Local Data
# ----------------------------
# Call the Get-SystemHW function to retrieve local system/hardware data
$systemData = Get-SystemHW

# Call the Get-DomainInfo function to retrieve local Active Directory domain information
$domainData = Get-DomainInfo

# ----------------------------
# 4. Extract Remote Workstation Data
# ----------------------------
# Ensure the ActiveDirectory module is available
Import-Module ActiveDirectory

# Retrieve all workstations from AD (adjust filter as needed)
$workstations = Get-ADComputer -Filter {OperatingSystem -like "*Workstation*"} -Properties OperatingSystem | Select-Object -ExpandProperty Name

# Define the path to the local GetSystemHW.ps1 script (to be executed remotely)
$remoteScriptPath = "${PSScriptRoot}\System\GetSystemHW.ps1"
if (-not (Test-Path $remoteScriptPath)) {
    Write-Error "Remote GetSystemHW.ps1 not found at $remoteScriptPath"
    exit
}

# Read the content of the GetSystemHW.ps1 script so it can be injected into remote sessions
$scriptContent = Get-Content -Path $remoteScriptPath -Raw

# Initialize an array to store results from each workstation
$remoteResults = @()

foreach ($ws in $workstations) {
    Write-Host "Processing workstation: $ws ..."
    try {
        # Remotely load and execute the Get-SystemHW function
        $result = Invoke-Command -ComputerName $ws -ScriptBlock {
            param($script)
            Invoke-Expression $script
            return Get-SystemHW
        } -ArgumentList $scriptContent -ErrorAction Stop

        $remoteResults += [PSCustomObject]@{
            WorkstationName = $ws
            Data            = $result
            Error           = $null
        }
    }
    catch {
        Write-Warning "Failed to get data from ${ws}: $_"
        $remoteResults += [PSCustomObject]@{
            WorkstationName = $ws
            Data            = $null
            Error           = $_.Exception.Message
        }
    }
}


# ----------------------------
# 5. Combine and Save the Data
# ----------------------------
# Combine all extracted data into one final output object
$finalOutput = @{
    LocalSystem = @{
        SystemHardware = $systemData
        DomainInfo     = $domainData
    }
    Workstations = $remoteResults
    RetrievedAt  = (Get-Date).ToString("dd-MMM-yyyy hh:mm:ss tt")
}

# Convert the final output to JSON (increase -Depth as needed for nested objects)
$jsonOutput = $finalOutput | ConvertTo-Json -Depth 6

# Save the JSON output to the file using UTF8 encoding
$jsonOutput | Out-File -FilePath $outputFilePath -Encoding UTF8

# Inform the user that the file has been saved
Write-Host "Data extraction completed. JSON output saved to $outputFilePath"
