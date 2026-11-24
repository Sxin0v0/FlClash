import 'package:fl_clash/common/quick_chain_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('orders custom revisions numerically', () {
    expect(compareQuickChainVersions('v0.9.4-quickchain.14',
        '0.9.4-quickchain.13'), greaterThan(0));
    expect(compareQuickChainVersions('v0.9.4-quickchain.10',
        '0.9.4-quickchain.9'), greaterThan(0));
  });
  test('does not offer the installed release or an older one', () {
    expect(compareQuickChainVersions('v0.9.4-quickchain.13',
        '0.9.4-quickchain.13'), 0);
    expect(compareQuickChainVersions('v0.9.4-quickchain.12',
        '0.9.4-quickchain.13'), lessThan(0));
  });
  test('new upstream version outranks older custom revisions', () {
    expect(compareQuickChainVersions('v0.9.5-quickchain.1',
        '0.9.4-quickchain.999'), greaterThan(0));
  });
  test('legacy native versions have revision zero', () {
    expect(compareQuickChainVersions('v0.9.4-quickchain.14',
        '0.9.4'), greaterThan(0));
    expect(currentQuickChainVersion('0.9.4'), '0.9.4');
  });
  test('rejects other core lines', () {
    expect(() => compareQuickChainVersions('v0.9.5-rs.1',
        '0.9.4-quickchain.13'), throwsFormatException);
  });
}
