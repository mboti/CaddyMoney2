enum SupportRequesterType {
  user,
  merchant;

  String toJson() => switch (this) {
        SupportRequesterType.user => 'user',
        SupportRequesterType.merchant => 'merchant',
      };

  static SupportRequesterType fromJson(dynamic v) {
    final s = v?.toString().trim().toLowerCase();
    return s == 'merchant' ? SupportRequesterType.merchant : SupportRequesterType.user;
  }

  String get displayName => switch (this) {
        SupportRequesterType.user => 'User',
        SupportRequesterType.merchant => 'Merchant',
      };
}
