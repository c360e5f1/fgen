# fgen.ps1

**Generate large quantities of random test files**

## Synopsis

```powershell
.\fgen.ps1
.\fgen.ps1 -FileCount <int> -AverageFileSize <size> -FileType <type> -OutputDirectory <path>
```

## Description

A PowerShell script that generates bulk random files on Windows for storage, compression, and file system testing. Supports two modes of operation: an interactive menu-driven interface and a non-interactive command-line interface (CLI mode).

Three file types are available:

| Type | Description | Use Case |
|------|-------------|----------|
| `sparse` | Files allocated at the target size but containing no written data. Uses NTFS sparse file support via fsutil. Consumes minimal disk space regardless of logical size. | Testing metadata handling and directory enumeration |
| `binary` | Files filled with pseudo-random bytes from System.Random. Written in 64KB buffer chunks for throughput. Produces incompressible data. | Testing storage I/O, network transfer, and backup tools |
| `text` | Files filled with repeated lorem ipsum passages via StreamWriter. Produces highly compressible, predictable content. | Testing compression ratios, deduplication engines, and archival tools |

When run interactively (no arguments), the script displays the equivalent CLI command before execution, allowing users to automate future runs.

## Parameters

### -FileCount \<int\>

Number of files to generate. Must be a positive integer.

### -AverageFileSize \<size\>

Target size for each generated file. Accepts a positive number with an optional unit suffix:

| Suffix | Meaning |
|--------|---------|
| `KB` | Kilobytes (×1024) |
| `MB` | Megabytes (×1048576) |
| `GB` | Gigabytes (×1073741824) |
| *(none)* | Bytes |

Decimal values are supported (e.g., `1.5GB`).

### -FileType \<sparse|binary|text\>

The type of file content to generate.

### -OutputDirectory \<path\>

Directory where files are written. Created automatically if it does not exist.

## Output

Files are named with the pattern:

```
file_<index>_<guid-fragment>.<ext>
```

Extensions: `.sparse`, `.bin`, `.txt`

On completion, a summary is displayed showing files created, total size, elapsed time, and any failures.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Validation error (invalid parameters, missing arguments) |

## Examples

**Interactive mode (menu-driven):**

```powershell
.\fgen.ps1
```

**Generate 100 incompressible binary files of 10MB for throughput testing:**

```powershell
.\fgen.ps1 -FileCount 100 -AverageFileSize "10MB" -FileType binary -OutputDirectory "C:\TestData\binary"
```

**Generate 1000 compressible text files of 500KB for dedup testing:**

```powershell
.\fgen.ps1 -FileCount 1000 -AverageFileSize "500KB" -FileType text -OutputDirectory "D:\DedupTest"
```

**Generate 5000 sparse files of 1GB for metadata stress testing (uses almost no disk space):**

```powershell
.\fgen.ps1 -FileCount 5000 -AverageFileSize "1GB" -FileType sparse -OutputDirectory "E:\SparseStress"
```

**Generate 50 binary files of 1.5GB for large-file transfer testing:**

```powershell
.\fgen.ps1 -FileCount 50 -AverageFileSize "1.5GB" -FileType binary -OutputDirectory "\\server\share\bigfiles"
```

**Generate 200 small text files of 4KB for filesystem metadata testing:**

```powershell
.\fgen.ps1 -FileCount 200 -AverageFileSize "4KB" -FileType text -OutputDirectory ".\lots-of-small-files"
```

## Notes

- Requires PowerShell 5.1 or later. No external modules or dependencies.
- Sparse file creation requires NTFS and uses `fsutil` (typically requires elevated privileges). If `fsutil` fails, the script falls back to creating a regular empty file at the target size.
- Binary file generation speed is limited by `System.Random` throughput and disk I/O. Expect roughly 200–400 MB/s on modern SSDs.
- Progress is reported via `Write-Progress` during generation.

***

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.
