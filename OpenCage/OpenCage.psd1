@{
    RootModule        = 'OpenCage.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'a9f1f1d5-1b49-4e7f-9c0f-3bce49963cf0'
    Author            = 'OpenCage Data GmbH'
    CompanyName       = 'OpenCage Data GmbH'
    Copyright         = 'Copyright (c) 2025 OpenCage Data GmbH'
    Description       = 'PowerShell module for interacting with the OpenCage Geocoding API.'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
        'Invoke-Geocode',
        'Invoke-ReverseGeocode'
    )

    CmdletsToExport    = @()
    AliasesToExport    = @()
    VariablesToExport  = @()
    FormatsToProcess   = @()
    TypesToProcess     = @()
    RequiredAssemblies = @()
    ScriptsToProcess   = @()
    NestedModules      = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('OpenCage', 'Geocoding', 'API', 'Geospatial')
            LicenseUri   = 'https://github.com/aliragas/opencage-powershell/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/aliragas/opencage-powershell'
            ReleaseNotes = 'https://github.com/aliragas/opencage-powershell/releases'
        }
    }
}
