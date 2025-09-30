# OpenCage PowerShell Module

A fully-featured PowerShell module for the [OpenCage Geocoding API](https://opencagedata.com/api), providing forward and reverse geocoding with first-class handling of quotas, errors, and optional API parameters.

## Features

- Forward (`Invoke-Geocode`) and reverse (`Invoke-ReverseGeocode`) geocoding helpers with comment-based help and PowerShell-native parameter validation.
- Supports common optional parameters such as `countrycode`, `language`, `bounds`, `abbrv`, `address_only`, `no_annotations`, `roadinfo`, and more via `-AdditionalParameters`.
- Defensive, global-friendly parsing: no assumptions about results, components, or rate metadata.
- Structured responses include the originating request URI, HTTP status code, rate-limit headers, and the full raw payload for advanced diagnostics.
- Built-in protection against accidental overuse: stops immediately on `402` and `403` and surfaces the API's `status.message`.
- Test suite powered by [Pester 5](https://pester.dev) using the official OpenCage test keys (including the `NOWHERE-INTERESTING` no-results scenario).

## Prerequisites

- PowerShell 7.0 or later (recommended 7.4+)
- Internet access to call the OpenCage API (tests make real requests)
- (For development) [Pester 5.5+](https://www.powershellgallery.com/packages/Pester) for running the test suite

Install Pester once per machine:

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
```

## Installation


The module namespace is `OpenCage`. Install it from the Powershell Gallery:


```powershell

Install-Module OpenCage -Scope CurrentUser

```

## Configuration

Never hardcode API keys. The module automatically reads `OPENCAGE_API_KEY` from your environment. You can also supply `-ApiKey` explicitly.

```powershell
# Windows (PowerShell)
setx OPENCAGE_API_KEY 'YOUR-KEY-HERE'

# macOS / Linux (bash, zsh)
export OPENCAGE_API_KEY='YOUR-KEY-HERE'
```

See the official advice on protecting your key: https://opencagedata.com/guides/how-to-protect-your-api-key

## Usage

All commands emit structured objects. Pipe to `Select-Object`/`Format-Table`, or inspect the `Results` array for fine-grained detail.

### Forward geocoding

```powershell
Invoke-Geocode -Query 'Frauenplan 1, Weimar, Germany' -Limit 1 -Language 'de' |
    Select-Object -ExpandProperty Results |
    Select-Object formatted, confidence
```

### Reverse geocoding

```powershell
Invoke-ReverseGeocode -Latitude 52.5432379 -Longitude 13.4142133 -RoadInfo |
    Select-Object -ExpandProperty Results |
    Select-Object formatted, @{ n = 'DriveOn'; e = { $_.annotations.roadinfo.drive_on } }
```

#### Inspect request metadata for monitoring / debugging

```powershell
Invoke-Geocode -Query 'Berlin, Germany' -Limit 1 |
    Select-Object formatted, confidence, HttpStatusCode, RequestUri
```

### Handling the "no results" scenario

```powershell
$result = Invoke-Geocode -Query 'NOWHERE-INTERESTING'
if (-not $result.HasResults) {
    Write-Host 'No matches found. Try refining your query or supplying bounds/countrycode.'
}
```

### Printing to STDOUT

```powershell
Invoke-Geocode -Query 'London, UK' -Limit 1 |
    Select-Object -ExpandProperty Results |
    Select-Object -ExpandProperty formatted |
    Write-Output
```

### Optional parameters

```powershell
Invoke-Geocode \
    -Query 'Weimar' \
    -CountryCode 'de' \
    -Language 'de' \
    -Abbreviate \
    -Bounds (-11.0, 49.0, 15.0, 55.0) \
    -AdditionalParameters @{ proximity = '50.98,11.33'; limit = 3 }
```

> 💡 Need a refresher on query formatting? Follow the OpenCage best practices: https://opencagedata.com/guides/how-to-format-your-geocoding-query

## Error handling & rate limits

- On `402` (quota exceeded) or `403` (key disabled/IP blocked) the module stops immediately and throws the message returned in `status.message`.
- Other non-success responses are surfaced as exceptions with the full status code and message.
- Free trial responses include a `Rate` object plus `X-RateLimit-*` headers (available on the returned object as `ResponseHeaders`). Subscription accounts omit rate metadata, and the module handles that gracefully.

## Development & testing

1. Clone the repository.
2. Install Pester if needed.
3. Run the test suite (uses OpenCage’s published test keys):

```powershell
Invoke-Pester -Path tests -Output Detailed
```
## Contributing

Pull requests and issues are welcome. Please:

- Follow the established naming and formatting conventions.
- Add or update tests for any changes in behaviour.
- Update the README and module manifest when adding new features.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
