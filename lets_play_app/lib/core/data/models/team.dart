class Team {
  final String id;
  final String name;
  final String sport;
  final String description;
  final String type; // e.g., '5x5', '3v3', 'Casual', 'Competitive'
  final String status; // 'Active', 'Inactive', 'Recruiting'
  final String privacy; // 'Public', 'Private', 'Invite Only'
  final String location;
  final int maxMembers;
  final int currentMembers;
  final int spotsLeft;
  final String ownerId;
  final String ownerName;
  final String? avatarUrl; // URL to team avatar/image
  final List<String> memberIds; // List of user IDs who are members
  final List<String> pendingInvites; // List of user IDs with pending invites
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPublic; // Whether the team appears in public searches

  Team({
    required this.id,
    required this.name,
    required this.sport,
    this.description = '',
    this.type = '5x5',
    this.status = 'Active',
    this.privacy = 'Public',
    this.location = '',
    this.maxMembers = 10,
    this.currentMembers = 0,
    this.spotsLeft = 0,
    required this.ownerId,
    required this.ownerName,
    this.avatarUrl,
    this.memberIds = const [],
    this.pendingInvites = const [],
    required this.createdAt,
    required this.updatedAt,
    this.isPublic = true,
  });

  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      sport: json['sport'] ?? '',
      description: json['description'] ?? '',
      type: json['type'] ?? '5x5',
      status: json['status'] ?? 'Active',
      privacy: json['privacy'] ?? 'Public',
      location: json['location'] ?? '',
      maxMembers: json['maxMembers'] ?? 10,
      currentMembers: json['currentMembers'] ?? 0,
      ownerId: json['ownerId'] ?? '',
      ownerName: json['ownerName'] ?? '',
      avatarUrl: json['avatarUrl'],
      memberIds: List<String>.from(json['memberIds'] ?? []),
      pendingInvites: List<String>.from(json['pendingInvites'] ?? []),
      createdAt: DateTime.tryParse(json['createdAt'] ?? DateTime.now().toIso8601String()) ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] ?? DateTime.now().toIso8601String()) ?? DateTime.now(),
      isPublic: json['isPublic'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'sport': sport,
      'description': description,
      'type': type,
      'status': status,
      'privacy': privacy,
      'location': location,
      'maxMembers': maxMembers,
      'currentMembers': currentMembers,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'avatarUrl': avatarUrl,
      'memberIds': memberIds,
      'pendingInvites': pendingInvites,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isPublic': isPublic,
    };
  }

  // Check if the team is full
  bool get isFull => currentMembers >= maxMembers || spotsLeft <= 0;

  // Check if the team is recruiting
  bool get isRecruiting => status == 'Recruiting' && !isFull;

  // Check if the team is active
  bool get isActive => status == 'Active';
}
