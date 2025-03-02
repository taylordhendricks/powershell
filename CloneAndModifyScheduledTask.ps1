#Run PowerShell as an administrator

# Define the original task name and folder
$OriginalTaskName = "OriginalTaskName"
$TaskFolder = "\Folder\"  # Specify the subfolder in the Task Scheduler Library

# Define the new task name
$NewTaskName = "newTaskName"

# Export the existing task to an XML file using PowerShell
$ExportPath = "$env:TEMP\Task.xml"
$taskXmlString = Export-ScheduledTask -TaskName $OriginalTaskName -TaskPath $TaskFolder

# Save the XML string to a file
[System.IO.File]::WriteAllText($ExportPath, $taskXmlString)

# Modify the XML file - for example, changing the task description
[xml]$taskXml = Get-Content -Path $ExportPath

# Modify the task action to point to a new executable
$taskXml.Task.Actions.Exec.Command = "C:\Scripts\pathToScript.bat"
$taskXml.Task.Triggers.CalendarTrigger.ScheduleByMonth.DaysOfMonth.Day = "2"

# Save the modified XML
$taskXml.Save($ExportPath)

# Register the new task using the modified XML
Register-ScheduledTask -Xml (Get-Content -Path $ExportPath -Raw) -TaskName $NewTaskName -TaskPath $TaskFolder

# Clean up the temporary file
Remove-Item $ExportPath
