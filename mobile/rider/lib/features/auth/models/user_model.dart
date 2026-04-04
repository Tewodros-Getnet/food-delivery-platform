class UserModel {
  final String id;
  final String email;
  final String role;
  final String? displayName;
  final String? phone;
  final String? profilePhotoUrl;
  final String status;

  const UserModel({
    required this.id,
    required this.email,
    required this.role,
    this.displayName,
    this.phone,
    this.profilePhotoUrl,
    required this.status,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['id'] as String,
    email: json['email'] as String,
    role: json['role'] as String,
    displayName: json['display_name'] as String?,
    phone: json['phone'] as String?,
    profilePhotoUrl: json['profile_photo_url'] as String?,
    status: json['status'] as String,
  );
}
