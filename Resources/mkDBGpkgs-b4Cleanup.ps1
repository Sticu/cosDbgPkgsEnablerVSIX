param (
      [Parameter(Mandatory=$true)] [string]$csprojfile = "",
      [switch] $forceCheckAll
      )

#-------
#HELPER - Prepend a multiline message with script specific marker (i.e. "[makeDBG]")
#-------
function OutputMessages
{
    param($message)
    $modifiedOutput = $message -split "`r`n" | Where-Object { $_.Trim() -ne "" }
    $modifiedOutput = $modifiedOutput -split "`r`n" | ForEach-Object { "[makeDBG]    $_" }
    $modifiedOutput = $modifiedOutput -join "`r`n"
    Write-Output $($modifiedOutput)
}


####################
# SCRIPT MAIN BODY #
####################
if ([string]::IsNullOrWhiteSpace($csprojfile) -or -not (Test-Path $csprojfile -PathType Leaf))
{
    Write-Error "ERROR: No/invalid .csproj file! Please provide a valid csproj file."
    exit 1
}

$CurrentFileName = Split-Path -Path $PSCommandPath -Leaf
Write-Output "[makeDBG] (Running the script: $CurrentFileName)"

#---Construct the name of the file that keeps track of the already handled packages (from previous runs)
# File name format: mkDBGpkg-<csproj_sanitized_path>.csv. Saved within the user %TEMP% folder.
# (Using the .csproj full PATH as part of the filename allows to have multiple identical projects handled independently by this script)
$TMP_FILENAME_ROOT = "mkDBGpkg"
$invalidFilenameChars = ([System.IO.Path]::GetInvalidFileNameChars() + [System.IO.Path]::GetInvalidPathChars() + "." + " ") -join ''
$invalidFilenameChars = [regex]::Escape($invalidFilenameChars)
$sanitizedFilename = $csprojfile -replace "[$invalidFilenameChars]", "-"
$handledPackagesTrackingFile = Join-Path $env:TEMP "$TMP_FILENAME_ROOT-$sanitizedFilename.csv"

# Retrieve the registered nuget sources - filter only on Costco based feeds.
# NOTE: this assumes Costco locations are in the form of "https://pkgs.dev.azure.com/COSTCOcloudops/..."
$xAllNugetSources = Get-PackageSource
[array]$costcoRegisteredPackageSources = Get-PackageSource | Where-Object {$_.Location -Like "*costco*"}
# Combine all the Costco based packages sources into an argument for "nuget list", like: -Source "location1" -Source "location2"...
$costcoLocations = $costcoRegisteredPackageSources| ForEach-Object { "-Source `"$($_.Location)`" " }
$locations_as_args = ($costcoLocations -join " ").Trim()

# Create "nuget list" arguments as an array
$nugetSearchPackagesArgs = @("list", $pkgname, "-AllVersions", "-PreRelease")
# Also add each nuget source as a separate argument
foreach ($source in $costcoRegisteredPackageSources) {
    $nugetSearchPackagesArgs += "-Source"
    $nugetSearchPackagesArgs += $source.Location
}

$flagUnhandledPackagesOnly = $FALSE
Write-Output "[makeDBG] Checking [$handledPackagesTrackingFile] for previously handled packages"
[array]$previouslyHandledPackages = [PSCustomObject]@()
if (Test-Path $handledPackagesTrackingFile -PathType Leaf) #file with previously handled packages does exist
{
    $previouslyHandledPackages = Import-Csv -Path $handledPackagesTrackingFile
    Write-Output "[makeDBG] Packages previously handled:`n$(OutputMessages($($previouslyHandledPackages | Format-Table | Out-String)))"
}
else #file does NOT exist
{
    $flagUnhandledPackagesOnly = $FALSE #if the temp file does not exist, we will handle ALL packages
    Write-Output "[makeDBG] No previously handled packages found. Will handle ALL project packages."
}

if ($forceCheckAll)
{
    $flagUnhandledPackagesOnly = $FALSE
    Write-Output "[makeDBG] 'forceCheckAll' flag specified => will check ALL project packages, including those previously handled"
}

# ---Retrieve all the NuGet packages referenced within the .csproj file---
Write-Output "[makeDBG]"
Write-Output "[makeDBG] Parsing project file: [$csprojfile]"

[array]$handledPackages = [PSCustomObject]@()

