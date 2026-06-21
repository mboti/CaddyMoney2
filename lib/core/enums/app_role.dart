enum AppRole {
  standardUser,
  merchant,
  admin;

  String get displayName {
    switch (this) {
      case AppRole.standardUser:
        return 'Standard User';
      case AppRole.merchant:
        return 'Merchant';
      case AppRole.admin:
        return 'Administrator';
    }
  }

  static AppRole fromString(String value) {
    switch (value.toLowerCase()) {
      case 'standarduser':
      case 'standard_user':
        return AppRole.standardUser;
      case 'merchant':
        return AppRole.merchant;
      case 'admin':
      case 'administrator':
        return AppRole.admin;
      default:
        return AppRole.standardUser;
    }
  }

  String toJson() => name;
}
