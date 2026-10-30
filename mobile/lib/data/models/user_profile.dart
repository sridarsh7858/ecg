/// The signed-in user. Deliberately minimal - only what the app actually needs.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.age,
    required this.createdAt,
    this.avatarSeed,
  });

  final String id;
  final String name;
  final String email;
  final int age;
  final DateTime createdAt;

  /// Optional seed used to pick a deterministic avatar colour/emoji.
  final String? avatarSeed;

  /// Up to two uppercase letters, used by the avatar widget.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final single = parts.first;
      return single.substring(0, single.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// First word of the name, used in greetings.
  String get firstName {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'there';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  UserProfile copyWith({
    String? name,
    String? email,
    int? age,
    String? avatarSeed,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      age: age ?? this.age,
      createdAt: createdAt,
      avatarSeed: avatarSeed ?? this.avatarSeed,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'age': age,
    'createdAt': createdAt.toIso8601String(),
    'avatarSeed': avatarSeed,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    age: (json['age'] as num).toInt(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    avatarSeed: json['avatarSeed'] as String?,
  );
}
