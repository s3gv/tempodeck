enum Subdivision { one, two, three, four, five, six, seven, eight }

extension SubdivisionExtension on Subdivision {
  int get pulseCount => index + 1;

  String get displayLabel => switch (this) {
    Subdivision.one => 'Off',
    _ => '+${pulseCount - 1}',
  };
}
