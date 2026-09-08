# Changelog

## [Unreleased]
### Added
- LiveMig: jumbo MTU, EEE off, DNS registration + NetBIOS off (same hygiene
  as storage); DNS/NetBIOS off also on StorageA/B
- Mgmt: EEE off (best-effort across vendor property names)

## [1.6.0] - 2026-09-08
### Changed
- `AzStorageKey` is `SecureString` end to end (function, forwarder, wrapper);
  decrypted only for the quorum call, cleared after, never logged
- Thin forwarders accept `-WhatIf` via `SupportsShouldProcess`

## [1.5.0] - 2026-09-08
### Added
- Post-rename verification (loud collision error instead of misconfiguration)
- 10 Gbps + RDMA preflight on storage/LiveMig, with SMB-binding fallback probe
- Dell preflight: poolable-disk (`CanPool`) throw, all-HDD warning, NIC driver
  table and BIOS virtualization check (advisory)
- Optional `-LiveMigrationIP` binds the migration network (`Add-VMMigrationNetwork`)
- `-LogPath` on deploy functions; `ConfirmImpact = High`
### Changed
- QoS cleanup touches only the `SMBDirect` policy (no more nuke-all)
- IP inputs validated (parse, A≠B, different subnets, prefix range 1–31)
- `Enable-NetAdapterRdma` by `-Name`; dropped bogus `Set-VMSwitch -EnableSoftwareRsc`

## [1.4.0] - 2026-09-08
### Added
- Console NIC picker (`Select-S2DNic`): per-role menus, exclusion, validation
- Dynamic vSwitch: SET team for 2+ VM NICs, plain vSwitch for 1

## [1.3.0] - 2026-09-08
### Changed
- **Breaking:** identity params are `Mandatory` with no environment defaults;
  engine prompts when missing. Values live in `DeployCmd-*` examples

## [1.2.0] - 2026-09-08
### Added
- Standard module layout (`Public/` + `Private/`, loader `.psm1`, manifest)

## [1.1.0] - 2026-09-08
### Added
- Split `Start-S2DDeployment` into `Start-S2DNodePrep` (per node) and
  `New-S2DCluster` (once); FR→EN `Test-Cluster` fallback
### Fixed
- En-dash parameters, `Select-Objectv` typo, `$ClusterName.Name` null pool,
  single-backslash UNC default
