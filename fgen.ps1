param(
    [Parameter(Mandatory=$false)]
    [int]$FileCount,

    [Parameter(Mandatory=$false)]
    [string]$AverageFileSize,

    [Parameter(Mandatory=$false)]
    [ValidateSet('sparse', 'binary', 'text')]
    [string]$FileType,

    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory
)

function ConvertTo-Bytes {
    param([string]$SizeString)

    # Return $null for empty or whitespace-only input
    if ([string]::IsNullOrWhiteSpace($SizeString)) {
        return $null
    }

    $SizeString = $SizeString.Trim()

    # Match a positive number (integer or decimal) followed by an optional unit suffix
    if ($SizeString -match '^(\d+\.?\d*)(KB|MB|GB)?$') {
        $numericPart = [double]$Matches[1]
        $suffix = $Matches[2]

        # Reject zero or negative numbers
        if ($numericPart -le 0) {
            return $null
        }

        $multiplier = switch ($suffix) {
            'KB' { 1024 }
            'MB' { 1048576 }
            'GB' { 1073741824 }
            default { 1 }
        }

        return [long]($numericPart * $multiplier)
    }

    # No match means invalid input
    return $null
}

function New-UniqueFilename {
    param(
        [string]$Directory,
        [string]$FileType,
        [int]$Index
    )

    # Map file type to extension
    $extension = switch ($FileType) {
        'sparse' { '.sparse' }
        'binary' { '.bin' }
        'text'   { '.txt' }
    }

    # Generate a GUID fragment (first 8 characters)
    $guidFragment = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)

    # Build filename with pattern: file_<index>_<guid-fragment>.<ext>
    $filename = "file_${Index}_${guidFragment}${extension}"

    return [System.IO.Path]::Combine($Directory, $filename)
}

function New-OutputDirectory {
    param(
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        [System.IO.Directory]::CreateDirectory($Path) | Out-Null
    }
}

function New-SparseFile {
    param(
        [string]$FilePath,
        [long]$SizeInBytes
    )

    try {
        # Step 1: Create an empty file
        $null = New-Item -Path $FilePath -ItemType File -Force

        # Step 2: Set the sparse flag using fsutil
        $sparseResult = & fsutil sparse setflag $FilePath 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "fsutil sparse setflag failed: $sparseResult"
        }

        # Step 3: Set the sparse range (from 0 to the target size)
        $rangeResult = & fsutil sparse setrange $FilePath 0 $SizeInBytes 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "fsutil sparse setrange failed: $rangeResult"
        }

        # Step 4: Set the end-of-file (logical size) via SetLength
        $fileStream = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
        try {
            $fileStream.SetLength($SizeInBytes)
        }
        finally {
            $fileStream.Close()
        }
    }
    catch {
        # Fallback: create a regular empty file with SetLength if fsutil fails
        Write-Warning "Sparse file creation failed for '$FilePath': $_. Falling back to regular empty file."
        try {
            # Ensure the file exists
            if (-not (Test-Path -Path $FilePath)) {
                $null = New-Item -Path $FilePath -ItemType File -Force
            }
            $fileStream = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::Write)
            try {
                $fileStream.SetLength($SizeInBytes)
            }
            finally {
                $fileStream.Close()
            }
        }
        catch {
            throw "Failed to create file '$FilePath': $_"
        }
    }
}

function New-BinaryFile {
    param(
        [string]$FilePath,
        [long]$SizeInBytes
    )

    $bufferSize = 64KB  # 65536 bytes
    $random = New-Object System.Random
    $fileStream = New-Object System.IO.FileStream($FilePath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)

    try {
        $bytesRemaining = $SizeInBytes

        while ($bytesRemaining -gt 0) {
            $chunkSize = [Math]::Min($bytesRemaining, $bufferSize)
            $buffer = New-Object byte[] $chunkSize
            $random.NextBytes($buffer)
            $fileStream.Write($buffer, 0, $chunkSize)
            $bytesRemaining -= $chunkSize
        }
    }
    finally {
        $fileStream.Close()
    }
}

function New-TextFile {
    param(
        [string]$FilePath,
        [long]$SizeInBytes
    )

    # Pre-built lorem ipsum text block (over 500 characters)
    $loremBlock = @"
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum. Curabitur pretium tincidunt lacus. Nulla gravida orci a odio. Nullam varius, turpis et commodo pharetra, est eros bibendum elit, nec luctus magna felis sollicitudin mauris. Integer in mauris eu nibh euismod gravida.
"@

    # Use UTF-8 encoding without BOM to avoid extra bytes at the start of the file
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $streamWriter = New-Object System.IO.StreamWriter($FilePath, $false, $utf8NoBom)

    try {
        $bytesWritten = 0
        $blockBytes = $utf8NoBom.GetByteCount($loremBlock)

        while ($bytesWritten -lt $SizeInBytes) {
            $bytesRemaining = $SizeInBytes - $bytesWritten

            if ($bytesRemaining -ge $blockBytes) {
                $streamWriter.Write($loremBlock)
                $bytesWritten += $blockBytes
            }
            else {
                # Write a partial block to reach the exact target size
                # Calculate how many characters fit in the remaining bytes
                $partialText = $loremBlock.Substring(0, [Math]::Min($loremBlock.Length, $bytesRemaining))
                # Trim to exact byte count
                while ($utf8NoBom.GetByteCount($partialText) -gt $bytesRemaining) {
                    $partialText = $partialText.Substring(0, $partialText.Length - 1)
                }
                $streamWriter.Write($partialText)
                $bytesWritten += $utf8NoBom.GetByteCount($partialText)
            }
        }
    }
    finally {
        $streamWriter.Close()
    }
}

