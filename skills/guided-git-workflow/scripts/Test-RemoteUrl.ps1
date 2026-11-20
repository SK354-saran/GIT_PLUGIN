<#
.SYNOPSIS
  Validate a Git remote URL before 'git remote add'. Read-only. Prints one JSON object.

.DESCRIPTION
  Accepts:
    https://github.com/<owner>/<repo>[.git][/]
    git@github.com:<owner>/<repo>[.git]
    ssh://git@github.com/<owner>/<repo>[.git]
  Rejects URLs that carry credentials (https://user:token@...), http:// URLs,
  and anything that is not a plain URL. Non-GitHub hosts are accepted with a warning.

  Output fields:
    valid, protocol (https|ssh), host, owner, repo,
    remoteUrl  canonical URL to pass to 'git remote add' (keeps the user's protocol)
    webUrl     https://<host>/<owner>/<repo>, base for the pull request link
    errors, warnings

.EXAMPLE
  Test-RemoteUrl.ps1 -Url "https://github.com/octocat/hello-world.git"
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Url
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$errors   = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$u = $Url.Trim()

$protocol = $null; $hostName = $null; $owner = $null; $repo = $null

# Never echo credentials back: redact userinfo in the output copy.
$display = $u -replace '^(https?://)[^/@\s]+@', '$1***@'

if ($u -match '\s') {
    $errors.Add('URL must not contain spaces.')
}
elseif ($u -match '^https?://[^/@]+@') {
    $errors.Add('URL contains a username or token before the host. Remove it; Git Credential Manager handles sign-in. Revoke the token if it was a real one.')
}
elseif ($u -match '^http://') {
    $errors.Add('Use https:// instead of http://.')
}
elseif ($u -match '^https://(?<host>[A-Za-z0-9.-]+)/(?<owner>[^/]+)/(?<repo>[^/]+?)(\.git)?/?$') {
    $protocol = 'https'; $hostName = $Matches['host']; $owner = $Matches['owner']; $repo = $Matches['repo']
}
elseif ($u -match '^git@(?<host>[A-Za-z0-9.-]+):(?<owner>[^/]+)/(?<repo>[^/]+?)(\.git)?$') {
    $protocol = 'ssh'; $hostName = $Matches['host']; $owner = $Matches['owner']; $repo = $Matches['repo']
}
elseif ($u -match '^ssh://git@(?<host>[A-Za-z0-9.-]+)(:\d+)?/(?<owner>[^/]+)/(?<repo>[^/]+?)(\.git)?/?$') {
    $protocol = 'ssh'; $hostName = $Matches['host']; $owner = $Matches['owner']; $repo = $Matches['repo']
}
else {
    $errors.Add('Not a recognized repository URL. Expected https://github.com/<owner>/<repo>.git or git@github.com:<owner>/<repo>.git')
    if ($u -match '^https://github\.com/[^/]+/?$') {
        $errors.Add('This looks like a user or organization page, not a repository. Add the repository name.')
    }
    if ($u -match '^https://github\.com/[^/]+/[^/]+/(tree|blob|pulls|issues)(/|$)') {
        $errors.Add('This is a page inside the repository. Use only https://github.com/<owner>/<repo>.')
    }
}

if ($null -ne $owner) {
    if ($hostName -ine 'github.com') {
        $warnings.Add("Host is '$hostName', not github.com. Continue only if that is intended.")
    }
    if ($hostName -ieq 'github.com') {
        if ($owner -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$') {
            $errors.Add("Owner '$owner' is not a valid GitHub user or organization name.")
        }
        if ($repo -notmatch '^[A-Za-z0-9._-]{1,100}$' -or $repo -eq '.' -or $repo -eq '..') {
            $errors.Add("Repository name '$repo' is not valid on GitHub.")
        }
    }
}

$remoteUrl = $null; $webUrl = $null
if ($errors.Count -eq 0 -and $null -ne $owner) {
    $webUrl = "https://$hostName/$owner/$repo"
    if ($protocol -eq 'https') { $remoteUrl = "$webUrl.git" }
    else                       { $remoteUrl = "git@${hostName}:$owner/$repo.git" }
}

$result = [ordered]@{
    input     = $display
    valid     = ($errors.Count -eq 0)
    protocol  = $protocol
    host      = $hostName
    owner     = $owner
    repo      = $repo
    remoteUrl = $remoteUrl
    webUrl    = $webUrl
    errors    = [string[]]$errors.ToArray()
    warnings  = [string[]]$warnings.ToArray()
}
ConvertTo-Json -InputObject $result -Depth 3
if ($result.valid) { exit 0 } else { exit 1 }
