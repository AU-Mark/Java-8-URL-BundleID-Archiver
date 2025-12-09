# Java 8 JRE Download Data

[![Update Java 8 Data](https://github.com/AU-Mark/Java8-Download-Data/actions/workflows/update-java-data.yml/badge.svg)](https://github.com/AU-Mark/Java8-Download-Data/actions/workflows/update-java-data.yml)

Automated daily scraper for Oracle Java 8 JRE download links from [java.com](https://www.java.com/en/download/manual.jsp).

## Features

- **Daily Updates**: Automatically checks for new Java 8 versions daily at 7:00 AM UTC
- **Version Tracking**: Maintains history of previous versions with their download links
- **Multi-Platform**: Captures all available platforms:
  - Windows (Online, x86 Offline, x64 Offline)
  - macOS (x64, ARM64)
  - Linux (x86, x64, RPM variants)
  - Solaris (SPARC64, x64)
- **Direct Download URLs**: Provides direct `javadl.oracle.com` AutoDL links with BundleIds

## JSON Schema

```json
{
  "Product": "Oracle Java 8 JRE",
  "LastUpdated": "2025-12-09T20:30:08Z",
  "SourceUrl": "https://www.java.com/en/download/manual.jsp",
  "Latest": {
    "Version": "8u471",
    "UpdateNumber": 471,
    "ReleaseDate": "October 21, 2025",
    "UpdatedOn": "2025-12-09T20:30:08Z",
    "Downloads": {
      "Windows_x64": {
        "Platform": "Windows_x64",
        "BundleId": "252627",
        "Url": "https://javadl.oracle.com/webapps/download/AutoDL?BundleId=252627_...",
        "FileSize": "38.48 MB"
      }
      // ... other platforms
    }
  },
  "Versions": {
    "8u461": {
      "Version": "8u461",
      "ArchivedOn": "2025-10-21T...",
      "Downloads": { ... }
    }
  }
}
```

## Usage

### Raw JSON URL

```
https://raw.githubusercontent.com/AU-Mark/Java8-Download-Data/main/data/Java.json
```

### PowerShell Example

```powershell
# Get the latest Windows x64 download URL
$javaData = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/AU-Mark/Java8-Download-Data/main/data/Java.json"
$downloadUrl = $javaData.Latest.Downloads.Windows_x64.Url
Write-Host "Java $($javaData.Latest.Version) - $downloadUrl"

# Download the installer
Invoke-WebRequest -Uri $downloadUrl -OutFile "jre-$($javaData.Latest.Version)-windows-x64.exe"
```

## Platform Keys

| Platform Key | Description |
|-------------|-------------|
| `Windows_Online` | Windows Online Installer (small bootstrap) |
| `Windows_x86` | Windows Offline 32-bit |
| `Windows_x64` | Windows Offline 64-bit |
| `macOS_x64` | macOS Intel (10.7.3+) |
| `macOS_ARM64` | macOS Apple Silicon (12+) |
| `Linux_x86` | Linux 32-bit tar.gz |
| `Linux_x64` | Linux 64-bit tar.gz |
| `Linux_x86_RPM` | Linux 32-bit RPM |
| `Linux_x64_RPM` | Linux 64-bit RPM |
| `Solaris_SPARC64` | Solaris SPARC 64-bit |
| `Solaris_x64` | Solaris x64 |

## How It Works

1. **Selenium Stealth**: Uses Chrome with stealth options to bypass bot detection
2. **HTML Parsing**: Extracts version info and download links via regex
3. **Version Comparison**: Only updates JSON when a new version is detected
4. **Version Archiving**: Previous versions are preserved in the `Versions` object

## Manual Trigger

The workflow can be manually triggered from the Actions tab if you need an immediate update.

## License

This tool collects publicly available information from java.com. Oracle Java is subject to the [Oracle Technology Network License Agreement](https://www.java.com/otnlicense/).
