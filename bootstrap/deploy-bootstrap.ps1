#Requires -Version 5.1
<#
.SYNOPSIS
    One-time setup: creates the IAM role GitHub Actions will assume to deploy
    private-netjimb-com. Run this once, locally, with your own AWS credentials.

.PARAMETER GitHubOrg
    Your GitHub org/username, e.g. NetJimB.

.PARAMETER RepositoryName
    The repo name, e.g. private-netjimb-com.

.PARAMETER HostedZoneId
    Route 53 hosted zone ID for netjimb.com.

.PARAMETER Branch
    Branch allowed to deploy. Defaults to main.

.PARAMETER SkipOidcProvider
    Pass this if your AWS account already has a GitHub Actions OIDC provider
    registered (check with: aws iam list-open-id-connect-providers). You'll
    be prompted for its ARN.

.PARAMETER ProjectTag
    Value for a "Project" tag on the deploy role itself  -  matches the tag
    template.yaml puts on the site's own resources by default. Set it to
    whatever value you use to group things in Resource Groups & Tag Editor.

.EXAMPLE
    .\deploy-bootstrap.ps1 -GitHubOrg NetJimB -RepositoryName private-netjimb-com -HostedZoneId Z0123456789ABCDEFGHI
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$GitHubOrg,

    [Parameter(Mandatory)]
    [string]$RepositoryName,

    [Parameter(Mandatory)]
    [string]$HostedZoneId,

    [string]$Branch = 'main',

    [switch]$SkipOidcProvider,

    [string]$ProjectTag = 'private-netjimb-com'
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

$params = @(
    "GitHubOrg=$GitHubOrg"
    "RepositoryName=$RepositoryName"
    "HostedZoneId=$HostedZoneId"
    "Branch=$Branch"
    "ProjectTag=$ProjectTag"
)

if ($SkipOidcProvider) {
    $existingArn = Read-Host "Existing GitHub OIDC provider ARN (from 'aws iam list-open-id-connect-providers')"
    $params += "CreateOidcProvider=false"
    $params += "ExistingOidcProviderArn=$existingArn"
}

Write-Host "==> Deploying bootstrap stack to us-east-1" -ForegroundColor Cyan
aws cloudformation deploy `
    --template-file (Join-Path $here 'github-oidc-role.yaml') `
    --stack-name private-netjimb-com-github-oidc `
    --region us-east-1 `
    --capabilities CAPABILITY_NAMED_IAM `
    --parameter-overrides $params
if ($LASTEXITCODE -ne 0) { throw "Bootstrap deploy failed" }

$roleArn = aws cloudformation describe-stacks `
    --stack-name private-netjimb-com-github-oidc `
    --region us-east-1 `
    --query "Stacks[0].Outputs[?OutputKey=='DeployRoleArn'].OutputValue" `
    --output text

Write-Host ""
Write-Host "==> Done" -ForegroundColor Green
Write-Host "Add these as Actions variables in the GitHub repo (Settings > Secrets and variables > Actions > Variables):"
Write-Host "  AWS_DEPLOY_ROLE_ARN   = $roleArn"
Write-Host "  HOSTED_ZONE_ID        = $HostedZoneId"
Write-Host "  COGNITO_DOMAIN_PREFIX = <pick a globally-unique prefix, e.g. netjimb-private>"
Write-Host "  DOMAIN_NAME           = private.netjimb.com"
Write-Host "  PROJECT_TAG           = $ProjectTag   (optional  -  defaults to this if you skip it)"
Write-Host ""
Write-Host "Then push to $Branch and the deploy.yml workflow takes it from there."
