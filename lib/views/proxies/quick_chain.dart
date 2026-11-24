import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'list.dart';
import 'tab.dart';

class QuickChainWorkspace extends ConsumerStatefulWidget {
  const QuickChainWorkspace({super.key, required this.profileId, required this.style, required this.onClose});
  final int profileId;
  final ProxiesType style;
  final VoidCallback onClose;
  @override
  ConsumerState<QuickChainWorkspace> createState() => _QuickChainWorkspaceState();
}

class _QuickChainWorkspaceState extends ConsumerState<QuickChainWorkspace> {
  List<String> _route = [];
  String? _group;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final old = ref.read(profileProvider(widget.profileId))?.overrides.quickChain;
    if (old != null && old.entry.isNotEmpty && old.exit.isNotEmpty) {
      _route = [old.entry, ...old.hops, old.exit];
      _group = old.group;
    }
  }

  bool _allowed(Proxy node) =>
      GroupTypeExtension.getGroupType(node.type) == null &&
      !reservedCustomProxyNames.contains(node.name);

  void _append(Proxy node) {
    if (_busy || !_allowed(node)) return;
    setState(() {
      if (node.providerName != null) {
        _message = '暂不支持 proxy-providers 节点参与链式代理；请选择订阅内联节点';
      } else if (_route.contains(node.name)) {
        _message = '节点已经在链路中；在右侧拖动排序或移除';
      } else if (_route.length >= 8) {
        _message = '最多支持八跳';
      } else {
        _route.add(node.name);
        _message = null;
      }
    });
  }

  // SliverPrismReorderableList.onReorderItem supplies the already
  // adjusted destination index. Do not subtract one again.
  void _reorder(int from, int to) {
    if (_busy ||
        from == to ||
        from < 0 ||
        to < 0 ||
        from >= _route.length ||
        to >= _route.length) {
      return;
    }
    setState(() {
      final node = _route.removeAt(from);
      _route.insert(to, node);
      _message = null;
    });
  }

  void _restore(Profile previous) {
    ref.read(profilesProvider.notifier).updateProfile(previous.id, (state) =>
        state.copyWith(
          selectedMap: previous.selectedMap,
          overrides: state.overrides.copyWith(quickChain: previous.overrides.quickChain),
        ));
  }

  Future<void> _rollback(Profile previous, String reason) async {
    _restore(previous);
    try {
      await ref.read(setupActionProvider.notifier).applyProfile(force: true);
      final chain = previous.overrides.quickChain;
      final group = chain.group;
      final selected = previous.selectedMap[group];
      if (group.isNotEmpty && selected != null && selected.isNotEmpty) {
        await ref.read(coreHandlerProvider).changeProxy(
          ChangeProxyParams(groupName: group, proxyName: selected));
      }
    } catch (error) {
      reason = '$reason；恢复原配置时发生错误：$error';
    }
    if (mounted) {
      setState(() { _busy = false; _message = reason; });
      dialogs.showBanner(reason, level: BannerLevel.error);
    }
  }

  List<String> _eligibleGroups(List<Group> groups) {
    if (_route.isEmpty) return [];
    final exit = _route.last;
    return [
      for (final group in groups)
        if (group.type == GroupType.Selector &&
            group.all.any((node) => node.name == exit))
          group.name,
    ];
  }

  Future<void> _connect() async {
    if (_busy || _route.length < 2) return;
    final before = ref.read(profileProvider(widget.profileId));
    if (before == null ||
        ref.read(currentProfileIdProvider) != widget.profileId) return;
    final groups = _eligibleGroups(ref.read(groupsProvider));
    final target = groups.contains(_group) ? _group : groups.firstOrNull;
    if (target == null) {
      setState(() => _message = '没有包含出口节点的 Selector 策略组');
      return;
    }
    setState(() { _busy = true; _group = target; _message = '正在应用并检测出口连通性…'; });
    final previous = before.overrides.quickChain;
    final selected = Map<String, String>.from(before.selectedMap);
    var oldSelection = selected[target] ?? '';
    if (previous.enabled) {
      if (previous.group == target) {
        oldSelection = previous.previousSelection;
      } else if (previous.group.isNotEmpty) {
        if (previous.previousSelection.isEmpty) {
          selected.remove(previous.group);
        } else {
          selected[previous.group] = previous.previousSelection;
        }
      }
    }
    final exit = _route.last;
    selected[target] = exit;
    final chain = QuickChain(
      enabled: true,
      entry: _route.first,
      hops: _route.length > 2 ? _route.sublist(1, _route.length - 1) : const [],
      exit: exit,
      group: target,
      previousSelection: oldSelection,
    );
    ref.read(profilesProvider.notifier).updateProfile(before.id, (state) =>
        state.copyWith(
          selectedMap: selected,
          overrides: state.overrides.copyWith(quickChain: chain),
        ));
    try {
      if (!await ref.read(setupActionProvider.notifier).applyProfile(force: true)) {
        throw StateError('内核没有接受链式代理配置');
      }
      // Verify the LIVE Mihomo configuration, not just the UI flag.
      // Before this check the missing profile-overrides propagation made a
      // perfectly healthy single-hop exit appear to be a successful chain.
      for (var index = 1; index < _route.length; index++) {
        final hop = _route[index];
        final preceding = _route[index - 1];
        final runtime = await ref.read(coreHandlerProvider)
            .getProxyDefinition(hop);
        if (runtime?['dialer-proxy'] != preceding) {
          throw StateError(
            '内核配置未生效：$hop 的 dialer-proxy 应为 $preceding，'
            '实际为 ${runtime?['dialer-proxy']}',
          );
        }
      }
      final changed = await ref.read(coreHandlerProvider).changeProxy(
        ChangeProxyParams(groupName: target, proxyName: exit));
      if (changed.message.isNotEmpty) throw StateError(changed.message);
      final testUrl = ref.read(patchClashConfigProvider).testUrl;
      final probe = await ref.read(coreHandlerProvider).testDelay(
        TestDelayParams(proxyName: exit, testUrl: testUrl, timeout: 10000));
      if (probe.value == null || probe.value! <= 0) {
        throw StateError('链路出口测试超时，节点可能不支持链式拨号');
      }
      if (mounted) setState(() {
        _busy = false;
        _message = '链路连接成功：${probe.value} ms';
      });
    } catch (error) {
      await _rollback(before, '链式代理失败，已回滚：$error');
    }
  }

  Future<void> _disconnect() async {
    if (_busy) return;
    final before = ref.read(profileProvider(widget.profileId));
    if (before == null || !before.overrides.quickChain.enabled) return;
    final old = before.overrides.quickChain;
    setState(() { _busy = true; _message = '正在恢复原始节点…'; });
    final selected = Map<String, String>.from(before.selectedMap);
    if (old.group.isNotEmpty && selected[old.group] == old.exit) {
      if (old.previousSelection.isEmpty) {
        selected.remove(old.group);
      } else {
        selected[old.group] = old.previousSelection;
      }
    }
    ref.read(profilesProvider.notifier).updateProfile(before.id, (state) =>
        state.copyWith(
          selectedMap: selected,
          overrides: state.overrides.copyWith(
            quickChain: old.copyWith(enabled: false),
          ),
        ));
    try {
      if (!await ref.read(setupActionProvider.notifier).applyProfile(force: true)) {
        throw StateError('恢复普通配置失败');
      }
      if (old.group.isNotEmpty && old.previousSelection.isNotEmpty) {
        final result = await ref.read(coreHandlerProvider).changeProxy(
          ChangeProxyParams(groupName: old.group, proxyName: old.previousSelection));
        if (result.message.isNotEmpty) throw StateError(result.message);
      }
      if (mounted) setState(() { _busy = false; _message = '链式代理已断开'; });
    } catch (error) {
      await _rollback(before, '断开链式代理失败：$error');
    }
  }

  /// Build an individual, keyed Prism card for the reorderable sliver.
  /// The upstream sort handle and lift decorator follow light/dark themes
  /// without the white Material overlay drawn by ReorderableListView.
  Widget _chainNode(int index) {
    final name = _route[index];
    final role = index == 0
        ? '入口'
        : index == _route.length - 1
            ? '出口'
            : '中继';

    return ReorderDragStartListener(
      key: ValueKey('chain-step-$name'),
      index: index,
      enabled: !_busy,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          radius: AppCorner.lg,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: [
              // Includes the app's native focus, keyboard and theme colors.
              SortHandle(index: index),
              SizedBox(
                width: 38,
                child: Text(
                  role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.footnote.of(context),
                ),
              ),
              Expanded(
                child: EmojiText(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.subheadline.of(context),
                ),
              ),
              IconButton(
                tooltip: '移除 $name',
                onPressed: _busy
                    ? null
                    : () => setState(() => _route.removeAt(index)),
                icon: const GlyphIcon(AppGlyphs.delete),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chainPane(List<Group> groups, bool connected) {
    final eligible = _eligibleGroups(groups);
    final picked = eligible.contains(_group) ? _group : eligible.firstOrNull;
    final canConnect = _route.length >= 2 && picked != null && !_busy;
    final path = _route.join(' → ');

    // One viewport for header, reorderable nodes and footer. Avoid a
    // shrink-wrapped nested ReorderableListView, whose layout and default
    // Material drag proxy made short-window drags janky and discolored.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            context.contentTopPadding + 12,
            16,
            20 + context.bottomInset,
          ),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: '退出链式代理模式',
                          onPressed: _busy ? null : widget.onClose,
                          icon: const GlyphIcon(AppGlyphs.close),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '快捷链式代理',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.title2.of(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      connected ? '链式代理已启用' : '点击左侧节点按顺序添加',
                      style: AppTextStyle.subheadline.of(context),
                    ),
                    const SizedBox(height: 18),
                    generateSection(
                      items: [
                        ListItem.toggle(
                          title: const Text('启用链式代理'),
                          value: connected,
                          onChanged: _busy || (!connected && !canConnect)
                              ? null
                              : (enabled) {
                                  if (enabled) {
                                    _connect();
                                  } else {
                                    _disconnect();
                                  }
                                },
                        ),
                        if (eligible.isNotEmpty)
                          ListItem<String?>.options(
                            title: const Text('应用到策略组'),
                            options: <String?>[null, ...eligible],
                            value: picked,
                            textBuilder: (name) => name ?? '请选择',
                            onChanged: (name) => setState(() => _group = name),
                          )
                        else
                          const ListItem(
                            title: Text('应用到策略组'),
                            subtitle: Text('尚未找到包含出口的策略组'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '点击左侧节点继续添加；拖动排序图标可调整顺序。',
                      style: AppTextStyle.footnote.of(context),
                    ),
                    const SizedBox(height: 10),
                    if (_route.isEmpty)
                      generateSection(
                        items: [
                          const ListItem(
                            title: Text('尚未添加节点'),
                            subtitle: Text('先选入口、再选出口；也可继续增加中继。'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (_route.isNotEmpty)
                SliverPrismReorderableList(
                  itemCount: _route.length,
                  itemBuilder: (_, index) => _chainNode(index),
                  // Same lift, scale and surface animation as upstream.
                  // The transparent Prism surface never introduces a white
                  // Material background in either theme.
                  proxyDecorator: (child, index, animation) =>
                      commonProxyDecorator(
                    _chainNode(index),
                    index,
                    animation,
                  ),
                  onReorderItem: _reorder,
                ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_route.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        '连接路径：Windows → $path → 目标网站',
                        style: AppTextStyle.footnote.of(context),
                      ),
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _message!,
                        style: AppTextStyle.footnote.of(context),
                      ),
                    ],
                    const SizedBox(height: 20),
                    TonalButton(
                      glyph: AppGlyphs.link,
                      label: _busy
                          ? '正在验证连接…'
                          : connected
                              ? '更新链路并验证'
                              : '连接并验证',
                      onPressed: canConnect ? _connect : null,
                    ),
                    if (connected) ...[
                      const SizedBox(height: 10),
                      TonalButton(
                        glyph: AppGlyphs.link,
                        label: '断开链式代理',
                        onPressed: _busy ? null : _disconnect,
                      ),
                    ],
                    const SizedBox(height: 10),
                    TonalButton(
                      glyph: AppGlyphs.delete,
                      label: '清空待编辑链路',
                      onPressed: _busy || _route.isEmpty
                          ? null
                          : () => setState(() => _route.clear()),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '规则模式仅影响所选策略组的连接，节点需要来自订阅 proxies 内联列表。',
                      style: AppTextStyle.footnote.of(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider(widget.profileId));
    final groups = ref.watch(groupsProvider);
    final connected = profile?.overrides.quickChain.enabled == true;
    // Both panes receive exactly half the available width.
    // No resizing of the native Windows window.
    return Row(
      children: [
        Expanded(
          child: widget.style == ProxiesType.tab
              ? ProxiesTabView(onChainNodeTap: _append)
              : ProxiesListView(onChainNodeTap: _append),
        ),
        Expanded(
          child: ColoredBox(
            color: context.colorScheme.surface,
            child: _chainPane(groups, connected),
          ),
        ),
      ],
    );
  }
}
