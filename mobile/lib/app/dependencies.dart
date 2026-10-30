import '../data/local/local_store.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/game_session_repository.dart';
import '../data/repositories/local_auth_repository.dart';
import '../data/repositories/local_repositories.dart';
import '../data/repositories/measurement_repository.dart';
import '../data/repositories/user_repository.dart';
import '../domain/ble/ble_service.dart';
import '../domain/ble/flutter_blue_ble_service.dart';
import '../domain/physiological/ble_physiological_data_source.dart';
import '../domain/physiological/demo_physiological_data_source.dart';
import '../domain/physiological/manual_physiological_data_source.dart';
import '../domain/physiological/physiological_data_source.dart';
import '../domain/stress/ml_stress_prediction_service.dart';
import '../domain/stress/stress_prediction_service.dart';
import '../state/auth_controller.dart';
import '../state/device_controller.dart';
import '../state/measurement_mode_controller.dart';
import '../state/settings_controller.dart';
import '../state/stress_controller.dart';

/// The composition root.
///
/// This is the ONLY place that names concrete implementations. Swapping the
/// demo engine for a trained model, or the local repositories for Firebase, is
/// a change to the two factory lines below - nothing in `features/` refers to
/// a concrete class.
///
///   MLStressPredictionService (the trained model, assets/models/)
///   DummyStressPredictionService is still here for tests and offline demos,
///   and is what MLStressPredictionService degrades to if the asset is
///   unloadable.
///
/// All three data sources are constructed and live simultaneously; which one
/// feeds a measurement is [MeasurementModeController.mode], chosen by the user
/// on the Measure screen. Nothing in `features/` names a concrete source.
///
/// See `docs/future_ml_training.md` and `docs/ble_protocol.md`.
class AppDependencies {
  AppDependencies._({
    required this.store,
    required this.authRepository,
    required this.userRepository,
    required this.measurementRepository,
    required this.gameSessionRepository,
    required this.predictionService,
    required this.demoDataSource,
    required this.manualDataSource,
    required this.bleDataSource,
    required this.bleService,
    required this.settingsController,
    required this.authController,
    required this.stressController,
    required this.deviceController,
    required this.modeController,
  });

  final LocalStore store;

  final AuthRepository authRepository;
  final UserRepository userRepository;
  final MeasurementRepository measurementRepository;
  final GameSessionRepository gameSessionRepository;

  final StressPredictionService predictionService;

  final DemoPhysiologicalDataSource demoDataSource;
  final ManualPhysiologicalDataSource manualDataSource;
  final BlePhysiologicalDataSource bleDataSource;

  final BleService bleService;

  final SettingsController settingsController;
  final AuthController authController;
  final StressController stressController;
  final DeviceController deviceController;
  final MeasurementModeController modeController;

  /// The data source currently feeding the app.
  PhysiologicalDataSource get activeDataSource => modeController.activeSource;

  /// Builds the object graph and restores persisted state.
  ///
  /// [store] and [predictionServiceOverride] exist so tests can supply an
  /// in-memory store and a zero-delay engine. Production always uses the
  /// defaults below.
  static Future<AppDependencies> bootstrap({
    LocalStore? store,
    StressPredictionService? predictionServiceOverride,
    BleService? bleServiceOverride,
  }) async {
    final localStore = store ?? await LocalStore.open();

    final settingsController = SettingsController(localStore);
    final authRepository = LocalAuthRepository(localStore);
    final userRepository = LocalUserRepository(localStore);
    final measurementRepository = LocalMeasurementRepository(localStore);
    final gameSessionRepository = LocalGameSessionRepository(localStore);

    // The trained engine. MLStressPredictionService loads
    // assets/models/stress_model.tflite in initialise() and falls back to the
    // demo heuristic - relabelling itself as demo - if the asset will not
    // load, so a broken model never masquerades as a trained one.
    final predictionService =
        predictionServiceOverride ?? MLStressPredictionService();

    late final DemoPhysiologicalDataSource demoDataSource;
    late final StressController stressController;

    demoDataSource = DemoPhysiologicalDataSource(
      targetLevel: () => stressController.demoLevel,
    );

    // The BLE stack. Tests and the developer panel pass a FakeBleService here,
    // which drives the entire Bluetooth path - scan, connect, packets - with
    // no hardware and no BLE plugin.
    final bleService = bleServiceOverride ?? FlutterBlueBleService();

    final manualDataSource = ManualPhysiologicalDataSource();
    final bleDataSource = BlePhysiologicalDataSource(bleService);

    final deviceController = DeviceController(bleService);
    final modeController = MeasurementModeController(
      demoSource: demoDataSource,
      manualSource: manualDataSource,
      bleSource: bleDataSource,
      store: localStore,
    );

    // Keep the Measure screen's readiness in step with the link: connecting a
    // wearable while sitting in Bluetooth mode should enable Analyze without
    // the user having to touch the mode selector again.
    deviceController.addListener(modeController.refresh);
    // -----------------------------------------------------------------------

    stressController = StressController(
      predictionService: predictionService,
      demoSource: demoDataSource,
      measurementRepository: measurementRepository,
      gameSessionRepository: gameSessionRepository,
      userRepository: userRepository,
      store: localStore,
    );

    final authController = AuthController(
      repository: authRepository,
      store: localStore,
    );

    await authController.restore();
    await stressController.load();
    await modeController.restore();

    return AppDependencies._(
      store: localStore,
      authRepository: authRepository,
      userRepository: userRepository,
      measurementRepository: measurementRepository,
      gameSessionRepository: gameSessionRepository,
      predictionService: predictionService,
      demoDataSource: demoDataSource,
      manualDataSource: manualDataSource,
      bleDataSource: bleDataSource,
      bleService: bleService,
      settingsController: settingsController,
      authController: authController,
      stressController: stressController,
      deviceController: deviceController,
      modeController: modeController,
    );
  }
}
