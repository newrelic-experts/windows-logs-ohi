###
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
    [string]$LogName=$(throw "-LogName is mandatory")
)


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
# Write timestamp to file to pull on next run.
###
Set-Content -Path $LAST_PULL_TIMESTAMP_FILE -Value (Get-Date -Format o)

###
# Add required 'event_type' to objects from Get-EventLog.
# Add optional 'log_name' value to object.
###
[array]$events | $events = Get-EventLog -LogName $LogName -After $timestamp | ForEach-Object {
    @{
        event_type = "WindowsEventLogSample"
        logType = $LogName
        message = $_.Message
        machineName = $_.MachineName
        source = $_.Source
        entryType = $_.EntryType
    }
} 
###
# Create hash table in required format for Infrastructure, populated
# with event object log data and pipe to ConvertTo-Json with
# -Compress argument required in order for Infrastructure to consume.
###
$payload = @{
    name = "com.newrelic.windows.eventlog"
    integration_version = "0.2.0"
    protocol_version = 2
    data = @(
        @{
            entity = @{
                name = $LogName
                type = "WindowsEventLog"
            }
            metrics = @($events)
            inventory = @{}
            events = @()
        }
    )
} | ConvertTo-Json -Depth 10 -Compress


###
# Output json string created above with regex to normalize date strings
# post json string conversion. Alternatively, you could create a
# new -NotePropertyName with the proper date string and remove
# the original object property. 
###
Write-Output ($payload -replace '"\\\/Date\((\d+)\)\\\/\"' ,'$1')
