$moduleRoot = Join-Path $PSScriptRoot '..' 'OpenCage'
Import-Module (Join-Path $moduleRoot 'OpenCage.psd1') -Force

Describe 'OpenCage PowerShell module' {
    $originalKey = $env:OPENCAGE_API_KEY

    BeforeEach {
        if ($null -ne $originalKey) {
            [Environment]::SetEnvironmentVariable('OPENCAGE_API_KEY', $originalKey, 'Process')
        }
        else {
            [Environment]::SetEnvironmentVariable('OPENCAGE_API_KEY', $null, 'Process')
        }
    }

    AfterAll {
        if ($null -ne $originalKey) {
            [Environment]::SetEnvironmentVariable('OPENCAGE_API_KEY', $originalKey, 'Process')
        }
        else {
            [Environment]::SetEnvironmentVariable('OPENCAGE_API_KEY', $null, 'Process')
        }
    }

    Context 'API key handling' {
        It 'throws when the API key is missing' {
            [Environment]::SetEnvironmentVariable('OPENCAGE_API_KEY', $null, 'Process')

            $caught = $false

            try {
                Invoke-Geocode -Query 'Berlin, Germany' -ErrorAction Stop
            }
            catch [System.InvalidOperationException] {
                $caught = $true
                $_.Exception.Message | Should -Match 'OpenCage API key'
            }

            $caught | Should -BeTrue
        }
    }

    Context 'Forward geocoding' {
        It 'returns at least one result for a valid query' {
            [Environment]::SetEnvironmentVariable('OPENCAGE_API_KEY', '6d0e711d72d74daeb2b0bfd2a5cdfdba', 'Process')
            $result = Invoke-Geocode -Query 'Frauenplan 1, Weimar, Germany' -Limit 1

            $result.Status.code | Should -Be 200
            $result.HasResults | Should -BeTrue
            $result.Results | Should -Not -BeNullOrEmpty
            $result.HttpStatusCode | Should -Be 200
            $result.RequestUri | Should -Match 'Frauenplan%201'
        }

        It 'handles the no results scenario gracefully' {
            [Environment]::SetEnvironmentVariable('OPENCAGE_API_KEY', '6d0e711d72d74daeb2b0bfd2a5cdfdba', 'Process')
            $result = Invoke-Geocode -Query 'NOWHERE-INTERESTING' -Limit 1

            $result.Status.code | Should -Be 200
            $result.HasResults | Should -BeFalse
            $result.TotalResults | Should -Be 0
        }

        It 'supports optional parameters like countrycode and language' {
            [Environment]::SetEnvironmentVariable('OPENCAGE_API_KEY', '6d0e711d72d74daeb2b0bfd2a5cdfdba', 'Process')
            $result = Invoke-Geocode -Query 'Weimar' -CountryCode 'de' -Language 'de' -Limit 1

            $result.Status.code | Should -Be 200
            $result.Results[0].components.country_code | Should -Be 'de'
        }

        It 'includes additional parameters and supports the Raw switch' {
            [Environment]::SetEnvironmentVariable('OPENCAGE_API_KEY', '6d0e711d72d74daeb2b0bfd2a5cdfdba', 'Process')

            $structured = Invoke-Geocode -Query 'Berlin, Germany' -Limit 1 -AdditionalParameters @{ no_annotations = $true }
            $structured.RequestUri | Should -Match 'no_annotations=1'

            $raw = Invoke-Geocode -Query 'Berlin, Germany' -Limit 1 -Raw
            $raw.status.code | Should -Be 200
        }
    }

    Context 'Reverse geocoding' {
        It 'returns a location for known coordinates' {
            [Environment]::SetEnvironmentVariable('OPENCAGE_API_KEY', '6d0e711d72d74daeb2b0bfd2a5cdfdba', 'Process')
            $result = Invoke-ReverseGeocode -Latitude 52.5432379 -Longitude 13.4142133

            $result.Status.code | Should -Be 200
            $result.HasResults | Should -BeTrue
            $result.Results[0].formatted | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Error handling for API responses' {
        It 'throws on quota exceeded (402)' {
            [Environment]::SetEnvironmentVariable('OPENCAGE_API_KEY', '4372eff77b8343cebfc843eb4da4ddc4', 'Process')

            $caught = $false

            try {
                Invoke-Geocode -Query 'Berlin, Germany' -ErrorAction Stop
            }
            catch [System.InvalidOperationException] {
                $caught = $true
                $_.Exception.Message | Should -Match '402'
            }

            $caught | Should -BeTrue
        }

        It 'throws on disabled key (403)' {
            [Environment]::SetEnvironmentVariable('OPENCAGE_API_KEY', '2e10e5e828262eb243ec0b54681d699a', 'Process')

            $caught = $false

            try {
                Invoke-Geocode -Query 'Berlin, Germany' -ErrorAction Stop
            }
            catch [System.InvalidOperationException] {
                $caught = $true
                $_.Exception.Message | Should -Match '403'
            }

            $caught | Should -BeTrue
        }
    }
}
