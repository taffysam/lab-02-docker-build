# Shipping Calculator CI/CD Labs

A hands-on CI/CD learning project that evolves a small Python shipping
calculator from basic continuous integration into a controlled
multi-environment Docker deployment pipeline.

The project demonstrates a core release principle:

> **Build once, test once, publish once, and promote the same immutable
> artifact through environments.**

## What Was Built

The final pipeline uses:

-   Python and `pytest` for the application and automated tests
-   Docker for packaging the application
-   GitHub Actions for CI/CD orchestration
-   GitHub Container Registry (GHCR) for container images
-   A Windows self-hosted GitHub Actions runner for deployment
-   Docker Desktop as the lab runtime
-   GitHub Environments for development and production configuration
-   GitHub production approval and branch restrictions
-   PowerShell deployment automation
-   Startup and functional verification
-   Automatic rollback
-   Immutable Docker image promotion by SHA-256 digest

## Final Pipeline

``` text
Pull Request
    |
    v
Unit Tests
    |
    v
Build Docker Image
    |
    v
Container Tests
    |
    v
Merge / Push to main
    |
    v
Publish Validated Image to GHCR
    |
    v
Capture Immutable @sha256 Reference
    |
    v
Deploy Automatically to DEV
    |
    +--> Startup Verification
    +--> Functional Verification
    +--> Rollback on Failure
    |
    v
GitHub Production Environment
    |
    v
Required Human Approval
    |
    v
Deploy SAME Immutable Image to PROD
    |
    +--> Production Configuration
    +--> Startup Verification
    +--> Functional Verification
    +--> Rollback on Failure
```

The final verification showed that DEV and PROD were running the same
Docker image:

``` text
sha256:3d23ae328c02c1edd6c25304cc2ac7441d67abaac944ea0925277f0c986eeefd
```

while retaining different configuration:

``` text
DEV:
APP_ENV=development
APP_NAME=shipping-calculator

PROD:
APP_ENV=production
APP_NAME=shipping-calculator
```

------------------------------------------------------------------------

# Lab 1 - Basic Continuous Integration

The first lab introduced the CI lifecycle around the Python shipping
calculator.

The application included standard and express shipping calculations and
was tested with `pytest`.

Typical local validation:

``` powershell
python -m pytest -v
```

The test suite eventually contained six passing tests.

Git workflow used during the labs:

``` powershell
git status
git switch -c feature/<feature-name>
git add .
git commit -m "<commit message>"
git push -u origin feature/<feature-name>
```

A Pull Request was then opened and merged into `main`.

This established the first important CI rule:

``` text
Developer change
      |
      v
Feature branch
      |
      v
Pull Request
      |
      v
Automated tests
      |
      v
Merge to main
```

------------------------------------------------------------------------

# Lab 2 - Docker Build and GHCR Publishing

The application was containerized with Docker.

Typical local commands:

``` powershell
docker build -t shipping-calculator .
docker run --rm shipping-calculator python -m pytest -v
```

GitHub Actions was then configured to:

1.  Run unit tests.
2.  Build the Docker image.
3.  Run tests inside the image.
4.  Save the validated Docker image.
5.  Upload it as a workflow artifact.
6.  Download that exact image in the publish job.
7.  Push it to GHCR.

The image naming pattern became:

``` text
ghcr.io/taffysam/lab-02-docker-build/shipping-calculator:<git-sha>
```

This was an important improvement over rebuilding during the publish
stage.

The pipeline became:

``` text
TEST
 |
 v
BUILD
 |
 v
TEST CONTAINER
 |
 v
SAVE IMAGE
 |
 v
PUBLISH SAME IMAGE
```

This established the **build-once** principle.

Useful Docker inspection commands:

``` powershell
docker images
docker ps
docker ps -a
docker logs <container-name>
docker inspect <container-name>
```

------------------------------------------------------------------------

# Lab 3 - Self-Hosted Deployment and Rollback

A Windows self-hosted GitHub Actions runner was installed in:

``` text
C:\actions-runner
```

Runner name:

``` text
shipping-dev-runner
```

Runner labels:

``` text
self-hosted
Windows
X64
```

Start the runner interactively with:

``` powershell
cd C:\actions-runner
.\run.cmd
```

