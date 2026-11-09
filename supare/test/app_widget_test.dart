import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supare/core/app_store.dart';
import 'package:supare/core/crypto_service.dart';
import 'package:supare/core/native_bridge.dart';
import 'package:supare/core/vault_auth.dart';
import 'package:supare/models/models.dart';
import 'package:supare/ui/app.dart';

class _Auth extends VaultAuth {
  @override
  bool get isUnlocked => false;
  @override
  Future<bool> get hasPin async => false;
  @override
  void lock() {}
}

class _Native extends NativeBridge {
  final scheduled = <String, Map<String, dynamic>>{};
  @override
  Future<void> scheduleTask(Map<String, dynamic> task) async {
    scheduled[task['id'] as String] = task;
  }

  @override
  Future<void> cancelTask(String id) async {
    scheduled.remove(id);
  }

  @override
  Future<List<Map<String, dynamic>>> drainActions() async => [];
  @override
  Future<void> ackActions(List<String> eventIds) async {}
  @override
  Future<void> setSecure(bool value) async {}
  @override
  Future<Map<String, dynamic>> getCapabilities() async => {
    'platform': 'android',
    'notifications': true,
    'exactAlarms': true,
    'fullScreen': true,
  };
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(condition(), true, reason: 'The async user action must finish');
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppStore store;
  late Directory directory;
  late _Native native;
  Future<void> create(WidgetTester tester) async {
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('supare_widgets_');
      native = _Native();
      store = await AppStore.open(
        directory: directory,
        databaseFactory: databaseFactoryFfiNoIsolate,
        crypto: CryptoService(
          testingKey: Uint8List.fromList(List.generate(32, (i) => i)),
        ),
        auth: _Auth(),
        native: native,
      );
    });
  }

  Future<void> clean(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await store.close();
      await directory.delete(recursive: true);
    });
  }

  testWidgets(
    'four tabs navigate to real task, wallet lock, and settings screens',
    (tester) async {
      await create(tester);
      await tester.pumpWidget(SupareApp(store: store));
      await tester.pumpAndSettle();
      for (final tab in ['Today', 'Upcoming', 'Wallet', 'Settings']) {
        expect(find.text(tab), findsOneWidget);
      }
      expect(find.text('Make room\nfor what matters.'), findsOneWidget);
      await tester.tap(find.text('Upcoming'));
      await tester.pumpAndSettle();
      expect(find.text('A little ahead.'), findsOneWidget);
      await tester.tap(find.text('Wallet'));
      await tester.pumpAndSettle();
      expect(find.text('Your private space'), findsOneWidget);
      expect(find.text('Create secure wallet'), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Your space.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Export encrypted backup'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Export encrypted backup'), findsOneWidget);
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.text('Make room\nfor what matters.'), findsOneWidget);
      var readyToClose = false;
      final drained = store.rescheduleAlarms().then((_) {
        readyToClose = true;
      });
      await _waitFor(tester, () => readyToClose);
      await drained;
      await clean(tester);
    },
  );

  testWidgets(
    'task form rejects empty title, saves, and persists its real reminder',
    (tester) async {
      await create(tester);
      await tester.pumpWidget(SupareApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New task'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save task'));
      await tester.tap(find.text('Save task'));
      await tester.pumpAndSettle();
      expect(find.text('Give your task a title'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'What needs doing?'),
        'Book Delhi train',
      );
      await tester.ensureVisible(find.text('Save task'));
      await tester.tap(find.text('Save task'));
      await _waitFor(
        tester,
        () => store.tasks.any((task) => task.title == 'Book Delhi train'),
      );
      final task = store.tasks.single;
      expect(task.title, 'Book Delhi train');
      expect(native.scheduled[task.id]?['mode'], 'normal');
      expect(find.text('A new intention'), findsNothing);
      var readyToClose = false;
      final drained = store.rescheduleAlarms().then((_) {
        readyToClose = true;
      });
      await _waitFor(tester, () => readyToClose);
      await drained;
      await clean(tester);
    },
  );

  testWidgets('complete and restore update history without deleting the task', (
    tester,
  ) async {
    await create(tester);
    final now = DateTime.now();
    await tester.runAsync(
      () => store.saveTask(
        TaskItem(
          id: 'ui-complete',
          title: 'Take medicine',
          due: DateTime(now.year, now.month, now.day, 0, 1),
        ),
      ),
    );
    await tester.pumpWidget(SupareApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('Take medicine'), findsOneWidget);
    await tester.tap(find.byTooltip('Complete task'));
    await _waitFor(tester, () => store.tasks.single.isCompleted);
    expect(find.text('Take medicine'), findsNothing);
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('Take medicine'), findsOneWidget);
    await tester.tap(find.byTooltip('Restore task'));
    await _waitFor(tester, () => !store.tasks.single.isCompleted);
    expect(find.text('Take medicine'), findsNothing);
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('Take medicine'), findsOneWidget);
    await clean(tester);
  });
}
