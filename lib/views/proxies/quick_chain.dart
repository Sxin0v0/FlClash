import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class QuickChainSheet extends ConsumerStatefulWidget {
  const QuickChainSheet({super.key, required this.profileId});

  final int profileId;

  @override
  ConsumerState<QuickChainSheet> createState() => _QuickChainSheetState();
}

class _QuickChainSheetState extends ConsumerState<QuickChainSheet> {
  String? _entry;
  String? _exit;
  String? _group;
  bool _enabled = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final stored =
        ref.read(profileProvider(widget.profileId))?.overrides.quickChain;
    _entry = stored?.entry.isNotEmpty == true ? stored!.entry : null;
    _exit = stored?.exit.isNotEmpty == true ? stored!.exit : null;
    _group = stored?.group.isNotEmpty == true ? stored!.group : null;
    _enabled = stored?.enabled ?? false;
  }

  Future<void> _save() async {
    if (_saving) return;
    final profile = ref.read(profileProvider(widget.profileId));
    if (profile == null ||
        profile.type == ProfileType.custom ||
        ref.read(currentProfileIdProvider) != widget.profileId) {
      return;
    }
    final entry = _entry;
    final exit = _exit;
    final group = _group;
    final enabled = _enabled;
    if (enabled &&
        (entry == null ||
            exit == null ||
            entry == exit ||
            group == null)) {
      return;
    }
    setState(() => _saving = true);
    ref.read(profilesProvider.notifier).updateProfile(profile.id, (state) {
      final selection = Map<String, String>.from(state.selectedMap);
      final oldChain = state.overrides.quickChain;
      var previousSelection = oldChain.previousSelection;
      final changedExit = oldChain.group != group || oldChain.exit != exit;
      if (oldChain.enabled &&
          (changedExit || !enabled) &&
          selection[oldChain.group] == oldChain.exit) {
        if (previousSelection.isEmpty) {
          selection.remove(oldChain.group);
        } else {
          selection[oldChain.group] = previousSelection;
        }
      }
      if (enabled) {
        if (!oldChain.enabled || oldChain.group != group) {
          previousSelection = selection[group!] ?? '';
        }
        selection[group!] = exit!;
      }
      return state.copyWith(
        selectedMap: selection,
        overrides: state.overrides.copyWith(
          quickChain: QuickChain(
            enabled: enabled,
            entry: entry ?? '',
            exit: exit ?? '',
            group: group ?? '',
            previousSelection: previousSelection,
          ),
        ),
      );
    });

    bool applied;
    try {
      applied = await ref.read(setupActionProvider.notifier).applyProfile(
        force: true,
      );
    } catch (_) {
      applied = false;
    }
    if (!applied) {
      ref.read(profilesProvider.notifier).updateProfile(profile.id, (state) {
        return state.copyWith(
          selectedMap: profile.selectedMap,
          overrides: state.overrides.copyWith(
            quickChain: profile.overrides.quickChain,
          ),
        );
      });
      try {
        await ref.read(setupActionProvider.notifier).applyProfile(force: true);
      } catch (_) {
        // The original settings remain saved for the next app start.
      }
      if (mounted) {
        setState(() => _saving = false);
        dialogs.showBanner(
          '链式代理应用失败，已恢复上一配置',
          level: BannerLevel.error,
        );
      }
      return;
    }

    if (!mounted) return;
    final oldChain = profile.overrides.quickChain;
    final restoreGroup = oldChain.group;
    final restoreName =
        ref.read(profileProvider(profile.id))?.selectedMap[restoreGroup];
    final changeGroup = enabled ? group : restoreGroup;
    final changeName = enabled ? exit : restoreName;
    if (changeGroup != null &&
        changeGroup.isNotEmpty &&
        changeName != null &&
        changeName.isNotEmpty) {
      try {
        await ref.read(proxiesActionProvider.notifier).changeProxy(
          groupName: changeGroup,
          proxyName: changeName,
        );
      } catch (_) {
        if (mounted) {
          setState(() => _saving = false);
          dialogs.showBanner(
            '链式配置已保存，但策略组切换失败',
            level: BannerLevel.warning,
          );
        }
        return;
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider(widget.profileId));
    final groups = ref.watch(groupsProvider);
    final nodeNames = <String>{};
    final exitNames = <String>{};
    for (final group in groups) {
      for (final node in group.all) {
        if (GroupTypeExtension.getGroupType(node.type) != null ||
            reservedCustomProxyNames.contains(node.name)) {
          continue;
        }
        nodeNames.add(node.name);
        if (node.providerName == null) exitNames.add(node.name);
      }
    }
    final entries = nodeNames.toList()..sort();
    final exits = exitNames.toList()..sort();
    final eligibleGroups = [
      for (final group in groups)
        if (group.type == GroupType.Selector &&
            group.all.any((node) => node.name == _exit))
          group.name,
    ];
    final valid = !_enabled ||
        (_entry != null &&
            _exit != null &&
            _entry != _exit &&
            entries.contains(_entry) &&
            exits.contains(_exit) &&
            eligibleGroups.contains(_group));
    final saved = profile?.overrides.quickChain;
    final summary = saved?.enabled == true
        ? '已配置: ' + saved!.entry + ' → ' + saved.exit
        : '未启用';

    return Scaffold(
      title: '快捷链式代理',
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          context.contentTopPadding,
          16,
          24 + context.bottomInset,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              summary,
              style: AppTextStyle.subheadline.of(context),
            ),
          ),
          generateSection(
            items: [
              ListItem.toggle(
                title: const Text('启用链式代理'),
                value: _enabled,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _enabled = value),
              ),
              ListItem<String?>.options(
                title: const Text('入口节点（前置）'),
                options: <String?>[null, ...entries],
                value: entries.contains(_entry) ? _entry : null,
                textBuilder: (name) => name ?? '请选择',
                onChanged: (name) => setState(() => _entry = name),
              ),
              ListItem<String?>.options(
                title: const Text('出口节点（落地）'),
                options: <String?>[null, ...exits],
                value: exits.contains(_exit) ? _exit : null,
                textBuilder: (name) => name ?? '请选择',
                onChanged: (name) => setState(() {
                  _exit = name;
                  _group = null;
                }),
              ),
              ListItem<String?>.options(
                title: const Text('应用到策略组'),
                options: <String?>[null, ...eligibleGroups],
                value: eligibleGroups.contains(_group) ? _group : null,
                textBuilder: (name) => name ?? '请选择',
                onChanged: (name) => setState(() => _group = name),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '连接路径: Windows → 入口 → 出口 → 目标网站',
            style: AppTextStyle.footnote.of(context),
          ),
          const SizedBox(height: 8),
          Text(
            '规则模式仅影响命中所选策略组的连接。出口仅支持订阅中 proxies 直接声明的节点；proxy-providers 提供的节点暂不支持作出口。',
            style: AppTextStyle.footnote.of(context),
          ),
          const SizedBox(height: 20),
          TonalButton(
            glyph: AppGlyphs.link,
            label: _saving ? '正在应用...' : '保存并应用',
            onPressed: !_saving && valid ? _save : null,
          ),
        ],
      ),
    );
  }
}
