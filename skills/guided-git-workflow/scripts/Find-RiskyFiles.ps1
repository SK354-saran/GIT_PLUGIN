<#
.SYNOPSIS
  Flag changed or untracked files that look like secrets or are too large for GitHub.
  Read-only. Run from inside the repository. Prints one JSON object.

.DESCRIPTION
  Looks at every path reported by 'git status' (staged, modified, untracked; ignored
  files are skipped because git does not report them). For each existing file it checks:
    - file name patterns (.env, *.pem, id_rsa, credentials.json, ...)
    - size: warning above -WarnSizeMB (default 50), blocked above 100 MB (GitHub hard limit)
    - content of text files up to 1 MB for common token formats

  The output never contains the matched secret value, only the path and the reason.

  Output: { repoRoot, scanned, findings: [ { path, severity: high|medium, reasons: [] } ], error }
#>
param(
    [int]$WarnSizeMB = 50
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

function Write-Result($obj) { ConvertTo-Json -InputObject $obj -Depth 5 }

# Windows PowerShell 5.1 turns native stderr into an error record; with 'Stop' that throws.
$ErrorActionPreference = 'Continue'
$root = (& git rev-parse --show-toplevel 2>$null)
$gitExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($gitExit -ne 0 -or -not $root) {
    Write-Result ([ordered]@{ repoRoot = $null; scanned = 0; findings = @(); error = 'Not inside a git repository.' })
    exit 1
}
$root = ($root | Select-Object -First 1).Trim()

# NUL-separated output keeps paths with spaces, quotes, or non-ASCII characters intact.
$raw = (& git -c core.quotepath=false status --porcelain=v1 -z --untracked-files=all) -join "`n"
$entries = $raw -split "`0"

$paths = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $entries.Length; $i++) {
    $e = $entries[$i].TrimStart("`n")
    if ($e.Length -lt 4) { continue }
    $xy = $e.Substring(0, 2)
    $paths.Add($e.Substring(3))
    if ($xy[0] -eq 'R' -or $xy[0] -eq 'C') { $i++ }   # skip the original path of a rename/copy
}

$namePatterns = @(
    @{ re = '(^|/)\.env$';                                    why = 'Environment file (.env) usually holds secrets' },
    @{ re = '(^|/)\.env\.(?!example$|sample$|template$|dist$)[^/]+$'; why = 'Environment file (.env.*) usually holds secrets' },
    @{ re = '\.(pem|key|p12|pfx|jks|keystore|ppk|asc|gpg)$'; why = 'Private key or certificate store' },
    @{ re = '(^|/)id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$';      why = 'SSH key file' },
    @{ re = '(^|/)(credentials|client_secret[^/]*|service[-_]?account[^/]*)\.json$'; why = 'Cloud credentials file' },
    @{ re = '(^|/)(\.npmrc|\.pypirc|\.netrc|_netrc|\.git-credentials)$'; why = 'Tool config that often stores tokens' },
    @{ re = '(^|/)secrets?\.(json|ya?ml|toml|ini|txt)$';     why = 'File named secrets' },
    @{ re = '\.tfstate(\.backup)?$';                          why = 'Terraform state can contain secrets' },
    @{ re = '(^|/)\.aws/credentials$';                        why = 'AWS credentials file' }
)

$contentPatterns = @(
    @{ re = 'AKIA[0-9A-Z]{16}';                               why = 'Looks like an AWS access key ID' },
    @{ re = 'gh[pousr]_[A-Za-z0-9]{36,}';                     why = 'Looks like a GitHub token' },
    @{ re = 'github_pat_[A-Za-z0-9_]{40,}';                   why = 'Looks like a GitHub fine-grained token' },
    @{ re = '-----BEGIN [A-Z ]*PRIVATE KEY-----';             why = 'Contains a private key block' },
    @{ re = 'xox[abprs]-[A-Za-z0-9-]{10,}';                   why = 'Looks like a Slack token' },
    @{ re = 'sk-[A-Za-z0-9_-]{32,}';                          why = 'Looks like an API secret key (sk-...)' },
    @{ re = 'AIza[0-9A-Za-z_-]{35}';                          why = 'Looks like a Google API key' },
    @{ re = '(?i)(api[_-]?key|secret|passw(or)?d|access[_-]?token)["'']?\s*[:=]\s*["''][^"''\s]{8,}["'']'; why = 'Hard-coded secret-like assignment' }
)

$findings = New-Object System.Collections.Generic.List[object]
$scanned = 0

foreach ($p in ($paths | Sort-Object -Unique)) {
    $full = Join-Path $root $p
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }   # deleted, or a directory
    $scanned++
    $reasons  = New-Object System.Collections.Generic.List[string]
    $severity = 'medium'
    $norm = $p -replace '\\', '/'

    foreach ($np in $namePatterns) {
        if ($norm -match $np.re) { $reasons.Add($np.why); $severity = 'high' }
    }

    $size = (Get-Item -LiteralPath $full).Length
    $mb = [math]::Round($size / 1MB, 1)
    if ($size -gt 100MB) {
        $reasons.Add("File is $mb MB; GitHub rejects files over 100 MB"); $severity = 'high'
    }
    elseif ($size -gt ($WarnSizeMB * 1MB)) {
        $reasons.Add("File is $mb MB; GitHub warns above 50 MB. Consider Git LFS")
    }

    if ($size -gt 0 -and $size -le 1MB) {
        $bytes = [System.IO.File]::ReadAllBytes($full)
        if ([Array]::IndexOf($bytes, [byte]0) -lt 0) {          # skip binary files
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            foreach ($cp in $contentPatterns) {
                if ($text -cmatch $cp.re) { $reasons.Add($cp.why); $severity = 'high' }
            }
        }
    }

    if ($reasons.Count -gt 0) {
        $findings.Add([ordered]@{ path = $norm; severity = $severity; reasons = [string[]]$reasons.ToArray() })
    }
}

Write-Result ([ordered]@{
    repoRoot = $root
    scanned  = $scanned
    findings = [object[]]$findings.ToArray()
    error    = $null
})
exit 0
