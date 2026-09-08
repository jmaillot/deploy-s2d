# S2DCluster

Deploys a 2-node Storage Spaces Direct (S2D) cluster on Windows Server 2025:
per-node network/storage prep, then one-shot cluster creation with quorum,
S2D enablement, and a mirrored CSV volume. Includes a safe-reboot runbook and a
disk-health repair helper. PowerShell 5.1, FR/EN locales supported.

## Requirements

- 2x Windows Server 2025 (Datacenter), Failover-Clustering + Hyper-V roles, **run elevated**
- **10 GbE or faster RDMA-capable adapters are mandatory for the storage fabric**
  (`StorageA`/`StorageB`: jumbo MTU 9014, QoS/DCB + RDMA are configured by NodePrep;
  below 10 GbE, S2D resync/repair traffic will saturate the link — unsupported setup)
- 1x witness: file share (`\\server\share$`) or Azure Cloud Witness (account + key)
- 1x static cluster IP; per-node static storage IPs
- NIC plan per node: N management + M VM + StorageA + StorageB + LiveMig (see below)

## Order of operations

```
1. Copy the folder to EACH node, run Invoke-S2DNodePrep.ps1 locally on each
2. From ONE node, run New-S2DCluster.ps1 once
3. Validate: Get-VirtualDisk / Get-StorageJob / Failover Cluster Manager
```

Always dry-run first (`-WhatIf`). Never run NodePrep from a workstation —
it renames the *local* NICs.

## Scripts

### 1. `Invoke-S2DNodePrep.ps1` — per node, run locally on each

Preflight first: `StorageA/B` and `LiveMig` must be **10 Gbps+ and RDMA-capable** —
anything slower (e.g. 1G) or non-RDMA throws before anything is changed. Then it
renames NICs (`StorageA/B`, `LiveMig`, `MgmtN`, `VMN`), sets jumbo MTU + static
storage IPs, QoS/DCB + RDMA, builds `vSwitch-VM` (SET team for 2+ VM NICs, plain
vSwitch for 1), disables VMQ/RSC, sets live migration to SMB.

```powershell
.\Invoke-S2DNodePrep.ps1 -MgmtAdapters "Mgmt01","Mgmt02" -VMAdapters "Vm01","Vm02" `
  -StorageA "Storage01" -StorageB "Storage02" -LiveMigrationAdapter "Live01" `
  -StorageAIP "192.168.200.1" -StorageBIP "192.168.201.1"
```

| Parameter | Required | Notes |
|---|---|---|
| `MgmtAdapters`, `VMAdapters` | no — picker if omitted | Any count (1+). Pass a comma list, or pick in the console menu. Already-picked NICs are hidden; one NIC can't serve two roles |
| `StorageA/B`, `LiveMigrationAdapter` | no — picker if omitted | Exactly **2 storage adapters** (one becomes StorageA, one StorageB — the two fabrics) and exactly **1 LiveMigration adapter**. One console menu per role |
| `StorageAIP/BIP` | yes | This node's storage IPs (differ per node); must parse, must differ, must sit on **different subnets** (multipath) |
| `StoragePrefix` | no | Default `24` (range 1–31) |
| `LiveMigrationIP/Prefix` | no | Optional. If supplied, LiveMig gets the IP and is bound as *the* migration network (`Set-VMHost`); if omitted you get a warning and migration traffic stays unbound |
| `LogPath` | no | Default `C:\S2D_Deployment.log` |

Preflight runs before anything changes (reads only, so it also runs under
`-WhatIf`): ≥4 physical NICs, 10 Gbps+ link + proven RDMA on Storage/LiveMig
(missing SMB binding info falls back to adapter RDMA settings — unproven RDMA
throws), poolable disks present (`CanPool`, i.e. PERC must be HBA/pass-through,
not RAID), all-HDD warns (no cache tier), plus a driver table and a BIOS
virtualization check (both advisory). Requires elevation. Renames are verified
after the fact — a collision from a prior partial run throws loudly instead of
misconfiguring. QoS cleanup touches only our `SMBDirect` policy.

