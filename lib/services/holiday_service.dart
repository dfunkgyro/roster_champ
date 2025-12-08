import 'package:uuid/uuid.dart';
import '../models.dart';

/// Service for managing bank holidays and school holidays by country
class HolidayService {
  static final HolidayService instance = HolidayService._internal();
  HolidayService._internal();

  final _uuid = const Uuid();

  /// Get bank holidays for a specific country and year
  List<BankHoliday> getBankHolidays(CountryCode country, int year) {
    switch (country) {
      case CountryCode.uk:
        return _getUKBankHolidays(year);
      case CountryCode.us:
        return _getUSBankHolidays(year);
      case CountryCode.au:
        return _getAUBankHolidays(year);
      case CountryCode.ca:
        return _getCABankHolidays(year);
      case CountryCode.nz:
        return _getNZBankHolidays(year);
      case CountryCode.ie:
        return _getIEBankHolidays(year);
      case CountryCode.de:
        return _getDEBankHolidays(year);
      case CountryCode.fr:
        return _getFRBankHolidays(year);
      case CountryCode.es:
        return _getESBankHolidays(year);
      case CountryCode.it:
        return _getITBankHolidays(year);
    }
  }

  /// Get school holidays for a specific country and year
  List<SchoolHoliday> getSchoolHolidays(CountryCode country, int year,
      {String? region}) {
    switch (country) {
      case CountryCode.uk:
        return _getUKSchoolHolidays(year, region);
      case CountryCode.us:
        return _getUSSchoolHolidays(year, region);
      case CountryCode.au:
        return _getAUSchoolHolidays(year, region);
      case CountryCode.ca:
        return _getCASchoolHolidays(year, region);
      case CountryCode.nz:
        return _getNZSchoolHolidays(year, region);
      default:
        return [];
    }
  }

  // ============================================================================
  // UK HOLIDAYS
  // ============================================================================

  List<BankHoliday> _getUKBankHolidays(int year) {
    return [
      BankHoliday(
        id: _uuid.v4(),
        name: 'New Year\'s Day',
        date: DateTime(year, 1, 1),
        country: CountryCode.uk,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Good Friday',
        date: _calculateEaster(year).subtract(const Duration(days: 2)),
        country: CountryCode.uk,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Easter Monday',
        date: _calculateEaster(year).add(const Duration(days: 1)),
        country: CountryCode.uk,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Early May Bank Holiday',
        date: _getFirstMondayOfMonth(year, 5),
        country: CountryCode.uk,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Spring Bank Holiday',
        date: _getLastMondayOfMonth(year, 5),
        country: CountryCode.uk,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Summer Bank Holiday',
        date: _getLastMondayOfMonth(year, 8),
        country: CountryCode.uk,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Christmas Day',
        date: DateTime(year, 12, 25),
        country: CountryCode.uk,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Boxing Day',
        date: DateTime(year, 12, 26),
        country: CountryCode.uk,
      ),
    ];
  }

