import 'package:caddymoney/core/enums/merchant_status.dart';

class MerchantModel {
  final String id;
  final String profileId;
  final String uniqueMerchantId;
  final String businessName;
  final String? ownerName;
  final String? ownerFirstName;
  final String? ownerLastName;
  final String businessEmail;
  final String? businessPhone;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? postalCode;
  final String? countryCode;
  final String? countryName;
  final String? businessCategory;
  final List<String> categories;
  final String? businessType;
  final String? registrationNumber;
  final String? taxNumber;
  final String? vatNumber;
  final DateTime? dateOfBirth;
  final String? nationality;
  final String? iban;
  final String? accountHolderName;
  final String? customerSupportAddress;
  final String? idDocumentPath;
  final String? proofOfAddressPath;
  final String? businessRegistrationDocPath;
  final String? logoPath;
  final bool? smsVerified;
  final bool? profileCompleted;
  final DateTime? profileCompletedAt;
  final MerchantStatus status;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? rejectedReason;
  final String? suspendedReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Optional persisted location for map previews and routing.
  ///
  /// Stored in Supabase as numeric columns (double precision).
  final double? latitude;
  final double? longitude;

  MerchantModel({
    required this.id,
    required this.profileId,
    required this.uniqueMerchantId,
    required this.businessName,
    this.ownerName,
    this.ownerFirstName,
    this.ownerLastName,
    required this.businessEmail,
    this.businessPhone,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.postalCode,
    this.countryCode,
    this.countryName,
    this.businessCategory,
    this.categories = const [],
    this.businessType,
    this.registrationNumber,
    this.taxNumber,
    this.vatNumber,
    this.dateOfBirth,
    this.nationality,
    this.iban,
    this.accountHolderName,
    this.customerSupportAddress,
    this.idDocumentPath,
    this.proofOfAddressPath,
    this.businessRegistrationDocPath,
    this.logoPath,
    this.smsVerified,
    this.profileCompleted,
    this.profileCompletedAt,
    required this.status,
    this.approvedBy,
    this.approvedAt,
    this.rejectedReason,
    this.suspendedReason,
    required this.createdAt,
    required this.updatedAt,
    this.latitude,
    this.longitude,
  });

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  factory MerchantModel.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'];
    final categories = rawCategories is List ? rawCategories.map((e) => e.toString()).toList() : <String>[];
    return MerchantModel(
      id: json['id'] as String,
      profileId: json['profile_id'] as String,
      uniqueMerchantId: json['unique_merchant_id'] as String,
      businessName: json['business_name'] as String,
      ownerName: json['owner_name'] as String?,
      ownerFirstName: json['owner_first_name'] as String?,
      ownerLastName: json['owner_last_name'] as String?,
      businessEmail: json['business_email'] as String,
      businessPhone: json['business_phone'] as String?,
      addressLine1: json['address_line1'] as String?,
      addressLine2: json['address_line2'] as String?,
      city: json['city'] as String?,
      postalCode: json['postal_code'] as String?,
      countryCode: json['country_code'] as String?,
      countryName: json['country_name'] as String?,
      businessCategory: json['business_category'] as String?,
      categories: categories,
      businessType: json['business_type'] as String?,
      registrationNumber: json['registration_number'] as String?,
      taxNumber: json['tax_number'] as String?,
      vatNumber: json['vat_number'] as String?,
      dateOfBirth: json['date_of_birth'] != null ? DateTime.parse(json['date_of_birth'] as String) : null,
      nationality: json['nationality'] as String?,
      iban: json['iban'] as String?,
      accountHolderName: json['account_holder_name'] as String?,
      customerSupportAddress: json['customer_support_address'] as String?,
      idDocumentPath: json['id_document_path'] as String?,
      proofOfAddressPath: json['proof_of_address_path'] as String?,
      businessRegistrationDocPath: json['business_registration_doc_path'] as String?,
      logoPath: json['logo_path'] as String?,
      smsVerified: json['sms_verified'] as bool?,
      profileCompleted: json['profile_completed'] as bool?,
      profileCompletedAt: json['profile_completed_at'] != null ? DateTime.parse(json['profile_completed_at'] as String) : null,
      status: MerchantStatus.fromString(json['status'] as String),
      approvedBy: json['approved_by'] as String?,
      approvedAt: json['approved_at'] != null ? DateTime.parse(json['approved_at'] as String) : null,
      rejectedReason: json['rejected_reason'] as String?,
      suspendedReason: json['suspended_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profile_id': profileId,
      'unique_merchant_id': uniqueMerchantId,
      'business_name': businessName,
      'owner_name': ownerName,
      'owner_first_name': ownerFirstName,
      'owner_last_name': ownerLastName,
      'business_email': businessEmail,
      'business_phone': businessPhone,
      'address_line1': addressLine1,
      'address_line2': addressLine2,
      'city': city,
      'postal_code': postalCode,
      'country_code': countryCode,
      'country_name': countryName,
      'business_category': businessCategory,
      'categories': categories,
      'business_type': businessType,
      'registration_number': registrationNumber,
      'tax_number': taxNumber,
      'vat_number': vatNumber,
      'date_of_birth': dateOfBirth?.toIso8601String(),
      'nationality': nationality,
      'iban': iban,
      'account_holder_name': accountHolderName,
      'customer_support_address': customerSupportAddress,
      'id_document_path': idDocumentPath,
      'proof_of_address_path': proofOfAddressPath,
      'business_registration_doc_path': businessRegistrationDocPath,
      'logo_path': logoPath,
      'sms_verified': smsVerified,
      'profile_completed': profileCompleted,
      'profile_completed_at': profileCompletedAt?.toIso8601String(),
      'status': status.toJson(),
      'approved_by': approvedBy,
      'approved_at': approvedAt?.toIso8601String(),
      'rejected_reason': rejectedReason,
      'suspended_reason': suspendedReason,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  MerchantModel copyWith({
    String? id,
    String? profileId,
    String? uniqueMerchantId,
    String? businessName,
    String? ownerName,
    String? ownerFirstName,
    String? ownerLastName,
    String? businessEmail,
    String? businessPhone,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? postalCode,
    String? countryCode,
    String? countryName,
    String? businessCategory,
    List<String>? categories,
    String? businessType,
    String? registrationNumber,
    String? taxNumber,
    String? vatNumber,
    DateTime? dateOfBirth,
    String? nationality,
    String? iban,
    String? accountHolderName,
    String? customerSupportAddress,
    String? idDocumentPath,
    String? proofOfAddressPath,
    String? businessRegistrationDocPath,
    String? logoPath,
    bool? smsVerified,
    bool? profileCompleted,
    DateTime? profileCompletedAt,
    MerchantStatus? status,
    String? approvedBy,
    DateTime? approvedAt,
    String? rejectedReason,
    String? suspendedReason,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? latitude,
    double? longitude,
  }) {
    return MerchantModel(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      uniqueMerchantId: uniqueMerchantId ?? this.uniqueMerchantId,
      businessName: businessName ?? this.businessName,
      ownerName: ownerName ?? this.ownerName,
      ownerFirstName: ownerFirstName ?? this.ownerFirstName,
      ownerLastName: ownerLastName ?? this.ownerLastName,
      businessEmail: businessEmail ?? this.businessEmail,
      businessPhone: businessPhone ?? this.businessPhone,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      city: city ?? this.city,
      postalCode: postalCode ?? this.postalCode,
      countryCode: countryCode ?? this.countryCode,
      countryName: countryName ?? this.countryName,
      businessCategory: businessCategory ?? this.businessCategory,
      categories: categories ?? this.categories,
      businessType: businessType ?? this.businessType,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      taxNumber: taxNumber ?? this.taxNumber,
      vatNumber: vatNumber ?? this.vatNumber,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      nationality: nationality ?? this.nationality,
      iban: iban ?? this.iban,
      accountHolderName: accountHolderName ?? this.accountHolderName,
      customerSupportAddress: customerSupportAddress ?? this.customerSupportAddress,
      idDocumentPath: idDocumentPath ?? this.idDocumentPath,
      proofOfAddressPath: proofOfAddressPath ?? this.proofOfAddressPath,
      businessRegistrationDocPath: businessRegistrationDocPath ?? this.businessRegistrationDocPath,
      logoPath: logoPath ?? this.logoPath,
      smsVerified: smsVerified ?? this.smsVerified,
      profileCompleted: profileCompleted ?? this.profileCompleted,
      profileCompletedAt: profileCompletedAt ?? this.profileCompletedAt,
      status: status ?? this.status,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      rejectedReason: rejectedReason ?? this.rejectedReason,
      suspendedReason: suspendedReason ?? this.suspendedReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}
