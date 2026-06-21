import 'package:caddymoney/core/enums/support_request_status.dart';
import 'package:caddymoney/core/enums/support_requester_type.dart';

class SupportRequestModel {
  final String id;
  final String ticketNumber;
  final SupportRequesterType requesterType;
  final String requesterProfileId;
  /// Optional UI-only display name for the requester.
  ///
  /// This is hydrated client-side (e.g. by admin list fetch) and is not
  /// persisted back into `support_requests`.
  final String? requesterDisplayName;
  final String subject;
  final String description;
  final SupportRequestStatus status;
  final String? adminResponse;
  final DateTime? respondedAt;
  final DateTime? requesterSeenAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  SupportRequestModel({
    required this.id,
    required this.ticketNumber,
    required this.requesterType,
    required this.requesterProfileId,
    this.requesterDisplayName,
    required this.subject,
    required this.description,
    required this.status,
    this.adminResponse,
    this.respondedAt,
    this.requesterSeenAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SupportRequestModel.fromJson(Map<String, dynamic> json) {
    DateTime readDate(dynamic v) {
      if (v is DateTime) return v;
      final s = v?.toString();
      return DateTime.tryParse(s ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
    }

    return SupportRequestModel(
      id: json['id'] as String,
      ticketNumber: (json['ticket_number'] ?? json['ticketNumber'] ?? '').toString(),
      requesterType: SupportRequesterType.fromJson(json['requester_type'] ?? json['requesterType']),
      requesterProfileId: (json['requester_profile_id'] ?? json['requesterProfileId'] ?? '').toString(),
      requesterDisplayName: (json['requester_display_name'] ?? json['requesterDisplayName'])?.toString(),
      subject: (json['subject'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      status: SupportRequestStatus.fromJson(json['status']),
      adminResponse: (json['admin_response'] ?? json['adminResponse'])?.toString(),
      respondedAt: (json['responded_at'] ?? json['respondedAt']) == null ? null : readDate(json['responded_at'] ?? json['respondedAt']),
      requesterSeenAt: (json['requester_seen_at'] ?? json['requesterSeenAt']) == null ? null : readDate(json['requester_seen_at'] ?? json['requesterSeenAt']),
      createdAt: readDate(json['created_at'] ?? json['createdAt']),
      updatedAt: readDate(json['updated_at'] ?? json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'ticket_number': ticketNumber,
        'requester_type': requesterType.toJson(),
        'requester_profile_id': requesterProfileId,
        // requesterDisplayName intentionally omitted (UI-only)
        'subject': subject,
        'description': description,
        'status': status.toJson(),
        'admin_response': adminResponse,
        'responded_at': respondedAt?.toIso8601String(),
        'requester_seen_at': requesterSeenAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  SupportRequestModel copyWith({
    String? id,
    String? ticketNumber,
    SupportRequesterType? requesterType,
    String? requesterProfileId,
    String? requesterDisplayName,
    String? subject,
    String? description,
    SupportRequestStatus? status,
    String? adminResponse,
    DateTime? respondedAt,
    DateTime? requesterSeenAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SupportRequestModel(
      id: id ?? this.id,
      ticketNumber: ticketNumber ?? this.ticketNumber,
      requesterType: requesterType ?? this.requesterType,
      requesterProfileId: requesterProfileId ?? this.requesterProfileId,
      requesterDisplayName: requesterDisplayName ?? this.requesterDisplayName,
      subject: subject ?? this.subject,
      description: description ?? this.description,
      status: status ?? this.status,
      adminResponse: adminResponse ?? this.adminResponse,
      respondedAt: respondedAt ?? this.respondedAt,
      requesterSeenAt: requesterSeenAt ?? this.requesterSeenAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
