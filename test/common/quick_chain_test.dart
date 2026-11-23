import 'dart:convert';

import 'package:fl_clash/common/quick_chain.dart';
import 'package:fl_clash/models/clash_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = <String, dynamic>{
    'proxies': [
      {'name': 'HK', 'type': 'socks5', 'server': 'hk.example', 'port': 1080},
      {'name': 'US', 'type': 'socks5', 'server': 'us.example', 'port': 1080},
    ],
  };

  test('enables entry to exit without mutating the subscription', () {
    final output = applyQuickChain(
      source,
      const QuickChain(enabled: true, entry: 'HK', exit: 'US'),
    );
    final nodes = output['proxies'] as List;
    expect((nodes[1] as Map)['dialer-proxy'], 'HK');
    expect(((source['proxies'] as List)[1] as Map)['dialer-proxy'], isNull);
  });

  test('preserves Hysteria2 port hopping when applying a chain', () {
    final config = <String, dynamic>{
      'proxies': [
        {'name': 'HK', 'type': 'socks5'},
        {
          'name': 'HY2',
          'type': 'hysteria2',
          'ports': '20000-20010',
          'hop-interval': '30s',
        },
      ],
    };
    final output = applyQuickChain(
      config,
      const QuickChain(enabled: true, entry: 'HK', exit: 'HY2'),
    );
    final node = (output['proxies'] as List)[1] as Map;
    expect(node['dialer-proxy'], 'HK');
    expect(node['ports'], '20000-20010');
    expect(node['hop-interval'], '30s');
  });

  test('rejects provider-only entry to avoid silent network failure', () {
    expect(
      () => applyQuickChain(
        source,
        const QuickChain(
          enabled: true,
          entry: 'Provider-Only',
          exit: 'US',
        ),
      ),
      throwsFormatException,
    );
  });

  test('rejects provider-only exit', () {
    expect(
      () => applyQuickChain(
        source,
        const QuickChain(
          enabled: true,
          entry: 'HK',
          exit: 'Provider-Only',
        ),
      ),
      throwsFormatException,
    );
  });

  test('applies the chain after profile modifications and keeps other fields', () {
    final profile = <String, dynamic>{
      ...source,
      'proxy-groups': [
        {'name': 'Node Select', 'type': 'select', 'proxies': ['HK', 'US']},
      ],
      'rules': ['MATCH,Node Select'],
    };
    final result = applyQuickChain(
      profile,
      const QuickChain(enabled: true, entry: 'HK', exit: 'US'),
    );
    expect((result['rules'] as List).single, 'MATCH,Node Select');
    expect((result['proxy-groups'] as List).length, 1);
    expect(((result['proxies'] as List).last as Map)['dialer-proxy'], 'HK');
  });

  test('disabled chain keeps the original config', () {
    expect(
      applyQuickChain(source, const QuickChain(entry: 'HK', exit: 'US')),
      same(source),
    );
  });

  test('rejects a missing exit', () {
    expect(
      () => applyQuickChain(
        source,
        const QuickChain(enabled: true, entry: 'HK', exit: 'Missing'),
      ),
      throwsFormatException,
    );
  });

  test('rejects a cycle', () {
    final cycle = <String, dynamic>{
      'proxies': [
        {'name': 'HK', 'dialer-proxy': 'US'},
        {'name': 'US'},
      ],
    };
    expect(
      () => applyQuickChain(
        cycle,
        const QuickChain(enabled: true, entry: 'HK', exit: 'US'),
      ),
      throwsFormatException,
    );
  });

  test('persists chain settings in profile override JSON', () {
    const original = ProfileOverrides(
      quickChain: QuickChain(
        enabled: true,
        entry: 'HK',
        exit: 'US',
        group: 'PROXY',
        previousSelection: 'DIRECT',
      ),
    );
    expect(
      ProfileOverrides.fromJson(
        jsonDecode(jsonEncode(original)) as Map<String, dynamic>,
      ).quickChain,
      original.quickChain,
    );
  });
}
