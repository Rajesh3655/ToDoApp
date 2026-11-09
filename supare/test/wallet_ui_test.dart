import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as imaging;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supare/core/app_store.dart';
import 'package:supare/core/crypto_service.dart';
import 'package:supare/core/native_bridge.dart';
import 'package:supare/core/vault_auth.dart';
import 'package:supare/models/models.dart';
import 'package:supare/ui/document_crop.dart';
import 'package:supare/ui/wallet.dart';

// UI tests inject authentication responses. Cryptographic PIN verification and
// native biometrics require the separate security/device tests.
class _UiAuth extends VaultAuth {
  bool unlocked = true;
  @override
  bool get isUnlocked => unlocked;
  @override
  Future<bool> get hasPin async => true;
  @override
  Future<bool> unlockWithPin(String pin) async {
    if (pin != '123456') return false;
    unlocked = true;
    notifyListeners();
    return true;
  }

  @override
  void lock() {
    unlocked = false;
    notifyListeners();
  }
}

class _UiNative extends NativeBridge {
  @override
  Future<void> cancelTask(String id) async {}
  @override
  Future<void> scheduleTask(Map<String, dynamic> task) async {}
  @override
  Future<void> setSecure(bool enabled) async {}
  @override
  Future<List<Map<String, dynamic>>> drainActions() async => [];
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (ready()) return;
  }
  fail('The asynchronous UI operation did not complete.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets(
    'wallet hides metadata while locked and opens only after successful PIN',
    (tester) async {
      late Directory directory;
      late AppStore store;
      final auth = _UiAuth();
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('supare_wallet_ui_');
        store = await AppStore.open(
          directory: directory,
          databaseFactory: databaseFactoryFfiNoIsolate,
          crypto: CryptoService(
            testingKey: Uint8List.fromList(List.generate(32, (i) => i)),
          ),
          auth: auth,
          native: _UiNative(),
        );
        await store.importDocument(
          const WalletDocument(
            id: 'income',
            name: 'Income Certificate',
            memberId: 'myself',
            number: 'PRIVATE-123',
            fileName: 'income.pdf',
            mimeType: 'application/pdf',
          ),
          Uint8List.fromList(utf8.encode('%PDF-1.4\n%%EOF')),
        );
        auth.lock();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WalletScreen(store: store)),
        ),
      );
      await _waitFor(
        tester,
        () => find.text('Wallet PIN').evaluate().isNotEmpty,
      );
      expect(find.text('Income Certificate'), findsNothing);
      expect(find.textContaining('PRIVATE-123'), findsNothing);
      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.text('Unlock'));
      await _waitFor(
        tester,
        () => find.textContaining('Could not unlock.').evaluate().isNotEmpty,
      );
      expect(auth.isUnlocked, false);
      expect(find.text('Income Certificate'), findsNothing);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Unlock'));
      await _waitFor(
        tester,
        () => find.text('Income Certificate').evaluate().isNotEmpty,
      );
      expect(auth.isUnlocked, true);
      expect(find.text('Income Certificate'), findsOneWidget);
      auth.lock();
      await tester.pump();
      expect(find.text('Income Certificate'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await store.close();
        await directory.delete(recursive: true);
      });
    },
  );

  testWidgets('manual scan crop returns a real cropped JPEG', (tester) async {
    final bytes = Uint8List.fromList(
      imaging.encodeJpg(imaging.Image(width: 100, height: 80)),
    );
    Uint8List? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await Navigator.push<Uint8List>(
                  context,
                  MaterialPageRoute(builder: (_) => DocumentCrop(bytes: bytes)),
                );
              },
              child: const Text('Scan'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Scan'));
    await tester.pump();
    await _waitFor(
      tester,
      () => find
          .byType(FilledButton)
          .evaluate()
          .any(
            (e) =>
                (e.widget as FilledButton).onPressed != null &&
                find.text('Use cropped scan').evaluate().isNotEmpty &&
                find.byType(Image).evaluate().isNotEmpty,
          ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use cropped scan'));
    await _waitFor(tester, () => result != null);
    final decoded = imaging.decodeJpg(result!);
    expect(decoded, isNotNull);
    expect(decoded!.width, 92);
    expect(decoded.height, 74);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'scan privacy guard removes the image when authorization expires',
    (tester) async {
      final unlocked = ValueNotifier<bool>(true);
      final bytes = Uint8List.fromList(
        imaging.encodeJpg(imaging.Image(width: 30, height: 40)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentCrop(
            bytes: bytes,
            privacyGuard: (context, child) => ValueListenableBuilder<bool>(
              valueListenable: unlocked,
              builder: (context, value, _) => value
                  ? child
                  : const Scaffold(body: Text('Unlock to continue')),
            ),
          ),
        ),
      );
      await _waitFor(tester, () => find.byType(Image).evaluate().isNotEmpty);
      unlocked.value = false;
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(find.text('Unlock to continue'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      unlocked.dispose();
    },
  );
}
