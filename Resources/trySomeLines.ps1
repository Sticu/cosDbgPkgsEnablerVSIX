$jsonPackages = dotnet package search NuGetLiboTest --exact-match --source "csiicu.perso" --verbosity detailed --prerelease --format json | ConvertFrom-Json
$jsonPackages2 = dotnet package search NuGetLiboTest --exact-match --source "https://pkgs.dev.azure.com/costcocloudops/Membership/_packaging/csiicu-v2-s1/nuget/v3/index.json" --prerelease --format json | ConvertFrom-Json
$jsonPackages3 = dotnet package search NuGetLiboTest --exact-match --source "https://pkgs.dev.azure.com/costcocloudops/Membership/_packaging/MGLO_Nuget_Packages/nuget/v3/index.json" --prerelease --format json | ConvertFrom-Json
$h1 = $jsonPackages | ConvertTo-Json -Depth 10
$h2 = $jsonPackages2 | ConvertTo-Json -Depth 10
$h3 = $jsonPackages3 | ConvertTo-Json -Depth 10


$h1 -eq $h2
Compare-Object $h1 $h2



#        $sources = Get-PackageSource
#        $sources
#        
#        Find-Package Newtonsoft.Json.Schema -ProviderName NuGet
#
#        $pachete = Find-Package -Name "Newtonsoft.Json" -Source "nuget.org" -ProviderName NuGet #-Credential $credential -ErrorAction Stop
#
#        $pachete = Find-Package -Name "Newtonsoft.Json" -AllVersions -AllowPrereleaseVersions `
#                    -Source "nuget.org" `
#                    -ProviderName NuGet #-Credential $credential -ErrorAction Stop
