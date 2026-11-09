import 'dart:math' as math;

class TaskItem {
  TaskItem({
    required this.id,
    required this.title,
    required this.due,
    this.description = '',
    this.reminder = 'normal',
    this.repeat = 'none',
    this.intervalDays = 1,
    this.important = false,
    this.completedAt,
    DateTime? createdAt,
    int? recurrenceDay,
    DateTime? recurrenceAnchor,
    String? seriesId,
  }) : _createdAt = createdAt ?? DateTime.now(),
       recurrenceDay = recurrenceDay ?? due.day,
       recurrenceAnchor = recurrenceAnchor ?? due,
       seriesId = seriesId ?? id;
  final String id, title, description, reminder, repeat, seriesId;
  final DateTime due, recurrenceAnchor;
  final int intervalDays, recurrenceDay;
  final bool important;
  final DateTime? completedAt;
  final DateTime _createdAt;
  DateTime get createdAt => _createdAt;
  bool get isCompleted => completedAt != null;
  bool get isOverdue => !isCompleted && due.isBefore(DateTime.now());
  TaskItem copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? due,
    String? reminder,
    String? repeat,
    String? seriesId,
    int? intervalDays,
    bool? important,
    DateTime? completedAt,
    bool clearCompleted = false,
    int? recurrenceDay,
    DateTime? recurrenceAnchor,
  }) => TaskItem(
    id: id ?? this.id,
    seriesId: seriesId ?? this.seriesId,
    title: title ?? this.title,
    description: description ?? this.description,
    due: due ?? this.due,
    reminder: reminder ?? this.reminder,
    repeat: repeat ?? this.repeat,
    intervalDays: intervalDays ?? this.intervalDays,
    important: important ?? this.important,
    completedAt: clearCompleted ? null : (completedAt ?? this.completedAt),
    createdAt: createdAt,
    recurrenceDay: recurrenceDay ?? this.recurrenceDay,
    recurrenceAnchor: recurrenceAnchor ?? this.recurrenceAnchor,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'seriesId': seriesId,
    'title': title,
    'description': description,
    'due': due.toIso8601String(),
    'reminder': reminder,
    'repeat': repeat,
    'intervalDays': intervalDays,
    'recurrenceDay': recurrenceDay,
    'recurrenceAnchor': recurrenceAnchor.toIso8601String(),
    'important': important,
    'completedAt': completedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };
  factory TaskItem.fromJson(Map<String, dynamic> json) => TaskItem(
    id: json['id'] as String,
    title: json['title'] as String,
    seriesId: json['seriesId'] as String?,
    description: json['description'] as String? ?? '',
    due: DateTime.parse(json['due'] as String),
    reminder: json['reminder'] as String? ?? 'normal',
    repeat: json['repeat'] as String? ?? 'none',
    intervalDays: json['intervalDays'] as int? ?? 1,
    recurrenceDay: json['recurrenceDay'] as int?,
    recurrenceAnchor: _date(json['recurrenceAnchor']),
    important: json['important'] as bool? ?? false,
    completedAt: _date(json['completedAt']),
    createdAt: _date(json['createdAt']),
  );

  /// Calendar recurrence preserves wall-clock time across daylight saving changes.
  /// Month-end dates clamp to the final day, e.g. January 31 -> February 28.
  DateTime? nextOccurrence([DateTime? after]) {
    if (repeat == 'none') return null;
    var threshold = after ?? DateTime.now();
    if (due.isAfter(threshold)) threshold = due;
    final anchor = recurrenceAnchor;
    var value = anchor;
    if (repeat == 'monthly') {
      var months = math.max(
        1,
        (threshold.year - anchor.year) * 12 + threshold.month - anchor.month,
      );
      do {
        final month = DateTime(anchor.year, anchor.month + months, 1);
        final day = math.min(
          recurrenceDay,
          DateTime(month.year, month.month + 1, 0).day,
        );
        value = DateTime(
          month.year,
          month.month,
          day,
          anchor.hour,
          anchor.minute,
          anchor.second,
        );
        months++;
      } while (!value.isAfter(threshold));
      return value;
    }
    final days = repeat == 'weekly'
        ? 7
        : repeat == 'custom'
        ? intervalDays
        : 1;
    if (days < 1 || days > 3660) {
      throw const FormatException('Invalid repeat interval');
    }
    final difference = threshold.difference(anchor).inDays;
    var cycles = math.max(1, difference ~/ days);
    do {
      value = DateTime(
        anchor.year,
        anchor.month,
        anchor.day + days * cycles,
        anchor.hour,
        anchor.minute,
        anchor.second,
      );
      cycles++;
    } while (!value.isAfter(threshold));
    return value;
  }
}

