import '../../core/phone/supported_country.dart';

/// The signed-in customer's account, as the API describes it.
///
/// [id] is the server's UUID, never a sequential database key — sequential ids
/// are enumerable and disclose how many customers exist.
class Customer {
  const Customer({
    required this.id,
    required this.firstName,
    required this.phone,
    this.lastName,
    this.email,
    this.phoneVerified = false,
    this.emailVerified = false,
    this.status = 'active',
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: json['id'] as String? ?? '',
    firstName: json['first_name'] as String? ?? '',
    lastName: json['last_name'] as String?,
    phone: json['phone'] as String? ?? '',
    email: json['email'] as String?,
    phoneVerified: json['phone_verified'] as bool? ?? false,
    emailVerified: json['email_verified'] as bool? ?? false,
    status: json['status'] as String? ?? 'active',
  );

  final String id;
  final String firstName;
  final String? lastName;

  /// E.164, e.g. `+919876543210`.
  final String phone;
  final String? email;
  final bool phoneVerified;
  final bool emailVerified;
  final String status;

  String get fullName {
    final String last = lastName?.trim() ?? '';
    return last.isEmpty ? firstName.trim() : '${firstName.trim()} $last';
  }

  /// The number as it should be shown back to the customer.
  ///
  /// Even to the account's owner: a phone screen is read over shoulders, and a
  /// full number in a screenshot sent to support is a number in a support
  /// ticket. The last four digits are enough to confirm which number it is.
  ///
  /// The format deliberately matches `PhoneNumber::masked()` on the server, so
  /// the number reads identically on the OTP screen (where the server produced
  /// the mask) and on the profile (where this did). Two different maskings of
  /// one number look like two different numbers.
  String get maskedPhone => maskE164(phone);

  /// Serialised into secure storage so a cold start can render a name before the
  /// network answers. Nothing sensitive lives here beyond what the profile
  /// screen already shows.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'first_name': firstName,
    'last_name': lastName,
    'phone': phone,
    'email': email,
    'phone_verified': phoneVerified,
    'email_verified': emailVerified,
    'status': status,
  };
}
