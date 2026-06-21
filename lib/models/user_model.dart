import 'package:caddymoney/core/enums/app_role.dart';
import 'package:caddymoney/core/enums/account_status.dart';

class UserModel {
  final String id;
  final String fullName;
  final String? firstName;
  final String? lastName;
  final String? username;
  final String email;
  final String? phone;
  final AppRole role;
  final AccountStatus status;
  final String? preferredLanguage;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserModel({
    required this.id,
    required this.fullName,
    this.firstName,
    this.lastName,
    this.username,
    required this.email,
    this.phone,
    required this.role,
    required this.status,
    this.preferredLanguage,
    this.avatarUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      username: json['username'] as String?,
      email: json['email'] as String,
      phone: json['phone'] as String?,
      role: AppRole.fromString(json['role'] as String),
      status: AccountStatus.fromString(json['status'] as String),
      preferredLanguage: json['preferred_language'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'first_name': firstName,
      'last_name': lastName,
      'username': username,
      'email': email,
      'phone': phone,
      'role': role.toJson(),
      'status': status.toJson(),
      'preferred_language': preferredLanguage,
      'avatar_url': avatarUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? id,
    String? fullName,
    String? firstName,
    String? lastName,
    String? username,
    String? email,
    String? phone,
    AppRole? role,
    AccountStatus? status,
    String? preferredLanguage,
    String? avatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      username: username ?? this.username,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      status: status ?? this.status,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