function Start-FileGeneration {
    param(
        [int]$FileCount,
        [long]$SizeInBytes,
        [string]$FileType,
        [string]$OutputDirectory
    )

    # Create output directory if needed
    New-OutputDirectory -Path $OutputDirectory

    # Initialize tracking
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $totalBytesWritten = 0
    $filesCreated = 0
    $failedFiles = 0

    for ($i = 1; $i -le $FileCount; $i++) {
        # Report progress
        $percentComplete = [int](($i - 1) / $FileCount * 100)
        Write-Progress -Activity "Generating $FileType files" `
            -Status "Creating file $i of $FileCount" `
            -PercentComplete $percentComplete

        # Generate unique filename
        $filePath = New-UniqueFilename -Directory $OutputDirectory -FileType $FileType -Index $i

        try {
            switch ($FileType) {
                'sparse' { New-SparseFile -FilePath $filePath -SizeInBytes $SizeInBytes }
                'binary' { New-BinaryFile -FilePath $filePath -SizeInBytes $SizeInBytes }
                'text'   { New-TextFile -FilePath $filePath -SizeInBytes $SizeInBytes }
            }
            $filesCreated++
            $totalBytesWritten += $SizeInBytes
        }
        catch {
            Write-Warning "Failed to create file '$filePath': $_"
            $failedFiles++
        }
    }

    # Complete the progress bar
    Write-Progress -Activity "Generating $FileType files" -Completed

    $stopwatch.Stop()

    return @{
        TotalFiles  = $filesCreated
        TotalBytes  = $totalBytesWritten
        ElapsedTime = $stopwatch.Elapsed
        FailedFiles = $failedFiles
    }
}

function Format-Size {
    param([long]$Bytes)

    if ($Bytes -ge 1073741824) {
        return "{0:N2} GB" -f ($Bytes / 1073741824)
    }
    elseif ($Bytes -ge 1048576) {
        return "{0:N2} MB" -f ($Bytes / 1048576)
    }
    elseif ($Bytes -ge 1024) {
        return "{0:N2} KB" -f ($Bytes / 1024)
    }
    else {
        return "$Bytes bytes"
    }
}

function Show-GenerationSummary {
    param([hashtable]$Result)

    Write-Host ""
    Write-Host "=== Generation Summary ===" -ForegroundColor Cyan
    Write-Host "Files created: $($Result.TotalFiles)"
    Write-Host "Total size:    $(Format-Size -Bytes $Result.TotalBytes)"
    Write-Host "Elapsed time:  $($Result.ElapsedTime.ToString('hh\:mm\:ss\.fff'))"
    if ($Result.FailedFiles -gt 0) {
        Write-Host "Failed files:  $($Result.FailedFiles)" -ForegroundColor Yellow
    }
    Write-Host "==========================" -ForegroundColor Cyan
}

# --- Menu Interface Functions ---

function Read-ValidatedInput {
    param(
        [string]$Prompt,
        [scriptblock]$Validator,
        [string]$ErrorMessage
    )

    while ($true) {
        $userInput = Read-Host -Prompt $Prompt
        if (& $Validator $userInput) {
            return $userInput
        }
        Write-Host $ErrorMessage -ForegroundColor Red
    }
}

function Show-Menu {
    Write-Host ""
    Write-Host "=== Random File Generator - Interactive Mode ===" -ForegroundColor Cyan
    Write-Host ""

    # Prompt for FileCount (validate: positive integer)
    $fileCountStr = Read-ValidatedInput `
        -Prompt "Enter the number of files to generate" `
        -Validator { param($val) $val -match '^\d+$' -and [int]$val -gt 0 } `
        -ErrorMessage "Invalid input. Please enter a positive integer."

    # Prompt for AverageFileSize (validate: ConvertTo-Bytes returns non-null)
    $sizeStr = Read-ValidatedInput `
        -Prompt "Enter the average file size (e.g., 100MB, 1.5GB, 500KB, 1024)" `
        -Validator { param($val) $null -ne (ConvertTo-Bytes -SizeString $val) } `
        -ErrorMessage "Invalid size format. Use a positive number with optional suffix (KB, MB, GB). Examples: 100MB, 1.5GB, 500KB, 1024"

    # Prompt for FileType (validate: one of sparse, binary, text)
    $fileType = Read-ValidatedInput `
        -Prompt "Enter the file type (sparse, binary, text)" `
        -Validator { param($val) $val -in @('sparse', 'binary', 'text') } `
        -ErrorMessage "Invalid file type. Please enter one of: sparse, binary, text"

    # Prompt for OutputDirectory (validate: non-empty string)
    $outputDir = Read-ValidatedInput `
        -Prompt "Enter the output directory path" `
        -Validator { param($val) -not [string]::IsNullOrWhiteSpace($val) } `
        -ErrorMessage "Output directory cannot be empty. Please enter a valid path."

    return @{
        FileCount        = [int]$fileCountStr
        SizeInBytes      = (ConvertTo-Bytes -SizeString $sizeStr)
        FileType         = $fileType
        OutputDirectory  = $outputDir
        OriginalSizeString = $sizeStr
    }
}