  List<SchoolHoliday> _getUKSchoolHolidays(int year, String? region) {
    return [
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'Christmas Holiday',
        startDate: DateTime(year - 1, 12, 20),
        endDate: DateTime(year, 1, 5),
        country: CountryCode.uk,
        region: region,
        year: year,
      ),
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'February Half Term',
        startDate: DateTime(year, 2, 12),
        endDate: DateTime(year, 2, 16),
        country: CountryCode.uk,
        region: region,
        year: year,
      ),
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'Easter Holiday',
        startDate: DateTime(year, 4, 1),
        endDate: DateTime(year, 4, 14),
        country: CountryCode.uk,
        region: region,
        year: year,
      ),
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'May Half Term',
        startDate: DateTime(year, 5, 27),
        endDate: DateTime(year, 5, 31),
        country: CountryCode.uk,
        region: region,
        year: year,
      ),
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'Summer Holiday',
        startDate: DateTime(year, 7, 20),
        endDate: DateTime(year, 9, 2),
        country: CountryCode.uk,
        region: region,
        year: year,
      ),
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'October Half Term',
        startDate: DateTime(year, 10, 21),
        endDate: DateTime(year, 10, 25),
        country: CountryCode.uk,
        region: region,
        year: year,
      ),
    ];
  }

  // ============================================================================
  // US HOLIDAYS
  // ============================================================================

  List<BankHoliday> _getUSBankHolidays(int year) {
    return [
      BankHoliday(
        id: _uuid.v4(),
        name: 'New Year\'s Day',
        date: DateTime(year, 1, 1),
        country: CountryCode.us,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Martin Luther King Jr. Day',
        date: _getNthWeekdayOfMonth(year, 1, DateTime.monday, 3),
        country: CountryCode.us,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Presidents\' Day',
        date: _getNthWeekdayOfMonth(year, 2, DateTime.monday, 3),
        country: CountryCode.us,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Memorial Day',
        date: _getLastMondayOfMonth(year, 5),
        country: CountryCode.us,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Independence Day',
        date: DateTime(year, 7, 4),
        country: CountryCode.us,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Labor Day',
        date: _getFirstMondayOfMonth(year, 9),
        country: CountryCode.us,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Columbus Day',
        date: _getNthWeekdayOfMonth(year, 10, DateTime.monday, 2),
        country: CountryCode.us,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Veterans Day',
        date: DateTime(year, 11, 11),
        country: CountryCode.us,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Thanksgiving',
        date: _getNthWeekdayOfMonth(year, 11, DateTime.thursday, 4),
        country: CountryCode.us,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Christmas Day',
        date: DateTime(year, 12, 25),
        country: CountryCode.us,
      ),
    ];
  }

  List<SchoolHoliday> _getUSSchoolHolidays(int year, String? region) {
    return [
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'Winter Break',
        startDate: DateTime(year - 1, 12, 20),
        endDate: DateTime(year, 1, 3),
        country: CountryCode.us,
        region: region,
        year: year,
      ),
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'Spring Break',
        startDate: DateTime(year, 3, 25),
        endDate: DateTime(year, 3, 29),
        country: CountryCode.us,
        region: region,
        year: year,
      ),
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'Summer Break',
        startDate: DateTime(year, 6, 15),
        endDate: DateTime(year, 8, 25),
        country: CountryCode.us,
        region: region,
        year: year,
      ),
    ];
  }

  // ============================================================================
  // AUSTRALIA HOLIDAYS
  // ============================================================================

  List<BankHoliday> _getAUBankHolidays(int year) {
    return [
      BankHoliday(
        id: _uuid.v4(),
        name: 'New Year\'s Day',
        date: DateTime(year, 1, 1),
        country: CountryCode.au,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Australia Day',
        date: DateTime(year, 1, 26),
        country: CountryCode.au,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Good Friday',
        date: _calculateEaster(year).subtract(const Duration(days: 2)),
        country: CountryCode.au,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Easter Saturday',
        date: _calculateEaster(year).subtract(const Duration(days: 1)),
        country: CountryCode.au,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Easter Monday',
        date: _calculateEaster(year).add(const Duration(days: 1)),
        country: CountryCode.au,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Anzac Day',
        date: DateTime(year, 4, 25),
        country: CountryCode.au,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Queen\'s Birthday',
        date: _getNthWeekdayOfMonth(year, 6, DateTime.monday, 2),
        country: CountryCode.au,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Christmas Day',
        date: DateTime(year, 12, 25),
        country: CountryCode.au,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Boxing Day',
        date: DateTime(year, 12, 26),
        country: CountryCode.au,
      ),
    ];
  }

  List<SchoolHoliday> _getAUSchoolHolidays(int year, String? region) {
    return [
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'Summer Holiday',
        startDate: DateTime(year - 1, 12, 20),
        endDate: DateTime(year, 1, 28),
        country: CountryCode.au,
        region: region,
        year: year,
      ),
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'Autumn Break',
        startDate: DateTime(year, 4, 8),
        endDate: DateTime(year, 4, 22),
        country: CountryCode.au,
        region: region,
        year: year,
      ),
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'Winter Break',
        startDate: DateTime(year, 7, 1),
        endDate: DateTime(year, 7, 15),
        country: CountryCode.au,
        region: region,
        year: year,
      ),
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'Spring Break',
        startDate: DateTime(year, 9, 23),
        endDate: DateTime(year, 10, 7),
        country: CountryCode.au,
        region: region,
        year: year,
      ),
    ];
  }

  // ============================================================================
  // CANADA HOLIDAYS
  // ============================================================================

  List<BankHoliday> _getCABankHolidays(int year) {
    return [
      BankHoliday(
        id: _uuid.v4(),
        name: 'New Year\'s Day',
        date: DateTime(year, 1, 1),
        country: CountryCode.ca,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Good Friday',
        date: _calculateEaster(year).subtract(const Duration(days: 2)),
        country: CountryCode.ca,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Victoria Day',
        date: _getLastMondayBeforeDate(year, 5, 25),
        country: CountryCode.ca,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Canada Day',
        date: DateTime(year, 7, 1),
        country: CountryCode.ca,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Labour Day',
        date: _getFirstMondayOfMonth(year, 9),
        country: CountryCode.ca,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Thanksgiving',
        date: _getNthWeekdayOfMonth(year, 10, DateTime.monday, 2),
        country: CountryCode.ca,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Remembrance Day',
        date: DateTime(year, 11, 11),
        country: CountryCode.ca,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Christmas Day',
        date: DateTime(year, 12, 25),
        country: CountryCode.ca,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Boxing Day',
        date: DateTime(year, 12, 26),
        country: CountryCode.ca,
      ),
    ];
  }

  List<SchoolHoliday> _getCASchoolHolidays(int year, String? region) {
    return [
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'Winter Break',
        startDate: DateTime(year - 1, 12, 20),
        endDate: DateTime(year, 1, 3),
        country: CountryCode.ca,
        region: region,
        year: year,
      ),
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'March Break',
        startDate: DateTime(year, 3, 11),
        endDate: DateTime(year, 3, 15),
        country: CountryCode.ca,
        region: region,
        year: year,
      ),
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'Summer Break',
        startDate: DateTime(year, 6, 25),
        endDate: DateTime(year, 9, 3),
        country: CountryCode.ca,
        region: region,
        year: year,
      ),
    ];
  }

  // ============================================================================
  // NEW ZEALAND HOLIDAYS
  // ============================================================================

  List<BankHoliday> _getNZBankHolidays(int year) {
    return [
      BankHoliday(
        id: _uuid.v4(),
        name: 'New Year\'s Day',
        date: DateTime(year, 1, 1),
        country: CountryCode.nz,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Day after New Year\'s Day',
        date: DateTime(year, 1, 2),
        country: CountryCode.nz,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Waitangi Day',
        date: DateTime(year, 2, 6),
        country: CountryCode.nz,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Good Friday',
        date: _calculateEaster(year).subtract(const Duration(days: 2)),
        country: CountryCode.nz,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Easter Monday',
        date: _calculateEaster(year).add(const Duration(days: 1)),
        country: CountryCode.nz,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Anzac Day',
        date: DateTime(year, 4, 25),
        country: CountryCode.nz,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Queen\'s Birthday',
        date: _getFirstMondayOfMonth(year, 6),
        country: CountryCode.nz,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Labour Day',
        date: _getNthWeekdayOfMonth(year, 10, DateTime.monday, 4),
        country: CountryCode.nz,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Christmas Day',
        date: DateTime(year, 12, 25),
        country: CountryCode.nz,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Boxing Day',
        date: DateTime(year, 12, 26),
        country: CountryCode.nz,
      ),
    ];
  }

  List<SchoolHoliday> _getNZSchoolHolidays(int year, String? region) {
    return [
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'Summer Holiday',
        startDate: DateTime(year - 1, 12, 15),
        endDate: DateTime(year, 2, 1),
        country: CountryCode.nz,
        region: region,
        year: year,
      ),
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'Autumn Break',
        startDate: DateTime(year, 4, 13),
        endDate: DateTime(year, 4, 28),
        country: CountryCode.nz,
        region: region,
        year: year,
      ),
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'Winter Break',
        startDate: DateTime(year, 7, 6),
        endDate: DateTime(year, 7, 21),
        country: CountryCode.nz,
        region: region,
        year: year,
      ),
      SchoolHoliday(
        id: _uuid.v4(),
        name: 'Spring Break',
        startDate: DateTime(year, 9, 28),
        endDate: DateTime(year, 10, 13),
        country: CountryCode.nz,
        region: region,
        year: year,
      ),
    ];
  }

  // ============================================================================
  // IRELAND HOLIDAYS
  // ============================================================================

  List<BankHoliday> _getIEBankHolidays(int year) {
    return [
      BankHoliday(
        id: _uuid.v4(),
        name: 'New Year\'s Day',
        date: DateTime(year, 1, 1),
        country: CountryCode.ie,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'St. Patrick\'s Day',
        date: DateTime(year, 3, 17),
        country: CountryCode.ie,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Good Friday',
        date: _calculateEaster(year).subtract(const Duration(days: 2)),
        country: CountryCode.ie,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Easter Monday',
        date: _calculateEaster(year).add(const Duration(days: 1)),
        country: CountryCode.ie,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'May Bank Holiday',
        date: _getFirstMondayOfMonth(year, 5),
        country: CountryCode.ie,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'June Bank Holiday',
        date: _getFirstMondayOfMonth(year, 6),
        country: CountryCode.ie,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'August Bank Holiday',
        date: _getFirstMondayOfMonth(year, 8),
        country: CountryCode.ie,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'October Bank Holiday',
        date: _getLastMondayOfMonth(year, 10),
        country: CountryCode.ie,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'Christmas Day',
        date: DateTime(year, 12, 25),
        country: CountryCode.ie,
      ),
      BankHoliday(
        id: _uuid.v4(),
        name: 'St. Stephen\'s Day',
        date: DateTime(year, 12, 26),
        country: CountryCode.ie,
      ),
    ];
  }

  // Simplified implementations for other countries
  List<BankHoliday> _getDEBankHolidays(int year) => [];
  List<BankHoliday> _getFRBankHolidays(int year) => [];
  List<BankHoliday> _getESBankHolidays(int year) => [];
  List<BankHoliday> _getITBankHolidays(int year) => [];

  // ============================================================================
  // UTILITY METHODS FOR DATE CALCULATIONS
  // ============================================================================

  /// Calculate Easter Sunday using the Computus algorithm
  DateTime _calculateEaster(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }

  /// Get the first Monday of a specific month
  DateTime _getFirstMondayOfMonth(int year, int month) {
    final firstDay = DateTime(year, month, 1);
    final daysUntilMonday = (DateTime.monday - firstDay.weekday + 7) % 7;
    return firstDay.add(Duration(days: daysUntilMonday));
  }

  /// Get the last Monday of a specific month
  DateTime _getLastMondayOfMonth(int year, int month) {
    final lastDay = DateTime(year, month + 1, 0);
    final daysBackToMonday = (lastDay.weekday - DateTime.monday + 7) % 7;
    return lastDay.subtract(Duration(days: daysBackToMonday));
  }

  /// Get the Nth occurrence of a weekday in a month
  DateTime _getNthWeekdayOfMonth(int year, int month, int weekday, int n) {
    final firstDay = DateTime(year, month, 1);
    final daysUntilWeekday = (weekday - firstDay.weekday + 7) % 7;
    final firstOccurrence = firstDay.add(Duration(days: daysUntilWeekday));
    return firstOccurrence.add(Duration(days: 7 * (n - 1)));
  }

  /// Get the last Monday before a specific date
  DateTime _getLastMondayBeforeDate(int year, int month, int day) {
    final targetDate = DateTime(year, month, day);
    var date = targetDate;
    while (date.weekday != DateTime.monday) {
      date = date.subtract(const Duration(days: 1));
    }
    return date;
  }

  /// Check if a date is a bank holiday
  bool isBankHoliday(DateTime date, CountryCode country) {
    final holidays = getBankHolidays(country, date.year);
    return holidays.any((holiday) =>
        holiday.date.year == date.year &&
        holiday.date.month == date.month &&
        holiday.date.day == date.day);
  }

  /// Check if a date falls within school holidays
  bool isSchoolHoliday(DateTime date, CountryCode country, {String? region}) {
    final holidays = getSchoolHolidays(country, date.year, region: region);
    return holidays.any((holiday) =>
        !date.isBefore(holiday.startDate) && !date.isAfter(holiday.endDate));
  }

  /// Get country display name
  String getCountryName(CountryCode country) {
    switch (country) {
      case CountryCode.uk:
        return 'United Kingdom';
      case CountryCode.us:
        return 'United States';
      case CountryCode.au:
        return 'Australia';
      case CountryCode.ca:
        return 'Canada';
      case CountryCode.nz:
        return 'New Zealand';
      case CountryCode.ie:
        return 'Ireland';
      case CountryCode.de:
        return 'Germany';
      case CountryCode.fr:
        return 'France';
      case CountryCode.es:
        return 'Spain';
      case CountryCode.it:
        return 'Italy';
    }
  }
}
