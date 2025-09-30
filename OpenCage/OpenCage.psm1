Set-StrictMode -Version Latest

$script:ModuleVersion = '0.1.0'
$script:ModuleUserAgent = "OpenCage.PowerShell/$($script:ModuleVersion) (+https://github.com/aliragas/opencage-powershell)"
$script:InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture

function Get-OpenCageApiKey {
    [CmdletBinding()]
    param(
        [string]$ApiKey
    )

    if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
        return $ApiKey
    }

    $scopes = @('Process', 'User', 'Machine')
    foreach ($scope in $scopes) {
        $value = [Environment]::GetEnvironmentVariable('OPENCAGE_API_KEY', $scope)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    throw [System.InvalidOperationException]::new('OpenCage API key not found. Set the OPENCAGE_API_KEY environment variable or use the -ApiKey parameter.')
}

function ConvertTo-OpenCageQueryString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Parameters
    )

    $pairs = [System.Collections.Generic.List[string]]::new()

    foreach ($key in $Parameters.Keys) {
        $value = $Parameters[$key]
        if ($null -eq $value) {
            continue
        }

        $escapedKey = [Uri]::EscapeDataString($key)

        switch ($value) {
            { $_ -is [bool] } {
                $escapedValue = [Uri]::EscapeDataString(([Convert]::ToInt32($_)).ToString())
                $pairs.Add("$escapedKey=$escapedValue")
                continue
            }
            { $_ -is [System.Array] -and -not ($_ -is [string]) } {
                $stringValue = ($_ |
                    ForEach-Object {
                        if ($_ -is [System.IFormattable]) {
                            $_.ToString($null, $script:InvariantCulture)
                        }
                        else {
                            $_.ToString()
                        }
                    }) -join ','
                $escapedValue = [Uri]::EscapeDataString($stringValue)
                $pairs.Add("$escapedKey=$escapedValue")
                continue
            }
            default {
                if ($value -is [System.IFormattable]) {
                    $stringValue = $value.ToString($null, $script:InvariantCulture)
                }
                else {
                    $stringValue = $value.ToString()
                }
                $escapedValue = [Uri]::EscapeDataString($stringValue)
                $pairs.Add("$escapedKey=$escapedValue")
            }
        }
    }

    return ($pairs -join '&')
}

function Invoke-OpenCageApiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Parameters,
        [string]$ApiKey
    )

    $resolvedKey = Get-OpenCageApiKey -ApiKey $ApiKey

    if (-not $Parameters.ContainsKey('q') -or [string]::IsNullOrWhiteSpace($Parameters['q'])) {
        throw [System.ArgumentException]::new('Query parameter "q" is required and cannot be empty.')
    }

    $effectiveParameters = [ordered]@{}
    foreach ($existingKey in $Parameters.Keys) {
        $effectiveParameters[$existingKey] = $Parameters[$existingKey]
    }
    $effectiveParameters['key'] = $resolvedKey

    $queryString = ConvertTo-OpenCageQueryString -Parameters $effectiveParameters
    $uri = "https://api.opencagedata.com/geocode/v1/json?$queryString"

    $headers = @{
        'User-Agent' = $script:ModuleUserAgent
        'Accept'     = 'application/json'
    }

    $responseHeaders = $null
    $statusCodeValue = $null
    $responseBody = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -SkipHttpErrorCheck -StatusCodeVariable statusCodeValue -ResponseHeadersVariable responseHeaders -ErrorAction Stop

    if ($null -eq $responseBody) {
        throw [System.Exception]::new('The OpenCage API did not return a response body.')
    }

    if (-not ($responseBody.PSObject.Properties.Name -contains 'status')) {
        throw [System.Exception]::new('Unexpected OpenCage API response format: missing status information.')
    }

    $statusCode = $responseBody.status.code
    $statusMessage = $responseBody.status.message

    if ($statusCode -ne 200) {
        $errorMessage = if ($statusMessage) {
            "OpenCage API error $($statusCode): $statusMessage"
        } else {
            "OpenCage API error $($statusCode)"
        }

        if ($statusCode -in @(402, 403)) {
            throw [System.InvalidOperationException]::new($errorMessage)
        }

        throw [System.Exception]::new($errorMessage)
    }

    $results = $responseBody.results
    if ($null -eq $results) {
        $resultCollection = @()
    }
    elseif ($results -is [System.Collections.IEnumerable] -and -not ($results -is [string])) {
        $resultCollection = @($results)
    }
    else {
        $resultCollection = ,$results
    }

    $hasResults = ($resultCollection.Count -gt 0)

    $rate = $null
    if ($responseBody.PSObject.Properties.Name -contains 'rate') {
        $rate = $responseBody.rate
    }

    $httpStatusCode = $null
    if ($null -ne $statusCodeValue) {
        try {
            $httpStatusCode = [int]$statusCodeValue
        }
        catch {
            $httpStatusCode = $statusCodeValue
        }
    }

    return [pscustomobject]@{
        Query          = $effectiveParameters['q']
        RequestUri     = $uri
        HttpStatusCode = $httpStatusCode
        Status         = $responseBody.status
        TotalResults   = $responseBody.total_results
        HasResults     = $hasResults
        Results        = $resultCollection
        Rate           = $rate
        ResponseHeaders = $responseHeaders
        Raw            = $responseBody
    }
}