A healthy runner displays:

``` text
Listening for Jobs
```

Docker Desktop was made available to the runner, allowing GitHub Actions
to execute deployments on the local Windows machine.

The deployment logic was moved into:

``` text
scripts/deploy.ps1
```

The script eventually supported both environments:

``` powershell
./scripts/deploy.ps1 `
  -Image <immutable-image-reference> `
  -Environment development
```

and:

``` powershell
./scripts/deploy.ps1 `
  -Image <immutable-image-reference> `
  -Environment production
```

Environment-specific container names were generated automatically:

``` text
development -> shipping-dev
production  -> shipping-prod
```

Rollback containers used:

``` text
shipping-dev-previous
shipping-prod-previous
```

## Safe Deployment Sequence

The deployment engine follows this order:

``` text
Pull candidate image
        |
        v
Remove stale backup
        |
        v
Stop current deployment
        |
        v
Rename current -> previous
        |
        v
Start candidate
        |
        v
Verify running state
        |
        v
Verify startup
        |
        v
Functional test
```

A particularly important design decision was:

> **Pull the candidate image before touching the running deployment.**

If the image cannot be pulled, the existing application remains
untouched.

## Startup Verification

Because this version of the application is a CLI application rather than
an HTTP service, health verification used application startup output.

The deployment waited for:

``` text
Shipping Calculator
```

rather than pretending that an HTTP `/health` endpoint existed.

## Functional Verification

The deployed container was tested with:

``` powershell
docker exec shipping-dev python -c "from app import calculate_shipping; assert calculate_shipping(7) == 100"
```

Production could be tested similarly:

``` powershell
docker exec shipping-prod python -c "from app import calculate_shipping; assert calculate_shipping(7) == 100"
```

## Rollback Testing

The deployment script supports:

``` powershell
-SimulateFailure
```

The simulated deployment deliberately starts a faulty candidate that
never produces the expected startup output.

The expected lifecycle is:

``` text
Healthy version
      |
      v
Preserve as previous
      |
      v
Start faulty candidate
      |
      v
Verification fails
      |
      v
Remove faulty candidate
      |
      v
Restore previous container
      |
      v
ROLLBACK COMPLETED
```

The lab verified that the original container ID was restored and that
the application remained functional after rollback.

------------------------------------------------------------------------

# Lab 4 - Development and Production Environments

GitHub Environments were created:

``` text
development
production
```

Development variables:

``` text
APP_ENV=development
APP_NAME=shipping-calculator
```

Production variables:

``` text
APP_ENV=production
APP_NAME=shipping-calculator
```

The workflows generate runtime files:

``` text
.env.dev
.env.prod
```

These files are not committed to Git.

The environment chain is:

``` text
GitHub Environment Variable
          |
          v
GitHub Actions Job
          |
          v
.env.dev / .env.prod
          |
          v
Docker --env-file
          |
          v
Running Container
```

Verification commands:

``` powershell
docker exec shipping-dev printenv APP_ENV
docker exec shipping-dev printenv APP_NAME

docker exec shipping-prod printenv APP_ENV
docker exec shipping-prod printenv APP_NAME
```

Expected result:

``` text
development
shipping-calculator

production
shipping-calculator
```

## Production Approval Gate

The `production` GitHub Environment was configured with a required
reviewer.

The deployment therefore pauses before production:

``` text
DEV successful
      |
      v
Production requested
      |
      v
WAITING FOR REVIEW
      |
      v
Human approval
      |
      v
Production deployment
```

This demonstrated that **automation does not require removing
governance**.

## Production Branch Restriction

The production environment was also restricted so that deployment is
permitted from `main`.

A temporary feature branch was used to verify that the environment
restriction prevented an unauthorized production deployment.

Temporary branch workflow:

``` powershell
git switch main
git switch -c test/prod-environment-restriction
git push -u origin test/prod-environment-restriction
```

Cleanup:

``` powershell
git switch main
git branch -D test/prod-environment-restriction
git push origin --delete test/prod-environment-restriction
```

This established two separate controls:

``` text
Branch restriction
    = Where a production deployment may originate

Required reviewer
    = Whether an allowed production deployment may proceed
```

------------------------------------------------------------------------

# Lab 5 - Automated Immutable Artifact Promotion

