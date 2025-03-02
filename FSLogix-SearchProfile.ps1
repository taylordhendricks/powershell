# FSLogix  User Folder Search Tool (for when flip_flop wasnt enabled)
#
# Synopsis:
# This PowerShell script provides a GUI-based tool for searching user profile folders
# across multiple network shares. It enables users to quickly locate folders associated
# with a given username, display their paths and sizes, and interact with the results.
#
# Features:
# - Windows Forms-based GUI with a search bar, DataGridView, and progress indicators.
# - Parallel searching across multiple network shares using background jobs.
# - Reads share locations dynamically from an external INI file (`config.ini`).
# - Resizable UI layout with dedicated panels for search input, results display, and status updates.
# - Right-click context menu and double-click navigation for interacting with folder paths.
# - Real-time status updates via a progress bar and status label.
#
# Prerequisites:
# - Windows OS with .NET Framework (System.Windows.Forms).
# - PowerShell Execution Policy allowing script execution.
# - Access to the network shares specified in `config.ini`.
#
# Usage:
# 1. Run the script (`User-folder-search-tool.ps1`).
# 2. Enter a username in the search bar and click 'Search'.
# 3. View results, including folder path and size.
# 4. Right-click or double-click on results to interact.
#
# Customization:
# - Modify [Shares] section in the `config.ini` to define network shares dynamically.
# - Modify [Settings] section in the `config.ini` for Font scaling.
#

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Functions (copied into each job) --
function Convert-SizeToString {
    param([double]$Bytes)
    if    ($Bytes -lt 1KB) { return ("{0} B" -f $Bytes) }
    elseif($Bytes -lt 1MB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    elseif($Bytes -lt 1GB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    else                   { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
}

function Get-FolderSize {
    param([string]$FolderPath)
    try {
        $totalBytes = (Get-ChildItem -Path $FolderPath -Recurse -ErrorAction SilentlyContinue |
                       Measure-Object -Property Length -Sum).Sum
        return Convert-SizeToString $totalBytes
    }
    catch {
        return "Unable to calculate size"
    }
}

# Function to check and create config.ini if missing
function Test-ConfigIniExists {
    param([string]$ConfigFilePath)
    if (-Not (Test-Path $ConfigFilePath)) {
        $sampleConfig = @"
[Shares]
; Add as many shares as you want to check just be sure to place on it's own line and start with 'Share#='' where '#' is the next number
Share1=\\server1\share1
Share2=\\server2\share2
Share3=\\server3\share3

[Settings]
; Avoid going above size 20
; Default = 11
FontSize=11
"@
        $sampleConfig | Set-Content -Path $ConfigFilePath -Encoding UTF8
        Write-Host "Created sample config.ini at: $ConfigFilePath"
    }
}

function Get-SharesFromIni {
    param(
        [string]$ConfigFile,
        [string]$Section = 'Shares'
    )

    $lines = Get-Content -Path $ConfigFile -ErrorAction Stop
    $insideTargetSection = $false
    $shareList = @()

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if (!$trimmed -or $trimmed.StartsWith('#') -or $trimmed.StartsWith(';')) {
            continue
        }

        if ($trimmed -match '^\[(.+)\]$') {
            $currentSection = $Matches[1]
            $insideTargetSection = ($currentSection -eq $Section)
            continue
        }

        if ($insideTargetSection -and ($trimmed -match '^(?<key>[^=]+)=(?<value>.+)$')) {
            $key = $Matches['key'].Trim()
            $value = $Matches['value'].Trim()
            $shareList += $value
        }
    }
    return $shareList
}

function Get-FontSizeFromIni {
    param([string]$ConfigFile, [string]$Section = 'Settings', [string]$Key = 'FontSize')

    $lines = Get-Content -Path $ConfigFile -ErrorAction SilentlyContinue
    $insideTargetSection = $false

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if (!$trimmed -or $trimmed.StartsWith('#') -or $trimmed.StartsWith(';')) { continue }
        
        if ($trimmed -match '^\[(.+)\]$') {
            $insideTargetSection = ($Matches[1] -eq $Section)
            continue
        }
        
        if ($insideTargetSection -and ($trimmed -match "^\s*$Key\s*=\s*(\d+)")) {
            return [int]$Matches[1]
        }
    }
    return 10  # Default font size if not found
}

function Get-LastModifiedDate {
    param([string]$FolderPath)
    try {
        return (Get-Item -Path $FolderPath -ErrorAction SilentlyContinue).LastWriteTime
    }
    catch {
        return "N/A"
    }
}

function Get-LastAccessedDate {
    param([string]$FolderPath)
    try {
        return (Get-Item -Path $FolderPath -ErrorAction SilentlyContinue).LastAccessTime
    }
    catch {
        return "N/A"
    }
}

function Get-ScriptDirectory {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($MyInvocation.MyCommand.Path) {
        return Split-Path $MyInvocation.MyCommand.Path
    }
    return [System.IO.Path]::GetDirectoryName(
        [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    )
}

$scriptDir = Get-ScriptDirectory
$iniPath   = Join-Path $scriptDir 'config.ini'
Test-ConfigIniExists -ConfigFilePath $iniPath
$global:Shares      = Get-SharesFromIni -ConfigFile $iniPath
$global:FontSize    = Get-FontSizeFromIni -ConfigFile $iniPath

if (!$Shares) {
    Write-Host "No shares found in [Shares] section of $iniPath"
    return
}

$form               = New-Object System.Windows.Forms.Form
$form.Font          = New-Object System.Drawing.Font("Segoe UI", $FontSize, [System.Drawing.FontStyle]::Regular)
$form.Text          = "User Folder Search"
$form.Size          = New-Object System.Drawing.Size(700, 500)
$form.MinimumSize   = New-Object System.Drawing.Size(700, 500) 
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'Sizable'

# ------------------------------------------------------------------------
# TOP Layout: TableLayoutPanel for label, textbox, button
# ------------------------------------------------------------------------
$tableTop = New-Object System.Windows.Forms.TableLayoutPanel
$tableTop.Dock = 'Top'
$tableTop.AutoSize = $true
$tableTop.AutoSizeMode = 'GrowAndShrink'
$tableTop.RowCount = 1
$tableTop.ColumnCount = 3

# Column 0: auto-size for label
$colStyleLabel = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)
$tableTop.ColumnStyles.Add($colStyleLabel)

# Column 1: fill for the textbox
$colStyleText = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)
$tableTop.ColumnStyles.Add($colStyleText)

