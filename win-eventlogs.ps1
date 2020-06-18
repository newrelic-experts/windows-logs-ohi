###
# This PowerShell script grabs the Windows event logs and posts them to New Relic Logs.
# v2.1 -  Updated to provide filtering out of event type (i.e. Verbose, Informational, Warning, Error, Critical) and EventID.
#
# The following command is required for testing:
#
# [System.Diagnostics.EventLog]::CreateEventSource("New Relic","Application")
###

###
# Parameters (a.k.a. Command Line Arguments)
# Usage: -LogName "LogName"
# Required - throw if missing
###

param (
    [string]$LogName=$(throw "-LogName is mandatory"),
	  [string]$nrLicenseKey=$(throw "-nrLicenseKey is mandatory"),
	  [string[]]$ExclLevel = "",
	  [string[]]$ExclEventID = ""
)

# App Version (so we know if someone's running an older release of this integration)
$appVersion = "2.1"

# New Relic Logs endpoint
$nrLogEndpoint = "https://log-api.newrelic.com/log/v1"

###
# Logic to handle getting new log entries by saving current date to file
# to use as -After argument of Get-Date in next pull. On first run we use current date.
# On subsequent runs it will use last date written to file.
#
# Uses LogName param to create timestamp for each LogName
###

$LAST_PULL_TIMESTAMP_FILE = "./last-pull-timestamp-$LogName.txt"


###
# If timestamp file exists, use it; otherwise,
# set timestamp to 15 minutes ago to pull some data on
# first run.
###

if(Test-Path $LAST_PULL_TIMESTAMP_FILE -PathType Leaf) {

    $timestamp = Get-Content -Path $LAST_PULL_TIMESTAMP_FILE -Encoding String | Out-String;
    $timestamp = [DateTime] $timestamp.ToString();

}else{

    $timestamp = (Get-Date).AddMinutes(-15);

}

###
# Write current timestamp to file to pull on next run.
###
Set-Content -Path $LAST_PULL_TIMESTAMP_FILE -Value (Get-Date -Format o)

###
# Pull events using -After param with timestamp.  Use PowerShell Calculated Properties to rename some properties to expected values.
# For some reason, the -or operator doesn't work as expected in a single Where-Object cmdlet, so I had to use two.
###
$events = Get-EventLog -LogName $LogName -After $timestamp | Where-Object {$_.EntryType -notin $ExclLevel} | Where-Object {$_.EventID -notin $ExclEventID} | Select-Object @{Name = "hostname"; Expression = {$_.MachineName}}, `
																																								                                                                              @{Name = "message"; Expression = {$_.Message}}, `
																																								                                                                              @{Name = "level"; Expression = {$_.EntryType}}, `
																																								                                                                              TimeGenerated, Category, EventID, Source, UserName;

###
# Add required 'event_type' to objects from Get-EventLog.
# Add optional 'log_name' value to object.
###
$events | ForEach({

	Add-Member -NotePropertyName 'event_type' -NotePropertyValue 'Windows Event Logs' -InputObject $_;
  Add-Member -NotePropertyName 'log_name' -NotePropertyValue $LogName -InputObject $_;

	# Recast Level (Informational, Warning, Critical) from an enum to a string so we see it in the UI.
	$_.Level = [string]$_.Level;

});

###
# Create hash table in required format for Logs, populated
# with event object log data and pipe to ConvertTo-Json with
# -Compress argument required in order for Logs to consume.
###
$logPayload = @($events) | ConvertTo-Json -Compress

##
# Output json string created above with regex to normalize date strings
# post json string conversion..
#
# For some reason, PowerShell won't let me rename the TimeGenerated event property in the event object, so we have to resort
# to using a regex here.
###
$logPayload = Write-Output ($logPayload -replace '"\\\/Date\((\d+)\)\\\/\"' ,'$1')
$logPayload = Write-Output ($logPayload -replace 'TimeGenerated', 'timestamp')
Write-Output $logPayload

# Set the headers expected by Logs
$headers = @{'Content-Type' = 'application/json'; 'X-License-Key' = $nrLicenseKey}

# Do the post to the Logs API
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$response = Invoke-WebRequest $nrLogEndpoint -Headers $headers -Method 'POST' -Body $logPayload

#
# Create a structure readable by NR Infra with metadata about this transaction for meta-Logging / debugging purposes
#
$nrMetaData = @{'event_type' = 'winEventLogAgt'; 'appVersion' = $appVersion; 'excludedEvents' = $ExclEventID; 'excludedLevels' = $ExclLevel; 'hostTime' = Get-Date -UFormat %s -Millisecond 0; 'pullAfter' = $timestamp.ToString(); 'logName' = $LogName; 'eventCount' = $events.Count; 'nrLogsResponse' = $response.StatusCode}

$metaPayload = @{
    name = "com.newrelic.windows.eventlog"
    integration_version = "0.1.0"
    protocol_version = 1
	  metrics = @($nrMetaData)
    inventory = @{}
    events = @()
} | ConvertTo-Json -Compress
Write-Output $metaPayload

#Write-Output "Response" $response.StatusCode
