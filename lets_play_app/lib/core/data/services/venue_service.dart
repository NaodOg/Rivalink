import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api_config.dart';
import 'auth_service.dart';
import 'cache_service.dart';
import 'upload_media_type.dart';

class Venue {
  final int id;
  final int ownerId;
  final String ownerName;
  final String name;
  final String description;
  final String address;
  final String city;
  final String location;
  final List<String> sports;
  final String sportsString;
  final double slotPrice;
  final int capacity;
  final List<String> amenities;
  final String amenitiesString;
  final List<String> images;
  final String imagesString;
  final String? openingTime;
  final String? closingTime;
  final bool isActive;
  final bool isAvailable;
  final String verificationStatus;
  final double averageRating;
  final int totalBookings;
  final List<Map<String, dynamic>> quickAvailableSlots;
  final String? primaryImage;

  Venue({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.name,
    required this.description,
    required this.address,
    required this.city,
    required this.location,
    required this.sports,
    required this.sportsString,
    required this.slotPrice,
    required this.capacity,
    required this.amenities,
    required this.amenitiesString,
    required this.images,
    required this.imagesString,
    this.openingTime,
    this.closingTime,
    required this.isActive,
    required this.isAvailable,
    required this.verificationStatus,
    required this.averageRating,
    required this.totalBookings,
    required this.quickAvailableSlots,
    this.primaryImage,
  });

  static int _toInt(dynamic v, [int d = 0]) {
    if (v == null) return d;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? d;
    return d;
  }

  static double _toDouble(dynamic v, [double d = 0.0]) {
    if (v == null) return d;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? d;
    return d;
  }

  static List<String> _toStrList(dynamic v) {
    if (v == null) return [];
    if (v is List) return v.map((e) => e.toString()).toList();
    return [];
  }

  factory Venue.fromJson(Map<String, dynamic> json) {
    return Venue(
      id: _toInt(json['id']),
      ownerId: _toInt(json['owner_id']),
      ownerName: json['owner_name']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      sports: _toStrList(json['sports']),
      sportsString: json['sports_string']?.toString() ?? '',
      slotPrice: _toDouble(json['slot_price']),
      capacity: _toInt(json['capacity']),
      amenities: _toStrList(json['amenities']),
      amenitiesString: json['amenities_string']?.toString() ?? '',
      images: _toStrList(json['images']),
      imagesString: json['images_string']?.toString() ?? '',
      openingTime: json['opening_time']?.toString(),
      closingTime: json['closing_time']?.toString(),
      isActive: json['is_active'] == true,
      isAvailable: json['is_available'] == true,
      verificationStatus: json['verification_status']?.toString() ?? 'pending',
      averageRating: _toDouble(json['average_rating']),
      totalBookings: _toInt(json['total_bookings']),
      quickAvailableSlots: (json['quick_available_slots'] as List<dynamic>? ?? [])
          .map((slot) => Map<String, dynamic>.from(slot as Map))
          .toList(),
      primaryImage: json['primary_image']?.toString(),
    );
  }
}

class VenueBooking {
  final int id;
  final int venueId;
  final String venueName;
  final int? matchId;
  final String? matchTitle;
  final int bookedById;
  final String bookedByName;
  final String date;
  final String startTime;
  final String endTime;
  final int hours;
  final double totalPrice;
  final String status;
  final String paymentStatus;
  final String notes;
  final DateTime createdAt;

  VenueBooking({
    required this.id,
    required this.venueId,
    required this.venueName,
    this.matchId,
    this.matchTitle,
    required this.bookedById,
    required this.bookedByName,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.hours,
    required this.totalPrice,
    required this.status,
    this.paymentStatus = 'unpaid',
    required this.notes,
    required this.createdAt,
  });