# Column 2: auto-size for the button
$colStyleButton = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)
$tableTop.ColumnStyles.Add($colStyleButton)

# Label
$labelUser              = New-Object System.Windows.Forms.Label
$labelUser.Text         = "Enter username:"
$labelUser.AutoSize     = $true
$labelUser.Font         = $form.Font
$labelUser.Margin       = New-Object System.Windows.Forms.Padding(5, 3, 5, 3)

# TextBox
$textboxUser            = New-Object System.Windows.Forms.TextBox
$textboxUser.Font       = $form.Font
$textboxUser.Dock       = 'Fill'

# Button
$buttonSearch           = New-Object System.Windows.Forms.Button
$buttonSearch.Font      = $form.Font
$buttonSearch.Text      = "Search"
$buttonSearch.AutoSize  = $true


# Add them to the TableLayout
[void]$tableTop.Controls.Add($labelUser,   0, 0)  # column 0
[void]$tableTop.Controls.Add($textboxUser, 1, 0)  # column 1
[void]$tableTop.Controls.Add($buttonSearch,2, 0)  # column 2

$form.AcceptButton = $buttonSearch

# ------------------------------------------------------------------------
# MIDDLE Panel => holds the DataGridView
# ------------------------------------------------------------------------
$panelMiddle = New-Object System.Windows.Forms.Panel
$panelMiddle.Dock = 'Fill'

$dataGrid                       = New-Object System.Windows.Forms.DataGridView
$dataGrid.Dock                  = 'Fill'
$dataGrid.AllowUserToAddRows    = $false
$dataGrid.ReadOnly              = $true
$dataGrid.DefaultCellStyle.Font = $form.Font
$dataGrid.SelectionMode         = 'FullRowSelect'
$dataGrid.MultiSelect           = $false

$dataGrid.AutoSizeColumnsMode   = 'None'
$dataGrid.AutoSizeRowsMode      = [System.Windows.Forms.DataGridViewAutoSizeRowsMode]::AllCells
$dataGrid.ColumnHeadersHeightSizeMode = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::AutoSize

# Path column (Fill)
$colPath = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colPath.Name         = 'Path'
$colPath.HeaderText   = 'Folder Path'
$colPath.Width        = 400
$colPath.AutoSizeMode = 'Fill'
$dataGrid.Columns.Add($colPath) | Out-Null

# Size column (fixed)
$colSize = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colSize.Name         = 'Size'
$colSize.HeaderText   = 'Size'
$colSize.Width        = 80
$colSize.AutoSizeMode = 'None'
$dataGrid.Columns.Add($colSize) | Out-Null

# Modified column (DisplayCells)
$colModified = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colModified.Name         = 'Modified'
$colModified.HeaderText   = 'Last Modified'
$colModified.Width        = 150
$colModified.AutoSizeMode = 'DisplayedCells'
$dataGrid.Columns.Add($colModified) | Out-Null

