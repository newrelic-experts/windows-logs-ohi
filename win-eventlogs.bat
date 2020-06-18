@ECHO OFF
powershell.exe -ExecutionPolicy Unrestricted -file win-eventlogs.ps1 -LogName %logname% -ExclLevel %excllevel% -ExclEventID %excleventid% -nrLicenseKey %nrlicensekey%
