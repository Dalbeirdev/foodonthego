import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/domain/models/saved_address.dart';
import 'package:foodonthego/features/addresses/widgets/postal_code_rules.dart';

void main() {
  group('SavedAddress parsing', () {
    test('reads what the API sends', () {
      final SavedAddress address = SavedAddress.fromJson(<String, dynamic>{
        'id': 'addr-1',
        'type': 'WORK',
        'label': 'Work',
        'address_line_1': 'Connaught Place',
        'address_line_2': null,
        'landmark': null,
        'city': 'New Delhi',
        'state': 'Delhi',
        'postal_code': '110001',
        'country_code': 'IN',
        'formatted_address': 'Connaught Place, New Delhi, Delhi 110001, IN',
        'latitude': null,
        'longitude': null,
        'place_id': null,
        'is_default': true,
      });

      expect(address.type, AddressType.work);
      expect(address.isDefault, isTrue);
      expect(address.localityLine, 'New Delhi, Delhi 110001');
    });

    test('survives fields the API omitted', () {
      final SavedAddress address = SavedAddress.fromJson(
        const <String, dynamic>{
          'id': 'addr-1',
          'type': 'HOME',
          'address_line_1': 'A Road',
          'city': 'Jaipur',
          'state': 'Rajasthan',
          'country_code': 'IN',
        },
      );

      expect(address.postalCode, isNull);
      expect(address.landmark, isNull);
      expect(address.isDefault, isFalse);
      expect(address.localityLine, 'Jaipur, Rajasthan');
    });

    test(
      'a type this build has never seen falls back rather than crashing',
      () {
        final SavedAddress address = SavedAddress.fromJson(
          const <String, dynamic>{
            'id': 'a',
            'type': 'WAREHOUSE',
            'address_line_1': 'A',
            'city': 'B',
            'state': 'C',
            'country_code': 'IN',
          },
        );

        // A newer server must not break an older app, and "Other" is the honest
        // description of a category it does not know.
        expect(address.type, AddressType.other);
      },
    );

    test('coordinates arrive as strings and stay precise', () {
      final SavedAddress address = SavedAddress.fromJson(
        const <String, dynamic>{
          'id': 'a',
          'type': 'HOME',
          'address_line_1': 'A',
          'city': 'B',
          'state': 'C',
          'country_code': 'IN',
          'latitude': '28.5602000',
          'longitude': '77.2043000',
        },
      );

      expect(address.latitude, closeTo(28.5602, 0.0000001));
      expect(address.hasCoordinates, isTrue);
    });

    test('absent coordinates are null, never zero', () {
      final SavedAddress address = SavedAddress.fromJson(
        const <String, dynamic>{
          'id': 'a',
          'type': 'HOME',
          'address_line_1': 'A',
          'city': 'B',
          'state': 'C',
          'country_code': 'IN',
        },
      );

      // 0,0 is a real place in the Gulf of Guinea; a route to it is a route into
      // the Atlantic.
      expect(address.latitude, isNull);
      expect(address.longitude, isNull);
      expect(address.hasCoordinates, isFalse);
    });

    test('the short address joins only the lines that exist', () {
      expect(
        SavedAddress.fromJson(const <String, dynamic>{
          'id': 'a',
          'type': 'HOME',
          'address_line_1': 'Flat 204',
          'address_line_2': '  ',
          'city': 'B',
          'state': 'C',
          'country_code': 'IN',
        }).shortAddress,
        'Flat 204',
      );
    });
  });

  group('AddressDraft payload', () {
    AddressDraft draft({
      String? label,
      String? line2,
      String? landmark,
      String? postal = '110016',
      bool isDefault = false,
    }) => AddressDraft(
      type: AddressType.home,
      label: label,
      addressLine1: ' 12 Green Park Road ',
      addressLine2: line2,
      landmark: landmark,
      city: ' New Delhi ',
      state: 'Delhi',
      postalCode: postal,
      countryCode: 'in',
      isDefault: isDefault,
    );

    test('trims every field on the way out', () {
      final Map<String, dynamic> json = draft().toJson();

      expect(json['address_line_1'], '12 Green Park Road');
      expect(json['city'], 'New Delhi');
    });

    test('blank optional fields are sent as absent, not empty', () {
      final Map<String, dynamic> json = draft(
        line2: '  ',
        landmark: '',
      ).toJson();

      // "" is not a landmark, and storing one makes every later null check wrong.
      expect(json['address_line_2'], isNull);
      expect(json['landmark'], isNull);
    });

    test(
      'a blank label is omitted so the server can name it from the type',
      () {
        expect(draft(label: '   ').toJson().containsKey('label'), isFalse);
        expect(
          draft(label: "Parents' House").toJson()['label'],
          "Parents' House",
        );
      },
    );

    test('the country code is upper-cased', () {
      expect(draft().toJson()['country_code'], 'IN');
    });

    test('the default preference is always stated', () {
      expect(draft().toJson()['is_default'], isFalse);
      expect(draft(isDefault: true).toJson()['is_default'], isTrue);
    });

    test('a null postal code stays null rather than becoming a string', () {
      expect(draft(postal: null).toJson()['postal_code'], isNull);
    });
  });

  group('postal code rules', () {
    test('India: six digits, first not zero, and a numeric keypad', () {
      final PostalCodeRule india = PostalCodeRule.forCountry('IN');

      expect(india.required, isTrue);
      expect(india.isNumeric, isTrue);
      expect(india.matches('110016'), isTrue);
      expect(india.matches('11001'), isFalse);
      expect(india.matches('010016'), isFalse);
    });

    test('the UK is alphanumeric and must not get a number pad', () {
      final PostalCodeRule uk = PostalCodeRule.forCountry('GB');

      // A UK postcode typed on a numeric keypad is impossible to enter.
      expect(uk.isNumeric, isFalse);
      expect(uk.matches('SW1A 1AA'), isTrue);
      expect(uk.matches('110016'), isFalse);
    });

    test('a country with no postcode system does not demand one', () {
      final PostalCodeRule uae = PostalCodeRule.forCountry('AE');

      expect(uae.required, isFalse);
    });

    test('an unlisted country is accepted rather than blocked', () {
      final PostalCodeRule france = PostalCodeRule.forCountry('FR');

      // Blocking would make an address impossible to save, which is worse than
      // a postcode nobody checked. The server re-validates either way.
      expect(france.required, isFalse);
      expect(france.matches('75008'), isTrue);
      expect(france.matches('D02 AF30'), isTrue);
    });

    test('the client rules mirror the server, never more strictly', () {
      // Any value the client accepts must be one the server could accept too;
      // the reverse is fine. A client stricter than the server rejects addresses
      // that are actually valid.
      expect(PostalCodeRule.forCountry('IN').matches('560001'), isTrue);
      expect(PostalCodeRule.forCountry('US').matches('10001-1234'), isTrue);
    });
  });

  group('error codes', () {
    test('the Module 04 codes are known to this build', () {
      expect(
        ApiErrorCode.fromWire('ADDRESS_LIMIT_REACHED'),
        ApiErrorCode.addressLimitReached,
      );
      expect(
        ApiErrorCode.fromWire('ADDRESS_NOT_FOUND'),
        ApiErrorCode.addressNotFound,
      );
    });

    test('neither is retryable — the caller has to change something', () {
      expect(ApiErrorCode.addressLimitReached.isRetryable, isFalse);
      expect(ApiErrorCode.addressNotFound.isRetryable, isFalse);
    });
  });

  group('address types', () {
    test('only Other makes the customer name the place', () {
      expect(AddressType.other.needsCustomLabel, isTrue);
      expect(AddressType.home.needsCustomLabel, isFalse);
      expect(AddressType.work.needsCustomLabel, isFalse);
    });

    test('the wire values match the server enum', () {
      expect(AddressType.home.wire, 'HOME');
      expect(AddressType.work.wire, 'WORK');
      expect(AddressType.other.wire, 'OTHER');
    });
  });
}