  factory VenueBooking.fromJson(Map<String, dynamic> json) {
    return VenueBooking(
      id: json['id'] ?? 0,
      venueId: json['venue_id'] ?? 0,
      venueName: json['venue_name'] ?? '',
      matchId: json['match_id'],
      matchTitle: json['match_title'],
      bookedById: json['booked_by_id'] ?? 0,
      bookedByName: json['booked_by_name'] ?? '',
      date: json['date'] ?? '',
      startTime: json['start_time'] ?? '',
      endTime: json['end_time'] ?? '',
      hours: json['hours'] ?? 1,
      totalPrice: (json['total_price'] ?? 0).toDouble(),
      status: json['status'] ?? 'pending',
      paymentStatus: json['payment_status'] ?? 'unpaid',
      notes: json['notes'] ?? '',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}

class VenueService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, String>?> _getAuth() async {
    try {
      final session = await AuthService.getSession();
      final token = session?['token'] as String?;
      if (token == null) return null;
      return {
        'Content-Type': 'application/json',
        'Authorization': 'Token $token',
      };
    } catch (e) {
      return null;
    }
  }

  static Future<List<Venue>> getVenues({
    String? sport,
    String? city,
    bool availableOnly = true,
    bool forceRefresh = false,
  }) async {
    final cacheKey =
        '${CacheService.venuesKey}_${sport ?? ''}_${city ?? ''}_$availableOnly';
    try {
      final venuesJson = await CacheService.cachedFetch<List<dynamic>>(
        key: cacheKey,
        cacheMinutes: 10,
        forceRefresh: forceRefresh,
        fetch: () async {
          String url = '$_baseUrl/venues/?available=${availableOnly.toString()}';
          if (sport != null && sport.isNotEmpty) {
            url += '&sport=$sport';
          }
          if (city != null && city.isNotEmpty) {
            url += '&city=$city';
          }

          final response = await http.get(Uri.parse(url)).timeout(ApiConfig.httpTimeout);
          if (response.statusCode != 200) {
            throw Exception('Server returned ${response.statusCode}');
          }
          final data = json.decode(response.body);
          return List<dynamic>.from(data['venues'] ?? const []);
        },
      );

      return venuesJson.map((v) => Venue.fromJson(v)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<Venue?> getVenue(int venueId) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/venues/$venueId/')).timeout(ApiConfig.httpTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return Venue.fromJson(data['venue']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<List<Venue>> getMyVenues() async {
    try {
      final headers = await _getAuth();
      if (headers == null) return [];

      final response = await http.get(
        Uri.parse('$_baseUrl/venues/my/'),
        headers: headers,
      ).timeout(ApiConfig.httpTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> venuesJson = data['venues'] ?? [];
        return venuesJson.map((v) => Venue.fromJson(v)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> createVenue({
    required String name,
    required String address,
    required String city,
    String description = '',
    String sports = '',
    double slotPrice = 0,
    int capacity = 0,
    String amenities = '',
    String? openingTime,
    String? closingTime,
    String? imagePath,
  }) async {
    try {
      final session = await AuthService.getSession();
      final token = session?['token'] as String?;
      if (token == null) return {'success': false, 'error': 'Not logged in'};

      final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/venues/create/'));
      request.headers['Authorization'] = 'Token $token';

      request.fields['name'] = name;
      request.fields['address'] = address;
      request.fields['city'] = city;
      if (description.isNotEmpty) request.fields['description'] = description;
      if (sports.isNotEmpty) request.fields['sports'] = sports;
      request.fields['slot_price'] = slotPrice.toString();
      request.fields['capacity'] = capacity.toString();
      if (amenities.isNotEmpty) request.fields['amenities'] = amenities;
      if (openingTime != null) request.fields['opening_time'] = openingTime;
      if (closingTime != null) request.fields['closing_time'] = closingTime;

      if (imagePath != null) {
        request.files.add(await http.MultipartFile.fromPath('image', imagePath, contentType: imageMediaType(imagePath)));
      }

      final streamed = await request.send().timeout(ApiConfig.httpTimeout);
      final response = await http.Response.fromStream(streamed);
      final dynamic data = json.decode(response.body);

      if (response.statusCode == 201) {
        final venueMap = (data is Map) ? data['venue'] : null;
        if (venueMap is Map<String, dynamic>) {
          return {'success': true, 'venue': Venue.fromJson(venueMap)};
        }
        return {'success': true};
      }

      String? errMsg;
      if (data is Map) {
        errMsg = data['error']?.toString();
      } else if (data is String) {
        errMsg = data;
      }
      return {'success': false, 'error': errMsg ?? 'Failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error'};
    }
  }

  static Future<Map<String, dynamic>> bookVenue({
    required int venueId,
    required String date,
    required String startTime,
    required String endTime,
    int? matchId,
    String notes = '',
  }) async {
    try {
      final headers = await _getAuth();
      if (headers == null) return {'success': false, 'error': 'Not logged in'};

      final response = await http.post(
        Uri.parse('$_baseUrl/venues/book/'),
        headers: headers,
        body: json.encode({
          'venue_id': venueId,
          'date': date,
          'start_time': startTime,
          'end_time': endTime,
          'match_id': matchId,
          'notes': notes,
        }),
      ).timeout(ApiConfig.httpTimeout);

      final data = json.decode(response.body);

      if (response.statusCode == 201) {
        CacheService.invalidateVenues();
        return {
          'success': true,
          'booking': VenueBooking.fromJson(data['booking']),
        };
      }
      return {'success': false, 'error': data['error'] ?? 'Failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error'};
    }
  }

  static Future<List<VenueBooking>> getVenueBookings({
    bool asOwner = true,
    int? venueId,
    String? status,
    String? scope,
  }) async {
    try {
      final headers = await _getAuth();
      if (headers == null) return [];

      var url = '$_baseUrl/venues/bookings/?as=${asOwner ? 'owner' : 'booker'}';
      if (venueId != null) url += '&venue_id=$venueId';
      if (status != null && status.isNotEmpty) url += '&status=$status';
      if (scope != null && scope.isNotEmpty) url += '&scope=$scope';

      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(ApiConfig.httpTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> bookingsJson = data['bookings'] ?? [];
        return bookingsJson.map((b) => VenueBooking.fromJson(b)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Owner: day-by-day slot grid for a venue.
  static Future<Map<String, dynamic>> getSchedule(int venueId, {String? from, String? to}) async {
    try {
      final headers = await _getAuth();
      if (headers == null) return {};
      var url = '$_baseUrl/venues/$venueId/schedule/';
      final params = <String>[];
      if (from != null) params.add('from=$from');
      if (to != null) params.add('to=$to');
      if (params.isNotEmpty) url += '?${params.join('&')}';
      final response = await http.get(Uri.parse(url), headers: headers).timeout(ApiConfig.httpTimeout);
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  /// Public: free/booked slots for a venue on a date.
  static Future<Map<String, dynamic>> getAvailability(int venueId, String date) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/venues/$venueId/availability/?date=$date'))
          .timeout(ApiConfig.httpTimeout);
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  /// Public: availability for a date range (week strip).
  static Future<Map<String, dynamic>> getAvailabilityRange(
      int venueId, String from, String to) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/venues/$venueId/availability/?from=$from&to=$to'))
          .timeout(ApiConfig.httpTimeout);
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  /// Owner: revenue breakdown (per venue + per month).
  static Future<Map<String, dynamic>> getRevenue() async {
    try {
      final headers = await _getAuth();
      if (headers == null) return {};
      final response = await http
          .get(Uri.parse('$_baseUrl/venues/revenue/'), headers: headers)
          .timeout(ApiConfig.httpTimeout);
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      return {};
    }
  }
  static Future<Map<String, dynamic>> updateBookingStatus({
    required int bookingId,
    required String status,
  }) async {
    try {
      final headers = await _getAuth();
      if (headers == null) return {'success': false, 'error': 'Not logged in'};

      final response = await http.post(
        Uri.parse('$_baseUrl/venues/bookings/$bookingId/'),
        headers: headers,
        body: json.encode({'status': status}),
      ).timeout(ApiConfig.httpTimeout);

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        CacheService.invalidateVenues();
        return {
          'success': true,
          'booking': VenueBooking.fromJson(data['booking']),
        };
      }
      return {'success': false, 'error': data['error'] ?? 'Failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error'};
    }
  }

  /// Start a Chapa checkout for a pending venue booking.
  static Future<Map<String, dynamic>> payBooking({
    required int bookingId,
    String returnUrl = '',
  }) async {
    try {
      final headers = await _getAuth();
      if (headers == null) return {'success': false, 'error': 'Not logged in'};
      final response = await http.post(
        Uri.parse('$_baseUrl/payments/venue/initialize/'),
        headers: headers,
        body: json.encode({'booking_id': bookingId, 'return_url': returnUrl}),
      ).timeout(ApiConfig.httpTimeout);
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        CacheService.invalidateVenues();
        return {'success': true, ...data};
      }
      return {'success': false, 'error': data['message'] ?? data['error'] ?? 'Payment failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error'};
    }
  }

  /// Availability for a single date (returns the day's slot list).
  static Future<List<Map<String, dynamic>>> getSlots(int venueId, String date) async {
    final data = await getAvailability(venueId, date);
    return (data['slots'] as List<dynamic>? ?? const [])
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();
  }
}
