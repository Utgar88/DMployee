import 'package:material_ui/material_ui.dart';

/// Dark tone of the artwork; matches `brand_background` on the Android side.
const brandBackground = Color(0xFF14121F);

/// Shows the loading screen with the artwork while [load] runs, then the
/// widget built from its result.
///
/// The artwork stays for at least [minimumDuration], so it does not just
/// flicker when loading is fast.
class StartupScreen<T> extends StatefulWidget {
  const StartupScreen({
    super.key,
    required this.load,
    required this.builder,
    this.minimumDuration = const Duration(milliseconds: 1500),
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final Duration minimumDuration;

  @override
  State<StartupScreen<T>> createState() => _StartupScreenState<T>();
}

class _StartupScreenState<T> extends State<StartupScreen<T>> {
  T? _data;
  bool _loaded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final minimum = Future<void>.delayed(widget.minimumDuration);
    try {
      final data = await widget.load();
      await minimum;
      if (!mounted) return;
      setState(() {
        _data = data;
        _loaded = true;
      });
    } on Object catch (error) {
      await minimum;
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (_loaded) {
      child = widget.builder(context, _data as T);
    } else if (_error != null) {
      child = _StartupError(error: _error!);
    } else {
      child = const _Splash();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: child,
    );
  }
}

/// The artwork, always shown completely in its own proportions (941 x 1672).
/// Where the screen is taller or wider, the dark brand color fills the rest
/// and the picture fades into it at top and bottom.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: brandBackground,
      child: Center(
        child: AspectRatio(
          aspectRatio: 941 / 1672,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Image(
                key: Key('splash-image'),
                image: AssetImage('assets/images/splash.jpg'),
                fit: BoxFit.cover,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      brandBackground,
                      brandBackground.withValues(alpha: 0),
                      brandBackground.withValues(alpha: 0),
                      brandBackground,
                    ],
                    stops: const [0, 0.06, 0.94, 1],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'DMployee konnte die gespeicherten Daten nicht laden.\n\n$error',
              key: const Key('startup-error'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
