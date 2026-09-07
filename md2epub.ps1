<#PSScriptInfo

.VERSION 1.0

.GUID 5f8e2a1b-4c3d-4e5f-8a2b-1c3d4e5f6a7b

.AUTHOR Mistral Vibe

.DESCRIPTION
MD2EPUB Converter - Automatically converts markdown files to EPUB format
using pandoc.exe. Extracts title and author from filename pattern "<title> by <author>".

Removes weblinks, uses first embedded image as cover, archives processed files.

.EXAMPLE
.\md2epub.ps1
Converts all matching .md files in D:\vault\Blinks to EPUB

.EXAMPLE
powershell.exe -ExecutionPolicy Bypass -File "D:\vault\Blinks\md2epub.ps1"
For scheduled task execution

#>

<#
.MODULE MANIFEST
#>

[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$TestRun = $false,
    [switch]$VerboseLogging = $false,
    [switch]$SkipCalibre = $false,
    [string]$CalibreLibrary = $null
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$ScriptName = "MD2EPUB Converter"
$ScriptVersion = "1.0.0"
$ScriptDate = "2026-09-06"

# Directories
$InputDir = "D:\vault\Blinks"
$OutputDir = "d:\books"
$ArchiveDir = "$InputDir\archive"

# Tools
$PandocPath = "d:\booktools\pandoc.exe"
$CalibrePath = "C:\Program Files\Calibre2\calibredb.exe"

# Calibre Integration
$AddToCalibre = $true
$CalibreLibraryPath = $null  # $null = use default library

# Output
$LogFile = "$OutputDir\md2epub.log"

# Settings
$MaxRetryAttempts = 2
$RetryDelaySeconds = 2
$TocDepth = 3
$EpubVersion = "epub3"
$Language = "en"

# ============================================================================
# LOGGING FUNCTION
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO",
        [switch]$NoTimestamp = $false
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    if ($NoTimestamp) {
        $logEntry = "[$Level] $Message"
    } else {
        $logEntry = "[$timestamp] [$Level] $Message"
    }
    
    # Ensure log directory exists
    $logDir = [System.IO.Path]::GetDirectoryName($LogFile)
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    # Write to log file
    Add-Content -Path $LogFile -Value $logEntry -Encoding UTF8
    
    # Also write to console
    $consoleColor = "White"
    switch ($Level) {
        "ERROR" { $consoleColor = "Red" }
        "WARN" { $consoleColor = "Yellow" }
        "SUCCESS" { $consoleColor = "Green" }
        default { $consoleColor = "White" }
    }
    
    if ($VerboseLogging -or $Level -in @("ERROR", "WARN", "SUCCESS")) {
        Write-Host "$logEntry" -ForegroundColor $consoleColor
    }
}

# ============================================================================
# INITIALIZATION
# ============================================================================

function Initialize-Environment {
    Write-Log "=== $ScriptName v$ScriptVersion - Starting ===" "INFO" -NoTimestamp
    Write-Log "Script path: $($MyInvocation.MyCommand.Definition)" "INFO"
    Write-Log "PowerShell version: $($PSVersionTable.PSVersion)" "INFO"
    
    # Validate pandoc exists
    if (-not (Test-Path $PandocPath)) {
        Write-Log "ERROR: Pandoc not found at $PandocPath" "ERROR"
        return $false
    }
    Write-Log "Pandoc found: $PandocPath" "INFO"
    
    # Create directories if they don't exist
    $directories = @($InputDir, $OutputDir, $ArchiveDir)
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            try {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-Log "Created directory: $dir" "INFO"
            } catch {
                Write-Log "Failed to create directory $dir : $_" "ERROR"
                return $false
            }
        }
    }
    
    return $true
}

# ============================================================================
# FILE PARSING
# ============================================================================

function Parse-Filename {
    param([string]$Filename)
    
    try {
        $basename = [System.IO.Path]::GetFileNameWithoutExtension($Filename)
        
        # Split on first occurrence of " by " only
        $parts = $basename -split ' by ', 2
        
        if ($parts.Count -eq 2 -and $parts[0].Trim() -ne "" -and $parts[1].Trim() -ne "") {
            return @{
                Success = $true
                Title = $parts[0].Trim()
                Author = $parts[1].Trim()
                BaseName = $basename
            }
        } else {
            return @{
                Success = $false
                Error = "Filename does not match pattern '<title> by <author>'"
            }
        }
    } catch {
        return @{
            Success = $false
            Error = "Error parsing filename: $_"
        }
    }
}

# ============================================================================
# PRE-PROCESSING: Remove Links, Detect Images
# ============================================================================

