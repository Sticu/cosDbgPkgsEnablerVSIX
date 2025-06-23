param (
    [string]$csprojfile = ""
    )

function OutputMessages
{
    param($message)
    $modifiedOutput = $message -split "`r`n" | Where-Object { $_.Trim() -ne "" }
    $modifiedOutput = $modifiedOutput -split "`r`n" | ForEach-Object { "[makeDBG]    $_" }
    $modifiedOutput = $modifiedOutput -join "`r`n"
    Write-Output $($modifiedOutput)
}

if ([string]::IsNullOrWhiteSpace($csprojfile)
{
    Write-Error "No csproj file specified. Please provide a valid csproj file."
    exit 1
}

