/// A PDF a trainer handed this user for one split or diet plan. Only the grant
/// travels to the app - the file itself is only ever shown in
/// `SecureDocumentScreen`.
class TrainerDocument {
  final String grantId;
  final String documentId;
  final String title;

  /// "Split" or "DietPlan".
  final String kind;
  final DateTime? grantedAtUtc;
  final String? trainerUsername;

  const TrainerDocument({
    required this.grantId,
    required this.documentId,
    required this.title,
    required this.kind,
    this.grantedAtUtc,
    this.trainerUsername,
  });

  factory TrainerDocument.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return TrainerDocument(
      grantId: map['grantId'] as String,
      documentId: map['documentId'] as String,
      title: map['title'] as String? ?? 'Document',
      kind: map['kind'] as String? ?? '',
      grantedAtUtc: DateTime.tryParse(map['grantedAtUtc'] as String? ?? ''),
      trainerUsername: map['trainerUsername'] as String?,
    );
  }
}

enum TrainerDocumentKind {
  split('Split'),
  dietPlan('DietPlan');

  final String wire;
  const TrainerDocumentKind(this.wire);
}
