class TeamInvitation {
  final String id;
  final String teamId;
  final String teamName;
  final String senderId; // Who sent the invitation
  final String senderName;
  final String recipientId; // Who received the invitation
  final String recipientName;
  final String status; // 'Pending', 'Accepted', 'Declined', 'Expired'
  final DateTime sentAt;
  final DateTime? respondedAt;
  final DateTime expiresAt;

  TeamInvitation({
    required this.id,
    required this.teamId,
    required this.teamName,
    required this.senderId,
    required this.senderName,
    required this.recipientId,
    required this.recipientName,
    this.status = 'Pending',
    required this.sentAt,
    this.respondedAt,
    required this.expiresAt,
  });

  factory TeamInvitation.fromJson(Map<String, dynamic> json) {
    return TeamInvitation(
      id: json['id'] ?? '',
      teamId: json['teamId'] ?? '',
      teamName: json['teamName'] ?? '',
      senderId: json['senderId'] ?? '',
      senderName: json['senderName'] ?? '',
      recipientId: json['recipientId'] ?? '',
      recipientName: json['recipientName'] ?? '',
      status: json['status'] ?? 'Pending',
      sentAt: DateTime.tryParse(json['sentAt'] ?? DateTime.now().toIso8601String()) ?? DateTime.now(),
      respondedAt: json['respondedAt'] != null ? DateTime.parse(json['respondedAt']) : null,
      expiresAt: DateTime.tryParse(json['expiresAt'] ?? DateTime.now().add(Duration(days: 7)).toIso8601String()) ?? DateTime.now().add(Duration(days: 7)),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'teamId': teamId,
      'teamName': teamName,
      'senderId': senderId,
      'senderName': senderName,
      'recipientId': recipientId,
      'recipientName': recipientName,
      'status': status,
      'sentAt': sentAt.toIso8601String(),
      'respondedAt': respondedAt?.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
    };
  }

  // Check if the invitation is still valid
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  // Check if the invitation is pending
  bool get isPending => status == 'Pending' && !isExpired;

  // Check if the invitation was accepted
  bool get isAccepted => status == 'Accepted';

  // Check if the invitation was declined
  bool get isDeclined => status == 'Declined';
}
