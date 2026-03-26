import 'package:equatable/equatable.dart';

/// User-editable metadata for a recorded flight.
///
/// Stored in the existing `flight_meta` key-value table using keys
/// prefixed with `user_`. No schema changes required.
class FlightMetadata extends Equatable {
  const FlightMetadata({
    this.name,
    this.notes,
    this.tags = const [],
    this.rating,
  });

  /// User-assigned name (e.g. "Morning survey at farm").
  final String? name;

  /// Free-form notes about the flight.
  final String? notes;

  /// Tags for categorisation (e.g. ["survey", "windy"]).
  final List<String> tags;

  /// Optional 1-5 rating.
  final int? rating;

  bool get hasName => name != null && name!.isNotEmpty;
  bool get hasNotes => notes != null && notes!.isNotEmpty;
  bool get hasTags => tags.isNotEmpty;

  FlightMetadata copyWith({
    String? name,
    String? notes,
    List<String>? tags,
    int? rating,
  }) {
    return FlightMetadata(
      name: name ?? this.name,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      rating: rating ?? this.rating,
    );
  }

  @override
  List<Object?> get props => [name, notes, tags, rating];
}