# Accessed column (DisplayCells)
$colAccessed = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colAccessed.Name         = 'Accessed'
$colAccessed.HeaderText   = 'Last Accessed'
$colAccessed.Width        = 150
$colAccessed.AutoSizeMode = 'DisplayedCells'
$dataGrid.Columns.Add($colAccessed) | Out-Null

# Context menu
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$contextMenu.Font = New-Object System.Drawing.Font("Segoe UI", $FontSize, [System.Drawing.FontStyle]::Regular)

$menuItemCopyPath     = $contextMenu.Items.Add("Copy Path")
$menuItemOpenExplorer = $contextMenu.Items.Add("Open in Explorer")
$dataGrid.ContextMenuStrip = $contextMenu

$dataGrid.add_CellMouseDown({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right -and $e.RowIndex -ge 0) {
        $dataGrid.ClearSelection()
        $dataGrid.Rows[$e.RowIndex].Selected = $true
        $dataGrid.CurrentCell = $dataGrid.Rows[$e.RowIndex].Cells[$e.ColumnIndex]
    }
})

$menuItemCopyPath.add_Click({
    if ($dataGrid.CurrentCell -and $dataGrid.CurrentCell.RowIndex -ge 0) {
        $rowIndex = $dataGrid.CurrentCell.RowIndex
        $folderPath = $dataGrid.Rows[$rowIndex].Cells['Path'].Value
        if ($folderPath) {
            [System.Windows.Forms.Clipboard]::SetText($folderPath)
            [System.Windows.Forms.MessageBox]::Show("Copied: $folderPath")
        }
    }
})

$menuItemOpenExplorer.add_Click({
    if ($dataGrid.CurrentCell -and $dataGrid.CurrentCell.RowIndex -ge 0) {
        $rowIndex = $dataGrid.CurrentCell.RowIndex
        $folderPath = $dataGrid.Rows[$rowIndex].Cells['Path'].Value
        if ($folderPath) {
            Start-Process explorer.exe $folderPath
        }
    }
})

[void]$panelMiddle.Controls.Add($dataGrid)

# ------------------------------------------------------------------------
# BOTTOM Panel (status + progress)
# ------------------------------------------------------------------------
$panelBottom = New-Object System.Windows.Forms.Panel
$panelBottom.Dock   = 'Bottom'
$panelBottom.Height = 60

$labelStatus = New-Object System.Windows.Forms.Label
$labelStatus.Font       = $form.Font
$labelStatus.AutoSize   = $true
$labelStatus.Text       = "Status: Idle..."
$labelStatus.Location   = New-Object System.Drawing.Point(20, 20)
$labelStatus.Anchor     = [System.Windows.Forms.AnchorStyles]::Left

# Panel for Progress Bar
$progressPanel = New-Object System.Windows.Forms.Panel
$progressPanel.Dock     = 'Right'
$progressPanel.Width    = 270
$progressPanel.Padding  = New-Object System.Windows.Forms.Padding(15, 10, 15, 10)
$progressPanel.Height   = $panelBottom.Height

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Size   = New-Object System.Drawing.Size(250, 15)
$progressBar.Dock   = 'Right'
$progressBar.Style  = 'Continuous'

[void]$progressPanel.Controls.Add($progressBar)
[void]$panelBottom.Controls.Add($progressPanel)
[void]$panelBottom.Controls.Add($labelStatus)

# ------------------------------------------------------------------------
# Add them in top -> middle -> bottom order
# ------------------------------------------------------------------------
$form.Controls.Add($panelBottom)
$form.Controls.Add($panelMiddle)
$form.Controls.Add($tableTop)  # your top 'panel' is now a TableLayoutPanel

# ------------------------------------------------------------------------
# Timer & background jobs
# ------------------------------------------------------------------------
$timerCheckJobs = New-Object System.Windows.Forms.Timer
$timerCheckJobs.Interval = 1000

$script:jobs = @()
$script:jobsTotal = 0