function Add-OpenCageOptionalParameters {
    param(
        [ref]$Target,
        [hashtable]$Source
    )

    if ($null -eq $Source) {
        return
    }

    $dictionary = $Target.Value

    foreach ($key in $Source.Keys) {
        if ([string]::IsNullOrWhiteSpace($key)) {
            continue
        }

        if (@('q', 'key') -contains $key) {
            continue
        }

        $value = $Source[$key]
        if ($null -eq $value) {
            continue
        }

        if ($value -is [bool]) {
            $dictionary[$key] = if ($value) { 1 } else { 0 }
        }
        elseif ($value -is [System.Management.Automation.SwitchParameter]) {
            $dictionary[$key] = if ($value.IsPresent) { 1 } else { 0 }
        }
        elseif ($value -is [System.IFormattable]) {
            $dictionary[$key] = $value.ToString($null, $script:InvariantCulture)
        }
        else {
            $dictionary[$key] = $value
        }
    }

    $Target.Value = $dictionary
}

<#
 .SYNOPSIS
 Performs forward geocoding via the OpenCage Geocoding API.

 .DESCRIPTION
 Sends an address or placename query to the OpenCage API and returns a structured
 response containing metadata, results, HTTP status, headers, and the original
 request URI. Supports the most common optional query parameters, defensive
 parsing for missing fields, and a -Raw switch for accessing the unmodified API
 payload.

 .PARAMETER Query
 A forward geocoding query string (address or placename). Must be at least two
 characters once trimmed.

 .PARAMETER ApiKey
 Overrides the OPENCAGE_API_KEY environment variable. If omitted the environment
 variable must be set.

 .PARAMETER CountryCode
 One or more ISO 3166-1 alpha-2 country codes used to restrict results. Codes are
 normalized to lowercase as required by the API.

 .PARAMETER Language
 Preferred language for the response (IETF language tag such as "en" or "pt-BR").

 .PARAMETER Limit
 Maximum number of forward geocoding results to return (1-100).

 .PARAMETER Bounds
 Four numeric values describing the southwest and northeast corners of a bounding
 box in the form: minLongitude, minLatitude, maxLongitude, maxLatitude.

 .PARAMETER ProximityLatitude
 Latitude component (decimal degrees) for the proximity bias hint. Must be used
 together with -ProximityLongitude.

 .PARAMETER ProximityLongitude
 Longitude component (decimal degrees) for the proximity bias hint. Must be used
 together with -ProximityLatitude.

 .PARAMETER Abbreviate
 When present, sets the abbrv optional parameter to 1 to request abbreviated
 formatted strings.

 .PARAMETER AddressOnly
 When set, instructs the API to return formatted strings without POI names.

 .PARAMETER NoAnnotations
 When set, requests that annotation data be omitted.

 .PARAMETER NoDedupe
 Disables result deduplication.

 .PARAMETER NoRecord
 Requests the API not to store the query contents.

 .PARAMETER Pretty
 Requests a pretty-printed JSON response (for debugging).

 .PARAMETER RoadInfo
 Requests the roadinfo optional behavior/annotation.

 .PARAMETER AdditionalParameters
 Hashtable of additional optional parameters to include. Reserved keys (q, key)
 are ignored.

 .PARAMETER Raw
 Returns the API payload exactly as received instead of the structured PowerShell
 response object.

 .OUTPUTS
