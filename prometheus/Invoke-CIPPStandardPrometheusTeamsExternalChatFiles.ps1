function Invoke-CIPPStandardPrometheusTeamsExternalChatFiles {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) PrometheusTeamsExternalChatFiles
    .SYNOPSIS
        (Label) Allow file sharing in external Teams chats (Prometheus)
    .DESCRIPTION
        (Helptext) Sets external chat file sharing in the Global Teams Files policy. Existing OneDrive and SharePoint sharing restrictions still apply.
        (DocsDescription) Controls FileSharingInChatsWithExternalUsers in the Global Teams Files policy. Changes only this property for the tenant assigned to the standard. Client changes can take several hours to appear.
    .NOTES
        CAT
            Teams Standards
        ADDEDCOMPONENT
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"name":"standards.PrometheusTeamsExternalChatFiles.state","label":"External chat file sharing","options":[{"label":"Enabled","value":"Enabled"},{"label":"Disabled","value":"Disabled"}]}
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-10-06
        POWERSHELLEQUIVALENT
            Set-CsTeamsFilesPolicy -Identity Global -FileSharingInChatsWithExternalUsers Enabled
        RECOMMENDEDBY
            Prometheus
        REQUIREDCAPABILITIES
            "MCOSTANDARD"
            "MCOEV"
            "MCOIMP"
            "TEAMS1"
            "Teams_Room_Standard"
    .LINK
        https://learn.microsoft.com/en-us/microsoftteams/share-files-loop-in-external-chats
    #>
    [CmdletBinding()]
    param($Tenant, $Settings)

    $StandardName = 'PrometheusTeamsExternalChatFiles'
    $WantedState = $Settings.state.value ?? $Settings.state

    # Require an explicit choice: an incomplete template must never disable sharing.
    if ($WantedState -notin @('Enabled', 'Disabled')) {
        throw 'Select Enabled or Disabled for external chat file sharing before running this standard.'
    }

    if (-not (Test-CIPPStandardLicense -StandardName $StandardName -TenantFilter $Tenant -Preset Teams)) {
        return
    }

    try {
        $CurrentState = New-TeamsRequestV2 -TenantFilter $Tenant -Type 'TeamsFilesPolicy' -Action Get -Identity 'Global'
        $CurrentValue = $CurrentState.FileSharingInChatsWithExternalUsers
        if ($CurrentValue -notin @('Enabled', 'Disabled')) {
            throw 'Teams returned no recognized FileSharingInChatsWithExternalUsers value; no policy was changed.'
        }

        if ($Settings.remediate -eq $true -and $CurrentValue -ne $WantedState) {
            # Send only the requested property; never replay or reset sibling policy values.
            $null = New-TeamsRequestV2 -TenantFilter $Tenant -Type 'TeamsFilesPolicy' -Action Set -Identity 'Global' -Parameters @{
                FileSharingInChatsWithExternalUsers = $WantedState
            }

            $CurrentState = New-TeamsRequestV2 -TenantFilter $Tenant -Type 'TeamsFilesPolicy' -Action Get -Identity 'Global'
            $CurrentValue = $CurrentState.FileSharingInChatsWithExternalUsers
            if ($CurrentValue -ne $WantedState) {
                throw "Teams has not confirmed external chat file sharing as $WantedState. Read back: $CurrentValue."
            }
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Global Teams Files policy: external chat file sharing set to $WantedState." -sev Info
        }

        if ($Settings.report -eq $true -or $Settings.remediate -eq $true) {
            Set-CIPPStandardsCompareField -FieldName "standards.$StandardName" -TenantFilter $Tenant -CurrentValue @{
                FileSharingInChatsWithExternalUsers = $CurrentValue
            } -ExpectedValue @{
                FileSharingInChatsWithExternalUsers = $WantedState
            }
        }

        if ($Settings.alert -eq $true -and $CurrentValue -ne $WantedState) {
            Write-StandardsAlert -message "Global Teams Files policy: external chat file sharing is $CurrentValue; expected $WantedState." -object $CurrentState -tenant $Tenant -standardName $StandardName -standardId $Settings.standardId
        }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not configure external Teams chat file sharing. Error: $ErrorMessage" -sev Error
        throw
    }
}