class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.name,
    this.relationship = 'Custom',
  });
  final String id, name, relationship;
  FamilyMember copyWith({String? name, String? relationship}) => FamilyMember(
    id: id,
    name: name ?? this.name,
    relationship: relationship ?? this.relationship,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'relationship': relationship,
  };
  factory FamilyMember.fromJson(Map<String, dynamic> json) => FamilyMember(
    id: json['id'] as String,
    name: json['name'] as String,
    relationship: json['relationship'] as String? ?? 'Custom',
  );
}

class WalletDocument {
  const WalletDocument({
    required this.id,
    required this.name,
    required this.memberId,
    this.category = 'Other',
    this.number = '',
    this.authority = '',
    this.issueDate,
    this.expiryDate,
    this.fields = const {},
    this.fileName = '',
    this.mimeType = '',
    this.fileId = '',
    this.favorite = false,
    this.lastOpened,
    this.digest = '',
  });
  final String id,
      name,
      category,
      memberId,
      number,
      authority,
      fileName,
      mimeType,
      fileId,
      digest;
  final Map<String, String> fields;
  final DateTime? issueDate, expiryDate, lastOpened;
  final bool favorite;
  WalletDocument copyWith({
    String? name,
    String? category,
    String? memberId,
    String? number,
    String? authority,
    DateTime? issueDate,
    DateTime? expiryDate,
    Map<String, String>? fields,
    String? fileName,
    String? mimeType,
    String? fileId,
    bool? favorite,
    DateTime? lastOpened,
    String? digest,
    bool clearIssueDate = false,
    bool clearExpiryDate = false,
  }) => WalletDocument(
    id: id,
    name: name ?? this.name,
    category: category ?? this.category,
    memberId: memberId ?? this.memberId,
    number: number ?? this.number,
    authority: authority ?? this.authority,
    issueDate: clearIssueDate ? null : issueDate ?? this.issueDate,
    expiryDate: clearExpiryDate ? null : expiryDate ?? this.expiryDate,
    fields: fields ?? this.fields,
    fileName: fileName ?? this.fileName,
    mimeType: mimeType ?? this.mimeType,
    fileId: fileId ?? this.fileId,
    favorite: favorite ?? this.favorite,
    lastOpened: lastOpened ?? this.lastOpened,
    digest: digest ?? this.digest,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'memberId': memberId,
    'number': number,
    'authority': authority,
    'issueDate': issueDate?.toIso8601String(),
    'expiryDate': expiryDate?.toIso8601String(),
    'fields': fields,
    'fileName': fileName,
    'mimeType': mimeType,
    'fileId': fileId,
    'favorite': favorite,
    'lastOpened': lastOpened?.toIso8601String(),
    'digest': digest,
  };
  factory WalletDocument.fromJson(Map<String, dynamic> json) => WalletDocument(
    id: json['id'] as String,
    name: json['name'] as String,
    memberId: json['memberId'] as String,
    category: json['category'] as String? ?? 'Other',
    number: json['number'] as String? ?? '',
    authority: json['authority'] as String? ?? '',
    issueDate: _date(json['issueDate']),
    expiryDate: _date(json['expiryDate']),
    fields: Map<String, String>.from(json['fields'] as Map? ?? {}),
    fileName: json['fileName'] as String? ?? '',
    mimeType: json['mimeType'] as String? ?? '',
    fileId: json['fileId'] as String? ?? '',
    favorite: json['favorite'] as bool? ?? false,
    lastOpened: _date(json['lastOpened']),
    digest: json['digest'] as String? ?? '',
  );
}

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.parse(value as String);