function Format-CliCommand {
    param(
        [int]$FileCount,
        [string]$AverageFileSize,
        [string]$FileType,
        [string]$OutputDirectory
    )

    return ".\fgen.ps1 -FileCount $FileCount -AverageFileSize `"$AverageFileSize`" -FileType $FileType -OutputDirectory `"$OutputDirectory`""
}

# --- Mode Detection and Validation ---

# Determine which parameters were explicitly bound by the caller
$boundParams = @()
if ($PSBoundParameters.ContainsKey('FileCount')) { $boundParams += 'FileCount' }
if ($PSBoundParameters.ContainsKey('AverageFileSize')) { $boundParams += 'AverageFileSize' }
if ($PSBoundParameters.ContainsKey('FileType')) { $boundParams += 'FileType' }
if ($PSBoundParameters.ContainsKey('OutputDirectory')) { $boundParams += 'OutputDirectory' }

if ($boundParams.Count -eq 0) {
    # No parameters provided — enter menu mode
    $confirmed = $false
    while (-not $confirmed) {
        $menuParams = Show-Menu

        # Display CLI equivalent
        $cliCommand = Format-CliCommand `
            -FileCount $menuParams.FileCount `
            -AverageFileSize $menuParams.OriginalSizeString `
            -FileType $menuParams.FileType `
            -OutputDirectory $menuParams.OutputDirectory

        Write-Host ""
        Write-Host "=== CLI Equivalent ===" -ForegroundColor Cyan
        Write-Host $cliCommand
        Write-Host "======================" -ForegroundColor Cyan
        Write-Host ""

        # Prompt for confirmation
        $confirmation = Read-Host -Prompt "Proceed with file generation? (Y/N)"
        if ($confirmation -eq 'Y' -or $confirmation -eq 'y') {
            $confirmed = $true
            $result = Start-FileGeneration `
                -FileCount $menuParams.FileCount `
                -SizeInBytes $menuParams.SizeInBytes `
                -FileType $menuParams.FileType `
                -OutputDirectory $menuParams.OutputDirectory
            Show-GenerationSummary -Result $result
        }
        elseif ($confirmation -eq 'N' -or $confirmation -eq 'n') {
            Write-Host "Generation cancelled. Returning to menu..." -ForegroundColor Yellow
            # Loop continues back to Show-Menu
        }
        else {
            Write-Host "Invalid input. Please enter Y or N." -ForegroundColor Red
            # Re-prompt for confirmation by not setting $confirmed, but also not looping back to menu
            # Instead, let's just loop back to the menu for simplicity
            Write-Host "Returning to menu..." -ForegroundColor Yellow
        }
    }
}
else {
    # CLI mode: at least one parameter was provided, so all are required
    $allParams = @('FileCount', 'AverageFileSize', 'FileType', 'OutputDirectory')
    $missingParams = $allParams | Where-Object { $_ -notin $boundParams }

    if ($missingParams.Count -gt 0) {
        Write-Error "CLI mode requires all parameters. Missing: $($missingParams -join ', ')"
        Write-Error "Usage: .\Generate-RandomFiles.ps1 -FileCount <n> -AverageFileSize `"<size>`" -FileType <type> -OutputDirectory `"<path>`""
        exit 1
    }

    # Validate FileCount is a positive integer
    if ($FileCount -le 0) {
        Write-Error "FileCount must be a positive integer."
        exit 1
    }

    # Validate FileType is one of the supported types
    $validFileTypes = @('sparse', 'binary', 'text')
    if ($FileType -notin $validFileTypes) {
        Write-Error "FileType must be one of: sparse, binary, text."
        exit 1
    }

    # Validate AverageFileSize parses successfully
    $sizeInBytes = ConvertTo-Bytes -SizeString $AverageFileSize
    if ($null -eq $sizeInBytes) {
        Write-Error "Invalid size format for AverageFileSize. Use a number with optional suffix (KB, MB, GB). Examples: 100MB, 1.5GB, 500KB, 1024"
        exit 1
    }

    # All validation passed — proceed with file generation
    $result = Start-FileGeneration -FileCount $FileCount -SizeInBytes $sizeInBytes -FileType $FileType -OutputDirectory $OutputDirectory
    Show-GenerationSummary -Result $result
}
