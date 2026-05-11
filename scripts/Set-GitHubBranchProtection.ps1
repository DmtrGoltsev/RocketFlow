param(
    [string]$Owner = "DmtrGoltsev",
    [string]$Repo = "RocketFlow",
    [string]$Branch = "master",
    [string]$Token = $env:GITHUB_TOKEN,
    [string[]]$RequiredChecks = @("backend-verify", "web-verify", "android-verify"),
    [switch]$RequirePullRequest,
    [switch]$EnforceAdmins,
    [string]$ApiVersion = "2022-11-28"
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host "[github-branch-protection] $Message"
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    throw "Set GITHUB_TOKEN or pass -Token. The token must have repository administration permission."
}

if ($RequiredChecks.Count -eq 0) {
    throw "At least one required check is required."
}

$uri = "https://api.github.com/repos/$Owner/$Repo/branches/$Branch/protection"
$headers = @{
    Authorization          = "Bearer $Token"
    Accept                 = "application/vnd.github+json"
    "X-GitHub-Api-Version" = $ApiVersion
    "User-Agent"           = "RocketFlow-CI-CD-Setup"
}

$pullRequestReviews = $null
if ($RequirePullRequest) {
    $pullRequestReviews = @{
        dismiss_stale_reviews           = $true
        require_code_owner_reviews      = $false
        required_approving_review_count = 1
        require_last_push_approval      = $false
    }
}

$body = @{
    required_status_checks        = @{
        strict   = $true
        contexts = $RequiredChecks
    }
    enforce_admins                = [bool]$EnforceAdmins
    required_pull_request_reviews = $pullRequestReviews
    restrictions                  = $null
    required_linear_history       = $false
    allow_force_pushes            = $false
    allow_deletions               = $false
    block_creations               = $false
    required_conversation_resolution = $true
    lock_branch                   = $false
    allow_fork_syncing            = $true
} | ConvertTo-Json -Depth 10

Write-Step "Applying branch protection to $Owner/$Repo branch $Branch."
Write-Step "Required checks: $($RequiredChecks -join ', ')"

Invoke-RestMethod `
    -Method Put `
    -Uri $uri `
    -Headers $headers `
    -ContentType "application/json" `
    -Body $body | Out-Null

Write-Step "Branch protection applied."
