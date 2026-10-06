BeforeAll {
    $OverlayRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset) }
    function New-TeamsRequestV2 { [CmdletBinding()] param($TenantFilter, $Type, $Action, $Identity, [hashtable]$Parameters) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $TenantFilter, $CurrentValue, $ExpectedValue) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }
    . (Join-Path $OverlayRoot 'Invoke-CIPPStandardPrometheusTeamsExternalChatFiles.ps1')
}

Describe 'Prometheus external Teams chat file sharing standard' {
    BeforeEach {
        $script:Policy = [pscustomobject]@{
            FileSharingInChatsWithExternalUsers = 'Disabled'
            NativeFileEntryPoints              = 'Enabled'
        }
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        $script:FailWrite = $false
        $script:IgnoreWrite = $false
        Mock Test-CIPPStandardLicense { $true }
        Mock Write-LogMessage { }
        Mock Write-StandardsAlert { }
        Mock Set-CIPPStandardsCompareField { }
        Mock New-TeamsRequestV2 {
            param($TenantFilter, $Type, $Action, $Identity, $Parameters)
            $script:Calls.Add(@{ Tenant = $TenantFilter; Type = $Type; Action = $Action; Identity = $Identity; Parameters = $Parameters })
            if ($Action -eq 'Set') {
                if ($script:FailWrite) { throw 'Write rejected' }
                if (-not $script:IgnoreWrite) { $script:Policy.FileSharingInChatsWithExternalUsers = $Parameters.FileSharingInChatsWithExternalUsers }
                return
            }
            $script:Policy
        }
    }

    It 'does not write for a report-only assignment' {
        Invoke-CIPPStandardPrometheusTeamsExternalChatFiles -Tenant 'contoso.com' -Settings @{ state = 'Enabled'; report = $true }
        Should -Invoke New-TeamsRequestV2 -Times 0 -Exactly -ParameterFilter { $Action -eq 'Set' }
        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            $CurrentValue.FileSharingInChatsWithExternalUsers -eq 'Disabled' -and
            $ExpectedValue.FileSharingInChatsWithExternalUsers -eq 'Enabled'
        }
    }

    It 'writes only the selected property to Global in the assigned tenant and reports its readback' {
        Invoke-CIPPStandardPrometheusTeamsExternalChatFiles -Tenant 'contoso.com' -Settings @{ state = @{ value = 'Enabled' }; remediate = $true }
        $Writes = @($script:Calls | Where-Object Action -EQ 'Set')
        $Writes.Count | Should -Be 1
        $Writes[0].Tenant | Should -Be 'contoso.com'
        $Writes[0].Type | Should -Be 'TeamsFilesPolicy'
        $Writes[0].Identity | Should -Be 'Global'
        @($Writes[0].Parameters.Keys).Count | Should -Be 1
        $Writes[0].Parameters.FileSharingInChatsWithExternalUsers | Should -Be 'Enabled'
        $script:Policy.NativeFileEntryPoints | Should -Be 'Enabled'
        Should -Invoke New-TeamsRequestV2 -Times 2 -Exactly -ParameterFilter { $Action -eq 'Get' }
        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            $CurrentValue.FileSharingInChatsWithExternalUsers -eq 'Enabled' -and $TenantFilter -eq 'contoso.com'
        }
    }

    It 'does not rewrite an already compliant policy' {
        $script:Policy.FileSharingInChatsWithExternalUsers = 'Enabled'
        Invoke-CIPPStandardPrometheusTeamsExternalChatFiles -Tenant 'contoso.com' -Settings @{ state = 'Enabled'; remediate = $true }
        Should -Invoke New-TeamsRequestV2 -Times 0 -Exactly -ParameterFilter { $Action -eq 'Set' }
    }

    It 'requires an explicit valid setting before any Teams request' {
        foreach ($State in @($null, '', 'false', 'NotConfigured')) {
            { Invoke-CIPPStandardPrometheusTeamsExternalChatFiles -Tenant 'contoso.com' -Settings @{ state = $State; remediate = $true } } | Should -Throw '*Select Enabled or Disabled*'
        }
        Should -Invoke New-TeamsRequestV2 -Times 0 -Exactly
    }

    It 'does not touch a tenant missing Teams licensing' {
        Mock Test-CIPPStandardLicense { $false }
        Invoke-CIPPStandardPrometheusTeamsExternalChatFiles -Tenant 'contoso.com' -Settings @{ state = 'Enabled'; remediate = $true }
        Should -Invoke New-TeamsRequestV2 -Times 0 -Exactly
    }

    It 'rejects an absent or unknown source policy instead of guessing' {
        $script:Policy.FileSharingInChatsWithExternalUsers = $null
        { Invoke-CIPPStandardPrometheusTeamsExternalChatFiles -Tenant 'contoso.com' -Settings @{ state = 'Enabled'; remediate = $true } } | Should -Throw '*no recognized*'
        Should -Invoke New-TeamsRequestV2 -Times 0 -Exactly -ParameterFilter { $Action -eq 'Set' }
    }

    It 'surfaces a write failure without reporting success' {
        $script:FailWrite = $true
        { Invoke-CIPPStandardPrometheusTeamsExternalChatFiles -Tenant 'contoso.com' -Settings @{ state = 'Enabled'; remediate = $true } } | Should -Throw '*Write rejected*'
        Should -Invoke Set-CIPPStandardsCompareField -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $message -like '*set to Enabled*' }
    }

    It 'does not claim activation when a write is not confirmed by Teams' {
        $script:IgnoreWrite = $true
        { Invoke-CIPPStandardPrometheusTeamsExternalChatFiles -Tenant 'contoso.com' -Settings @{ state = 'Enabled'; remediate = $true } } | Should -Throw '*has not confirmed*'
        Should -Invoke Set-CIPPStandardsCompareField -Times 0 -Exactly
    }

    It 'can explicitly restore Disabled using the same single-property write' {
        $script:Policy.FileSharingInChatsWithExternalUsers = 'Enabled'
        Invoke-CIPPStandardPrometheusTeamsExternalChatFiles -Tenant 'contoso.com' -Settings @{ state = 'Disabled'; remediate = $true }
        $script:Policy.FileSharingInChatsWithExternalUsers | Should -Be 'Disabled'
        $script:Policy.NativeFileEntryPoints | Should -Be 'Enabled'
    }
}
