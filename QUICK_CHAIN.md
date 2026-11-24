# FlClash Quick Chain (unofficial Windows fork)

Based on chen08209/FlClash. Built independently of the official release.

## Quick multi-hop proxy
On the Proxies page, click the link icon. Select an entry, optional intermediate hops, an exit, and the selector group. Intermediate nodes appear in the order added. Selecting the empty option removes that hop. The configuration persists per profile without editing subscription files.

For reliability, all chain nodes (including the entry) must currently be inline in the profile's `proxies` array. Provider-backed nodes are visible but not addable until provider support can be verified. Traffic must use the selected selector group; provider-only subscriptions with no inline exit are not supported.

## Existing IPv6 settings
Settings > General > Core > Add override > IPv6. The Android VPN IPv6 receive switch is separate: Settings > Network > VPN > IPv6.

## Existing Hysteria2 port hopping
The upstream node editor already supports `ports` and `hop-interval` on the relevant Hysteria protocols. The destination server must be configured to accept the matching ports. Chain overrides preserve these fields.

## Release channel
Windows builds use `--env stable` to remove the top-right DEV build banner. This does not imply the build is an official FlClash release. The Windows EXE is unsigned and may trigger Microsoft SmartScreen. Back up existing configuration first.

## Automatic upstream sync
The scheduled workflow `.github/workflows/sync-upstream-quick-chain.yml` lives on `main`, runs daily, and can be triggered manually. It merges upstream `main` into fork `main`, then fork `main` into `quick-chain`. Conflicts fail the workflow without dropping changes. Successful updates explicitly dispatch the Windows release workflow using GitHub's Actions API (automated GITHUB_TOKEN pushes do not trigger push workflows). Windows releases are uploaded only when generation, analysis, tests and packaging pass. Schedules may be delayed by GitHub.

## Chain-mode UX and connection protection

The proxy page now opens an inline two-pane chain workspace instead of a narrow nested sheet. The native window size is never changed. The page divides into equal-width proxy and chain panes, and each pane reflows independently. Click proxy cards in order to append hops; drag the chain list to reorder; delete individual hops; click Connect to apply and probe the chain's final outbound. On a setup, selector-change or delay-test failure, the app attempts to restore the previous profile override and selection. A passing outbound probe is a limited connectivity check, not proof that all sites or UDP protocols work.

## Chain UI theme and reorder behavior

The entry and exit are shown in the ordered node list, not repeated in the settings section. The settings section contains only the enable switch and the selector group. Sorting uses upstream `SliverPrismReorderableList`, `SortHandle` and `commonProxyDecorator` for its lifted surface, scale animation and theme-aware foreground/background. This avoids the default Flutter Material drag overlay (which can render an inconsistent light rectangle in dark mode) and the nested shrink-wrapped reorder list. Both light and dark colors derive from the active Prism theme. Build success and widget visual QA remain distinct from real-device visual testing.
