<#
.SYNOPSIS
    Updates Java 8 download links from java.com

.DESCRIPTION
    Fetches the latest Java 8 JRE download links from the Oracle Java manual download page
    and saves them as a standardized JSON file with version tracking.

    Uses Selenium with stealth options to bypass potential bot protection.

    The JSON maintains:
    - "Latest" entry with current version info and all download URLs
    - Historical versions preserved with their original URLs

.PARAMETER OutputPath
    Path to the data folder. Defaults to ../data relative to script location.

.PARAMETER SkipVersionCheck
    Skip checking if version has changed (always update).

.EXAMPLE
    .\Update-JavaData.ps1

.EXAMPLE
    .\Update-JavaData.ps1 -OutputPath "C:\Data"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$SkipVersionCheck
)

# Set output path
if (-not $OutputPath) {
    $OutputPath = Join-Path $PSScriptRoot "..\data"
}

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$Url = 'https://www.java.com/en/download/manual.jsp'
$JsonPath = Join-Path $OutputPath "Java.json"
$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Java 8 Download Data Updater" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Timestamp: $timestamp" -ForegroundColor Gray
Write-Host "Output: $JsonPath" -ForegroundColor Gray
Write-Host ""

#region Helper Functions

function Get-JavaDataSelenium {
    <#
    .SYNOPSIS
        Fetches Java download data using Selenium.
    #>
    param([string]$Url)

    Write-Host "[Java] Fetching data using Selenium..." -ForegroundColor Cyan
    Write-Host "[Java] URL: $Url" -ForegroundColor Gray

    # Try to find Selenium module
    $seleniumModule = Get-Module -ListAvailable -Name Selenium
    if (-not $seleniumModule) {
        Write-Error "[Java] Selenium module not found. Please install with: Install-Module -Name Selenium"
        return $null
    }

    # Find Selenium assemblies
    $seleniumPath = $seleniumModule.ModuleBase
    $assembliesPath = Join-Path $seleniumPath "assemblies"
    $webDriverDll = Join-Path $assembliesPath "WebDriver.dll"

    if (-not (Test-Path $webDriverDll)) {
        Write-Error "[Java] WebDriver.dll not found at: $webDriverDll"
        return $null
    }

    # Load WebDriver
    if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq "WebDriver" })) {
        Add-Type -Path $webDriverDll -ErrorAction Stop
    }

    $driver = $null

    try {
        # Create Chrome options with stealth settings
        $chromeOptions = New-Object OpenQA.Selenium.Chrome.ChromeOptions
        $chromeOptions.AddExcludedArgument("enable-automation")
        $chromeOptions.AddArgument("--disable-blink-features=AutomationControlled")
        $chromeOptions.AddArgument("--disable-extensions")
        $chromeOptions.AddArgument("--disable-http2")
        $chromeOptions.AddArgument("--no-sandbox")
        $chromeOptions.AddArgument("--disable-dev-shm-usage")
        $chromeOptions.AddArgument("--disable-gpu")
        $chromeOptions.AddArgument("--disable-infobars")
        $chromeOptions.AddArgument("--disable-notifications")
        $chromeOptions.AddArgument("--disable-popup-blocking")
        $chromeOptions.AddArgument("--window-size=1920,1080")
        $chromeOptions.AddArgument("--start-maximized")
        $chromeOptions.AddArgument("--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36")
        $chromeOptions.AddArgument("--lang=en-US")
        $chromeOptions.AddArgument("--headless=new")
        $chromeOptions.AddArgument("--log-level=3")
        $chromeOptions.AddArgument("--silent")

        # Create service
        $chromeDriverPath = Join-Path $assembliesPath "chromedriver.exe"
        if (Test-Path $chromeDriverPath) {
            $chromeService = [OpenQA.Selenium.Chrome.ChromeDriverService]::CreateDefaultService($assembliesPath)
        } else {
            $chromeService = [OpenQA.Selenium.Chrome.ChromeDriverService]::CreateDefaultService()
        }
        $chromeService.HideCommandPromptWindow = $true
        $chromeService.SuppressInitialDiagnosticInformation = $true

        Write-Host "[Java] Starting Chrome..." -ForegroundColor Cyan
        $driver = New-Object OpenQA.Selenium.Chrome.ChromeDriver($chromeService, $chromeOptions)
        $driver.Manage().Timeouts().PageLoad = [TimeSpan]::FromSeconds(60)

        Write-Host "[Java] Navigating to page..." -ForegroundColor Cyan
        $driver.Navigate().GoToUrl($Url)

        # Wait for page to load
        Start-Sleep -Seconds 5

        Write-Host "[Java] Page loaded: $($driver.Title)" -ForegroundColor Green

        $html = $driver.PageSource

        # Check for errors
        if ($html -match "ERR_|can't be reached|Access Denied|blocked") {
            throw "Page load failed or blocked"
        }

        # Extract version information
        $version = $null
        $updateNumber = $null
        $releaseDate = $null

        if ($html -match 'Version\s+8\s+Update\s+(\d+)') {
            $updateNumber = $Matches[1]
            $version = "8u$updateNumber"
            Write-Host "[Java] Found version: Java $version" -ForegroundColor Green
        }

        if ($html -match 'Release\s+date:\s*([^<]+)') {
            $releaseDate = $Matches[1].Trim()
            Write-Host "[Java] Release date: $releaseDate" -ForegroundColor Green
        }

        if (-not $version) {
            Write-Error "[Java] Could not extract version information"
            return $null
        }

        # Extract download links with platform info
        $downloads = @{}

        # Pattern: BundleId with hash - capture both title and link text
        # Format: <a href="URL" title="TITLE">LINKTEXT</a>
        $linkPattern = '<a\s+href="(https://javadl\.oracle\.com/webapps/download/AutoDL\?BundleId=(\d+)_([a-f0-9]+))"[^>]*title="([^"]+)"[^>]*>([^<]+)</a>'
        $linkMatches = [regex]::Matches($html, $linkPattern, 'IgnoreCase')

        Write-Host "[Java] Found $($linkMatches.Count) download links" -ForegroundColor Cyan

        foreach ($match in $linkMatches) {
            $fullUrl = $match.Groups[1].Value
            $bundleId = $match.Groups[2].Value
            $hash = $match.Groups[3].Value
            $title = $match.Groups[4].Value
            $linkText = $match.Groups[5].Value.Trim()

            # Determine platform from link text (more specific than title)
            $platform = $null

            # Use specific pattern matching based on link text
            switch -Regex ($linkText) {
                '^Windows Online$'                   { $platform = 'Windows_Online' }
                '^Windows Offline$'                  { $platform = 'Windows_x86' }
                '^Windows Offline \(64-bit\)$'       { $platform = 'Windows_x64' }
                '^macOS x64$'                        { $platform = 'macOS_x64' }
                '^macOS ARM64$'                      { $platform = 'macOS_ARM64' }
                '^Linux RPM$'                        { $platform = 'Linux_x86_RPM' }
                '^Linux$'                            { $platform = 'Linux_x86' }
                '^Linux x64$'                        { $platform = 'Linux_x64' }
                '^Linux x64 RPM$'                    { $platform = 'Linux_x64_RPM' }
                '^Solaris SPARC \(64-bit\)$'         { $platform = 'Solaris_SPARC64' }
                '^Solaris x64$'                      { $platform = 'Solaris_x64' }
            }

            if ($platform -and -not $downloads.ContainsKey($platform)) {
                # Extract file size from nearby text
                $fileSize = $null
                $sizePattern = "BundleId=$bundleId[^<]*</a>[^<]*<[^>]*>[^<]*filesize:\s*([\d.]+\s*MB)"
                if ($html -match $sizePattern) {
                    $fileSize = $Matches[1]
                }

                $downloads[$platform] = [PSCustomObject]@{
                    Platform = $platform
                    BundleId = $bundleId
                    Url = $fullUrl
                    FileSize = $fileSize
                }

                Write-Host "  [$platform] BundleId: $bundleId" -ForegroundColor Gray
            }
        }

        if ($downloads.Count -eq 0) {
            Write-Error "[Java] No download links extracted"
            return $null
        }

        # Convert downloads hashtable to PSCustomObject for JSON serialization
        $downloadsObj = [PSCustomObject]@{}
        foreach ($key in $downloads.Keys) {
            $downloadsObj | Add-Member -NotePropertyName $key -NotePropertyValue $downloads[$key]
        }

        # Build result object
        $result = [PSCustomObject]@{
            Version = $version
            UpdateNumber = [int]$updateNumber
            ReleaseDate = $releaseDate
            Downloads = $downloadsObj
        }

        Write-Host "[Java] Extracted $($downloads.Count) platform downloads" -ForegroundColor Green
        return $result

    } catch {
        Write-Error "[Java] Selenium failed: $_"
        return $null
    } finally {
        if ($driver) {
            try {
                Write-Host "[Java] Closing browser..." -ForegroundColor Gray
                $driver.Quit()
            } catch { }
        }
    }
}

