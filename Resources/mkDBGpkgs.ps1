#"C:\mlty\consumeNugetLib\consumeNugetLib.csproj"
#"C:\mlty\conUseTestNuget\conUseTestNuget.csproj"
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
    Write-Error "[makeDBG] ERROR: No/invalid .csproj file! Please provide a valid csproj file."
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

# Retrieve the registered nuget sources - filter on Costco based feeds.
# NOTE: this assumes that Costco locations are in the form of "https://pkgs.dev.azure.com/COSTCOcloudops/..."
[array]$allRegisteredPackageDepots = Get-PackageSource
[array]$availablePackagesDepots = $allRegisteredPackageDepots
[array]$costcoRegisteredPackageDepots = $allRegisteredPackageDepots | Where-Object {$_.Location -Like "*costco*"}
if ($costcoRegisteredPackageDepots.Count -eq 0)
{
    Write-Output "[makeDBG] ---No Costco specific NuGet depots, will search on ALL <$($availablePackagesDepots.Count)> registered depots"
    $displayDepotsMessage = $(OutputMessages($availablePackagesDepots | Format-Table Name, Location -Autosize | Out-String -Width 256))
    Write-Output "[makeDBG] Found <$($availablePackagesDepots.Count)> registered NuGet depot(s):"
    Write-Output "$displayDepotsMessage"
    Write-Output "[makeDBG]"
}
else
{
    $availablePackagesDepots = $costcoRegisteredPackageDepots
    $displayDepotsMessage = $(OutputMessages($costcoRegisteredPackageDepots | Format-Table Name, Location -Autosize | Out-String -Width 256))
    Write-Output "[makeDBG] Found <$($costcoRegisteredPackageDepots.Count)> registered Costco specific NuGet depot(s):"
    Write-Output "$displayDepotsMessage"
    Write-Output "[makeDBG]"
}

$flagUnhandledPackagesOnly = $FALSE
Write-Output "[makeDBG] Checking [$handledPackagesTrackingFile] for previously handled packages"
[array]$previouslyHandledPackages = [PSCustomObject]@()
if (Test-Path $handledPackagesTrackingFile -PathType Leaf) #file with previously handled packages does exist
{
    $previouslyHandledPackages = Import-Csv -Path $handledPackagesTrackingFile
    Write-Output "[makeDBG] Packages previously handled:`n$(OutputMessages($($previouslyHandledPackages | Format-Table | Out-String)))"
    Write-Output "[makeDBG]"
}
else #tracking file does NOT exist
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
[array]$debugifieddPackages = [PSCustomObject]@()

[xml]$csproj = Get-Content $csprojfile
$referencedPackages = $csproj.Project.ItemGroup.PackageReference | Where-Object { $_ -ne $null }
Write-Output "[makeDBG] Found reference(s):`n$(OutputMessages($($referencedPackages | Format-Table | Out-String)))"
Write-Output "[makeDBG]"
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

    if (-not ($pkgversion.EndsWith("-dbg"))) #if the current package is not already a DEBUG one, go handle it
    {
        Write-Output "[makeDBG] --- Searching for:             [$pkgname / $pkgversionDBG]..."
        
        $dbgPackageFound = $false
        foreach ($pkgsDepot in $availablePackagesDepots)
        {
            Write-Output "[makeDBG] --- Looking for pkgs on the NuGet depot named: [$($pkgsDepot.Name)]"
            $jsonPackages = dotnet package search $pkgname --exact-match `
                                --source "$($pkgsDepot.Name)" --verbosity detailed `
                                --prerelease --format json | ConvertFrom-Json
            if ($jsonPackages.problems.Count -gt 0)
            {
                Write-Output "[makeDBG] ----- ERROR getting packages from this NuGet depot. (Check and/or enable the source URL in Visual Studio)"
                Write-Output "[makeDBG] ----- ERRORMSG: $($jsonPackages.problems[0].text)"
            }
            else
            {
                #combine all the packages found
                $allPackagesFound = $jsonPackages.searchResult | ForEach-Object { $_.packages } | Where-Object { $_ }
                $allPackagesFound = @($allPackagesFound)
                Write-Output "[makeDBG] ---- found <$($allPackagesFound.Count)> [$pkgname] packages on depot: [$($pkgsDepot.Name)])"
                if ($allPackagesFound -imatch $pkgversionDBG)
                {
                    Write-Output "[makeDBG] ---- found DEBUG version [$pkgname / $pkgversionDBG] on NuGet depot [$($pkgsDepot.Name)])"
                    $dbgPackageFound = $true
                    break
                }
            }
        }

        #if there's a DEBUG version (suffixed with '-dbg') within the available versions returned by the lookup cmd above
        if ($dbgPackageFound)
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
            $debugifiedPackages += [PSCustomObject]@{package=$pkgname;version=$pkgversionDBG}
        }
        else
        {
            $handledPackages += [PSCustomObject]@{package=$pkgname;version=$pkgversion}
            Write-Output "[makeDBG] --- NO DBG version found as [$pkgname / $pkgversionDBG], skip handling."
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
Write-Output "[makeDBG] ===================================================================================================="
Write-Output "[makeDBG] Debugified <$($debugifiedPackages.Count)> packages."
Write-Output "[makeDBG] Debugified packages:`n$(OutputMessages($($debugifiedPackages | Format-Table | Out-String)))"
Write-Output "[makeDBG] ===================================================================================================="
Write-Output "[makeDBG] (Saving handled packages info to: $handledPackagesTrackingFile)"
$handledPackages | Export-Csv -Path $handledPackagesTrackingFile -NoTypeInformation

Write-Output "[makeDBG] DONE!"
