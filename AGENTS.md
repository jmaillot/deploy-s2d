# Project: S2DCluster

Windows PowerShell 5.1, S2D on Windows Server 2025 (FR-FR locale). Pester 5 unit tests + GitHub Actions CI.
Layout: `Deploy-S2D/` is the shippable module (loader `.psm1` dot-sources
`Private/` then `Public/`, one function per file, explicit `FunctionsToExport`,
`en-US/` about help). `Scripts/` holds thin forwarders (`Import-Module` + splat),
the reboot runbook, canned examples, and the vendored helper. Legacy files live
in `archive/`.

## Commands
- Syntax check (Windows): `pwsh -NoProfile -Command "[void][System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw '<file>'), [ref]$null)"`
- Lint: `Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1` (fix all Errors before merge; scope scans to active code, not `archive/`)
- Test: `Invoke-Pester -Path ./Tests` (Pester 5; CI runs this + analyzer errors on push/PR)
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
- Display text inside functions must use `Write-Host`/`Write-Verbose`, never bare
  strings — bare output is captured into the caller's assignment (it once
  silently joined a return value instead of displaying).
- Wrap CIM-module cmdlets with exotic parameter types (e.g. `Get-PhysicalDisk`)
  in thin private helpers — Pester cannot generate mocks for them directly.
- Explicit `-ErrorAction Stop` on load-bearing lookups (`Get-StoragePool`, `Get-Cluster`);
- No environment-specific defaults in shared code (`HV1`, `Ethernet N`, lab UNC paths).
  Identity values (names, IPs, cluster) are `[Parameter(Mandatory)]` with no default —
  the engine prompts when missing, which also keeps automation safe. Only technical
  tuning keeps defaults (`StoragePrefix 24`, reserve `20%`). Conditionally required
  values get boundary `throw`s. Exception: NIC discovery in `Start-S2DNodePrep` may
  prompt via console `Select-S2DNic` (numbered menu with help text, reprompts on
  invalid input, `Q` aborts, non-interactive throws) — allowed because NIC names
  are discoverable local state, and supplied values skip the picker entirely so
  automation is unaffected.
  `-SilentlyContinue` only with a comment explaining why failure is safe.
- No `$script:` globals for parameter passing — use function params / splatting.
- No `Invoke-Expression`, no `$global:` scope, no positional arguments in calls.
- No backtick line continuations — use splatting or natural line breaks.
- Comment-based help required on every public function and script:
  `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` (each parameter), `.EXAMPLE` (copy-pasteable).
- `[OutputType()]` on all public functions.
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
- Don't touch `archive/` or `Scripts/Clear-PhysicalDiskHealthData.ps1` (vendored) without explicit approval.
- Keep standalone scripts thin — logic goes in the `.psm1`, not duplicated in `.ps1`.
- Verify with the repo's own checks (parser + ScriptAnalyzer) before declaring done.