#endregion

#region Main Execution

# Fetch current data
$javaData = Get-JavaDataSelenium -Url $Url

if (-not $javaData) {
    Write-Error "[Java] Failed to fetch Java data"
    exit 1
}

# Load existing JSON if present
$existingData = $null
if (Test-Path $JsonPath) {
    try {
        $existingData = Get-Content $JsonPath -Raw | ConvertFrom-Json
        Write-Host "[Java] Loaded existing data from: $JsonPath" -ForegroundColor Cyan
    } catch {
        Write-Warning "[Java] Could not parse existing JSON, will create new file"
    }
}

# Check if version has changed
$versionChanged = $true
if ($existingData -and $existingData.Latest -and -not $SkipVersionCheck) {
    if ($existingData.Latest.Version -eq $javaData.Version) {
        Write-Host "[Java] Version unchanged ($($javaData.Version)). Skipping update." -ForegroundColor Yellow
        $versionChanged = $false
    }
}

if ($versionChanged) {
    Write-Host "[Java] Processing version update..." -ForegroundColor Cyan

    # Initialize or update the JSON structure
    $jsonOutput = if ($existingData) {
        # Preserve existing structure
        $existingData
    } else {
        # Create new structure
        [PSCustomObject]@{
            Product = "Oracle Java 8 JRE"
            LastUpdated = $timestamp
            SourceUrl = $Url
            Latest = $null
            Versions = [PSCustomObject]@{}
        }
    }

    # If there was a previous "Latest", move it to Versions
    if ($existingData -and $existingData.Latest -and $existingData.Latest.Version -ne $javaData.Version) {
        $oldVersion = $existingData.Latest.Version
        Write-Host "[Java] Archiving previous version: $oldVersion" -ForegroundColor Cyan

        # Add old version to Versions object
        $jsonOutput.Versions | Add-Member -NotePropertyName $oldVersion -NotePropertyValue ([PSCustomObject]@{
            Version = $existingData.Latest.Version
            UpdateNumber = $existingData.Latest.UpdateNumber
            ReleaseDate = $existingData.Latest.ReleaseDate
            ArchivedOn = $timestamp
            Downloads = $existingData.Latest.Downloads
        }) -Force
    }

    # Update Latest
    $jsonOutput.Latest = [PSCustomObject]@{
        Version = $javaData.Version
        UpdateNumber = $javaData.UpdateNumber
        ReleaseDate = $javaData.ReleaseDate
        UpdatedOn = $timestamp
        Downloads = $javaData.Downloads
    }

    $jsonOutput.LastUpdated = $timestamp

    # Save JSON
    $jsonOutput | ConvertTo-Json -Depth 10 | Out-File -FilePath $JsonPath -Encoding UTF8
    Write-Host "[Java] Saved to: $JsonPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Version: $($javaData.Version)" -ForegroundColor White
Write-Host "  Update Number: $($javaData.UpdateNumber)" -ForegroundColor White
Write-Host "  Release Date: $($javaData.ReleaseDate)" -ForegroundColor White
Write-Host "  Platforms: $($javaData.Downloads.Count)" -ForegroundColor White
Write-Host "  Version Changed: $versionChanged" -ForegroundColor $(if ($versionChanged) { 'Green' } else { 'Yellow' })
Write-Host "========================================" -ForegroundColor Cyan

exit 0

#endregion
