# Project: S2DCluster

Windows PowerShell 5.1, S2D on Windows Server 2025 (FR-FR locale). No tests, no CI.
Layout: `Deploy-S2D.psd1/.psm1` is the module (loader dot-sources `Private/` then
`Public/`, one function per file, explicit `FunctionsToExport`). `Private/Write-S2DLog.ps1`
owns logging (`Write-S2DLog`; the `Write-Log` name collides with a PS Core built-in). Public: `Start-S2DNodePrep` (per-node), `New-S2DCluster` (once),
`Start-S2DDeployment` (back-compat wrapper). `Invoke-*.ps1` / `New-*.ps1` are thin
forwarders (`Import-Module` + splat). Legacy files live in `archive/`.

## Commands
- Syntax check (Windows): `pwsh -NoProfile -Command "[void][System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw '<file>'), [ref]$null)"`
- Lint: `Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1` (fix all Errors before merge; scope scans to active code, not `archive/`)
- Dry run: every destructive script must support `-WhatIf`; verify with `-WhatIf` first
- Encoding: save `.ps1`/`.psm1`/`.psd1` with UTF-8 BOM whenever they contain non-ASCII
  (French strings like `Réseau` silently garble on Windows PowerShell 5.1 without it)
- 5.1-parity: only `CmdletBinding`/`OutputType` attributes on functions
  (`SuppressMessageAttribute` fails to import on 5.1 — fix the finding or exclude it
  in `PSScriptAnalyzerSettings.psd1` instead). Validate every change with
  `Import-Module` on the 5.1 host, not just lint.

## PowerShell conventions (enforce on every change)
- `[CmdletBinding(SupportsShouldProcess=$true)]` on anything that changes system state;
  guard with `if ($PSCmdlet.ShouldProcess(...))`. No bare `exit` in library code — `throw`.
- No aliases in committed code (`?`, `%`, `select` banned); full cmdlet names only.
- ASCII hyphens only for parameters. Never paste en/em dashes (`–`, `—` break parsing).
- Explicit `-ErrorAction Stop` on load-bearing lookups (`Get-StoragePool`, `Get-Cluster`);
  `-SilentlyContinue` only with a comment explaining why failure is safe.
- No `$script:` globals for parameter passing — use function params / splatting.
- Secrets (`AzStorageKey`) as `SecureString`, never `Write-Host`/`Write-Log` them.
- FR-first, EN-fallback for locale-dependent `Test-Cluster -Include` names
  (`Espaces de stockage direct...` then `Storage Spaces Direct...`).
- UNC paths always `\\server\share`. Validate non-empty IPs before `Remove-/New-NetIPAddress`;
  scope removals with `-InterfaceAlias`.
- Idempotency: `if (-not (Get-...)) { New-... }` for cluster, vSwitch, volumes.
- Single resume in maintenance flows (`Resume-ClusterNode -Failback Immediate` once,
  after resync jobs complete). Wait loops filter on active `JobState`, with timeout + Failed abort.

## Boundaries
- Never `Set-ExecutionPolicy Unrestricted`; use `RemoteSigned` + signed module.
- Don't touch `archive/` or `Clear-PhysicalDiskHealthData.ps1` (vendored) without explicit approval.
- Keep standalone scripts thin — logic goes in the `.psm1`, not duplicated in `.ps1`.
- Verify with the repo's own checks (parser + ScriptAnalyzer) before declaring done.