Initially, image promotion required manually copying the Docker digest.

The old process was:

``` text
Publish
   |
   v
Human copies digest
   |
   v
DEV

Human copies digest
   |
   v
PROD
```

Lab 5 removed the human artifact handoff.

The publish job exposes an output:

``` yaml
outputs:
  image: ${{ steps.image-ref.outputs.image }}
```

The immutable reference is captured using:

``` bash
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' $IMAGE:$TAG)

echo "image=$DIGEST" >> "$GITHUB_OUTPUT"
```

A downstream deployment can consume it with:

``` yaml
DEPLOY_IMAGE: ${{ needs.publish.outputs.image }}
```

The resulting pipeline became:

``` text
PUBLISH
   |
   | immutable @sha256 output
   v
DEV
   |
   | DEV must succeed
   v
PRODUCTION APPROVAL
   |
   v
PROD
```

The production job depends on both publishing and successful DEV
deployment:

``` yaml
needs:
  - publish
  - deploy-development
```

Production receives the image directly from the publisher:

``` yaml
DEPLOY_IMAGE: ${{ needs.publish.outputs.image }}
```

It does **not** rebuild the application and it does **not** create a
separate production artifact.

## PR Versus Main Behaviour

For Pull Requests:

``` text
Unit Tests                         PASS
Build and Validate                 PASS
Publish                            SKIPPED
DEV Deployment                     SKIPPED
PROD Deployment                    SKIPPED
```

Publishing is protected by:

``` yaml
if: github.event_name == 'push' && github.ref == 'refs/heads/main'
```

After merging to `main`:

``` text
Unit Tests                         PASS
Build and Validate                 PASS
Publish                            PASS
DEV Deployment                     PASS
Production Approval                WAIT
PROD Deployment                    PASS after approval
```

This creates a useful separation:

> **PRs validate changes. Merges to main publish and promote releases.**

------------------------------------------------------------------------

# Final Immutable Artifact Verification

The exact Docker image used by each running container can be inspected
with:

``` powershell
$devImage = docker inspect shipping-dev --format '{{.Image}}'
$prodImage = docker inspect shipping-prod --format '{{.Image}}'

Write-Host "DEV  image: $devImage"
Write-Host "PROD image: $prodImage"
```

Equality check:

``` powershell
if ($devImage -eq $prodImage) {
    Write-Host "PROMOTION VERIFIED: DEV and PROD use the same immutable image."
}
else {
    Write-Host "WARNING: DEV and PROD are using different images."
}
```

The final lab result was:

``` text
DEV  image: sha256:3d23ae328c02c1edd6c25304cc2ac7441d67abaac944ea0925277f0c986eeefd
PROD image: sha256:3d23ae328c02c1edd6c25304cc2ac7441d67abaac944ea0925277f0c986eeefd

PROMOTION VERIFIED: DEV and PROD use the same immutable image.
```

This proves:

``` text
             ONE IMMUTABLE ARTIFACT
                      |
             +--------+--------+
             |                 |
             v                 v
            DEV               PROD
      development config   production config
```

------------------------------------------------------------------------

# Useful Git Commands

Check repository state:

``` powershell
git status
```

Create a feature branch:

``` powershell
git switch -c feature/<name>
```

Stage and commit:

``` powershell
git add .
git commit -m "<message>"
```

Push branch:

``` powershell
git push -u origin feature/<name>
```

Return to main:

``` powershell
git switch main
```

Synchronize main:

``` powershell
git fetch origin
git merge --ff-only origin/main
```

Inspect changes:

``` powershell
git diff
git diff --check
git diff --stat
```

Delete a local branch:

``` powershell
git branch -D <branch>
```

Delete a remote branch:

``` powershell
git push origin --delete <branch>
```

------------------------------------------------------------------------

# Useful Docker Commands

List running containers:

``` powershell
docker ps
```

List all containers:

``` powershell
docker ps -a
```

Inspect a container:

``` powershell
docker inspect shipping-dev
```

Read logs:

``` powershell
docker logs shipping-dev
```

Read environment configuration:

``` powershell
docker exec shipping-dev printenv APP_ENV
```

Run application verification:

``` powershell
docker exec shipping-dev python -c "from app import calculate_shipping; assert calculate_shipping(7) == 100"
```

