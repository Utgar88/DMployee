import 'package:material_ui/material_ui.dart';

/// The button that opens the menu on the left, for the app bar of each
/// area; null if [onOpenMenu] is null.
Widget? menuButton(VoidCallback? onOpenMenu) => onOpenMenu == null
    ? null
    : IconButton(
        key: const Key('open-menu'),
        tooltip: 'Menü',
        onPressed: onOpenMenu,
        icon: const Icon(Icons.menu),
      );
