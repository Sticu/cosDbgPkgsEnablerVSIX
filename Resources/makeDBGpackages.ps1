param (
    [string]$csprojfile = "C:\MLTY\conUseTestNuget\conUseTestNuget.csproj"
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

#---Construct the name of the file that keeps track of the already touched packages 
$TMP_FILENAME_ROOT = "mkDBGpkg"
$invalidFilenameChars = ([System.IO.Path]::GetInvalidFileNameChars() + [System.IO.Path]::GetInvalidPathChars() + "." + " ") -join ''
$invalidFilenameChars = [regex]::Escape($invalidFilenameChars)
$sanitizedFilename = $csprojfile -replace "[$invalidFilenameChars]", "-"
$handledPackagesTrackingFile = $env:TEMP + "\$($TMP_FILENAME_ROOT)-$($sanitizedFilename).csv"
$flagUnhandledPackagesOnly = $FALSE

# ---Check if the package(s) replacement with DEBUG packages is NOT desired
# The logic is based on how the current script file, present within the project folders in VS(!), is marked for build:
# - Do no copy: will NOT perform the packages DEBUGification
# - Copy if newer: will PERFORM the packages DEBUGification
# - Copy always:   will PERFORM the packages DEBUGification
$CurrentFileName = Split-Path -Path $PSCommandPath -Leaf
Write-Output "[makeDBG] Running the script: $CurrentFileName"

Write-Output "[makeDBG] Checking [$handledPackagesTrackingFile] for previously handled packages"
[array]$previouslyHandledPackages = [PSCustomObject]@()
if (Test-Path $handledPackagesTrackingFile)
{
    $previouslyHandledPackages = Import-Csv -Path $handledPackagesTrackingFile
    Write-Output "[makeDBG] Previously handled:`n$(OutputMessages($($previouslyHandledPackages | Format-Table | Out-String)))"
}

# Read the script's 'Copy to Output Directory' setting (if any) as set in the VS project
[xml]$csproj = Get-Content $csprojfile
$items = $csproj.Project.ItemGroup.None | Where-Object { $_.Update -eq $CurrentFileName }
$copySetting = $items.CopyToOutputDirectory
#when the script is marked as "Do not copy", just bail out (after deleting the temp file keeping track of handled packages)
if ([string]::IsNullOrWhiteSpace($items) -or ($copySetting -eq "Never"))
{
    Write-Output "[makeDBG] DEBUG Patching NOT enforced ('Copy to Output Directory setting'= $copySetting). NO ACTION DONE."
    if (Test-Path $handledPackagesTrackingFile)
    {
        Remove-Item -Path $handledPackagesTrackingFile
    }
    exit(0)
}
#when the script is marked as "Copy if newer", keep in mind to handle only the previously unhandled packages
elseif ($copySetting -eq "PreserveNewest")
{
    Write-Output "[makeDBG] NOTE: will act on previously unhandled packages ONLY ('Copy to Output Directory setting'= $copySetting)"
    $flagUnhandledPackagesOnly = $TRUE
}
else
{
    Write-Output "[makeDBG] NOTE: will handle ALL referenced packages ('Copy to Output Directory setting'= $copySetting)"
}

#--- Install the Azure Artifacts credential provider. TODO: do this only if it's not alread installed
Invoke-Expression (Invoke-RestMethod -Uri 'https://aka.ms/install-artifacts-credprovider.ps1')

# ---Retrieve all the referenced NuGet packages and try to replace them with DEBUG version, IF these does exist
Write-Output "[makeDBG] Parsing project file: [$csprojfile]"

[array]$handledPackages = [PSCustomObject]@()

[xml]$csproj = Get-Content $csprojfile
$referencedPackages = $csproj.Project.ItemGroup.PackageReference
foreach ($package in $referencedPackages)
{
    $pkgname = $($package.Include)
    $pkgversion = $($package.Version)
    $packageAlreadyHandled = $previouslyHandledPackages | Where-Object {($_.package -eq $pkgname) -and ($_.version -eq $pkgversion)}

    #(occasionally, there are ItemGroups within the .csproj that don't reference packages and comes here as null/empty ->> skip them)
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
Write-Output "[makeDBG] Handled ALL detected packages:`n$(OutputMessages($($handledPackages | Format-Table | Out-String)))"

Write-Output "[makeDBG] (Saving handled packages info to: $handledPackagesTrackingFile)"
$handledPackages | Export-Csv -Path $handledPackagesTrackingFile -NoTypeInformation

Write-Output "[makeDBG] DONE!"
#dotnet restore
#nuget restore
