// AppScope — exposes the app-wide [AppController] to the widget tree via an
// InheritedNotifier, so pages rebuild when queue/progress/settings change.

import 'package:flutter/widgets.dart';

import 'app_controller.dart';

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope.of() called outside an AppScope');
    return scope!.notifier!;
  }
}
