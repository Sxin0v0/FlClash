import 'package:fl_clash/models/clash_config.dart';

/// Configure an ordered dialer chain; subscriptions remain unchanged.
/// Never accept a silently unresolved node: the Core may otherwise start
/// with a valid-looking selector but without a usable outbound.
Map<String, dynamic> applyQuickChain(
  Map<String, dynamic> config,
  QuickChain chain,
) {
  if (!chain.enabled) return config;
  final path = [
    chain.entry.trim(),
    ...chain.hops.map((name) => name.trim()),
    chain.exit.trim(),
  ];
  if (path.length < 2 || path.any((name) => name.isEmpty) ||
      path.toSet().length != path.length) {
    throw const FormatException('链式代理节点不能缺失或重复');
  }
  final rawProxies = config['proxies'];
  if (rawProxies is! List) {
    throw const FormatException('当前订阅没有可用于链式代理的内联节点');
  }
  final nodeNames = <String>{
    for (final node in rawProxies)
      if (node is Map && node['name'] is String) node['name'] as String,
  };
  // A named provider node is only loaded after the core parses providers.
  // Do not claim it works as a dialer target when it cannot be resolved here.
  for (final name in path) {
    if (!nodeNames.contains(name)) {
      throw FormatException(
        '节点 $name 不在订阅 proxies 内联列表中。'
        '目前不能直接链式引用 proxy-providers 节点，请在订阅中提供内联节点。',
      );
    }
  }
  final links = <String, String>{
    for (var index = 1; index < path.length; index++)
      path[index]: path[index - 1],
  };
  final updated = [
    for (final node in rawProxies)
      if (node is Map && links.containsKey(node['name']))
        {...node.cast<String, dynamic>(), 'dialer-proxy': links[node['name']]}
      else
        node,
  ];
  final dialers = <String, String>{
    for (final node in updated)
      if (node is Map &&
          node['name'] is String &&
          node['dialer-proxy'] is String)
        node['name'] as String: node['dialer-proxy'] as String,
  };
  for (final origin in links.keys) {
    final visited = <String>{};
    var current = origin;
    while (dialers.containsKey(current)) {
      if (!visited.add(current)) {
        throw const FormatException('链式代理检测到 dialer-proxy 循环依赖');
      }
      current = dialers[current]!;
    }
  }
  return {...config, 'proxies': updated};
}
