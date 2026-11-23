import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart' show Material, MaterialType, ReorderableListView;
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
  String? _browseGroup;
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

  void _reorder(int from, int to) {
    if (_busy) return;
    setState(() {
      if (to > from) to--;
      _route.insert(to, _route.removeAt(from));
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

  Widget _chainPane(List<Group> groups, bool connected) {
    final eligible = _eligibleGroups(groups);
    final picked = eligible.contains(_group) ? _group : eligible.firstOrNull;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text('代理链配置',
                style: AppTextStyle.title2.of(context))),
            TonalButton(label: '退出模式',
                onPressed: _busy ? null : widget.onClose),
          ]),
          const SizedBox(height: 10),
          Text('点击左侧节点逐个添加；按右侧拖动柄调整顺序。',
              style: AppTextStyle.footnote.of(context)),
          const SizedBox(height: 10),
          if (_route.isEmpty)
            const Padding(
              padding: EdgeInsets.all(22),
              child: Text('请从左侧依次点击入口、下一跳、出口。'),
            ),
          if (_route.isNotEmpty)
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                child: ReorderableListView.builder(
                  itemCount: _route.length,
                  onReorder: _reorder,
                  itemBuilder: (context, i) {
                    final name = _route[i];
                    final role = i == 0 ? '入口' :
                        (i == _route.length - 1 ? '出口' : '中继');
                    return Card(
                      key: ValueKey('chain-step-$name'),
                      radius: AppCorner.lg,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      child: Row(children: [
                        SizedBox(width: 40, child: Text(role,
                            style: AppTextStyle.footnote.of(context))),
                        Expanded(child: EmojiText(name,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.subheadline.of(context))),
                        IconButton(
                          tooltip: '移除 $name',
                          onPressed: _busy ? null : () =>
                              setState(() => _route.removeAt(i)),
                          icon: const GlyphIcon(AppGlyphs.delete),
                        ),
                        const SizedBox(width: 40),
                      ]),
                    );
                  },
                ),
              ),
            ),
          if (_route.isEmpty) const Spacer(),
          if (_route.isNotEmpty) Text(
            '连接顺序：${_route.join(' → ')}',
            style: AppTextStyle.footnote.of(context),
          ),
          const SizedBox(height: 10),
          if (eligible.isNotEmpty)
            ListItem<String?>.options(
              title: const Text('应用到策略组'),
              options: <String?>[null, ...eligible],
              value: picked,
              textBuilder: (value) => value ?? '请选择',
              onChanged: (value) => setState(() => _group = value),
            ),
          if (_message != null) Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Text(_message!, style: AppTextStyle.footnote.of(context)),
          ),
          const SizedBox(height: 10),
          TonalButton(
            glyph: AppGlyphs.link,
            label: _busy ? '正在验证…' :
                (connected ? '更新链路并验证' : '连接并验证'),
            onPressed: _busy || _route.length < 2 || picked == null
                ? null : _connect,
          ),
          if (connected) ...[
            const SizedBox(height: 8),
            TonalButton(
              glyph: AppGlyphs.link,
              label: '断开链式代理',
              onPressed: _busy ? null : _disconnect,
            ),
          ],
          const SizedBox(height: 8),
          TonalButton(
            glyph: AppGlyphs.delete,
            label: '清空链路',
            onPressed: _busy ? null : () => setState(() => _route.clear()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider(widget.profileId));
    final groups = ref.watch(groupsProvider);
    final connected = profile?.overrides.quickChain.enabled == true;
    // Keep the original proxy grid and group cards at their original sizes.
    // This pane *covers* the right half, like the existing groups in list mode.
    // The original cards receive chain taps instead of selecting a proxy.
    return LayoutBuilder(
      builder: (context, size) {
        final panelWidth = size.maxWidth >= 760
            ? size.maxWidth * 0.51
            : size.maxWidth * 0.80;
        return Stack(
          children: [
            Positioned.fill(
              child: widget.style == ProxiesType.tab
                  ? ProxiesTabView(onChainNodeTap: _append)
                  : ProxiesListView(onChainNodeTap: _append),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: panelWidth,
              child: ColoredBox(
                color: context.colorScheme.surface,
                child: _chainPane(groups, connected),
              ),
            ),
          ],
        );
      },
    );
  }
}
