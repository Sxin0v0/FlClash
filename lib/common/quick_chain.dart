import 'package:fl_clash/models/clash_config.dart';

/// Builds a dialer route without changing the imported subscription.
/// The first hop may be a provider node; subsequent hops must be inline.
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
  if (path.any((name) => name.isEmpty) ||
      path.toSet().length != path.length) {
    throw const FormatException('Quick chain requires distinct named nodes.');
  }
  final rawProxies = config['proxies'];
  if (rawProxies is! List) {
    throw const FormatException('Quick chain requires inline proxies.');
  }
  final inlineNames = <String>{
    for (final node in rawProxies)
      if (node is Map && node['name'] is String) node['name'] as String,
  };
  for (final name in path.skip(1)) {
    if (!inlineNames.contains(name)) {
      throw FormatException('Quick chain node is not inline: $name');
    }
  }
  final links = <String, String>{
    for (var index = 1; index < path.length; index++)
      path[index]: path[index - 1],
  };
  final updatedProxies = [
    for (final node in rawProxies)
      if (node is Map && links.containsKey(node['name']))
        {...node.cast<String, dynamic>(), 'dialer-proxy': links[node['name']]}
      else
        node,
  ];
  final dialers = <String, String>{
    for (final node in updatedProxies)
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
        throw const FormatException('Quick chain creates a dialer loop.');
      }
      current = dialers[current]!;
    }
  }
  return {...config, 'proxies': updatedProxies};
}
