import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/config/firebase_emulator_options.dart';

void main() {
  const base = FirebaseOptions(apiKey: 'fake', appId: 'fake', messagingSenderId: 'fake', projectId: 'production-example');
  test('default leaves current Firebase options intact', () {
    expect(isolatedEmulatorOptions(base, emulatorsEnabled: false, requestedProjectId: '').projectId, 'production-example');
  });
  test('demo id is permitted only with emulators', () {
    expect(isolatedEmulatorOptions(base, emulatorsEnabled: true, requestedProjectId: 'demo-proxiplay-usb').projectId, 'demo-proxiplay-usb');
    expect(() => isolatedEmulatorOptions(base, emulatorsEnabled: false, requestedProjectId: 'demo-proxiplay-usb'), throwsStateError);
    expect(() => isolatedEmulatorOptions(base, emulatorsEnabled: true, requestedProjectId: 'production-example'), throwsStateError);
  });
}