System.Management.Automation.PSCustomObject

 .EXAMPLE
 Invoke-Geocode -Query 'Frauenplan 1, Weimar, Germany' -Limit 1
 Retrieves a single result for Goethe National Museum and returns the structured response
 including metadata such as HttpStatusCode and RequestUri.

 .EXAMPLE
 Invoke-Geocode -Query 'Nowhere-Interesting' -Limit 1
 Demonstrates handling of the no-results scenario. Inspect the HasResults property to
 determine whether any matches were found before accessing the Results collection.
#>
function Invoke-Geocode {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Query,
        [string]$ApiKey,
        [string[]]$CountryCode,
        [string]$Language,
        [ValidateRange(1,100)][int]$Limit,
        [double[]]$Bounds,
        [double]$ProximityLatitude,
        [double]$ProximityLongitude,
        [switch]$Abbreviate,
        [switch]$AddressOnly,
        [switch]$NoAnnotations,
        [switch]$NoDedupe,
        [switch]$NoRecord,
        [switch]$Pretty,
        [switch]$RoadInfo,
        [hashtable]$AdditionalParameters,
        [switch]$Raw
    )

    $params = [ordered]@{
        q = $Query
    }

    if ($CountryCode) {
        $normalizedCodes = @()
        foreach ($code in $CountryCode) {
            if ([string]::IsNullOrWhiteSpace($code)) {
                continue
            }

            $normalizedCodes += $code.ToString().ToLowerInvariant()
        }

        if (-not $normalizedCodes) {
            throw [System.ArgumentException]::new('CountryCode must contain at least one non-empty ISO 3166-1 alpha-2 code.')
        }

        $params['countrycode'] = [string]::Join(',', $normalizedCodes)
    }

    if ($PSBoundParameters.ContainsKey('Language')) {
        $params['language'] = $Language
    }

    if ($PSBoundParameters.ContainsKey('Limit')) {
        $params['limit'] = $Limit
    }

    if ($Bounds) {
        if ($Bounds.Count -ne 4) {
            throw [System.ArgumentException]::new('Bounds must contain exactly four numeric values: minLongitude, minLatitude, maxLongitude, maxLatitude.')
        }

        $params['bounds'] = ($Bounds | ForEach-Object { $_.ToString($script:InvariantCulture) }) -join ','
    }

    if ($PSBoundParameters.ContainsKey('ProximityLatitude') -or $PSBoundParameters.ContainsKey('ProximityLongitude')) {
        if (-not ($PSBoundParameters.ContainsKey('ProximityLatitude') -and $PSBoundParameters.ContainsKey('ProximityLongitude'))) {
            throw [System.ArgumentException]::new('Both ProximityLatitude and ProximityLongitude must be specified together.')
        }

        $lat = $ProximityLatitude.ToString($script:InvariantCulture)
        $lng = $ProximityLongitude.ToString($script:InvariantCulture)
        $params['proximity'] = "$lat,$lng"
    }

    if ($Abbreviate.IsPresent) {
        $params['abbrv'] = 1
    }

    if ($AddressOnly.IsPresent) {
        $params['address_only'] = 1
    }

    if ($NoAnnotations.IsPresent) {
        $params['no_annotations'] = 1
    }

    if ($NoDedupe.IsPresent) {
        $params['no_dedupe'] = 1
    }

    if ($NoRecord.IsPresent) {
        $params['no_record'] = 1
    }

    if ($Pretty.IsPresent) {
        $params['pretty'] = 1
    }

    if ($RoadInfo.IsPresent) {
        $params['roadinfo'] = 1
    }

    Add-OpenCageOptionalParameters -Target ([ref]$params) -Source $AdditionalParameters

    $result = Invoke-OpenCageApiRequest -Parameters $params -ApiKey $ApiKey

    if ($Raw.IsPresent) {
        return $result.Raw
    }

    return $result
}

