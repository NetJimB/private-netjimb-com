#Requires -Version 5.1
<#
.SYNOPSIS
    Revokes someone's access to private.netjimb.com.

.PARAMETER Email
    The email address (username) to remove.

.EXAMPLE
    .\Remove-CognitoUser.ps1 -Email someone@example.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Email
)

$ErrorActionPreference = 'Stop'

$userPoolId = aws ssm get-parameter --name /private-netjimb-com/user-pool-id --query Parameter.Value --output text --region us-east-1
if (-not $userPoolId -or $userPoolId -eq 'None') {
    throw "Could not find the User Pool ID in SSM. Has the stack been deployed?"
}

aws cognito-idp admin-delete-user `
    --user-pool-id $userPoolId `
    --username $Email `
    --region us-east-1

if ($LASTEXITCODE -eq 0) {
    Write-Host "Removed $Email. Their existing session cookie will stop working once it expires or they sign out; delete now takes effect immediately for new logins."
}
