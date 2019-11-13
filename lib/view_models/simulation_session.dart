import 'dart:async' show Timer;
import 'package:aqua/models/card.dart';
import 'package:aqua/models/player_hand_setting.dart';
import 'package:aqua/models/simulation_result.dart';
import 'package:aqua/models/simulator.dart';
import 'package:aqua/services/simulation_isolate_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class SimulationSession {
  SimulationSession.initial({@required this.analytics})
      : assert(analytics != null),
        board = ValueNotifier(<Card>[null, null, null, null, null]),
        playerHandSettings = ValueNotifier([]),
        results = ValueNotifier([]),
        error = ValueNotifier(null),
        progress = ValueNotifier(0) {
    board.addListener(_onSituationChanged);
    playerHandSettings.addListener(_onSituationChanged);
  }

  final FirebaseAnalytics analytics;

  final ValueNotifier<List<Card>> board;

  final ValueNotifier<List<PlayerHandSetting>> playerHandSettings;

  final ValueNotifier<List<SimulationResult>> results;

  final ValueNotifier<SimulationCancelException> error;

  final ValueNotifier<double> progress;

  SimulationIsolateService _simulationIsolateService;

  Timer _timer;

  void _onSituationChanged() {
    if (_timer != null) {
      _timer.cancel();
      _timer = null;
    }

    _timer = Timer(Duration(milliseconds: 600), () async {
      _timer = null;

      if (_simulationIsolateService != null) {
        _simulationIsolateService.dispose();

        analytics.logEvent(name: "end_simulation", parameters: {
          "number_of_players": playerHandSettings.value.length,
          "number_of_cards_in_board": board.value.length,
        });
      }

      results.value = [];

      _simulationIsolateService = SimulationIsolateService();

      await _simulationIsolateService.initialize();

      _simulationIsolateService
        ..onSimulated.listen(
          (details) {
            error.value = null;
            results.value = details.results;
            progress.value =
                details.timesSimulated / details.timesWillBeSimulated;
          },
          onError: (error) {
            _simulationIsolateService.dispose();
            _simulationIsolateService = null;

            if (error is SimulationCancelException) {
              debugPrint("simulation canceled: ${error.runtimeType}");

              this.error.value = error;

              return;
            }

            throw error;
          },
        )
        ..onSimulated.first.then((_) {
          analytics
              .logEvent(name: "receive_simulation_first_tick", parameters: {
            "number_of_players": playerHandSettings.value.length,
            "number_of_cards_in_board": board.value.length,
          });
        })
        ..requestSimulation(
          playerHandSettings: playerHandSettings.value,
          board: board.value,
        );
    });
  }
}