<#
 .SYNOPSIS
 Performs reverse geocoding via the OpenCage Geocoding API.

 .DESCRIPTION
 Sends a latitude/longitude coordinate pair to the OpenCage API and returns a
 structured response containing metadata, results, HTTP status, headers, and
 the original request URI. Optional switches mirror the forward geocoding
 command and a -Raw switch returns the unmodified API payload.

 .PARAMETER Latitude
 Decimal degree latitude value between -90 and 90 inclusive.

 .PARAMETER Longitude
 Decimal degree longitude value between -180 and 180 inclusive.

 .PARAMETER ApiKey
 Overrides the OPENCAGE_API_KEY environment variable. If omitted the environment
 variable must be set.

 .PARAMETER Language
 Preferred response language (IETF language tag such as "en" or "pt-BR").

 .PARAMETER AddressOnly
 When set, instructs the API to return formatted strings without POI names.

 .PARAMETER NoAnnotations
 Requests that annotation data be omitted from the response.

 .PARAMETER NoRecord
 Requests that the API not store the query contents.

 .PARAMETER Pretty
 Requests a pretty-printed JSON response (for debugging).

 .PARAMETER RoadInfo
 Requests the roadinfo optional behavior/annotation.

 .PARAMETER AdditionalParameters
 Hashtable of additional optional parameters to include. Reserved keys (q, key)
 are ignored.

 .PARAMETER Raw
 Returns the API payload exactly as received instead of the structured PowerShell
 response object.

 .OUTPUTS
 System.Management.Automation.PSCustomObject

 .EXAMPLE
 Invoke-ReverseGeocode -Latitude 51.9526622 -Longitude 7.6324709
 Returns the address information associated with the supplied coordinates in Münster,
 Germany.

 .EXAMPLE
 Invoke-ReverseGeocode -Latitude 52.5432379 -Longitude 13.4142133 -RoadInfo
 Requests additional road metadata (when available) while returning the structured
 response object for further inspection or formatting.
#>
function Invoke-ReverseGeocode {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][ValidateRange(-90,90)][double]$Latitude,
        [Parameter(Mandatory)][ValidateRange(-180,180)][double]$Longitude,
        [string]$ApiKey,
        [string]$Language,
        [switch]$AddressOnly,
        [switch]$NoAnnotations,
        [switch]$NoRecord,
        [switch]$Pretty,
        [switch]$RoadInfo,
        [hashtable]$AdditionalParameters,
        [switch]$Raw
    )

    $lat = $Latitude.ToString($script:InvariantCulture)
    $lng = $Longitude.ToString($script:InvariantCulture)

    $params = [ordered]@{
        q = "$lat,$lng"
    }

    if ($PSBoundParameters.ContainsKey('Language')) {
        $params['language'] = $Language
    }

    if ($AddressOnly.IsPresent) {
        $params['address_only'] = 1
    }

    if ($NoAnnotations.IsPresent) {
        $params['no_annotations'] = 1
    }

    if ($NoRecord.IsPresent) {
        $params['no_record'] = 1
    }

    if ($Pretty.IsPresent) {
        $params['pretty'] = 1
    }

    if ($RoadInfo.IsPresent) {
        $params['roadinfo'] = 1
    }

    Add-OpenCageOptionalParameters -Target ([ref]$params) -Source $AdditionalParameters

    $result = Invoke-OpenCageApiRequest -Parameters $params -ApiKey $ApiKey

    if ($Raw.IsPresent) {
        return $result.Raw
    }

    return $result
}

Export-ModuleMember -Function @('Invoke-Geocode', 'Invoke-ReverseGeocode')
