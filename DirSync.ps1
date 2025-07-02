<#
.SYNOPSIS
    Interactively synchronizes the contents of any two directories, selected via a graphical interface.

.DESCRIPTION
    This script provides a fully interactive way to synchronize two folders, whether they are on the
    same computer or on different computers across a network.
    1. It prompts the user to select the first folder using a file explorer dialog.
    2. It then prompts the user to select the second folder. This can be a local path (e.g., C:\...)
       or a network path (e.g., \\ComputerName\C$\...).
    3. It then performs a two-way sync, copying any missing files and folders between the two
       locations to make them identical.
    4. Finally, it outputs a list of all items that were copied.

.EXAMPLE
    .\Sync-CyberDirectory-Interactive.ps1
    (The script will open two folder browser dialogs to make your selections.)

.NOTES
    - For remote synchronization, you must have administrative privileges on the remote computer.
    - PowerShell Remoting must be enabled on the remote machine ('Enable-PSRemoting -Force').
    - The account running the script needs read/write permissions to the target folders, including
      administrative shares (e.g., C$) if used for remote paths.
#>

# --- Add .NET Assembly for Folder Browser Dialog ---
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
}
catch {
    Write-Error "Failed to load Windows Forms assembly. This script requires the .NET Framework."
    exit
}


# --- Function to let the user select a folder ---
function Get-FolderSelection {
    param([string]$Description)

    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = $Description
    $folderBrowser.ShowNewFolderButton = $true # Allow creating new folders
    $folderBrowser.RootFolder = "MyComputer"

    if ($folderBrowser.ShowDialog() -eq "OK") {
        return $folderBrowser.SelectedPath
    }
    else {
        Write-Host "Folder selection was cancelled. Exiting script."
        exit
    }
}


# --- Script Body ---

# Initialize an array to log the actions taken
$addedFilesLog = @()

# --- Function to Synchronize from Source to Destination ---
function Sync-Directory {
    param (
        [string]$SourceFullPath,
        [string]$DestinationFullPath
    )

    # Determine the source/destination names for logging purposes
    $sourceName = if ($SourceFullPath.StartsWith("\\")) { "remote path '$SourceFullPath'" } else { "local path '$SourceFullPath'" }
    $destinationName = if ($DestinationFullPath.StartsWith("\\")) { "remote path '$DestinationFullPath'" } else { "local path '$DestinationFullPath'" }

    Write-Host "--- Starting sync from $sourceName to $destinationName ---"

    # Check if the source directory exists
    if (-not (Test-Path $SourceFullPath)) {
        Write-Warning "Source directory $SourceFullPath does not exist. Skipping this sync direction."
        return
    }

    # Ensure the base directory exists on the destination, create if it doesn't
    if (-not (Test-Path $DestinationFullPath)) {
        Write-Host "Creating directory $DestinationFullPath..."
        try {
            New-Item -ItemType Directory -Path $DestinationFullPath -Force -ErrorAction Stop | Out-Null
            $addedFilesLog += "CREATED DIRECTORY: $DestinationFullPath"
        }
        catch {
             Write-Error "Failed to create directory on destination: $DestinationFullPath. Error: $_"
             return
        }
    }

    # Get all items from the source directory
    try {
        $sourceItems = Get-ChildItem -Path $SourceFullPath -Recurse -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to access source directory $SourceFullPath. Check permissions and network connectivity."
        return
    }

    # Compare source items with the destination
    foreach ($item in $sourceItems) {
        # Construct the corresponding path on the destination by replacing the base path
        $destinationItemPath = $item.FullName.Replace($SourceFullPath, $DestinationFullPath)

        # Check if the item exists on the destination
        if (-not (Test-Path $destinationItemPath)) {
            # If it doesn't exist, copy it
            Write-Host "Copying $($item.Name) to $destinationName..."

            # Create the parent directory on the destination if it doesn't exist
            $parentDir = Split-Path -Path $destinationItemPath -Parent
            if (-not (Test-Path $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }

            try {
                Copy-Item -Path $item.FullName -Destination $destinationItemPath -Recurse -Force -ErrorAction Stop
                $addedFilesLog += "COPIED: $($item.FullName) -> $destinationItemPath"
            }
            catch {
                Write-Error "Failed to copy $($item.FullName). Error: $_"
            }
        }
    }
    Write-Host "--- Sync from $sourceName to $destinationName complete ---`n"
}

# --- Main Execution ---

# 1. Interactively get the two folders to synchronize
$path1 = Get-FolderSelection -Description "STEP 1: Select the FIRST folder to synchronize"
$path2 = Get-FolderSelection -Description "STEP 2: Select the SECOND folder to synchronize"

Write-Host "Starting directory synchronization..."
Write-Host "Folder 1: $path1"
Write-Host "Folder 2: $path2"
Write-Host "-----------------------------------------------------------------"

# Sync from Folder 1 to Folder 2
Sync-Directory -SourceFullPath $path1 -DestinationFullPath $path2

# Sync from Folder 2 to Folder 1 (to catch any unique files)
Sync-Directory -SourceFullPath $path2 -DestinationFullPath $path1

# --- Output Results ---
Write-Host "================================================================="
Write-Host "Synchronization Complete. The following changes were made:"
Write-Host "================================================================="

if ($addedFilesLog.Count -eq 0) {
    Write-Host "No changes were needed. Directories were already in sync."
}
else {
    # Display unique changes only
    ($addedFilesLog | Get-Unique) | ForEach-Object { Write-Host $_ }
}

Write-Host "================================================================="
