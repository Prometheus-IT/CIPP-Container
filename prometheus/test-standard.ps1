$ErrorActionPreference = 'Stop'
$Pester = Get-Module -ListAvailable Pester | Where-Object Version -GE '5.7.1' | Select-Object -First 1
if (-not $Pester) {
    Install-Module Pester -RequiredVersion 5.7.1 -Repository PSGallery -Scope CurrentUser -Force -SkipPublisherCheck
}
Import-Module Pester -MinimumVersion 5.7.1 -Force
$Result = Invoke-Pester -Path (Join-Path $PSScriptRoot 'tests/Invoke-CIPPStandardPrometheusTeamsExternalChatFiles.Tests.ps1') -Output Detailed -PassThru
if ($Result.FailedCount -ne 0 -or $Result.PassedCount -lt 9) {
    throw 'External Teams chat file-sharing standard tests failed.'
}
