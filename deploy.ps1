#Requires -Version 5.1
<#
.SYNOPSIS
    Deploys the private.netjimb.com login-gated page (Cognito + Lambda@Edge + CloudFront + S3).

.DESCRIPTION
    Builds the Lambda@Edge auth function, deploys the CloudFormation/SAM stack
    (must run in us-east-1  -  required for both Lambda@Edge and the CloudFront
    ACM certificate), then uploads the placeholder page to the new S3 bucket.

.PARAMETER HostedZoneId
    Route 53 hosted zone ID for netjimb.com. Find it with:
    aws route53 list-hosted-zones-by-name --dns-name netjimb.com --query "HostedZones[0].Id" --output text

.PARAMETER CognitoDomainPrefix
    A globally-unique prefix for the Cognito Hosted UI domain, e.g. "netjimb-private".
    It becomes <prefix>.auth.us-east-1.amazoncognito.com, so pick something distinctive.

.PARAMETER DomainName
    The subdomain to serve the private page from. Defaults to private.netjimb.com.

.PARAMETER ProjectTag
    Value for a "Project" tag applied to every taggable resource, so
    Resource Groups & Tag Editor in the console can list this alongside
    other stacks (in any region) that share the same tag value.

.EXAMPLE
    .\deploy.ps1 -HostedZoneId Z0123456789ABCDEFGHI -CognitoDomainPrefix netjimb-private
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$HostedZoneId,

    [Parameter(Mandatory)]
    [string]$CognitoDomainPrefix,

    [string]$DomainName = 'private.netjimb.com',

    [string]$StackName = 'private-netjimb-com',

    [string]$ProjectTag = 'private-netjimb-com'
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

Write-Host "==> Checking prerequisites" -ForegroundColor Cyan
foreach ($cmd in @('aws', 'sam', 'npm')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "$cmd is required on PATH. Install AWS CLI v2, AWS SAM CLI, and Node.js/npm first."
    }
}

Write-Host "==> Installing Lambda auth dependencies" -ForegroundColor Cyan
Push-Location (Join-Path $here 'lambda-auth')
try {
    npm install --omit=dev
    if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
}
finally {
    Pop-Location
}

Write-Host "==> Building (sam build)" -ForegroundColor Cyan
sam build --template-file (Join-Path $here 'template.yaml')
if ($LASTEXITCODE -ne 0) { throw "sam build failed" }

Write-Host "==> Deploying stack '$StackName' to us-east-1" -ForegroundColor Cyan
Write-Host "    (Lambda@Edge and the CloudFront cert both require us-east-1 regardless of your other resources.)"
sam deploy `
    --stack-name $StackName `
    --region us-east-1 `
    --capabilities CAPABILITY_IAM `
    --parameter-overrides "DomainName=$DomainName" "HostedZoneId=$HostedZoneId" "CognitoDomainPrefix=$CognitoDomainPrefix" "ProjectTag=$ProjectTag" `
    --resolve-s3 `
    --no-confirm-changeset `
    --no-fail-on-empty-changeset
if ($LASTEXITCODE -ne 0) {
    # Give a specific answer for the most common first-deploy failure: the
    # Cognito domain prefix being taken (it's a global namespace across all
    # AWS accounts, so there's no way to know for sure ahead of time).
    $reason = aws cloudformation describe-stack-events `
        --stack-name $StackName `
        --region us-east-1 `
        --query "StackEvents[?LogicalResourceId=='UserPoolDomain' && contains(ResourceStatus, 'FAILED')].ResourceStatusReason" `
        --output text 2>$null

    if ($reason) {
        Write-Host ""
        Write-Host "==> The Cognito domain prefix '$CognitoDomainPrefix' looks taken:" -ForegroundColor Yellow
        Write-Host "    $reason"
        Write-Host ""
        Write-Host "Pick a different -CognitoDomainPrefix and re-run this script."
    }
    throw "sam deploy failed"
}

Write-Host "==> Uploading placeholder page" -ForegroundColor Cyan
$bucket = aws cloudformation describe-stacks `
    --stack-name $StackName `
    --region us-east-1 `
    --query "Stacks[0].Outputs[?OutputKey=='ContentBucketName'].OutputValue" `
    --output text
if (-not $bucket) { throw "Could not read ContentBucketName output from stack" }

aws s3 cp (Join-Path $here 'content\index.html') "s3://$bucket/index.html" --region us-east-1
if ($LASTEXITCODE -ne 0) { throw "Failed to upload placeholder page" }

Write-Host ""
Write-Host "==> Done" -ForegroundColor Green
Write-Host "Site:    https://$DomainName"
Write-Host "Bucket:  $bucket"
Write-Host ""
Write-Host "It can take 15-20 minutes for CloudFront to finish deploying globally on first run,"
Write-Host "and DNS/certificate validation can add a few more minutes."
Write-Host ""
Write-Host "Invite someone with:"
Write-Host "    .\New-CognitoUser.ps1 -Email someone@example.com"