function Preprocess-File {
    param(
        [string]$FilePath,
        [ref]$FirstImage
    )
    
    try {
        # Read file content
        $content = Get-Content -Path $FilePath -Raw -Encoding UTF8
        
        # Remove YAML front matter (everything between --- lines at the beginning)
        if ($content.StartsWith("---")) {
            $lines = $content -split "`n"
            $inYaml = $false
            $newLines = @()
            foreach ($line in $lines) {
                if ($line -eq "---" -and -not $inYaml) {
                    $inYaml = $true
                } elseif ($line -eq "---" -and $inYaml) {
                    $inYaml = $false
                } elseif (-not $inYaml) {
                    $newLines += $line
                }
            }
            $content = $newLines -join "`n"
        }
        
        # Remove markdown links: [text](url) -> text
        $linkPattern = '\[([^\]]+)\]\([^\)]+\)'
        $content = $content -replace $linkPattern, '$1'
        
        # Remove HTML audio/video tags
        $content = $content -replace '<audio[^>]*>.*?</audio>', ''
        $content = $content -replace '<video[^>]*>.*?</video>', ''
        $content = $content -replace '<iframe[^>]*>.*?</iframe>', ''
        
        # Remove other HTML tags
        $content = $content -replace '<[^>]+>', ''
        
        # Remove bare URLs
        $content = $content -replace 'https?://[^\s]+', ''
        $content = $content -replace 'www\.[^\s]+', ''
        
        # Detect first markdown image: ![alt](path)
        $imagePattern = '\!\[[^\]]*\]\(([^\)]+)\)'
        $imageMatches = [regex]::Matches($content, $imagePattern)
        
        if ($imageMatches.Count -gt 0) {
            $firstImagePath = $imageMatches[0].Groups[1].Value
            # Resolve relative path if needed
            if ($firstImagePath -notlike "*:*" -and $firstImagePath -notlike "\\*" -and $firstImagePath -notlike "/*") {
                $fileDir = [System.IO.Path]::GetDirectoryName($FilePath)
                $firstImagePath = Join-Path -Path $fileDir -ChildPath $firstImagePath
            }
            if (Test-Path $firstImagePath) {
                $FirstImage.Value = $firstImagePath
                Write-Log "First image detected: $firstImagePath" "INFO"
            } else {
                Write-Log "Image reference found but file not accessible: $firstImagePath" "WARN"
            }
        }
        
        # Create temporary file in input directory (to avoid path issues)
        $tempDir = $InputDir
        $tempPath = Join-Path -Path $tempDir -ChildPath "md2epub_$(Get-Date -Format 'yyyyMMdd_HHmmss_fff').md"
        
        # Write preprocessed content
        $content | Out-File -FilePath $tempPath -Encoding UTF8
        
        return @{
            Success = $true
            TempFilePath = $tempPath
            LinksRemoved = ($content -cmatch $linkPattern).Count
            ImagesFound = $imageMatches.Count
        }
        
    } catch {
        Write-Log "Error preprocessing file $FilePath : $_" "ERROR"
        return @{
            Success = $false
            Error = $_
        }
    }
}

# ============================================================================
# PANDOC CONVERSION
# ============================================================================

