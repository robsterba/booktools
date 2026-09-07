# Book Tools - MD2EPUB Converter

A collection of tools for book processing and conversion.

## 📚 MD2EPUB Converter

**Script**: `md2epub.ps1`  
**Purpose**: Automatically converts Markdown files to EPUB format using Pandoc

### Features

- **Automatic Metadata Extraction**: Parses filenames in format `<title> by <author>.md`
- **Weblink Removal**: Strips all markdown hyperlinks, HTML tags, and bare URLs while preserving link text
- **Image Handling**: Detects embedded images, uses first image as EPUB cover
- **EPUB Metadata**: Sets proper title, author, and language metadata
- **Archive Management**: Automatically moves processed files to archive directory
- **Calibre Integration**: **NEW** - Automatically adds converted EPUBs to Calibre library
- **Error Handling**: Retries failed conversions once, then continues with next file
- **Comprehensive Logging**: Complete logging to `d:\books\md2epub.log`

### Requirements

- **Pandoc**: `pandoc.exe` must be in `d:\booktools\`
- **Calibre**: `calibredb.exe` must be installed (default: `C:\Program Files\Calibre2\`)
- **PowerShell**: Windows PowerShell 5.1 or later
- **File Naming**: Files must follow pattern `<title> by <author>.md`

### Usage

#### Basic Conversion
```powershell
# Navigate to booktools directory
cd d:\booktools

# Run the converter
.\md2epub.ps1
```

#### Test Run (No file movement)
```powershell
.\md2epub.ps1 -TestRun -VerboseLogging
```

#### Manual Execution from Anywhere
```powershell
powershell.exe -ExecutionPolicy Bypass -File "d:\booktools\md2epub.ps1"
```

#### Skip Calibre Integration
```powershell
.\md2epub.ps1 -SkipCalibre
```

#### Specify Custom Calibre Library
```powershell
.\md2epub.ps1 -CalibreLibrary "D:\My Calibre Library"
```

### Input/Output

- **Input Directory**: `D:\vault\Blinks` (configurable in script)
- **Output Directory**: `d:\books` (configurable in script)
- **Archive Directory**: `D:\vault\Blinks\archive\` (auto-created)
- **Log File**: `d:\books\md2epub.log`

### Configuration

Edit these variables at the top of `md2epub.ps1`:

```powershell
$InputDir = "D:\vault\Blinks"
$OutputDir = "d:\books"
$PandocPath = "d:\booktools\pandoc.exe"
$CalibrePath = "C:\Program Files\Calibre2\calibredb.exe"
$AddToCalibre = $true
$CalibreLibraryPath = $null  # $null = use default library
$MaxRetryAttempts = 2
$RetryDelaySeconds = 2
$TocDepth = 3
$EpubVersion = "epub3"
$Language = "en"
```

### File Structure

```
d:\booktools\\
├── pandoc.exe          # Pandoc conversion engine
├── md2epub.ps1        # Main conversion script
└── README.md           # This documentation

Calibre Library (default location)
├── metadata.db        # Calibre database
└── <Author>\\
    └── <Title>\\
        └── <Title> by <Author>.epub  # Imported EPUB files

d:\vault\Blinks\\
├── *.md                # Markdown files to convert
└── archive\\          # Processed files moved here

d:\books\\
├── *.epub             # Generated EPUB files
└── md2epub.log        # Conversion log
```

### Calibre Integration

The script automatically adds converted EPUB files to your Calibre library with proper metadata:

- **Title**: Extracted from filename (before " by ")
- **Author**: Extracted from filename (after " by ")
- **Language**: English (configurable)
- **Format**: EPUB3

**Requirements**:
- Calibre must be installed
- `calibredb.exe` must be accessible

**Disable Calibre**: Use `-SkipCalibre` parameter

**Custom Library**: Use `-CalibreLibrary "path"` parameter

### Supported File Pattern

Files must be named: `<title> by <author>.md`

Examples:
- ✅ `The 10X Rule by Grant Cardone.md`
- ✅ `Why Plato Matters Now by Angie Hobbs.md`
- ❌ `My Book.md` (missing " by " delimiter)
- ❌ `Book.md` (missing author)

### Preprocessing

Before conversion, the script thoroughly cleans the content:
1. **Removes YAML front matter** (to avoid conflicts with explicit metadata)
2. **Strips markdown links** (`[text](url)` → `text`)
3. **Removes HTML tags** (audio, video, iframe, etc.)
4. **Removes bare URLs** (http://, https://, www.)
5. **Detects embedded images** (first image used as EPUB cover)

**Note**: This ensures Pandoc doesn't try to fetch external resources during conversion.

### Error Handling

- **File Parsing Errors**: Skipped with warning logged
- **Pandoc Errors**: Retried once after 2-second delay, then skipped
- **File System Errors**: Handled gracefully with detailed logging
- **All errors**: Logged to `d:\books\md2epub.log` with timestamps

### Scheduling

#### Windows Task Scheduler

1. Open **Task Scheduler**
2. Click **Create Task**
3. **General Tab**:
   - Name: `MD2EPUB Converter`
   - Description: `Convert markdown files to EPUB format`
   - Security options: `Run whether user is logged on or not`
4. **Triggers Tab**:
   - New → Daily at preferred time or On Startup
5. **Actions Tab**:
   - New → Start a program
   - Program: `powershell.exe`
   - Arguments: `-ExecutionPolicy Bypass -File "d:\booktools\md2epub.ps1"`
   - Start in: `d:\booktools`

#### Manual Schedule Testing
```powershell
# Test scheduled task immediately
schtasks /run /tn "MD2EPUB Converter"
```

### Examples

#### Convert All Files
```powershell
.\md2epub.ps1
```

#### Test Run (Preview)
```powershell
.\md2epub.ps1 -TestRun
```

#### Verbose Logging
```powershell
.\md2epub.ps1 -VerboseLogging
```

#### Help
```powershell
.\md2epub.ps1 -Help
```

### Notes

- EPUB files are **overwritten** if they already exist
- Processed MD files are **moved to archive** (not deleted)
- Script creates required directories automatically
- All operations are logged with timestamps and status

### Troubleshooting

**Issue**: No files processed
- **Solution**: Check that files follow naming pattern `<title> by <author>.md`

**Issue**: Files not archived
- **Solution**: Conversion must succeed first; check for errors in log

**Issue**: Links not removed
- **Solution**: Verify preprocessing step in log shows "removed X links"

**Issue**: Pandoc not found
- **Solution**: Check `$PandocPath` variable points to correct location

### Version History

- **v1.0.0** (2026-09-06): Initial release with full feature set

### License

Free for personal use. Script provided as-is without warranty.