Omit NIC names to get guided picking: one numbered console menu per role, each
stating the role your pick **will be renamed to** (`1/5` = StorageA, `2/5` =
StorageB, `3/5` = LiveMig, `4/5` = MGMT, `5/5` = VM) with invalid input
reprompting instead of failing. For MGMT/VM enter comma numbers (`0,2`); blank
means none. `Q` aborts. Console-native (works on Server Core, help stays
visible) — no popup. Example with only Mgmt/VM omitted: 2 menus appear, the
rest use your values.

### 2. `New-S2DCluster.ps1` — once, from one node

Validates (`Test-Cluster`, FR-first/EN-fallback), creates the cluster, sets quorum,
enables S2D, creates the mirrored CSV (ReFS), constrains SMB Multichannel to
StorageA/B, renames cluster networks.

```powershell
.\New-S2DCluster.ps1 -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" `
  -ClusterIP "192.168.1.240" -WitnessType "FileShare" `
  -FileShareWitness "\\NTSVR22.intra-pdl.fr\ClusterPDL$" `
  -VolumeName "CSV_S2D" -SizingMode "Auto"
```

| Parameter | Required | Notes |
|---|---|---|
| `ClusterName`, `ClusterNodes`, `ClusterIP` | yes | Nodes accept any count |
| `WitnessType` | no | `FileShare` (default) or `Cloud` |
| `FileShareWitness` | FileShare only | UNC path; throws if missing |
| `AzStorageAccount/Key` | Cloud only | Throw if missing |
| `SizingMode` | no | `Auto` (default, keeps `CapacityReservePercent`, default 20%; `-UseFullPool` skips reserve) or `Fixed` (requires `-VolumeSize`, e.g. `2TB`) |

### 3. `Reboot-S2D.ps1` — safe reboot of one node

Guided 10-step runbook: health check → drain → storage maintenance → reboot →
exit maintenance → resync wait (timeout, default 120 min) → resume with failback.
Run from a *different* node; resumes at step 7 if the node already rebooted.

```powershell
.\Reboot-S2D.ps1 -NodeName "HV1"                     # interactive
.\Reboot-S2D.ps1 -NodeName "HV1" -Force -WhatIf      # dry-run, no prompts
```

### 4. `Clear-PhysicalDiskHealthData.ps1` — vendored, use as-is

Don MacGregor's Health Service flag resetter (Intent/Policy via `healthapi.dll`).
Do not modify without approval.

```powershell
Get-PhysicalDisk -UniqueId <id> | Clear-PhysicalDiskHealthData -Intent -Force
```

### Module + canned examples

- `Deploy-S2D.psd1/.psm1` (v1.3.0): `Start-S2DNodePrep`, `New-S2DCluster`,
  `Start-S2DDeployment` (back-compat wrapper). `Public/` = one function per file,
  `Private/Write-S2DLog.ps1` = logging.
- `DeployCmd-1-NodePrep.ps1` / `DeployCmd-2-Cluster.ps1`: copy-paste examples
  with lab values. `archive/` holds retired files.

## Design notes (why)

- **Storage takes exactly 2 adapters by design** — one NIC renamed to StorageA,
  one to StorageB (the two fabrics the QoS/RDMA/SMB-constraint code is written
  for). Extra NICs belong in the MGMT/VM pools. Teamed/multi-NIC-per-fabric
  storage would be a different design.
- **LiveMigration takes exactly 1 adapter by design.** One LiveMig network per
  host is the supported topology (Hyper-V fails over to other networks if it
  drops). Multi-NIC live migration would be a different design — open an issue
  if you need it.
- **No environment defaults in shared code.** Names/IPs are `Mandatory` (the
  engine prompts when missing); only technical tuning has defaults. Values live
  in the `DeployCmd-*` examples. This is why a custom question-menu was rejected:
  `Mandatory` already prompts interactively *and* stays automation-safe.
- **Idempotent where it matters**: cluster, vSwitch, and volume steps guard with
  `Get-` before `New-`; maintenance resume happens exactly once, after resync.
- **Every destructive path supports `-WhatIf`**; lint gate is
  `Invoke-ScriptAnalyzer -Settings .\PSScriptAnalyzerSettings.psd1` (see `AGENTS.md`).
