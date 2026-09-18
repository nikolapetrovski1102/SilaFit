import 'package:flutter/material.dart';

import '../../core/widgets/in_app_web_view.dart';

/// Pushes an in-app browser searching the web for [exerciseName]'s form -
/// the fallback for exercises with no `demoVideoUrl` (see
/// [free-exercise-db](https://github.com/yuhonas/free-exercise-db) gaps), so
/// there's still a one-tap way to see what the movement looks like.
Future<void> openExerciseWebSearch(
  BuildContext context, {
  required String exerciseName,
}) {
  final query = Uri.https('www.google.com', '/search',
      {'q': '$exerciseName exercise form'});
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => InAppWebViewScreen(title: exerciseName, url: query.toString()),
  ));
}
