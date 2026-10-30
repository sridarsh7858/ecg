import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Build the object graph once, before the first frame, so no screen ever has
  // to deal with a half-initialised controller.
  final dependencies = await AppDependencies.bootstrap();

  runApp(NeuroPulseApp(dependencies: dependencies));
}
