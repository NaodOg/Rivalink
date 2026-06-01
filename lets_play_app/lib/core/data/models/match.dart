class PlayFairMatch {
  final String id;
  final String title;
  final String sport;
  final String description;
  final String location;
  final DateTime dateTime;
  final int maxPlayers;
  final int currentPlayers;
  final int spotsLeft;
  final double price;
  final String organizerId;
  final String organizerName;
  final bool isOrganizer;

  PlayFairMatch({
    required this.id,
    required this.title,
    required this.sport,
    this.description = '',
    required this.location,
    required this.dateTime,
    this.maxPlayers = 10,
    this.currentPlayers = 0,
    this.spotsLeft = 0,
    this.price = 0,
    required this.organizerId,
    this.organizerName = '',
    this.isOrganizer = false,
  });

  factory PlayFairMatch.fromJson(Map<String, dynamic> json) {
    return PlayFairMatch(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      sport: json['sport'] ?? '',
      description: json['description'] ?? '',
      location: json['location'] ?? '',
      dateTime: DateTime.tryParse(json['date_time'] ?? '') ?? DateTime.now(),
      maxPlayers: json['max_players'] ?? 10,
      currentPlayers: json['current_players'] ?? 0,
      spotsLeft: json['spots_left'] ?? 0,
      price: double.tryParse(json['price']?.toString() ?? '0') ?? 0,
      organizerId: json['organizer_id']?.toString() ?? '',
      organizerName: json['organizer_name'] ?? '',
      isOrganizer: json['is_organizer'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'sport': sport,
      'description': description,
      'location': location,
      'date_time': dateTime.toIso8601String(),
      'max_players': maxPlayers,
      'price': price,
    };
  }

  bool get isFull => currentPlayers >= maxPlayers || spotsLeft <= 0;
  
  String get formattedPrice => price == 0 ? 'Free' : 'Br ${price.toStringAsFixed(2)}';
  
  String get formattedDate {
    final now = DateTime.now();
    final diff = dateTime.difference(now);
    
    if (diff.inDays == 0) {
      return 'Today, ${_formatTime(dateTime)}';
    } else if (diff.inDays == 1) {
      return 'Tomorrow, ${_formatTime(dateTime)}';
    } else if (diff.inDays < 7) {
      return '${_dayName(dateTime.weekday)}, ${_formatTime(dateTime)}';
    } else {
      return '${dateTime.day}/${dateTime.month}, ${_formatTime(dateTime)}';
    }
  }
  
  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${dt.minute.toString().padLeft(2, '0')} $period';
  }
  
  String _dayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }
}
