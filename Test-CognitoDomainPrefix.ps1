#Requires -Version 5.1
<#
.SYNOPSIS
    Checks whether a Cognito Hosted UI domain prefix is already taken.

.DESCRIPTION
    Cognito domain prefixes share one global namespace across every AWS
    account, not just yours, so this doesn't require your stack (or any
    Cognito resources) to exist yet.

    describe-user-pool-domain returns an empty DomainDescription for a
    prefix nobody has claimed, and a populated one (with a Status) for a
    prefix that's in use  -  that's the check this script relies on. It's a
    long-standing, widely-used technique, though AWS doesn't spell it out
    in the API docs, so treat "available" here as "very likely available"
    and let the actual deploy be the final word.

.PARAMETER Prefix
    The prefix to check, e.g. netjimb-private (without the
    .auth.us-east-1.amazoncognito.com suffix).

.EXAMPLE
    .\Test-CognitoDomainPrefix.ps1 -Prefix netjimb-private
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Prefix
)

$ErrorActionPreference = 'Stop'

$json = aws cognito-idp describe-user-pool-domain --domain $Prefix --region us-east-1 --output json
$result = $json | ConvertFrom-Json

if ($null -eq $result.DomainDescription -or $null -eq $result.DomainDescription.Status) {
    Write-Host "'$Prefix' looks AVAILABLE." -ForegroundColor Green
    Write-Host "It becomes: $Prefix.auth.us-east-1.amazoncognito.com"
}
else {
    Write-Host "'$Prefix' is already TAKEN (status: $($result.DomainDescription.Status))." -ForegroundColor Yellow
    Write-Host "Pick a different prefix."
}
