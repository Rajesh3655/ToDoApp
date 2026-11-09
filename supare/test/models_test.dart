import 'package:flutter_test/flutter_test.dart';
import 'package:supare/models/models.dart';

void main() {
  group('calendar repeat behavior', () {
    test('monthly preserves original end-of-month anchor', () {
      final task = TaskItem(
        id: 'monthly',
        title: 'Renew pass',
        due: DateTime(2027, 1, 31, 10, 30),
        repeat: 'monthly',
      );
      expect(
        task.nextOccurrence(DateTime(2027, 2, 1)),
        DateTime(2027, 2, 28, 10, 30),
      );
      expect(
        task.nextOccurrence(DateTime(2027, 2, 28, 11)),
        DateTime(2027, 3, 31, 10, 30),
      );
      expect(
        task.nextOccurrence(DateTime(2027, 12, 31, 11)),
        DateTime(2028, 1, 31, 10, 30),
      );
    });
    test(
      'daily ignores missed periods and remains strictly after the threshold',
      () {
        final task = TaskItem(
          id: 'daily',
          title: 'Medicine',
          due: DateTime(2027, 1, 1, 9),
          repeat: 'daily',
        );
        expect(
          task.nextOccurrence(DateTime(2027, 1, 10, 8)),
          DateTime(2027, 1, 10, 9),
        );
        expect(
          task.nextOccurrence(DateTime(2027, 1, 10, 9)),
          DateTime(2027, 1, 11, 9),
        );
      },
    );
    test('weekly and custom retain cadence across a year boundary', () {
      final task = TaskItem(
        id: 'weekly',
        title: 'Call family',
        due: DateTime(2027, 12, 29, 18),
        repeat: 'weekly',
      );
      expect(
        task.nextOccurrence(DateTime(2028, 1, 1)),
        DateTime(2028, 1, 5, 18),
      );
      expect(
        task
            .copyWith(repeat: 'custom', intervalDays: 3)
            .nextOccurrence(DateTime(2028, 1, 1, 19)),
        DateTime(2028, 1, 4, 18),
      );
      expect(task.copyWith(repeat: 'none').nextOccurrence(), isNull);
    });
  });
  test('document serialization retains all family form-filling metadata', () {
    final original = WalletDocument(
      id: 'income',
      name: 'Income Certificate',
      memberId: 'father',
      category: 'Income Certificate',
      number: 'CERT-123',
      authority: 'District office',
      issueDate: DateTime(2026, 11, 1),
      expiryDate: DateTime(2027, 11, 1),
      fields: {'Annual income': '120000', 'Applicant name': 'A. Kumar'},
      fileName: 'income.pdf',
      mimeType: 'application/pdf',
      fileId: 'encrypted-file-1',
      favorite: true,
      lastOpened: DateTime(2026, 11, 9, 10, 30),
      digest: 'opaque-checksum',
    );
    expect(
      WalletDocument.fromJson(original.toJson()).toJson(),
      original.toJson(),
    );
    final cleared = original.copyWith(
      clearIssueDate: true,
      clearExpiryDate: true,
    );
    expect(cleared.issueDate, isNull);
    expect(cleared.expiryDate, isNull);
    expect(cleared.fields['Annual income'], '120000');
    expect(cleared.memberId, 'father');
  });
}
