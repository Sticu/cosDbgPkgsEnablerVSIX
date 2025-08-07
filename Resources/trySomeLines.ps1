
        $sources = Get-PackageSource
        $sources
        
        Find-Package Newtonsoft.Json.Schema -ProviderName NuGet

        $pachete = Find-Package -Name "Newtonsoft.Json" -Source "nuget.org" -ProviderName NuGet #-Credential $credential -ErrorAction Stop

        $pachete = Find-Package -Name "Newtonsoft.Json" -AllVersions -AllowPrereleaseVersions `
                    -Source "nuget.org" `
                    -ProviderName NuGet #-Credential $credential -ErrorAction Stop
