class TeamActivity {
  final String id;
  final String teamId;
  final String type; // 'match', 'practice', 'event', 'announcement'
  final String title;
  final String description;
  final DateTime startTime;
  final DateTime endTime;
  final String location;
  final String organizerId;
  final String organizerName;
  final int maxParticipants;
  final int confirmedParticipants;
  final List<String> participantIds; // IDs of confirmed participants
  final List<String> interestedIds; // IDs of interested participants
  final bool isPublic;
  final DateTime createdAt;
  final DateTime updatedAt;

  TeamActivity({
    required this.id,
    required this.teamId,
    required this.type,
    required this.title,
    this.description = '',
    required this.startTime,
    required this.endTime,
    this.location = '',
    required this.organizerId,
    required this.organizerName,
    this.maxParticipants = 20,
    this.confirmedParticipants = 0,
    this.participantIds = const [],
    this.interestedIds = const [],
    this.isPublic = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TeamActivity.fromJson(Map<String, dynamic> json) {
    return TeamActivity(
      id: json['id'] ?? '',
      teamId: json['teamId'] ?? '',
      type: json['type'] ?? 'event',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      startTime: DateTime.tryParse(json['startTime'] ?? DateTime.now().toIso8601String()) ?? DateTime.now(),
      endTime: DateTime.tryParse(json['endTime'] ?? DateTime.now().add(Duration(hours: 1)).toIso8601String()) ?? DateTime.now().add(Duration(hours: 1)),
      location: json['location'] ?? '',
      organizerId: json['organizerId'] ?? '',
      organizerName: json['organizerName'] ?? '',
      maxParticipants: json['maxParticipants'] ?? 20,
      confirmedParticipants: json['confirmedParticipants'] ?? 0,
      participantIds: List<String>.from(json['participantIds'] ?? []),
      interestedIds: List<String>.from(json['interestedIds'] ?? []),
      isPublic: json['isPublic'] ?? true,
      createdAt: DateTime.tryParse(json['createdAt'] ?? DateTime.now().toIso8601String()) ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] ?? DateTime.now().toIso8601String()) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'teamId': teamId,
      'type': type,
      'title': title,
      'description': description,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'location': location,
      'organizerId': organizerId,
      'organizerName': organizerName,
      'maxParticipants': maxParticipants,
      'confirmedParticipants': confirmedParticipants,
      'participantIds': participantIds,
      'interestedIds': interestedIds,
      'isPublic': isPublic,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // Check if the activity is in the future
  bool get isInFuture => DateTime.now().isBefore(startTime);

  // Check if the activity is happening now
  bool get isNow => DateTime.now().isAfter(startTime) && DateTime.now().isBefore(endTime);

  // Check if the activity has ended
  bool get hasEnded => DateTime.now().isAfter(endTime);

  // Calculate how many spots are left
  int get spotsLeft => maxParticipants - confirmedParticipants;

  // Check if the activity is full
  bool get isFull => confirmedParticipants >= maxParticipants;
}
