/// Shared validation helpers used by write validators.
///
/// Provides common checks for text, numeric ranges, minimums, and beat units.
mixin ValidationHelpers {
  static const Set<int> supportedBeatUnits = {1, 2, 4, 8, 16, 32};

  void requireText({
    required String? value,
    required String label,
    required String message,
  }) {
    if (value != null && value.trim().isNotEmpty) {
      return;
    }

    throw ArgumentError.value(value, label, message);
  }

  void requireInRange({
    required int value,
    required int minimum,
    required int maximum,
    required String label,
  }) {
    if (value >= minimum && value <= maximum) {
      return;
    }

    throw ArgumentError.value(
      value,
      label,
      '$label must be between $minimum and $maximum.',
    );
  }

  void requireMinimum({
    required int value,
    required int minimum,
    required String label,
    String? message,
  }) {
    if (value >= minimum) {
      return;
    }

    throw ArgumentError.value(
      value,
      label,
      message ?? '$label must be greater than or equal to $minimum.',
    );
  }

  void requireBeatUnit(int beatUnit, String label) {
    if (supportedBeatUnits.contains(beatUnit)) {
      return;
    }

    throw ArgumentError.value(
      beatUnit,
      label,
      'Beat unit must be one of ${supportedBeatUnits.toList()}.',
    );
  }
}