function Convert-File {
    param(
        [string]$MdPath
    )
    
    $filename = [System.IO.Path]::GetFileName($MdPath)
    Write-Log "Processing: $filename" "INFO"
    
    # Step 1: Parse filename
    $parsed = Parse-Filename -Filename $filename
    if (-not $parsed.Success) {
        Write-Log "Skipping $filename - $($parsed.Error)" "WARN"
        return @{ Success = $false; Error = $parsed.Error; Filename = $filename }
    }
    
    $title = $parsed.Title
    $author = $parsed.Author
    $outputFile = "$OutputDir\$($filename.Replace('.md', '.epub'))"
    
    Write-Log "Title: $title, Author: $author" "INFO"
    Write-Log "Output: $outputFile" "INFO"
    
    # Step 2: Pre-process file (remove links, detect images)
    $firstImage = $null
    $preprocessed = Preprocess-File -FilePath $MdPath -FirstImage ([ref]$firstImage)
    
    if (-not $preprocessed.Success) {
        Write-Log "Preprocessing failed for $($filename): $($preprocessed.Error)" "ERROR"
        return @{ Success = $false; Error = $preprocessed.Error; Filename = $filename }
    }
    
    Write-Log "Preprocessing complete: removed $($preprocessed.LinksRemoved) links, found $($preprocessed.ImagesFound) images" "INFO"
    
    # Step 3: Build pandoc command
    $pandocArgs = @(
        "$($preprocessed.TempFilePath)",
        "-o", "$outputFile",
        "--metadata", "title=$title",
        "--metadata", "author=$author",
        "--metadata", "lang=$Language",
        "--from=markdown",
        "--to=$EpubVersion",
        "--standalone",
        "--toc",
        "--toc-depth=$TocDepth",
        "--epub-title-page"
    )
    
    # Add cover image if available
    if ($firstImage -and (Test-Path $firstImage)) {
        $pandocArgs += "--epub-cover-image", $firstImage
        Write-Log "Using cover image: $firstImage" "INFO"
    }
    
    Write-Log "Pandoc command: $PandocPath $($pandocArgs -join ' ')" "INFO"
    
    # Step 4: Execute pandoc with retry logic
    $success = $false
    $lastError = $null
    
    for ($attempt = 1; $attempt -le $MaxRetryAttempts; $attempt++) {
        Write-Log "Attempt $attempt/$MaxRetryAttempts for $filename" "INFO"
        
        try {
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = $PandocPath
            # Quote the input file path if it contains spaces
            $quotedArgs = $pandocArgs | ForEach-Object { 
                if ($_ -like "* *" -and $_ -notlike '"*"') { "`"$_`"" } else { $_ }
            }
            $processInfo.Arguments = $quotedArgs -join ' '
            $processInfo.RedirectStandardError = $true
            $processInfo.RedirectStandardOutput = $true
            $processInfo.UseShellExecute = $false
            $processInfo.CreateNoWindow = $true
            $processInfo.WorkingDirectory = $InputDir
            
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $processInfo
            $process.Start() | Out-Null
            
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            
            $exitCode = $process.ExitCode
            
            if ($exitCode -eq 0) {
                $success = $true
                Write-Log "Pandoc conversion successful (exit code: $exitCode)" "SUCCESS"
                break
            } else {
                $lastError = "Exit code: $exitCode. Stderr: $stderr"
                Write-Log "Pandoc failed (attempt $attempt/$MaxRetryAttempts): $lastError" "ERROR"
            }
            
        } catch {
            $lastError = "Exception: $_"
            Write-Log "Exception during conversion (attempt $attempt/$MaxRetryAttempts): $lastError" "ERROR"
        }
        
        # Delay before retry (except on last attempt)
        if ($attempt -lt $MaxRetryAttempts -and -not $success) {
            Write-Log "Waiting $RetryDelaySeconds seconds before retry..." "INFO"
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
    
    # Step 5: Cleanup temporary file
    try {
        if (Test-Path $preprocessed.TempFilePath) {
            Remove-Item -Path $preprocessed.TempFilePath -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Log "Warning: Could not delete temp file $($preprocessed.TempFilePath): $_" "WARN"
    }
    
    if ($success) {
        # Step 6: Archive original file
        $archivePath = "$ArchiveDir\$filename"
        try {
            if ($TestRun) {
                Write-Log "[TEST MODE] Would move $MdPath to $archivePath" "INFO"
            } else {
                Move-Item -Path $MdPath -Destination $archivePath -Force -ErrorAction Stop
                Write-Log "Archived: $filename -> $ArchiveDir\$filename" "SUCCESS"
            }
        } catch {
            Write-Log "Failed to archive $($filename): $_" "ERROR"
            # Still consider conversion successful if pandoc worked
        }
        
        # Add to Calibre library
        if (-not $TestRun) {
            Add-To-Calibre -EpubFilePath $outputFile -Title $title -Author $author
        } else {
            Write-Log "[TEST MODE] Would add to Calibre: $outputFile" "INFO"
        }
        
        return @{
            Success = $true
            Filename = $filename
            OutputFile = $outputFile
            Title = $title
            Author = $author
        }
    } else {
        return @{
            Success = $false
            Filename = $filename
            Error = $lastError
        }
    }
}

# ============================================================================
# CALIBRE INTEGRATION
# ============================================================================

function Add-To-Calibre {
    param(
        [string]$EpubFilePath,
        [string]$Title,
        [string]$Author
    )
    
    # Only add to Calibre if enabled and file exists
    if (-not $AddToCalibre -or $SkipCalibre -or -not (Test-Path $EpubFilePath)) {
        return $false
    }
    
    try {
        # Build calibre command
        $calibreArgs = @(
            "add",
            "`"$EpubFilePath`"",  # Quote the file path
            "--title=`"$Title`"",
            "--authors=`"$Author`"",
            "--languages=en"
        )
        
        # Add library path if specified (parameter overrides config)
        $libraryPath = $CalibreLibrary
        if (-not [string]::IsNullOrEmpty($libraryPath)) {
            $calibreArgs += "--with-library=`"$libraryPath`""
        } elseif (-not [string]::IsNullOrEmpty($CalibreLibraryPath)) {
            $calibreArgs += "--with-library=`"$CalibreLibraryPath`""
        }
        
        Write-Log "Adding to Calibre: $EpubFilePath" "INFO"
        
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $CalibrePath
        $processInfo.Arguments = $calibreArgs -join ' '
        $processInfo.RedirectStandardError = $true
        $processInfo.RedirectStandardOutput = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        
        $exitCode = $process.ExitCode
        
        if ($exitCode -eq 0) {
            Write-Log "Successfully added to Calibre library: $Title by $Author" "SUCCESS"
            return $true
        } else {
            Write-Log "Failed to add to Calibre (exit code: $exitCode): $stderr" "ERROR"
            return $false
        }
        
    } catch {
        Write-Log "Exception adding to Calibre: $_" "ERROR"
        return $false
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Display help
if ($Help) {
    Get-Help -Name $MyInvocation.MyCommand.Definition -Detailed
    exit 0
}

Write-Log "=== STARTING $ScriptName v$ScriptVersion ===" "INFO" -NoTimestamp
Write-Log "Mode: $(if ($TestRun) { 'TEST RUN (no files moved)' } else { 'PRODUCTION' })" "INFO"

# Initialize environment
if (-not (Initialize-Environment)) {
    Write-Log "Environment initialization failed. Exiting." "ERROR"
    exit 1
}

# Find all markdown files matching pattern
Write-Log "Scanning for .md files in $InputDir..." "INFO"

$mdFiles = Get-ChildItem -Path $InputDir -Filter "*.md" | 
    Where-Object { 
        $_.Name -match ' by ' -and 
        $_.Name -notlike "*archive*" -and
        $_.FullName -notlike "*$ArchiveDir*"
    } | 
    Sort-Object -Property Name

$totalFiles = $mdFiles.Count
Write-Log "Found $totalFiles .md file(s) matching pattern" "INFO"

if ($totalFiles -eq 0) {
    Write-Log "No matching files found. Exiting." "INFO"
    exit 0
}

# Process files
$results = @()
$convertedCount = 0
$failedCount = 0
$skippedCount = 0

foreach ($file in $mdFiles) {
    Write-Log "`n--- Processing $($file.Name) ---" "INFO"
    
    $result = Convert-File -MdPath $file.FullName
    $results += $result
    
    if ($result.Success) {
        $convertedCount++
    } elseif ($result.Error -like "*does not match pattern*" -or $result.Error -like "*Filename does not match*") {
        $skippedCount++
    } else {
        $failedCount++
    }
}

# ============================================================================
# REPORTING
# ============================================================================

Write-Log "`n=== CONVERSION REPORT ===" "INFO" -NoTimestamp
Write-Log "Total files found: $totalFiles" "INFO"
Write-Log "Successfully converted: $convertedCount" "SUCCESS"

if ($skippedCount -gt 0) {
    Write-Log "Skipped (invalid pattern): $skippedCount" "WARN"
}

if ($failedCount -gt 0) {
    Write-Log "Failed: $failedCount" "ERROR"
}

Write-Log "Log file: $LogFile" "INFO"

# List successfully converted files
if ($convertedCount -gt 0) {
    Write-Log "`nSuccessfully converted files:" "INFO"
    $results | Where-Object { $_.Success } | ForEach-Object {
        Write-Log "  [OK] $($_.Filename) -> $($_.OutputFile)" "SUCCESS"
    }
}

# List failed files
if ($failedCount -gt 0) {
    Write-Log "`nFailed files:" "ERROR"
    $results | Where-Object { -not $_.Success -and $_.Error -notlike "*does not match pattern*" } | ForEach-Object {
        Write-Log "  [FAIL] $($_.Filename): $($_.Error)" "ERROR"
    }
}

# List skipped files
if ($skippedCount -gt 0) {
    Write-Log "`nSkipped files (invalid naming pattern):" "WARN"
    $results | Where-Object { -not $_.Success -and $_.Error -like "*does not match pattern*" } | ForEach-Object {
        Write-Log "  [SKIP] $($_.Filename)" "WARN"
    }
}

Write-Log "`n=== $ScriptName - COMPLETED ===" "INFO" -NoTimestamp

# Exit with appropriate code
if ($failedCount -gt 0) {
    exit 1  # Partial failure
} elseif ($convertedCount -gt 0) {
    exit 0  # Success
} else {
    exit 0  # Nothing to do (all skipped)
}