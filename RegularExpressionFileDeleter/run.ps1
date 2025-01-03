# Define the root directory to scan
$rootDirectory = "C:\Users\LeanderAndersen\OneDrive - AGS IT-partner AS\Programering\RegularExpressionFileDeleter\Testfolder"

# Define filename patterns to match (regular expressions)
$patterns = @(
    "^Agent_Install .*\.msi$",        # Matches filename.exe, filename(1).exe, etc.
    "^Agent_Install.*\.msi$"     # Add other patterns as needed
)

# Function to check if a file matches any of the patterns
function MatchesPattern {
    param (
        [string]$fileName,
        [array]$patterns
    )

    foreach ($pattern in $patterns) {
        if ($fileName -match $pattern) {
            return $true
        }
    }
    return $false
}

# Function to recursively scan, delete files, and remove empty directories
function CleanDirectory {
    param (
        [string]$directoryPath,
        [array]$patterns
    )

    # Get all files in the current directory
    $files = Get-ChildItem -Path $directoryPath -File -Recurse

    foreach ($file in $files) {
        if (MatchesPattern -fileName $file.Name -patterns $patterns) {
            # Delete the file if it matches a pattern
            Write-Output "Deleting file: $($file.FullName)"
            Remove-Item -Path $file.FullName -Force
        }
    }

    # Get all subdirectories and check for emptiness
    $directories = Get-ChildItem -Path $directoryPath -Directory -Recurse

    foreach ($dir in $directories) {
        if (-not (Get-ChildItem -Path $dir.FullName -Recurse)) {
            # Delete the directory if it's empty
            Write-Output "Deleting empty directory: $($dir.FullName)"
            Remove-Item -Path $dir.FullName -Force -Recurse
        }
    }
}

# Run the cleanup process
CleanDirectory -directoryPath $rootDirectory -patterns $patterns
