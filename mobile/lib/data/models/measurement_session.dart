import 'physiological_input_packet.dart';
import 'stress_prediction.dart';

/// One completed check-in: the features captured plus the estimate produced.
///
/// A measurement may later be linked to the game the user played afterwards,
/// which is what closes the biofeedback loop in History.
class MeasurementSession {
  const MeasurementSession({
    required this.id,
    required this.prediction,
    required this.recordedAt,
    required this.durationSeconds,
    this.packet,
    this.gameSessionId,
    this.gameName,
    this.gameScore,
    this.postStressLevel,
  });

  final String id;
  final StressPrediction prediction;
  final DateTime recordedAt;
  final int durationSeconds;

  /// The full input packet this reading was produced from.
  ///
  /// Nullable because sessions saved before this field existed do not have
  /// one, and because the prediction itself only ever needed the narrow
  /// cardiovascular view. Keeping the whole packet is what lets History show
  /// GSR, movement and battery for a reading, and what a future model needs in
  /// order to be re-run over past data.
  final PhysiologicalInputPacket? packet;

  /// Where the values came from. Falls back to the prediction's own tag for
  /// sessions recorded before packets were stored.
  PhysiologicalSource get source =>
      packet?.source ?? PhysiologicalSource.fromTag(prediction.source);

  /// Set once the user plays a game from this measurement's result screen.
  final String? gameSessionId;
  final String? gameName;
  final int? gameScore;

  /// Simulated post-game level, 1..5. Null until a game is played.
  final int? postStressLevel;

  bool get hasGame => gameSessionId != null;

  MeasurementSession copyWith({
    PhysiologicalInputPacket? packet,
    String? gameSessionId,
    String? gameName,
    int? gameScore,
    int? postStressLevel,
  }) {
    return MeasurementSession(
      id: id,
      prediction: prediction,
      recordedAt: recordedAt,
      durationSeconds: durationSeconds,
      packet: packet ?? this.packet,
      gameSessionId: gameSessionId ?? this.gameSessionId,
      gameName: gameName ?? this.gameName,
      gameScore: gameScore ?? this.gameScore,
      postStressLevel: postStressLevel ?? this.postStressLevel,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'prediction': prediction.toJson(),
    'recordedAt': recordedAt.toIso8601String(),
    'durationSeconds': durationSeconds,
    if (packet != null) 'packet': packet!.toJson(),
    'gameSessionId': gameSessionId,
    'gameName': gameName,
    'gameScore': gameScore,
    'postStressLevel': postStressLevel,
  };

  factory MeasurementSession.fromJson(Map<String, dynamic> json) =>
      MeasurementSession(
        id: json['id'] as String,
        prediction: StressPrediction.fromJson(
          Map<String, dynamic>.from(json['prediction'] as Map),
        ),
        recordedAt: DateTime.parse(json['recordedAt'] as String),
        durationSeconds: (json['durationSeconds'] as num).toInt(),
        packet: json['packet'] == null
            ? null
            : PhysiologicalInputPacket.fromJson(
                Map<String, dynamic>.from(json['packet'] as Map),
              ),
        gameSessionId: json['gameSessionId'] as String?,
        gameName: json['gameName'] as String?,
        gameScore: (json['gameScore'] as num?)?.toInt(),
        postStressLevel: (json['postStressLevel'] as num?)?.toInt(),
      );
}
