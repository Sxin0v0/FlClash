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
