import 'package:flutter/services.dart';
import '../models/models.dart';

/// Native operating-system scheduling. Errors are intentionally propagated to UI.
class NativeBridge {
  static const channel = MethodChannel('app.supare/native');
  Future<void> scheduleTask(Map<String, dynamic> task) async {
    await channel.invokeMethod<void>('scheduleTask', task);
  }

  Future<void> schedule(TaskItem task) => scheduleTask({
    'id': task.id,
    'title': task.title,
    'body': task.description,
    'dueMillis': task.due.millisecondsSinceEpoch,
    'mode': task.reminder,
    'repeat': task.repeat,
    'intervalDays': task.intervalDays,
    'anchorDay': task.recurrenceDay,
    if (task.repeat != 'none')
      'recurrenceDue': task.nextOccurrence(task.due)!.millisecondsSinceEpoch,
  });
  Future<void> cancelTask(String id) =>
      channel.invokeMethod<void>('cancelTask', {'id': id});
  Future<Map<String, dynamic>> getCapabilities() async =>
      Map<String, dynamic>.from(
        await channel.invokeMethod<Map>('getCapabilities') ?? {},
      );
  Future<void> requestAlarmPermissions() =>
      channel.invokeMethod<void>('requestAlarmPermissions');
  Future<void> setSecure(bool enabled) =>
      channel.invokeMethod<void>('setSecure', {'enabled': enabled});
  Future<List<Map<String, dynamic>>> drainActions() async =>
      (await channel.invokeMethod<List>('drainActions') ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Future<void> ackActions(List<String> eventIds) =>
      channel.invokeMethod<void>('ackActions', {'eventIds': eventIds});
  Future<void> previewFile(String path, String mimeType) => channel
      .invokeMethod<void>('previewFile', {'path': path, 'mimeType': mimeType});
}
