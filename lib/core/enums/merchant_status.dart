enum MerchantStatus {
  pending,
  approved,
  rejected,
  suspended;

  String get displayName {
    switch (this) {
      case MerchantStatus.pending:
        return 'Pending';
      case MerchantStatus.approved:
        return 'Approved';
      case MerchantStatus.rejected:
        return 'Rejected';
      case MerchantStatus.suspended:
        return 'Suspended';
    }
  }

  static MerchantStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'pending':
        return MerchantStatus.pending;
      case 'approved':
        return MerchantStatus.approved;
      case 'rejected':
        return MerchantStatus.rejected;
      case 'suspended':
        return MerchantStatus.suspended;
      default:
        return MerchantStatus.pending;
    }
  }

  String toJson() => name;
}
