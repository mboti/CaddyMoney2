class SavedRecipientModel {
  final String ownerUserId;
  final String recipientUserId;
  final String recipientEmail;
  final String? recipientFullName;
  final DateTime createdAt;

  const SavedRecipientModel({
    required this.ownerUserId,
    required this.recipientUserId,
    required this.recipientEmail,
    required this.createdAt,
    this.recipientFullName,
  });

  factory SavedRecipientModel.fromRow(Map<String, dynamic> row) {
    final recipient = row['recipient'];
    final recipientMap = recipient is Map ? Map<String, dynamic>.from(recipient) : <String, dynamic>{};
    return SavedRecipientModel(
      ownerUserId: row['owner_user_id']?.toString() ?? '',
      recipientUserId: row['recipient_user_id']?.toString() ?? '',
      recipientEmail: recipientMap['email']?.toString() ?? '',
      recipientFullName: recipientMap['full_name']?.toString(),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
