<#
.SYNOPSIS
  PreToolUse hook: ask the user in the IDE before any 'git commit' or 'git push' runs.

.DESCRIPTION
  Kiro passes the tool call as JSON on stdin. This script looks for a shell command
  string in that JSON and, if it runs 'git commit' or 'git push', prints a
  permissionDecision "ask" so the IDE shows a confirmation prompt. Any other command
  passes through silently. The script never blocks on its own (always exit 0), so a
  parsing problem cannot lock the user out of the shell tool.

  Hook command:
    powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\git-confirm-gate.ps1"
#>
$ErrorActionPreference = 'SilentlyContinue'

$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }

# Collect every string value under keys that usually hold the command text.
$commands = New-Object System.Collections.Generic.List[string]
function Get-CommandStrings($node) {
    if ($null -eq $node) { return }
    if ($node -is [System.Management.Automation.PSCustomObject]) {
        foreach ($prop in $node.PSObject.Properties) {
            if ($prop.Value -is [string] -and $prop.Name -match '^(command|cmd|script)$') {
                $commands.Add($prop.Value)
            }
            else { Get-CommandStrings $prop.Value }
        }
    }
    elseif ($node -is [System.Collections.IEnumerable] -and -not ($node -is [string])) {
        foreach ($item in $node) { Get-CommandStrings $item }
    }
}

$parsed = $null
try { $parsed = $raw | ConvertFrom-Json } catch { $parsed = $null }
if ($null -ne $parsed) { Get-CommandStrings $parsed }
if ($commands.Count -eq 0) { $commands.Add($raw) }   # unknown shape: scan the raw text

# git [global options] commit|push   (global options like -C <path>, -c k=v, --no-pager)
$pattern = '(?i)\bgit(\.exe)?["'']?(\s+(-C\s+("[^"]*"|''[^'']*''|\S+)|-c\s+\S+|--[a-z-]+(=\S+)?))*\s+(?<verb>commit|push)\b'

$verbs = @()
foreach ($c in $commands) {
    foreach ($m in [regex]::Matches($c, $pattern)) { $verbs += $m.Groups['verb'].Value.ToLowerInvariant() }
}
if ($verbs.Count -eq 0) { exit 0 }

$verbs = $verbs | Sort-Object -Unique
$isTrunkPush = $false
foreach ($c in $commands) {
    if ($c -match '(?i)\bgit\b.*\bpush\b.*(\s|:)(main|master|develop)(\s|$|"|'')') { $isTrunkPush = $true }
}

$reason = "This command runs git $($verbs -join ' and '). Confirm that the guided workflow step was approved."
if ($isTrunkPush) { $reason = "This command pushes to a trunk branch (main/master/develop). Confirm you want to push there." }

$decision = @{
    hookSpecificOutput = @{
        permissionDecision       = 'ask'
        permissionDecisionReason = $reason
    }
}
ConvertTo-Json -InputObject $decision -Depth 3 -Compress
exit 0
