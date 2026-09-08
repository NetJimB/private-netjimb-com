#Requires -Version 5.1
<#
.SYNOPSIS
    Invites someone to private.netjimb.com (admin-created user, no public sign-up).

.DESCRIPTION
    Creates a Cognito user by email. Cognito emails them a temporary password;
    they'll be required to set a new one on first login. Since the User Pool
    has AllowAdminCreateUserOnly enabled, this is the only way new accounts
    get created.

.PARAMETER Email
    The email address to invite. This becomes their username.

.EXAMPLE
    .\New-CognitoUser.ps1 -Email someone@example.com
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

aws cognito-idp admin-create-user `
    --user-pool-id $userPoolId `
    --username $Email `
    --user-attributes "Name=email,Value=$Email" "Name=email_verified,Value=true" `
    --desired-delivery-mediums EMAIL `
    --region us-east-1

if ($LASTEXITCODE -eq 0) {
    Write-Host "Invited $Email. They'll get a temporary password by email and set their own on first login."
}
