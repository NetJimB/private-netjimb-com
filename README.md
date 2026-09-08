# private.netjimb.com — login-gated page

A private subdomain that only people you explicitly invite can log into.
No public sign-up: accounts are created by you via Cognito.

## How it works

```
Browser --> CloudFront (private.netjimb.com)
              |
              +-- Lambda@Edge (viewer-request): checks for a valid session cookie
              |     - no/expired cookie -> redirect to Cognito Hosted UI login
              |     - Cognito redirects back to /parseauth with an auth code
              |     - Lambda exchanges the code for tokens, sets HttpOnly session cookies
              |     - valid cookie -> request continues to the origin
              |
              +-- S3 bucket (private, only reachable via CloudFront) -- your actual content
```

- **Cognito User Pool** — `AllowAdminCreateUserOnly` is on, so there's no self-service
  sign-up page. You invite people with `New-CognitoUser.ps1`; they get a temporary
  password by email and set their own on first login.
- **Lambda@Edge** — uses [`cognito-at-edge`](https://github.com/awslabs/cognito-at-edge)
  to do the actual OAuth dance and cookie handling. Runs on every viewer request to
  the CloudFront distribution, before anything is served from S3.
- **SSM Parameter Store** — the Lambda function reads its Cognito config (pool ID,
  client ID, domain, region) from SSM at cold start instead of environment variables,
  since Lambda@Edge doesn't support env vars. This also means one `sam deploy` sets
  everything up — no separate step to wire Cognito IDs into the Lambda code.
- **S3 + CloudFront + ACM + Route 53** — a separate bucket and distribution from your
  main netjimb.com site, so this doesn't touch anything already running there.

## Prerequisites

- AWS CLI v2, logged in with credentials that can create Cognito, S3, CloudFront,
  Lambda, IAM, ACM, Route 53, and SSM resources.
- [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html).
- Node.js + npm (to install the Lambda's dependencies before packaging).
- A Route 53 hosted zone for `netjimb.com` in the same AWS account (you already use
  Route 53 as your registrar for it).

## Deploy

```powershell
# Find your hosted zone ID if you don't have it handy:
aws route53 list-hosted-zones-by-name --dns-name netjimb.com --query "HostedZones[0].Id" --output text

.\deploy.ps1 -HostedZoneId Z0123456789ABCDEFGHI -CognitoDomainPrefix netjimb-private
```

`CognitoDomainPrefix` has to be globally unique across all AWS accounts (it becomes
`<prefix>.auth.us-east-1.amazoncognito.com`), so pick something distinctive —
`netjimb-private` might already be taken. Check first with:

```powershell
.\Test-CognitoDomainPrefix.ps1 -Prefix netjimb-private
```

If you'd rather skip the pre-check, that's fine too — `deploy.ps1` detects a
taken prefix from the failed stack event and tells you to pick a different
one and re-run, instead of leaving you to dig through a generic CloudFormation
failure.

Everything deploys to **us-east-1**, regardless of where your other AWS resources
live — that's a hard requirement for both Lambda@Edge and the CloudFront certificate.

First deploy takes a while: CloudFront distributions typically take 15–20 minutes to
propagate globally, and the DNS-validated ACM certificate adds a few more minutes.

## Invite / remove people

```powershell
.\New-CognitoUser.ps1 -Email someone@example.com
.\Remove-CognitoUser.ps1 -Email someone@example.com
```

There's no admin UI beyond these two scripts and the AWS Cognito console — for a
handful of known users that's simpler than building one.

## Updating the private content

The placeholder page is `content/index.html`. Replace it (and add more files
alongside it) then re-upload:

```powershell
aws s3 sync .\content s3://<ContentBucketName>\ --region us-east-1
```

Get the bucket name from the stack outputs:

```powershell
aws cloudformation describe-stacks --stack-name private-netjimb-com --region us-east-1 `
    --query "Stacks[0].Outputs" --output table
```

Because the CloudFront cache behavior uses `CachingDisabled` (auth-gated content
shouldn't be cached at the edge), updates show up immediately — no invalidation
needed.

## Redeploying after a change

Re-run `.\deploy.ps1` with the same parameters — SAM/CloudFormation will update the
existing stack rather than create a new one.

## Running this from GitHub instead (CI/CD)

This repo includes `.github/workflows/deploy.yml`, which runs the same
`sam build` / `sam deploy` / content-sync steps automatically on every push to
`main` that touches `template.yaml`, `lambda-auth/`, or `content/`. It
authenticates to AWS via GitHub's OIDC provider — no long-lived AWS access
keys are stored as GitHub secrets.

### One-time setup

1. **Create the repo and push this code:**

   ```powershell
   git init
   git add .
   git commit -m "Initial private.netjimb.com stack"
   git branch -M main
   git remote add origin https://github.com/NetJimB/private-netjimb-com.git
   git push -u origin main
   ```

2. **Bootstrap the deploy role** — this has to be done once, locally, with
   your own AWS credentials, since GitHub Actions can't create the IAM role
   it will later assume:

   ```powershell
   .\bootstrap\deploy-bootstrap.ps1 -GitHubOrg NetJimB -RepositoryName private-netjimb-com -HostedZoneId Z0123456789ABCDEFGHI
   ```

   If your AWS account already has a GitHub Actions OIDC provider registered
   (check with `aws iam list-open-id-connect-providers`), add
   `-SkipOidcProvider` and it'll prompt for the existing provider's ARN
   instead of trying to create a duplicate — AWS only allows one per URL per
   account.

   This prints a role ARN at the end.

3. **Add repo variables** — in the GitHub repo, under *Settings → Secrets and
   variables → Actions → Variables*, add:

   | Variable | Value |
   |---|---|
   | `AWS_DEPLOY_ROLE_ARN` | the ARN printed by the bootstrap script |
   | `HOSTED_ZONE_ID` | your Route 53 hosted zone ID |
   | `COGNITO_DOMAIN_PREFIX` | the globally-unique prefix you picked |
   | `DOMAIN_NAME` | `private.netjimb.com` |

   None of these are secret (the role can only be assumed from this specific
   repo/branch), so plain Variables are fine — no need for Secrets.

4. **Push, or run it manually.** The workflow fires on the next push to
   `main` that touches the relevant files, or trigger it by hand from the
   Actions tab (it's also set up for `workflow_dispatch`).

### What the deploy role can and can't do

The bootstrap template scopes the deploy role to just what this stack needs —
its own CloudFormation stack, its own S3 bucket, its own Lambda function, an
IAM role matching its own naming pattern, its own SSM parameters, and the one
Route 53 hosted zone you pass in. Cognito, ACM, and CloudFront don't support
resource-level scoping for the actions SAM needs, so those three are granted
account-wide — still limited to those three services, nothing else. If you
reuse this pattern for other stacks later, give each its own role rather than
widening this one.

You can still run `.\deploy.ps1` locally any time too — the GitHub Actions
workflow and the local script deploy the exact same template, they just use
different credentials to do it.

## Notes / things to revisit later

- Cognito's built-in invitation email is plain and unbranded; you can customize it
  in the User Pool's message templates, or swap in SES for nicer branded email.
- MFA is off by default. Turn it on per-user or pool-wide in the Cognito console if
  you want it for this group.
- Session cookies last 7 days (`cookieExpirationDays` in `lambda-auth/index.js`).
- If you ever want self-service password reset, Cognito supports it out of the box —
  currently only account *creation* is admin-only, not password resets for existing
  users.
