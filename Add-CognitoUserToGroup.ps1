#Requires -Version 5.1
<#
.SYNOPSIS
    Adds someone to a role/permissions group for private.netjimb.com.

.DESCRIPTION
    Groups exist in the Cognito User Pool but nothing enforces them yet --
    see the comment above AdminsGroup/EditorsGroup in template.yaml. This
    script is just the manual, CLI-only way to manage membership until an
    admin UI exists.

.PARAMETER Email
    The email address (username) of the person to add.

.PARAMETER GroupName
    Admins or Editors.

.EXAMPLE
    .\Add-CognitoUserToGroup.ps1 -Email someone@example.com -GroupName Editors
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Email,

    [Parameter(Mandatory)]
    [ValidateSet('Admins', 'Editors')]
    [string]$GroupName
)

$ErrorActionPreference = 'Stop'

$userPoolId = aws ssm get-parameter --name /private-netjimb-com/user-pool-id --query Parameter.Value --output text --region us-east-1
if (-not $userPoolId -or $userPoolId -eq 'None') {
    throw "Could not find the User Pool ID in SSM. Has the stack been deployed?"
}

aws cognito-idp admin-add-user-to-group `
    --user-pool-id $userPoolId `
    --username $Email `
    --group-name $GroupName `
    --region us-east-1

if ($LASTEXITCODE -eq 0) {
    Write-Host "Added $Email to $GroupName."
    Write-Host "Note: this only takes effect on their next login -- an already-issued session token still carries their old group membership until it's refreshed or they sign in again."
}