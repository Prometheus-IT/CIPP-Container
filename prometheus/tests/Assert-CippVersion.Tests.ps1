BeforeAll {
    $Source = if ($env:PROMETHEUS_CIPP_SOURCE) {
        $env:PROMETHEUS_CIPP_SOURCE
    } else {
        Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }
    function Invoke-CIPPRestMethod { param($Uri) }
    . (Join-Path $Source 'backend/Modules/CIPPCore/Public/Assert-CippVersion.ps1')
}

Describe 'Prometheus build versions with the official CIPP version comparison' {
    BeforeEach {
        $script:OriginalNG = $env:CIPPNG
        $script:OriginalVersion = $env:APP_VERSION
        $env:CIPPNG = 'true'
        $env:APP_VERSION = '11.0.2+prometheus.220099ea.1bd40d415549'
        $script:ReleaseVersion = '11.0.2'
        Mock Invoke-CIPPRestMethod { $script:ReleaseVersion }
    }
    AfterEach {
        $env:CIPPNG = $script:OriginalNG
        $env:APP_VERSION = $script:OriginalVersion
    }

    It 'recognizes the current stable release and preserves the complete build identity' {
        $Result = Assert-CippVersion -CIPPVersion $env:APP_VERSION
        $Result.OutOfDateCIPP | Should -BeFalse
        $Result.OutOfDateCIPPAPI | Should -BeFalse
        $Result.LocalCIPPVersion | Should -BeExactly $env:APP_VERSION
        $Result.LocalCIPPAPIVersion | Should -BeExactly $env:APP_VERSION
    }

    It 'uses the running container version when the frontend version is omitted' {
        $Result = Assert-CippVersion
        $Result.OutOfDateCIPP | Should -BeFalse
        $Result.OutOfDateCIPPAPI | Should -BeFalse
    }

    It 'still reports a newer official release <Remote>' -ForEach @(
        @{ Remote = '11.0.3' }
        @{ Remote = '11.1.0' }
        @{ Remote = '12.0.0' }
    ) {
        $script:ReleaseVersion = $Remote
        $Result = Assert-CippVersion -CIPPVersion $env:APP_VERSION
        $Result.OutOfDateCIPP | Should -BeTrue
        $Result.OutOfDateCIPPAPI | Should -BeTrue
    }

    It 'does not report an older official release as an update' {
        $script:ReleaseVersion = '11.0.1'
        $Result = Assert-CippVersion -CIPPVersion $env:APP_VERSION
        $Result.OutOfDateCIPP | Should -BeFalse
        $Result.OutOfDateCIPPAPI | Should -BeFalse
    }

    It 'still treats a genuine prerelease as older than the final release' {
        $env:APP_VERSION = '11.0.2-preview.1'
        $Result = Assert-CippVersion -CIPPVersion $env:APP_VERSION
        $Result.OutOfDateCIPP | Should -BeTrue
        $Result.OutOfDateCIPPAPI | Should -BeTrue
    }

    It 'reports a stale frontend independently of an up-to-date backend' {
        $Result = Assert-CippVersion -CIPPVersion '11.0.1+prometheus.aaaaaaaa.123456789abc'
        $Result.OutOfDateCIPP | Should -BeTrue
        $Result.OutOfDateCIPPAPI | Should -BeFalse
    }

    It 'keeps custom builds distinguishable without creating a false official update' {
        $FrontendVersion = '11.0.2+prometheus.220099ea.abcdef012345.build.12345'
        $Result = Assert-CippVersion -CIPPVersion $FrontendVersion
        $Result.LocalCIPPVersion | Should -Not -BeExactly $Result.LocalCIPPAPIVersion
        $Result.OutOfDateCIPP | Should -BeFalse
        $Result.OutOfDateCIPPAPI | Should -BeFalse
    }
}
