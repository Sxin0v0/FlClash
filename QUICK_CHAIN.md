# FlClash Quick Chain (unofficial Windows fork)

Based on chen08209/FlClash. Built independently of the official release.

## Quick multi-hop proxy
On the Proxies page, click the link icon. Select an entry, optional intermediate hops, an exit, and the selector group. Intermediate nodes appear in the order added. Selecting the empty option removes that hop. The configuration persists per profile without editing subscription files.

The entry may come from a proxy-provider. All intermediate hops and the exit need inline nodes in the profile's `proxies` array. Traffic must use the selected selector group; provider-only subscriptions with no inline exit are not supported.

## Existing IPv6 settings
Settings > General > Core > Add override > IPv6. The Android VPN IPv6 receive switch is separate: Settings > Network > VPN > IPv6.

## Existing Hysteria2 port hopping
The upstream node editor already supports `ports` and `hop-interval` on the relevant Hysteria protocols. The destination server must be configured to accept the matching ports. Chain overrides preserve these fields.

## Release channel
Windows builds use `--env stable` to remove the top-right DEV build banner. This does not imply the build is an official FlClash release. The Windows EXE is unsigned and may trigger Microsoft SmartScreen. Back up existing configuration first.

## Automatic upstream sync
The scheduled workflow `.github/workflows/sync-upstream-quick-chain.yml` lives on `main`, runs daily, and can be triggered manually. It merges upstream `main` into fork `main`, then fork `main` into `quick-chain`. Conflicts fail the workflow without dropping changes. Successful updates explicitly dispatch the Windows release workflow using GitHub's Actions API (automated GITHUB_TOKEN pushes do not trigger push workflows). Windows releases are uploaded only when generation, analysis, tests and packaging pass. Schedules may be delayed by GitHub.
