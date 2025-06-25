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


###################
# SCRIPT MAIN BODY
###################
if ([string]::IsNullOrWhiteSpace($csprojfile))
{
    Write-Error "No .csproj file specified. Please provide a valid csproj file!"
    exit 1
}

$CurrentFileName = Split-Path -Path $PSCommandPath -Leaf
Write-Output "[makeDBG] Running the script: $CurrentFileName"

#---Construct the name of the file that keeps track of the already touched packages 
$TMP_FILENAME_ROOT = "mkDBGpkg"
$invalidFilenameChars = ([System.IO.Path]::GetInvalidFileNameChars() + [System.IO.Path]::GetInvalidPathChars() + "." + " ") -join ''
$invalidFilenameChars = [regex]::Escape($invalidFilenameChars)
$sanitizedFilename = $csprojfile -replace "[$invalidFilenameChars]", "-"
$handledPackagesTrackingFile = $env:TEMP + "\$($TMP_FILENAME_ROOT)-$($sanitizedFilename).csv"
$flagUnhandledPackagesOnly = $FALSE

Write-Output "[makeDBG] Checking [$handledPackagesTrackingFile] for previously handled packages"
[array]$previouslyHandledPackages = [PSCustomObject]@()
if (Test-Path $handledPackagesTrackingFile)
{
    $previouslyHandledPackages = Import-Csv -Path $handledPackagesTrackingFile
    Write-Output "[makeDBG] Packages previously handled:`n$(OutputMessages($($previouslyHandledPackages | Format-Table | Out-String)))"
}
else
{
    Write-Output "[makeDBG] (No 'previously handled packages' file was found)."
}

if ($forceCheckAll)
{
    Write-Output "[makeDBG] (forceCheckAll specified => will check ALL project packages, including those already handled)"
}

# ---Retrieve all the referenced NuGet packages and try to replace them with DEBUG version, IF these do exist
Write-Output "[makeDBG] Parsing project file: [$csprojfile]"

[array]$handledPackages = [PSCustomObject]@()

[xml]$csproj = Get-Content $csprojfile
$referencedPackages = $csproj.Project.ItemGroup.PackageReference | Where-Object { $_ -ne $null }
Write-Output "[makeDBG] Found reference(s) to:`n$(OutputMessages($($referencedPackages | Format-Table | Out-String)))"
if ($referencedPackages.Count -eq  0)
{
    Write-Output "[makeDBG] No <PackageReference> found, probably not a .Net project; attempting .Net Framework style."
    $referencedPackages = $csproj.Project.ItemGroup.Reference | Where-Object { $_ -ne $null }
    if ($referencedPackages.Count -eq  0)
    {
        Write-Output "[makeDBG] No <Reference> found, NOTHING TO DO."
    }
}

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
    Write-Output "[makeDBG] - Found reference to package: [$pkgname / $pkgversion]"
    if ($flagUnhandledPackagesOnly -and $packageAlreadyHandled)
    {
        Write-Output "[makeDBG] --- [$pkgname / $pkgversion] ALREADY handled and ONLY newer packages are targeted. Skip."
        $handledPackages += [PSCustomObject]@{package=$pkgname;version=$pkgversion}
        continue
    }

    $pkgversionDBG = $pkgversion + "-dbg" #The DEBUG package will have the VERSION suffix as '-dbg'

    if (-not ($pkgversion.EndsWith("-dbg"))) #this is our DEBUG suffix marker
    {
        Write-Output "[makeDBG] --- Searching for:            [$pkgname / $pkgversionDBG]..."
        
        # Get only Costco based feeds from all the registered Nuget sources.
        # NOTE: this assumes Costco locations are in the form of "https://pkgs.dev.azure.com/COSTCOcloudops/..."
        [array]$CostcoRegisteredPackageSources = Get-PackageSource | Where-Object {$_.Location -Like "*costco*"}

        # Combine all the Costco based packages sources into an argument for "nuget list", like: -Source "location1" -Source "location2"...
        $costcoLocations = $CostcoRegisteredPackageSources| ForEach-Object { "-Source `"$($_.Location)`" " }
        $locations_as_args = $costcoLocations -join " "

        #Execute a NUGET LIST command
        $packagesLookup = Invoke-Expression "nuget list $pkgname $($locations_as_args) -AllVersions -PreRelease"

        #if there's a DEBUG version (suffixed with '-dbg') within the available versions returned by 'nuget list' cmd above
        if ($packagesLookup -match $pkgversionDBG)
        {
            Write-Output "[makeDBG] --- ... DEBUG version as [$pkgname / $pkgversionDBG] FOUND, installing..."
            dotnet add package $pkgname --version $pkgversionDBG
            Write-Output "[makeDBG] --- ... DEBUG version [$pkgname / $pkgversionDBG] installed."
            $handledPackages += [PSCustomObject]@{package=$pkgname;version=$pkgversionDBG}
        }
        else
        {
            $handledPackages += [PSCustomObject]@{package=$pkgname;version=$pkgversion}
            Write-Output "[makeDBG] --- ... NO DEBUG version found as [$pkgname / $pkgversionDBG], skipping."
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