[xml]$csproj = Get-Content $csprojfile
$referencedPackages = $csproj.Project.ItemGroup.PackageReference | Where-Object { $_ -ne $null }
Write-Output "[makeDBG] Found reference(s):`n$(OutputMessages($($referencedPackages | Format-Table | Out-String)))"
if ($referencedPackages.Count -eq  0)
{
    Write-Output "[makeDBG] No <PackageReference> found, probably not a .net project; attempting .netFramework style."
    $referencedPackages = $csproj.Project.ItemGroup.Reference | Where-Object { $_ -ne $null }
    if ($referencedPackages.Count -eq  0)
    {
        Write-Output "[makeDBG] No <Reference> found. NOTHING TO DO."
    }
}

# Handle each of the referenced package retrieved above
foreach ($package in $referencedPackages)
{
    $pkgname = $($package.Include)
    $pkgversion = $($package.Version)
    $packageAlreadyHandled = $previouslyHandledPackages | Where-Object {($_.package -eq $pkgname) -and ($_.version -eq $pkgversion)}

    # (occasionally, there are ItemGroups within the .csproj that don't reference packages and comes here as null/empty ->> skip them)
    if ([string]::IsNullOrWhiteSpace($pkgname) -or [string]::IsNullOrWhiteSpace($pkgversion))
    {
        Write-Output "[makeDBG] (not a reference itemgroup, skip)"
        continue
    }

    Write-Output "[makeDBG] - Handling referenced package: [$pkgname / $pkgversion]"
    if ($packageAlreadyHandled -and -not ($forceCheckAll))
    {
        Write-Output "[makeDBG] --- [$pkgname / $pkgversion] ALREADY handled and ONLY newer packages are targeted. Skip."
        $handledPackages += [PSCustomObject]@{package=$pkgname;version=$pkgversion}
        continue
    }

    $pkgversionDBG = $pkgversion + "-dbg" #The DEBUG package will have the VERSION suffix as '-dbg'

    if (-not ($pkgversion.EndsWith("-dbg"))) #if the current package is not already a DEBUG one
    {
        Write-Output "[makeDBG] --- Searching for:             [$pkgname / $pkgversionDBG]..."
        
        Write-Output "[makeDBG] ---(Searching on location(s): [$locations_as_args])"
        if ([string]::IsNullOrWhiteSpace($locations_as_args))
        {
            Write-Output "[makeDBG] ---(No Costco specific nuget sources registered, will search on ALL registered sources)"
        }

        #Execute the NUGET LIST command (TODO: INSTALL nuget if not installed)
        #$nugetSearchPackagesCommand = "nuget list $pkgname $($locations_as_args) -AllVersions -PreRelease"
        #$packagesLookup = Invoke-Expression $nugetSearchPackagesCommand
        #$packagesLookup = & nuget $nugetArgs 2>&1 | Tee-Object -Variable output #2>&1

        # Call nuget with the array of arguments; the methods above does not work with the -Source argument
        #$packagesLookup = & nuget $nugetSearchPackagesArgs $pkgname | Out-Host


        ###$process = Start-Process -FilePath "nuget" -ArgumentList $nugetSearchPackagesArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput "C:\Users\csiic\AppData\Local\Temp\aaaa.txt"

        #iex "& { $(irm https://aka.ms/install-artifacts-credprovider.ps1) } -InstallNet8"

        Write-Output "[makeDBG] (...looking...)"

        #$jsonPackages = dotnet package search "newtonsoft" --verbosity detailed --prerelease --format json | ConvertFrom-Json
        #$allPackages = $jsonPackages.searchResult | ForEach-Object { $_.packages }
        #$jsonPackages.searchResult.Count
        #$jsonPackages.searchResult[0].packages.Count

        $dbgPackageFound = $false
        foreach ($costcoPkgSrc in $costcoRegisteredPackageSources)
        {
            Write-Output "[makeDBG] --- Looking for pkgs on your NuGet depot named: [$($costcoPkgSrc.Name)]"
            $jsonPackages = dotnet package search $pkgname --exact-match `
                                --source "$($costcoPkgSrc.Name)" --verbosity detailed `
                                --prerelease --format json | ConvertFrom-Json
            if ($jsonPackages.problems.Count -gt 0)
            {
                Write-Output "[makeDBG] ----- ERROR with the packages NuGet depot. (Maybe not enabled in Visual Studio?)"
                Write-Output "[makeDBG] ----- ERROR: $($jsonPackages.problems[0].text)"
            }
            else
            {
                #combine all the packages found
                $allPackagesFound = $jsonPackages.searchResult | ForEach-Object { $_.packages }
                Write-Output "[makeDBG] ---- found $($allPackagesFound.Count) packages on source: [$($costcoPkgSrc.Name)])"
                if ($allPackagesFound -imatch $pkgversionDBG)
                {
                    Write-Output "[makeDBG] ---- DEBUG version [$pkgname / $pkgversionDBG] FOUND on NuGet depot: [$($costcoPkgSrc.Name)])"
                    #$dbgPackageFound = $true
                    break
                }
            }
        }
        if (-not $dbgPackageFound)
        {
            Write-Output "[makeDBG] --- DEBUG version [$pkgname / $pkgversionDBG] NOT FOUND on any of the Costco NuGet depots."
        }

        $sources = Get-PackageSource
        $sources
        
        ###Find-Package -Name Newtonsoft.Json
        $jsonPackages = dotnet package search NuGetLiboTest --exact-match --source "csiicu.perso" --verbosity detailed --prerelease --format json | ConvertFrom-Json
        
        $jsonPackages1 = dotnet package search NuGetLiboTest --exact-match --source "csiicu-experiment-cosco" --verbosity detailed --prerelease --format json | ConvertFrom-Json

        $jsonPackages2 = dotnet package search NuGetLiboTest --exact-match --source "https://pkgs.dev.azure.com/costcocloudops/Membership/_packaging/csiicu-v2-s1/nuget/v3/index.json" --prerelease --format json | ConvertFrom-Json

        $jsonPackages3 = dotnet package search NuGetLiboTest --exact-match --source "https://pkgs.dev.azure.com/costcocloudops/Membership/_packaging/MGLO_Nuget_Packages/nuget/v3/index.json" --prerelease --format json | ConvertFrom-Json

        #$credential = Get-Credential -Message "Please provide credentials for the Costco feeds (if needed)."

        $pachete = Find-Package -Name $pkgname  -AllVersions -AllowPrereleaseVersions `
                    -Source "nuget.org" `
                    -ProviderName NuGet #-Credential $credential -ErrorAction Stop
                    

        #$pachete = Find-Package -AllVersions -AllowPrereleaseVersions -Source $CostcoRegisteredPackageSources[0].Location -ErrorAction Stop -ProviderName NuGet
        $pachete | ForEach-Object {
            $_.Id + " " + $_.Version
        } | Out-Host


        #special case: if the use didn't authenticate to the Costco feeds, the nuget list command will return an error message
        $credentialsneeded = $packagesLookup  | Where-Object {$_ -Like "*Please provide credentials*"}

        $credentialsneeded

        #if there's a DEBUG version (suffixed with '-dbg') within the available versions returned by 'nuget list' cmd above
        if ($packagesLookup -match $pkgversionDBG)
        {
            Write-Output "[makeDBG] --- ... DEBUG version as [$pkgname / $pkgversionDBG] FOUND, installing..."
            try
            {
                # Attempt to install the DEBUG version of the package
                dotnet add $csprojfile package $pkgname --version $pkgversionDBG
            }
            catch
            {
                Write-Error "[makeDBG] ERROR: Failed to install DEBUG version [$pkgname / $pkgversionDBG]."
                continue
            }
            
            Write-Output "[makeDBG] --- ... DEBUG version [$pkgname / $pkgversionDBG] installed."
            $handledPackages += [PSCustomObject]@{package=$pkgname;version=$pkgversionDBG}
        }
        else
        {
            $handledPackages += [PSCustomObject]@{package=$pkgname;version=$pkgversion}
            Write-Output "[makeDBG] --- ...NO DBG version found as [$pkgname / $pkgversionDBG], skip handling."
        }
    }
    else
    {
        $handledPackages += [PSCustomObject]@{package=$pkgname;version=$pkgversion}
        Write-Output "[makeDBG] --- Skip (DEBUG version already installed)."
    }
}

Write-Output "[makeDBG] ===================================================================================================="
Write-Output "[makeDBG] Done handling these packages:`n$(OutputMessages($($handledPackages | Format-Table | Out-String)))"

Write-Output "[makeDBG] (Saving handled packages info to: $handledPackagesTrackingFile)"
$handledPackages | Export-Csv -Path $handledPackagesTrackingFile -NoTypeInformation

Write-Output "[makeDBG] DONE!"