Inspect image identity:

``` powershell
docker inspect shipping-dev --format '{{.Image}}'
```

Remove a container:

``` powershell
docker rm -f <container-name>
```

Pull an immutable image:

``` powershell
docker pull ghcr.io/<owner>/<repository>/shipping-calculator@sha256:<digest>
```

------------------------------------------------------------------------

# PowerShell Lesson: `if` and `else`

When working interactively, the complete PowerShell statement must be
entered together:

``` powershell
if ($condition) {
    Write-Host "True"
}
else {
    Write-Host "False"
}
```

Entering the `if` block, executing it, and then entering `else`
separately causes:

``` text
else : The term 'else' is not recognized...
```

This is a PowerShell input issue and does not invalidate the result of
the already executed `if` block.

------------------------------------------------------------------------

# Important CI/CD Lessons

The project demonstrated several production-relevant principles.

**Build once.** Do not rebuild an application for each environment.

**Promote immutable artifacts.** Use a SHA-256 digest when artifact
identity matters.

**Separate application from configuration.** The same image can run in
DEV and PROD with different environment variables.

**Test before publishing.** Only a validated image should become the
release artifact.

**Verify after deployment.** A successfully started container does not
automatically mean the application is healthy.

**Design rollback before failure occurs.** Preserve a known-good version
and make restoration deterministic.

**Protect production outside the deployment script.** Approval gates and
deployment-source restrictions belong at the platform/environment
boundary.

**Fail safely.** Pull a candidate image before disrupting the currently
running application.

**PR validation and deployment are different concerns.** A Pull Request
can build and test without being allowed to publish or deploy.

------------------------------------------------------------------------

# Current Lab Limitations

This is intentionally a learning environment.

DEV and PROD are separate logical environments but currently run on the
same Docker Desktop host. They therefore do not provide true
infrastructure isolation.

The application is currently a CLI application rather than an HTTP
service, so startup-log and functional-command verification are used
instead of a real load-balancer health endpoint.

The self-hosted Windows runner is both an automation runner and closely
associated with the local deployment host. A cloud-native design should
separate CI/CD orchestration from the infrastructure that runs the
application.

These limitations form the starting point for the next phase.

------------------------------------------------------------------------

# Next Phase - AWS Cloud-Native CI/CD

The next project will rebuild these concepts using AWS-native
infrastructure.

Planned architecture:

``` text
GitHub
   |
   v
CI Tests
   |
   v
Docker Build
   |
   v
GitHub OIDC -> AWS
   |
   v
Amazon ECR
   |
   | immutable image
   v
Amazon ECS / Fargate DEV
   |
   v
Application Load Balancer Health Check
   |
   v
Production Approval
   |
   v
Amazon ECS / Fargate PROD
   |
   v
CloudWatch Logs
```

Terraform will provision the AWS infrastructure.

The AWS phase will introduce concepts such as:

-   Amazon ECR
-   Amazon ECS
-   AWS Fargate
-   Application Load Balancer
-   ECS task definitions and services
-   CloudWatch Logs
-   IAM roles
-   GitHub Actions OIDC federation
-   Terraform-managed infrastructure
-   Real HTTP health checks
-   Cloud-native deployment and rollback strategies

The goal is not to discard the lessons from this project, but to apply
the same CI/CD principles to real cloud infrastructure.

------------------------------------------------------------------------

## Project Status

**Labs 1-5 completed successfully.**

Final capabilities demonstrated:

``` text
CI                              COMPLETE
Docker build/test               COMPLETE
GHCR publishing                 COMPLETE
Build-once pipeline             COMPLETE
Self-hosted deployment          COMPLETE
DEV environment                 COMPLETE
PROD environment                COMPLETE
Environment configuration       COMPLETE
Startup verification            COMPLETE
Functional verification         COMPLETE
Rollback                        COMPLETE
Production approval             COMPLETE
Production branch restriction   COMPLETE
Immutable artifact promotion    COMPLETE
Automated DEV -> PROD flow      COMPLETE
```

Next milestone:

**AWS Cloud-Native CI/CD with Terraform, ECR, ECS/Fargate, ALB,
CloudWatch, GitHub Actions and OIDC.**
