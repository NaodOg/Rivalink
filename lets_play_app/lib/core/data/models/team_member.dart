class TeamMember {
  final String id;
  final String userId;
  final String userName;
  final String teamId;
  final String role; // 'Owner', 'Admin', 'Member', 'Pending'
  final DateTime joinedAt;
  final bool isActive;
  final String? avatarUrl;
  final int? skillLevel; // 1-10 scale
  final List<String> positions; // e.g., ['Forward', 'Midfielder']

  TeamMember({
    required this.id,
    required this.userId,
    required this.userName,
    required this.teamId,
    this.role = 'Member',
    required this.joinedAt,
    this.isActive = true,
    this.avatarUrl,
    this.skillLevel,
    this.positions = const [],
  });

  factory TeamMember.fromJson(Map<String, dynamic> json) {
    return TeamMember(
      id: json['id'] ?? '',
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? '',
      teamId: json['teamId'] ?? '',
      role: json['role'] ?? 'Member',
      joinedAt: DateTime.tryParse(json['joinedAt'] ?? DateTime.now().toIso8601String()) ?? DateTime.now(),
      isActive: json['isActive'] ?? true,
      avatarUrl: json['avatarUrl'],
      skillLevel: json['skillLevel'],
      positions: List<String>.from(json['positions'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'teamId': teamId,
      'role': role,
      'joinedAt': joinedAt.toIso8601String(),
      'isActive': isActive,
      'avatarUrl': avatarUrl,
      'skillLevel': skillLevel,
      'positions': positions,
    };
  }

  // Check if the member is the owner
  bool get isOwner => role == 'Owner';

  // Check if the member is an admin
  bool get isAdmin => role == 'Admin' || role == 'Owner';

  // Check if the member is pending approval
  bool get isPending => role == 'Pending';
}