$timerCheckJobs.Add_Tick({
    if ($script:jobs.Count -gt 0) {
        foreach ($j in $script:jobs) {
            Write-Host "[Timer Tick] Job $($j.Id) State: $($j.State)"
        }
        Write-Host "[Timer Tick] Checking Job Status"
        $completed = Get-Job | Where-Object { $_.State -in 'Completed','Failed','Stopped' }
        if ($completed) {
            foreach ($job in $completed) {
                Write-Host "[Timer Tick] Receiving job ID $($job.Id)"
                $results = Receive-Job -Job $job -ErrorAction SilentlyContinue
                Remove-Job -Job $job -Force | Out-Null
                $script:jobs = $script:jobs | Where-Object { $_.Id -ne $job.Id }

                if ($results) {
                    foreach ($item in $results) {
                        Write-Host "[Timer Tick] Adding '$($item.Path)' to datagrid"
                        [void]$dataGrid.Rows.Add(
                            $item.Path,
                            $item.Size,
                            $item.Modified,
                            $item.Accessed
                        )
                    }
                }
            }
        }

        $completedCount = $script:jobsTotal - $script:jobs.Count
        $labelStatus.Text = "Status: Searching... ($completedCount of $($script:jobsTotal) complete)"
        $progressBar.Value = $completedCount

        if ($script:jobs.Count -eq 0) {
            $timerCheckJobs.Stop()
            Write-Host "[Timer Tick] All jobs complete. ($completedCount of $($script:jobsTotal))"
            $labelStatus.Text = "Status: Search Complete. ($completedCount of $($script:jobsTotal))"
            $progressBar.Value = $progressBar.Maximum
        }
    }
    else {
        $timerCheckJobs.Stop()
        if ($script:jobsTotal -eq 0) {
            Write-Host "[Timer Tick] No jobs => Idle"
            $labelStatus.Text = "Status: Idle"
            $progressBar.Value = 0
        }
    }
})

$buttonSearch.Add_Click({
    $username = $textboxUser.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($username)) {
        [System.Windows.Forms.MessageBox]::Show("Please enter a username.")
        return
    }

    $dataGrid.Rows.Clear()
    $oldJobs = Get-Job -ErrorAction SilentlyContinue | Where-Object { $_.State -in 'Running','Completed','Failed','Stopped' }
    if ($oldJobs) {
        Remove-Job -Job $oldJobs -Force | Out-Null
    }

    $script:jobs      = @()
    $script:jobsTotal = $Shares.Count

    $labelStatus.Text = "Status: Starting $($script:jobsTotal) jobs..."

    $progressBar.Minimum = 0
    $progressBar.Maximum = $script:jobsTotal
    $progressBar.Value   = 0

    foreach ($share in $Shares) {
        $scriptBlock = {
            param($share, $username)
            try {
                function Convert-SizeToString {
                    param([double]$Bytes)
                    if    ($Bytes -lt 1KB) { return ("{0} B" -f $Bytes) }
                    elseif($Bytes -lt 1MB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
                    elseif($Bytes -lt 1GB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
                    else                   { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
                }
                function Get-FolderSize {
                    param([string]$FolderPath)
                    try {
                        $totalBytes = (Get-ChildItem -Path $FolderPath -Recurse -ErrorAction SilentlyContinue |
                                       Measure-Object -Property Length -Sum).Sum
                        return Convert-SizeToString $totalBytes
                    }
                    catch {
                        return "Unable to calculate size"
                    }
                }
                function Get-LastModifiedDate {
                    param([string]$FolderPath)
                    try {
                        return (Get-Item -Path $FolderPath -ErrorAction SilentlyContinue).LastWriteTime
                    }
                    catch {
                        return "N/A"
                    }
                }
                function Get-LastAccessedDate {
                    param([string]$FolderPath)
                    try {
                        return (Get-Item -Path $FolderPath -ErrorAction SilentlyContinue).LastAccessTime
                    }
                    catch {
                        return "N/A"
                    }
                }

                $collected = @()
                try {
                    $dirs = Get-ChildItem -Path $share -Directory -ErrorAction SilentlyContinue
                    $userDirs = $dirs | Where-Object { $_.Name -like "*_$username" }

                    foreach ($dir in $userDirs) {
                        $collected += [pscustomobject]@{
                            Path     = $dir.FullName
                            Size     = Get-FolderSize -FolderPath $dir.FullName
                            Modified = Get-LastModifiedDate -FolderPath $dir.FullName
                            Accessed = Get-LastAccessedDate -FolderPath $dir.FullName
                        }
                    }
                }
                catch {
                    $_ | Out-File "C:\\Temp\\JobError_$($share -replace '\\\\','-').log"
                }
                return $collected
            }
            catch {
                $_ | Out-File "C:\\Temp\\JobError_main_$($share -replace '\\\\','-').log"
            }
        }

        $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $share, $username
        Write-Host "[ButtonClick] Started job $($job.Id) for share $share. State: $($job.State)"
        $script:jobs += $job
        Write-Host "[ButtonClick] => Now $($script:jobs.Count) total jobs in array"
    }

    $timerCheckJobs.Start()
})

$dataGrid.add_CellDoubleClick({
    param([System.Object]$sender, [System.Windows.Forms.DataGridViewCellEventArgs]$e)
    if ($e.RowIndex -ge 0) {
        $folderPath = $dataGrid.Rows[$e.RowIndex].Cells["Path"].Value
        if ($folderPath) {
            Start-Process "explorer.exe" $folderPath
        }
    }
})

[void] $form.ShowDialog()
