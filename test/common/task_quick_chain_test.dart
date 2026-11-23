import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

const _proxies = <Map<String, dynamic>>[
  {'name': 'HK', 'type': 'socks5', 'server': 'hk.example', 'port': 1080},
  {'name': 'JP', 'type': 'socks5', 'server': 'jp.example', 'port': 1080},
  {'name': 'US', 'type': 'socks5', 'server': 'us.example', 'port': 1080},
];

Future<YamlMap> build(QuickChain chain) async {
  final real = await makeRealProfileTask(
    MakeRealProfileState(
      profilesPath: '/profiles',
      profileId: 1,
      rawConfig: {
        'proxies': _proxies,
        'proxy-groups': [
          {'name': 'Selector', 'type': 'select', 'proxies': ['US', 'JP', 'HK']},
        ],
        'rules': ['MATCH,Selector'],
      },
      realPatchConfig: const PatchClashConfig(),
      overrides: ProfileOverrides(quickChain: chain),
      appendSystemDns: false,
      proxyGroups: const [],
      rules: const [],
      addedRules: const [],
      defaultUA: 'FlClash-Test',
    ),
  );
  return loadYaml(real.yaml) as YamlMap;
}

void main() {
  test('generated runtime profile carries every dialer-proxy link', () async {
    final yaml = await build(const QuickChain(
      enabled: true,
      entry: 'HK',
      hops: ['JP'],
      exit: 'US',
      group: 'Selector',
    ));
    final proxies = yaml['proxies'] as YamlList;
    expect((proxies[0] as YamlMap).containsKey('dialer-proxy'), isFalse);
    expect((proxies[1] as YamlMap)['dialer-proxy'], 'HK');
    expect((proxies[2] as YamlMap)['dialer-proxy'], 'JP');
    expect((yaml['rules'] as YamlList).single, 'MATCH,Selector');
  });

  test('disabled chain does not inject dialer-proxy links', () async {
    final yaml = await build(const QuickChain(
      entry: 'HK',
      exit: 'US',
    ));
    final proxies = yaml['proxies'] as YamlList;
    expect((proxies[2] as YamlMap).containsKey('dialer-proxy'), isFalse);
  });

  test('invalid selected proxy refuses to build a fake connected chain', () async {
    expect(
      () => build(const QuickChain(
        enabled: true,
        entry: 'Missing',
        exit: 'US',
      )),
      throwsFormatException,
    );
  });
}
