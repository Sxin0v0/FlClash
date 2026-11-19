import 'package:fl_clash/models/clash_config.dart';

/// Applies a dialer without editing the user's subscription file.
Map<String, dynamic> applyQuickChain(
  Map<String, dynamic> config,
  QuickChain chain,
) {
  if (!chain.enabled) return config;

  final entry = chain.entry.trim();
  final exit = chain.exit.trim();
  if (entry.isEmpty || exit.isEmpty || entry == exit) {
    throw const FormatException('Quick chain requires two different nodes.');
  }
  final rawProxies = config['proxies'];
  if (rawProxies is! List) {
    throw const FormatException('Quick chain exit is not in inline proxies.');
  }
  final exitExists = rawProxies.any(
    (node) => node is Map && node['name'] == exit,
  );
  if (!exitExists) {
    throw FormatException('Quick chain exit not found: $exit');
  }
  final updatedProxies = [
    for (final node in rawProxies)
      if (node is Map && node['name'] == exit)
        {...node.cast<String, dynamic>(), 'dialer-proxy': entry}
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
  final visited = <String>{};
  var current = exit;
  while (dialers.containsKey(current)) {
    if (!visited.add(current)) {
      throw const FormatException('Quick chain creates a dialer loop.');
    }
    current = dialers[current]!;
  }
  return {...config, 'proxies': updatedProxies};
}
