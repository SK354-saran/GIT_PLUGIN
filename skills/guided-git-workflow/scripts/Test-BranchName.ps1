<#
.SYNOPSIS
  Validate or build a branch name that follows Conventional Branch 1.1.0.

.DESCRIPTION
  Read-only. Prints one JSON object.

  Validate:  Test-BranchName.ps1 -Name "feature/add-login-page"
  Build:     Test-BranchName.ps1 -Type feature -Description "Add login page (PROJ-123)"

  Output fields:
    name      the name that was checked (built from Type + Description in build mode)
    valid     true if the name matches the Conventional Branch grammar and git accepts it
    isTrunk   true for main / master / develop
    type      the prefix type, or null
    errors    list of reasons the name is invalid
    warnings  non-blocking notes (for example, a long description)
#>
[CmdletBinding(DefaultParameterSetName = 'Validate')]
param(
    [Parameter(ParameterSetName = 'Validate', Mandatory = $true, Position = 0)]
    [string]$Name,

    [Parameter(ParameterSetName = 'Build', Mandatory = $true)]
    [ValidateSet('feature', 'feat', 'bugfix', 'fix', 'hotfix', 'release', 'chore',
                 'ai', 'copilot', 'cursor', 'claude', 'codex')]
    [string]$Type,

    [Parameter(ParameterSetName = 'Build', Mandatory = $true)]
    [string]$Description,

    [Parameter(ParameterSetName = 'Build')]
    [ValidateRange(10, 100)]
    [int]$MaxDescriptionLength = 50
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Types  = @('feature', 'feat', 'bugfix', 'fix', 'hotfix', 'release', 'chore',
            'ai', 'copilot', 'cursor', 'claude', 'codex')
$Trunks = @('main', 'master', 'develop')
$DescPattern = '^[a-z0-9]+(\.[a-z0-9]+)*(-[a-z0-9]+(\.[a-z0-9]+)*)*$'

function ConvertTo-BranchDescription {
    param([string]$Text, [int]$MaxLength)
    $s = $Text.ToLowerInvariant()
    $s = $s -replace '[^a-z0-9.]+', '-'     # anything else becomes a hyphen
    $s = $s -replace '\.{2,}', '.'          # no consecutive dots
    $s = $s -replace '-*\.-*', '.'          # no hyphen next to a dot
    $s = $s -replace '-{2,}', '-'           # no consecutive hyphens
    $s = $s.Trim('-', '.')
    if ($s.Length -gt $MaxLength) {
        $cut = $s.Substring(0, $MaxLength)
        $lastHyphen = $cut.LastIndexOf('-')
        if ($lastHyphen -gt 0) { $cut = $cut.Substring(0, $lastHyphen) }
        $s = $cut.Trim('-', '.')
    }
    return $s
}

if ($PSCmdlet.ParameterSetName -eq 'Build') {
    $desc = ConvertTo-BranchDescription -Text $Description -MaxLength $MaxDescriptionLength
    $Name = "$Type/$desc"
}

$errors   = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$isTrunk  = $Trunks -ccontains $Name
$branchType     = $null

if (-not $isTrunk) {
    if ($Name -cnotmatch '/') {
        $errors.Add("Missing '<type>/' prefix. Use one of: $($Types -join ', '). Trunk names allowed without prefix: $($Trunks -join ', ').")
    }
    else {
        $slash = $Name.IndexOf('/')
        $branchType  = $Name.Substring(0, $slash)
        $desc  = $Name.Substring($slash + 1)

        if ($Types -cnotcontains $branchType) {
            if ($Types -contains $branchType) {
                $errors.Add("Type '$branchType' must be lowercase.")
            }
            else {
                $errors.Add("Unknown type '$branchType'. Allowed: $($Types -join ', '). Docs/test/ci/refactor work goes under 'chore/'.")
            }
        }

        if ($desc.Length -eq 0)         { $errors.Add('Description after the slash is empty.') }
        elseif ($desc -cnotmatch $DescPattern) {
            if ($desc -cmatch '[A-Z]')        { $errors.Add('Uppercase letters are not allowed.') }
            if ($desc -match '\s')            { $errors.Add('Spaces are not allowed; use hyphens.') }
            if ($desc -match '_')             { $errors.Add('Underscores are not allowed; use hyphens.') }
            if ($desc -match '/')             { $errors.Add('Only one slash is allowed (between type and description).') }
            if ($desc -match '[^A-Za-z0-9.\-_/\s]') { $errors.Add('Special characters are not allowed; use only a-z, 0-9, hyphen, dot.') }
            if ($desc -match '--')            { $errors.Add('Consecutive hyphens are not allowed.') }
            if ($desc -match '\.\.')          { $errors.Add('Consecutive dots are not allowed.') }
            if ($desc -match '-\.|\.-')       { $errors.Add('A hyphen next to a dot is not allowed.') }
            if ($desc -match '^[-.]')         { $errors.Add('Description must not start with a hyphen or dot.') }
            if ($desc -match '[-.]$')         { $errors.Add('Description must not end with a hyphen or dot.') }
            if ($errors.Count -eq 0)          { $errors.Add('Description does not match the Conventional Branch grammar.') }
        }

        if ($desc.Length -gt 50) {
            $warnings.Add("Description is $($desc.Length) characters; consider 50 or fewer.")
        }
        if ($branchType -ceq 'release' -and $desc -cnotmatch '^v?\d') {
            $warnings.Add("Release branches usually start with a version, for example 'release/v1.2.0'.")
        }
    }
}

# Extra safety: ask git itself, if available.
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git -and $errors.Count -eq 0) {
    $ErrorActionPreference = 'Continue'   # PS 5.1 treats native stderr as an error record
    & git check-ref-format --branch $Name *> $null
    $refExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($refExit -ne 0) { $errors.Add('git check-ref-format rejected this name.') }
}

$result = [ordered]@{
    name     = $Name
    valid    = ($errors.Count -eq 0)
    isTrunk  = $isTrunk
    type     = $branchType
    errors   = [string[]]$errors.ToArray()
    warnings = [string[]]$warnings.ToArray()
}
ConvertTo-Json -InputObject $result -Depth 3
if ($result.valid) { exit 0 } else { exit 1 }
