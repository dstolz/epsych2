# digest.ps1 — render a GitHub issues JSON dump as a compact, model-facing digest.
#
# Called by fetch.sh; not meant to be run by hand. Windows PowerShell 5.1 compatible
# (no ternary, no ??, no -AsHashtable).
#
#   -IssuesJson   path to the array-of-issues JSON written by curl
#   -CommentsDir  directory holding comments-<N>.json files (optional)
#   -BodyLimit    max characters of issue body to print (0 = unlimited)
#   -Header       one-line banner describing the query
#   -ListTargets  print "<number> <comment count>" per issue and exit (planning pass)

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$IssuesJson,
    [string]$CommentsDir = '',
    [int]$BodyLimit = 4000,
    [string]$Header = 'issues',
    [switch]$ListTargets
)

$ErrorActionPreference = 'Stop'

# Returns a (possibly empty) array on success, $null only on a genuine failure.
# ConvertFrom-Json yields $null for an empty array, so "[]" is checked before parsing —
# otherwise "no issues matched" is indistinguishable from "the payload was garbage".
function Read-Json {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    # GitHub pretty-prints an empty array as "[\n\n]\n", so compare with all whitespace gone.
    if (($raw -replace '\s', '') -eq '[]') { return ,@() }
    try {
        $parsed = $raw | ConvertFrom-Json
    } catch {
        return $null
    }
    # Comma operator: returning a bare @() would unroll to $null at the call site,
    # which would read as a parse failure.
    if ($null -eq $parsed) { return ,@() }
    return $parsed
}

$issues = Read-Json -Path $IssuesJson
if ($null -eq $issues) {
    Write-Output 'ERROR: could not parse the issues payload.'
    exit 2
}

# A single-object response (detail mode) must still iterate as a list.
if ($issues -isnot [System.Array]) { $issues = @($issues) }

# The /issues endpoint returns pull requests too; they carry a pull_request key.
$issues = @($issues | Where-Object { $null -eq $_.pull_request })

if ($ListTargets) {
    foreach ($i in $issues) {
        if ($i.comments -gt 0) { Write-Output "$($i.number) $($i.comments)" }
    }
    exit 0
}

if ($issues.Count -eq 0) {
    Write-Output "NO_ISSUES"
    exit 3
}

function Get-Age {
    param([string]$Stamp)
    try {
        $d = [datetime]::Parse($Stamp, [Globalization.CultureInfo]::InvariantCulture)
        $days = [int]((Get-Date) - $d).TotalDays
        if ($days -eq 0) { return 'today' }
        if ($days -eq 1) { return '1 day ago' }
        return "$days days ago"
    } catch { return 'unknown' }
}

function Format-Body {
    param([string]$Text, [int]$Limit)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '  (no body)' }
    $t = $Text -replace "`r`n", "`n"
    $truncated = $false
    if ($Limit -gt 0 -and $t.Length -gt $Limit) {
        $t = $t.Substring(0, $Limit)
        $truncated = $true
    }
    $lines = $t -split "`n" | ForEach-Object { '  ' + $_ }
    $out = ($lines -join "`n")
    if ($truncated) { $out = $out + "`n  [... body truncated; re-run with --full for the rest ...]" }
    return $out
}

Write-Output "=== $Header ==="
Write-Output "$($issues.Count) issue(s). Pull requests excluded."
Write-Output ''

foreach ($i in $issues) {
    $labels = @($i.labels | ForEach-Object { $_.name })
    $labelStr = '(none)'
    if ($labels.Count -gt 0) { $labelStr = ($labels -join ', ') }

    $assignees = @($i.assignees | ForEach-Object { $_.login })
    $assigneeStr = '(unassigned)'
    if ($assignees.Count -gt 0) { $assigneeStr = ($assignees -join ', ') }

    $milestone = '(none)'
    if ($null -ne $i.milestone) { $milestone = $i.milestone.title }

    Write-Output ('-' * 78)
    Write-Output "#$($i.number)  $($i.title)"
    Write-Output ('-' * 78)
    Write-Output "state:     $($i.state)"
    Write-Output "author:    $($i.user.login)"
    Write-Output "opened:    $($i.created_at)  ($(Get-Age -Stamp $i.created_at))"
    Write-Output "updated:   $($i.updated_at)  ($(Get-Age -Stamp $i.updated_at))"
    Write-Output "labels:    $labelStr"
    Write-Output "assignee:  $assigneeStr"
    Write-Output "milestone: $milestone"
    Write-Output "comments:  $($i.comments)"
    Write-Output "url:       $($i.html_url)"
    Write-Output 'body:'
    Write-Output (Format-Body -Text $i.body -Limit $BodyLimit)

    if ($CommentsDir -ne '' -and $i.comments -gt 0) {
        $cpath = Join-Path $CommentsDir "comments-$($i.number).json"
        $comments = Read-Json -Path $cpath
        if ($null -ne $comments) {
            if ($comments -isnot [System.Array]) { $comments = @($comments) }
            Write-Output ''
            Write-Output "comments ($($comments.Count)):"
            foreach ($c in $comments) {
                Write-Output "  * $($c.user.login) on $($c.created_at):"
                Write-Output (Format-Body -Text $c.body -Limit 1500)
            }
        }
    }
    Write-Output ''
}

exit 0
