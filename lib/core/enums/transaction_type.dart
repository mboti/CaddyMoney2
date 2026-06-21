enum TransactionType {
  userToUser,
  userToMerchant,
  refund,
  adjustment;

  String get displayName {
    switch (this) {
      case TransactionType.userToUser:
        return 'User to User';
      case TransactionType.userToMerchant:
        return 'User to Merchant';
      case TransactionType.refund:
        return 'Refund';
      case TransactionType.adjustment:
        return 'Adjustment';
    }
  }

  static TransactionType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'usertouser':
      case 'user_to_user':
        return TransactionType.userToUser;
      case 'usertomerchant':
      case 'user_to_merchant':
        return TransactionType.userToMerchant;
      case 'refund':
        return TransactionType.refund;
      case 'adjustment':
        return TransactionType.adjustment;
      default:
        return TransactionType.userToUser;
    }
  }

  String toJson() => name;
}
