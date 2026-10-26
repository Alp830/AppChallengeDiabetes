import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'ai/ai_retry.dart';
import 'ai/ai_retry_status.dart';
import 'app_features.dart';
import 'cgm/data/glucose_repository.dart';
import 'cgm/screens/glucose_settings_page.dart';
import 'design/app_motion.dart';
import 'design/app_radius.dart';
import 'design/app_theme.dart';
import 'design/friendly_errors.dart';
import 'design/load_error.dart';
import 'design/spacing.dart';
import 'design/text_scale.dart';
import 'design/title_case.dart';
import 'design/undo_snack_bar.dart';
import 'firebase_options.dart';
import 'fridge/burst_capture.dart';
import 'fridge/freshness.dart';
import 'fridge/fridge_scan_dialog.dart';
import 'fridge/scan/fridge_scan_pipeline.dart';
import 'fridge/scan/fridge_scan_service.dart';
import 'fridge/scan/photo_prep.dart';
import 'fridge/scan/scan_models.dart';
import 'fridge/photo_quality.dart';
import 'fridge/selectable_fridge_grid.dart';
import 'home/mvp_home_page.dart';
import 'meals/data/meal_repository.dart';
import 'meals/models/meal_qa_models.dart';
import 'meals/screens/meal_lab_page.dart';
import 'meals/screens/meal_log_page.dart';
import 'meals/screens/meal_qa_sheet.dart';
import 'meals/services/meal_priority_policy.dart';
import 'meals/saved/saved_recipe.dart';
import 'meals/saved/saved_recipes_repository.dart';
import 'meals/saved/saved_recipes_page.dart';
import 'navigation/app_feature_navigation.dart';
import 'onboarding/first_meal_coach.dart';
import 'sleep/data/sleep_repository.dart';
import 'sleep/services/evening_food_context_service.dart';
import 'settings/data/app_preferences_repository.dart';
import 'settings/models/meal_nutrition_preferences.dart';

export 'fridge/scan/fridge_scan_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['AtkinsonHyperlegibleNext'], license);
  });
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AppEnvironment.load();

  runApp(const MyApp());
}

class AppEnvironment {
  static const _dartDefineGeminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
  );
  static final Map<String, String> _values = {};

  static Future<void> load() async {
    try {
      final envFile = await rootBundle.loadString('.env');
      _values.addAll(_parse(envFile));
    } catch (_) {
      // Keep --dart-define support for builds that do not bundle a .env file.
    }
  }

  /// Lets widget tests drive the meal agent with a `MockClient` without a
  /// bundled `.env` file. Pass an empty string to clear it again.
  @visibleForTesting
  static void setGeminiApiKeyForTesting(String value) =>
      _values['GEMINI_API_KEY'] = value;

  static String get geminiApiKey {
    final envApiKey = (_values['GEMINI_API_KEY'] ?? '').trim();

    if (envApiKey.isNotEmpty && envApiKey != 'put_your_gemini_api_key_here') {
      return envApiKey;
    }

    return _dartDefineGeminiApiKey;
  }

  static Map<String, String> _parse(String source) {
    final values = <String, String>{};

    for (final line in source.split('\n')) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty || trimmedLine.startsWith('#')) {
        continue;
      }

      final normalizedLine = trimmedLine.startsWith('export ')
          ? trimmedLine.substring(7).trim()
          : trimmedLine;
      final equalsIndex = normalizedLine.indexOf('=');
      if (equalsIndex <= 0) {
        continue;
      }

      final key = normalizedLine.substring(0, equalsIndex).trim();
      var value = normalizedLine.substring(equalsIndex + 1).trim();

      if (value.length >= 2) {
        final startsAndEndsWithDoubleQuote =
            value.startsWith('"') && value.endsWith('"');
        final startsAndEndsWithSingleQuote =
            value.startsWith("'") && value.endsWith("'");

        if (startsAndEndsWithDoubleQuote || startsAndEndsWithSingleQuote) {
          value = value.substring(1, value.length - 1);
        }
      }

      values[key] = value;
    }

    return values;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Wellness Companion',
      theme: AppTheme.light(),
      home: home ?? const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const AuthPage();
        }

        if (!user.emailVerified) {
          return EmailVerificationPage(user: user);
        }

        return MainPage(user: user);
      },
    );
  }
}

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({super.key, required this.user});

  final User user;

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  bool _isChecking = false;
  bool _isSending = false;
  String? _message;

  Future<void> _checkVerification() async {
    setState(() {
      _isChecking = true;
      _message = null;
    });

    try {
      await widget.user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;

      if (refreshedUser?.emailVerified != true && mounted) {
        setState(() {
          _message =
              'Your email is not verified yet. Open the link in the email and try again.';
        });
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() {
          _message = FriendlyErrors.describe(
            error,
            context: 'email verification',
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  Future<void> _resendVerification() async {
    setState(() {
      _isSending = true;
      _message = null;
    });

    try {
      await widget.user.sendEmailVerification();
      if (mounted) {
        setState(() {
          _message = 'A new verification email was sent.';
        });
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() {
          _message = FriendlyErrors.describe(
            error,
            context: 'email verification',
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _isChecking || _isSending;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your email')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.s24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.mark_email_unread_outlined, size: 64),
                const SizedBox(height: Spacing.s24),
                Text(
                  'Check your inbox',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Spacing.s12),
                Text(
                  'We sent a verification link to ${widget.user.email ?? 'your email address'}. Open it before continuing.',
                  textAlign: TextAlign.center,
                ),
                if (_message != null) ...[
                  const SizedBox(height: Spacing.s16),
                  Text(_message!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: Spacing.s24),
                FilledButton(
                  onPressed: isBusy ? null : _checkVerification,
                  child: Text(
                    _isChecking ? 'Checking…' : 'I verified my email',
                  ),
                ),
                TextButton(
                  onPressed: isBusy ? null : _resendVerification,
                  child: Text(_isSending ? 'Sending…' : 'Resend email'),
                ),
                TextButton(
                  onPressed: isBusy
                      ? null
                      : () => FirebaseAuth.instance.signOut(),
                  child: const Text('Use a different account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;
  String? _authError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _authError = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      UserCredential credential;

      if (_isSignUp) {
        credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        await _createUserProfile(credential.user!, email);
        await credential.user!.sendEmailVerification();
      } else {
        credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        await _touchUserProfile(credential.user!, email);
      }

      if (mounted) {
        Navigator.of(context).maybePop();
      }
    } on FirebaseAuthException catch (error) {
      setState(() {
        _authError = FriendlyErrors.auth(error);
      });
    } catch (error) {
      setState(() {
        _authError = FriendlyErrors.describe(error, context: 'auth');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _authError = null;
    });

    try {
      final provider = GoogleAuthProvider();
      final credential = kIsWeb
          ? await FirebaseAuth.instance.signInWithPopup(provider)
          : await FirebaseAuth.instance.signInWithProvider(provider);
      final user = credential.user;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'missing-user',
          message: 'Google did not return a user account.',
        );
      }

      if (credential.additionalUserInfo?.isNewUser ?? false) {
        await user.delete();
        await FirebaseAuth.instance.signOut();

        if (mounted) {
          setState(() {
            _authError =
                'No account found for that Google address. Create an account with email first.';
          });
        }
        return;
      }

      await _touchUserProfile(user, user.email ?? '');

      if (mounted) {
        Navigator.of(context).maybePop();
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() {
          _authError = FriendlyErrors.auth(error);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _authError = FriendlyErrors.describe(error, context: 'auth');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      setState(
        () => _authError =
            'Enter your email above, then tap "Forgot password?" again.',
      );
      return;
    }
    setState(() {
      _isLoading = true;
      _authError = null;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'If an account exists for $email, a reset link is on its way.',
          ),
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _authError = FriendlyErrors.auth(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createUserProfile(User user, String email) {
    return FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
      'lastSignInAt': FieldValue.serverTimestamp(),
      // Only brand-new accounts get the first-meal guide; existing users have
      // no such field, so their Home page is unchanged.
      'firstMealGuide': firstMealGuidePendingValue,
    }, SetOptions(merge: true));
  }

  Future<void> _touchUserProfile(User user, String email) {
    return FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'email': email,
      'lastSignInAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.s24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.eco,
                        size: 48,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: Spacing.s8),
                      Text(
                        'Wellness Companion',
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Spacing.s4),
                      Text(
                        "Turn what's in your fridge into meal ideas.",
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Spacing.s32),
                      Text(
                        _isSignUp ? 'Create account' : 'Sign In',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Spacing.s16),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter your email';
                          }

                          if (!value.contains('@')) {
                            return 'Enter a valid email';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: Spacing.s12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        autofillHints: _isSignUp
                            ? const [AutofillHints.newPassword]
                            : const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Enter your password';
                          }
                          if (_isSignUp && value.length < 6) {
                            return 'Use at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      if (!_isSignUp)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _isLoading ? null : _resetPassword,
                            child: const Text('Forgot password?'),
                          ),
                        ),
                      if (_authError != null) ...[
                        const SizedBox(height: Spacing.s8),
                        Text(
                          _authError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: Spacing.s16),
                      FilledButton(
                        onPressed: _isLoading ? null : _submit,
                        child: Text(
                          _isLoading
                              ? 'Please wait\u2026'
                              : _isSignUp
                              ? 'Create account'
                              : 'Sign In',
                        ),
                      ),
                      const SizedBox(height: Spacing.s12),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Spacing.s12,
                            ),
                            child: Text(
                              'or',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: Spacing.s12),
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _signInWithGoogle,
                        icon: const Icon(Icons.account_circle_outlined),
                        label: const Text('Continue with Google'),
                      ),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                setState(() {
                                  _isSignUp = !_isSignUp;
                                  _authError = null;
                                });
                              },
                        child: Text(
                          _isSignUp
                              ? 'Already have an account? Sign in'
                              : 'New here? Create an account',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({
    super.key,
    required this.user,
    this.diabetesEnabled = AppFeatures.diabetesEnabled,
    this.preferencesRepository,
    this.savedRecipesStore,
  });

  final User user;
  final bool diabetesEnabled;

  /// Injection points; the real Firestore-backed versions are used in the app.
  final AppPreferencesStore? preferencesRepository;
  final SavedRecipesStore? savedRecipesStore;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  // Home sits in the middle of the bottom nav, flanked by the two features.
  static const _fridgeTabIndex = 0;
  static const _homeTabIndex = 1;
  static const _agentTabIndex = 2;

  int _selectedIndex = _homeTabIndex;
  int _tabChangeDirection = 1;

  /// Lets the host confirm/save/discard unsaved fridge edits before the user
  /// navigates away from the Fridge tab.
  final GlobalKey<FridgePageState> _fridgeKey = GlobalKey<FridgePageState>();

  /// Same idea for Meals: the tab asks the user before abandoning a recipe
  /// request that is still in flight.
  final GlobalKey<AgentPageState> _agentKey = GlobalKey<AgentPageState>();

  late final AppPreferencesStore _preferences =
      widget.preferencesRepository ?? AppPreferencesRepository();
  late final SavedRecipesStore _savedRecipes =
      widget.savedRecipesStore ?? SavedRecipesRepository();

  /// Whether this account still has the first-meal guide waiting for it.
  bool _firstMealGuidePending = false;
  StreamSubscription<bool>? _firstMealGuideSubscription;

  /// True while the user is being walked through their first meal on Meals.
  bool _firstMealGuideActive = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _fridgeSubscription;

  /// Latest fridge contents; null until the first snapshot arrives.
  List<StoredFoodItem>? _fridgeItems;

  /// Plain-language load error, or null.
  String? _fridgeError;

  @override
  void initState() {
    super.initState();
    _subscribeToFridge();
    _firstMealGuideSubscription = _preferences
        .watchFirstMealGuidePending(widget.user.uid)
        .listen(
          (pending) {
            if (mounted && pending != _firstMealGuidePending) {
              setState(() => _firstMealGuidePending = pending);
            }
          },
          // A guide we can't read is a guide we don't show.
          onError: (Object error) => debugPrint('first meal guide: $error'),
        );
  }

  @override
  void dispose() {
    _fridgeSubscription?.cancel();
    _firstMealGuideSubscription?.cancel();
    super.dispose();
  }

  /// Marks the guide finished so it never comes back on this account.
  void _completeFirstMealGuide() {
    setState(() {
      _firstMealGuidePending = false;
      _firstMealGuideActive = false;
    });
    unawaited(
      _preferences.completeFirstMealGuide(widget.user.uid).catchError((
        Object error,
      ) {
        // Worst case the card returns next launch; nothing to interrupt the
        // user with here.
        debugPrint('first meal guide: $error');
      }),
    );
  }

  Future<void> _startFirstMeal() async {
    setState(() => _firstMealGuideActive = true);
    await _goToPage(_agentTabIndex);
  }

  Future<void> _openSavedRecipes() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => SavedRecipesPage(
          userId: widget.user.uid,
          store: _savedRecipes,
          geminiApiKey: AppEnvironment.geminiApiKey,
          diabetesEnabled: widget.diabetesEnabled,
          preferencesRepository: _preferences,
          onOpenMeals: () {
            Navigator.of(context).pop();
            _goToPage(_agentTabIndex);
          },
        ),
      ),
    );
  }

  /// One subscription for the life of the shell, so switching tabs never
  /// re-subscribes and flashes a loading spinner.
  void _subscribeToFridge() {
    _fridgeSubscription?.cancel();
    _fridgeError = null;
    _fridgeSubscription = _fridgeItemsCollection(widget.user.uid)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen(
          (snapshot) => setState(() {
            _fridgeItems = snapshot.docs
                .map(StoredFoodItem.fromDocument)
                .toList();
            _fridgeError = null;
          }),
          onError: (Object error) => setState(
            () => _fridgeError = FriendlyErrors.describe(
              error,
              context: 'fridge stream',
            ),
          ),
        );
  }

  /// Asks whichever tab the user is leaving whether that is okay: the Fridge
  /// guards unsaved edits, Meals guards a recipe request still in flight.
  ///
  /// Only the current tab is kept alive (see the `AnimatedSwitcher` below), so
  /// unsaved fridge edits and a loading recipe can never be in progress at the
  /// same time. If that ever changes, this is the one place a combined
  /// "here's everything you'd lose" dialog belongs.
  Future<bool> _confirmLeaveCurrentTab() async {
    switch (_selectedIndex) {
      case _fridgeTabIndex:
        final fridgeState = _fridgeKey.currentState;
        return fridgeState == null || await fridgeState.confirmLeave();
      case _agentTabIndex:
        final agentState = _agentKey.currentState;
        return agentState == null || await agentState.confirmLeave();
      default:
        return true;
    }
  }

  Future<void> _goToPage(int index) async {
    if (index == _selectedIndex) {
      return;
    }

    if (!await _confirmLeaveCurrentTab()) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _tabChangeDirection = index > _selectedIndex ? 1 : -1;
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final animationDuration = reduceMotion
        ? AppMotion.reducedFade
        : AppMotion.medium;
    final largeText = useLargeTextLayout(context);
    final titleScale = math.min(
      MediaQuery.textScalerOf(context).scale(22) / 22,
      2.0,
    );

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: Spacing.s16,
        toolbarHeight: 60 + (16 + 28 * (largeText ? 2 : 1)) * titleScale,
        title: _HeaderTitle(
          eyebrow: _headerEyebrow(user),
          title: _headerTitle(user),
          maxTitleLines: largeText ? 2 : 1,
        ),
        actions: [
          _HeaderAction(
            tooltip: 'Account',
            icon: Icons.account_circle_outlined,
            onPressed: _showAccountSheet,
          ),
          const SizedBox(width: Spacing.s8),
        ],
      ),
      body: AnimatedSwitcher(
        duration: animationDuration,
        reverseDuration: animationDuration,
        switchInCurve: AppMotion.enter,
        switchOutCurve: AppMotion.exit,
        transitionBuilder: (child, animation) {
          if (reduceMotion) {
            return FadeTransition(opacity: animation, child: child);
          }
          final isIncoming = child.key == ValueKey(_selectedIndex);
          final horizontalOffset = isIncoming
              ? 0.07 * _tabChangeDirection
              : -0.04 * _tabChangeDirection;
          final slideAnimation = Tween<Offset>(
            begin: Offset(horizontalOffset, 0),
            end: Offset.zero,
          ).animate(animation);

          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slideAnimation, child: child),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(_selectedIndex),
          child: _selectedPage(user),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _goToPage,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.kitchen_outlined),
            selectedIcon: Icon(Icons.kitchen),
            label: 'Fridge',
          ),
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu),
            label: 'Meals',
          ),
        ],
      ),
    );
  }

  Future<void> _showAccountSheet() async {
    final user = widget.user;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(_userDisplayName(user) ?? 'Your account'),
              subtitle: user.email == null ? null : Text(user.email!),
            ),
            const Divider(),
            if (widget.diabetesEnabled)
              ListTile(
                leading: const Icon(Icons.monitor_heart_outlined),
                title: const Text('Glucose & data sources'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  AppFeatureNavigation.pushDiabetesPage<void>(
                    context,
                    diabetesEnabled: widget.diabetesEnabled,
                    builder: (context) => GlucoseSettingsPage(
                      userId: user.uid,
                      diabetesEnabled: widget.diabetesEnabled,
                    ),
                  );
                },
              ),
            ListTile(
              key: const Key('accountSignOut'),
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () {
                Navigator.pop(sheetContext);
                _signOut();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Runs the same leave guard as a tab switch before signing out.
  Future<void> _signOut() async {
    if (!await _confirmLeaveCurrentTab()) return;
    await FirebaseAuth.instance.signOut();
  }

  String? _userDisplayName(User user) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final emailName = user.email?.split('@').first.trim();
    if (emailName != null && emailName.isNotEmpty) return emailName;
    return null;
  }

  String _headerEyebrow(User user) {
    switch (_selectedIndex) {
      case _fridgeTabIndex:
        return "Let's get cooking";
      case _agentTabIndex:
        return 'Cook from what you have';
      default:
        final hour = DateTime.now().hour;
        if (hour < 12) return 'Good Morning';
        if (hour < 17) return 'Good Afternoon';
        return 'Good Evening';
    }
  }

  String _headerTitle(User user) {
    switch (_selectedIndex) {
      case _fridgeTabIndex:
        return 'Your Fridge';
      case _agentTabIndex:
        return 'Meal Ideas';
      default:
        return _userDisplayName(user) ?? 'Welcome back';
    }
  }

  Widget _selectedPage(User user) {
    if (_selectedIndex == _homeTabIndex) {
      final displayName = user.displayName?.trim();
      final emailName = user.email?.split('@').first.trim();
      final items = _fridgeItems;
      return MvpHomePage(
        userId: user.uid,
        userName: displayName?.isNotEmpty == true ? displayName : emailName,
        onOpenFridge: () => _goToPage(_fridgeTabIndex),
        fridgeItemCount: items?.length,
        expiringCount: items == null
            ? 0
            : items.where((stored) {
                final status = freshnessFor(stored.foodItem.expiryDate);
                return status == Freshness.expired ||
                    status == Freshness.expiringSoon;
              }).length,
        showFirstMealGuide: _firstMealGuidePending,
        onStartFirstMeal: _startFirstMeal,
        onSkipFirstMeal: _completeFirstMealGuide,
        savedRecipesStore: _savedRecipes,
        onOpenSavedRecipes: _openSavedRecipes,
      );
    }

    final fridgeError = _fridgeError;
    if (fridgeError != null) {
      return Center(
        child: LoadErrorView(
          message: fridgeError,
          onRetry: () => setState(_subscribeToFridge),
        ),
      );
    }
    final storedItems = _fridgeItems;
    if (storedItems == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_selectedIndex == _fridgeTabIndex) {
      return FridgePage(
        key: _fridgeKey,
        initialItems: storedItems,
        onCommit: (changes) => _commitFridgeChanges(user.uid, changes),
        onAddSelectedToMeal: (foods) => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (context) => MealLogPage(
              userId: user.uid,
              geminiApiKey: AppEnvironment.geminiApiKey,
              initialName: foods.map((food) => food.name).join(', '),
              diabetesEnabled: widget.diabetesEnabled,
            ),
          ),
        ),
      );
    }

    return AgentPage(
      key: _agentKey,
      foodItems: [for (final stored in storedItems) stored.foodItem],
      userId: user.uid,
      geminiApiKey: AppEnvironment.geminiApiKey,
      diabetesEnabled: widget.diabetesEnabled,
      preferencesRepository: _preferences,
      savedRecipesStore: _savedRecipes,
      firstMealGuide: _firstMealGuideActive && _firstMealGuidePending,
      onFirstMealGuideDone: _completeFirstMealGuide,
    );
  }

  CollectionReference<Map<String, dynamic>> _fridgeItemsCollection(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('fridgeItems');
  }

  /// Applies a batch of staged fridge edits atomically. Only invoked when the
  /// user explicitly saves (or confirms saving on navigation away).
  Future<void> _commitFridgeChanges(String uid, FridgeChangeSet changes) async {
    if (changes.isEmpty) {
      return;
    }

    final collection = _fridgeItemsCollection(uid);
    final batch = FirebaseFirestore.instance.batch();

    for (final foodItem in changes.additions) {
      batch.set(collection.doc(), foodItem.toFirestore());
    }
    changes.updates.forEach((id, foodItem) {
      batch.update(collection.doc(id), {
        ...foodItem.toFirestore(includeCreatedAt: false),
        // update() keeps fields it doesn't mention, so a cleared review must
        // be deleted explicitly.
        if (foodItem.scanReview == null) 'scanReview': FieldValue.delete(),
      });
    });
    for (final id in changes.deletions) {
      batch.delete(collection.doc(id));
    }

    await batch.commit();
  }
}

/// Two-line contextual header title: a small muted eyebrow over a bold title.
class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle({
    required this.eyebrow,
    required this.title,
    this.maxTitleLines = 1,
  });

  final String eyebrow;
  final String title;
  final int maxTitleLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          titleCase(title),
          maxLines: maxTitleLines,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineMedium?.copyWith(fontSize: 36),
        ),
      ],
    );
  }
}

/// Soft circular icon button for the header's account action.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: Spacing.s8),
      child: Material(
        color: scheme.surface,
        shape: CircleBorder(side: BorderSide(color: scheme.outlineVariant)),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          iconSize: 20,
          color: scheme.onSurface,
          icon: Icon(icon),
        ),
      ),
    );
  }
}

/// A staged batch of fridge edits, applied atomically when the user saves.
class FridgeChangeSet {
  const FridgeChangeSet({
    required this.additions,
    required this.updates,
    required this.deletions,
  });

  /// New items with no backing document yet.
  final List<FoodItem> additions;

  /// Existing documents (keyed by id) whose contents changed.
  final Map<String, FoodItem> updates;

  /// Ids of documents removed from the working set.
  final List<String> deletions;

  bool get isEmpty => additions.isEmpty && updates.isEmpty && deletions.isEmpty;

  int get count => additions.length + updates.length + deletions.length;
}

/// One item in the local working copy. [docId] is null for freshly added items
/// that have not been persisted; [original] is the last-saved snapshot used to
/// detect edits.
class _FridgeDraft {
  _FridgeDraft({required this.localId, this.docId, required this.item})
    : original = item;

  final int localId;
  final String? docId;
  final FoodItem original;
  FoodItem item;
}

/// One Undo-able removal: the drafts taken out and the draft order before, so
/// they can be put back relative to whatever neighbours remain.
class _FridgeRemoval {
  _FridgeRemoval({
    required this.generation,
    required this.orderBefore,
    required this.removed,
  });

  final int generation;
  final List<int> orderBefore;
  final List<_FridgeDraft> removed;
  bool restored = false;
}

enum _UnsavedChoice { save, discard, cancel }

/// The Fridge tab. Edits (add / edit / delete) are staged in a local working
/// copy and only written to the backing store when the user explicitly saves.
/// Deletion happens via the edit sheet or multi-select — the old
/// swipe-up "Ground" disposal mechanic has been removed.
class FridgePage extends StatefulWidget {
  const FridgePage({
    super.key,
    required this.initialItems,
    required this.onCommit,
    this.onAddSelectedToMeal,
  });

  /// The last-saved fridge contents from the backing store.
  final List<StoredFoodItem> initialItems;

  /// Persists the staged [FridgeChangeSet]. Called only on an explicit save.
  final Future<void> Function(FridgeChangeSet changes) onCommit;

  final Future<void> Function(List<FoodItem> foods)? onAddSelectedToMeal;

  @override
  State<FridgePage> createState() => FridgePageState();
}

class FridgePageState extends State<FridgePage> {
  final List<_FridgeDraft> _drafts = [];
  final Set<String> _baselineIds = {};
  int _nextLocalId = 0;
  bool _isDirty = false;
  bool _isSaving = false;
  int _selectionCount = 0;

  /// Bumped whenever the draft list is replaced wholesale (Discard, a reseed,
  /// a save), so an Undo from before that point can't put a stale draft back.
  int _draftGeneration = 0;

  /// The latest removal; the only one the snackbar's Undo can restore.
  _FridgeRemoval? _lastRemoval;

  /// The undo snackbar on screen, and how many items were removed while it or
  /// its predecessors were continuously showing.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _removalSnack;
  int _removedInBurst = 0;

  /// Whether there are staged edits that have not been saved.
  bool get isDirty => _isDirty;

  @override
  void initState() {
    super.initState();
    _seedFromInitial();
  }

  @override
  void didUpdateWidget(covariant FridgePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt fresh data from the backing store only when there are no pending
    // edits, so a background refresh never clobbers unsaved work.
    if (!_isDirty && !identical(oldWidget.initialItems, widget.initialItems)) {
      setState(_seedFromInitial);
    }
  }

  void _seedFromInitial() {
    _draftGeneration++;
    _lastRemoval = null;
    _drafts
      ..clear()
      ..addAll(
        widget.initialItems.map(
          (stored) => _FridgeDraft(
            localId: _nextLocalId++,
            docId: stored.id,
            item: stored.foodItem,
          ),
        ),
      );
    _baselineIds
      ..clear()
      ..addAll(widget.initialItems.map((stored) => stored.id));
    _isDirty = false;
  }

  /// Items ranked by earliest expiration date (nulls last), keyed by each
  /// draft's [_FridgeDraft.localId]. Not by list index: a delete or an undo
  /// shifts every later index, which handed a tile's key (and its open
  /// tooltip) to a different item and crashed the grid's layout. The grid's
  /// callbacks hand ids back; [_draftIndex] turns them into indices.
  List<MapEntry<int, FoodItem>> get _rankedItems {
    final entries = [
      for (final draft in _drafts) MapEntry(draft.localId, draft.item),
    ];
    entries.sort((a, b) {
      final aDate = a.value.expiryDate;
      final bDate = b.value.expiryDate;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });
    return entries;
  }

  /// Shows a fridge message clear of the unsaved-changes bar, so Save and
  /// Discard stay reachable while the message is on screen.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
  _showFridgeSnackBar(
    ScaffoldMessengerState messenger, {
    required Widget content,
    SnackBarAction? action,
    bool autoDismiss = false,
  }) {
    final liftAboveSaveBar = _isDirty;
    // Replace, don't queue: drop anything waiting and remove the visible one
    // outright, so the new message shows at once instead of after the old
    // one's exit animation and a line of earlier messages.
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    return messenger.showSnackBar(
      SnackBar(
        content: content,
        action: action,
        persist: autoDismiss ? false : null,
        duration: undoSnackBarDuration,
        behavior: liftAboveSaveBar
            ? SnackBarBehavior.floating
            : SnackBarBehavior.fixed,
        margin: liftAboveSaveBar
            ? const EdgeInsets.fromLTRB(Spacing.s8, 0, Spacing.s8, 72)
            : null,
      ),
    );
  }

  void _mutate(VoidCallback change) {
    setState(() {
      change();
      _isDirty = true;
    });
  }

  void _addDraft(FoodItem item) {
    _mutate(
      () => _drafts.add(_FridgeDraft(localId: _nextLocalId++, item: item)),
    );
  }

  void _addDrafts(Iterable<FoodItem> items) {
    _mutate(() {
      for (final item in items) {
        _drafts.add(_FridgeDraft(localId: _nextLocalId++, item: item));
      }
    });
  }

  int _draftIndex(int localId) =>
      _drafts.indexWhere((draft) => draft.localId == localId);

  void _editDraft(int index, FoodItem item) {
    _mutate(() => _drafts[index].item = item);
  }

  /// Removes the drafts at [indices] and returns what [_restoreRemoval]
  /// needs to put them back.
  _FridgeRemoval _removeDraftsRecorded(Iterable<int> indices) {
    final removal = _FridgeRemoval(
      generation: _draftGeneration,
      orderBefore: [for (final draft in _drafts) draft.localId],
      removed: [
        for (final index in indices.toSet().toList()..sort()) _drafts[index],
      ],
    );
    _removeDrafts(indices);
    _lastRemoval = removal;
    return removal;
  }

  /// Puts [removal] back, each draft right after the nearest earlier neighbour
  /// that still exists (else at the start). Does nothing if it was already
  /// restored, isn't the latest removal, or the draft list was replaced since.
  void _restoreRemoval(_FridgeRemoval removal) {
    if (!mounted ||
        removal.restored ||
        !identical(_lastRemoval, removal) ||
        removal.generation != _draftGeneration) {
      return;
    }
    removal.restored = true;
    setState(() {
      for (final draft in removal.removed) {
        final position = removal.orderBefore.indexOf(draft.localId);
        var insertAt = 0;
        for (var i = position - 1; i >= 0; i--) {
          final at = _draftIndex(removal.orderBefore[i]);
          if (at >= 0) {
            insertAt = at + 1;
            break;
          }
        }
        _drafts.insert(insertAt, draft);
      }
      _isDirty = !_buildChangeSet().isEmpty;
    });
  }

  void _removeDrafts(Iterable<int> indices) {
    final ordered = indices.toList()..sort((a, b) => b.compareTo(a));
    _mutate(() {
      for (final index in ordered) {
        _drafts.removeAt(index);
      }
    });
  }

  FridgeChangeSet _buildChangeSet() {
    final additions = <FoodItem>[];
    final updates = <String, FoodItem>{};
    final remaining = <String>{};
    for (final draft in _drafts) {
      final docId = draft.docId;
      if (docId == null) {
        additions.add(draft.item);
      } else {
        remaining.add(docId);
        if (!_sameFoodItem(draft.item, draft.original)) {
          updates[docId] = draft.item;
        }
      }
    }
    final deletions = [
      for (final id in _baselineIds)
        if (!remaining.contains(id)) id,
    ];
    return FridgeChangeSet(
      additions: additions,
      updates: updates,
      deletions: deletions,
    );
  }

  /// Persists staged edits. Returns true when the fridge is left in a saved
  /// (non-dirty) state — including the no-op case where nothing was pending.
  Future<bool> save() async {
    if (_isSaving) {
      return false;
    }

    final changes = _buildChangeSet();
    if (changes.isEmpty) {
      if (mounted) {
        setState(() => _isDirty = false);
      }
      return true;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSaving = true);
    try {
      await widget.onCommit(changes);
      if (!mounted) {
        return true;
      }
      setState(() {
        _isSaving = false;
        _isDirty = false;
        _draftGeneration++;
        _lastRemoval = null;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Fridge changes saved.')),
      );
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      setState(() => _isSaving = false);
      _showFridgeSnackBar(
        messenger,
        content: Text(FriendlyErrors.describe(error, context: 'fridge save')),
        action: SnackBarAction(label: 'Retry', onPressed: save),
      );
      return false;
    }
  }

  /// Throws away staged edits and reverts to the last-saved contents.
  void discard() {
    setState(_seedFromInitial);
  }

  /// Called by the host before navigating away from the Fridge tab. Returns
  /// true when it is safe to leave: either nothing was pending, or the user
  /// chose to save or discard.
  Future<bool> confirmLeave() async {
    if (!_isDirty) {
      return true;
    }

    final pendingCount = _buildChangeSet().count;
    final choice = await showDialog<_UnsavedChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save fridge changes?'),
        content: Text(
          pendingCount == 1
              ? 'You have 1 unsaved change to your fridge. Save it before '
                    'leaving?'
              : 'You have $pendingCount unsaved changes to your fridge. Save '
                    'them before leaving?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_UnsavedChoice.cancel),
            child: const Text('Keep editing'),
          ),
          TextButton(
            key: const Key('fridgeDiscardChanges'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_UnsavedChoice.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            key: const Key('fridgeSaveChanges'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_UnsavedChoice.save),
            child: const Text('Save changes'),
          ),
        ],
      ),
    );

    switch (choice) {
      case _UnsavedChoice.save:
        return save();
      case _UnsavedChoice.discard:
        discard();
        return true;
      case _UnsavedChoice.cancel:
      case null:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ranked = _rankedItems;

    final selecting = _selectionCount > 0;
    final scheme = Theme.of(context).colorScheme;
    final barShowing = selecting || _isDirty;

    return Stack(
      children: [
        if (_drafts.isEmpty)
          _FridgeEmptyState(
            onScan: () => _takeFridgePhoto(context),
            onAdd: () => _showAddFoodSheet(context),
          )
        else
          SelectableFridgeGrid(
            items: ranked,
            onEdit: (id) => _showEditFoodSheet(context, _draftIndex(id)),
            onDelete: (id) => _stageDraftDeletion(
              ScaffoldMessenger.of(context),
              _draftIndex(id),
            ),
            onRemoveSelected: (ids) async {
              final messenger = ScaffoldMessenger.of(context);
              final indices = ids
                  .map(_draftIndex)
                  .where((index) => index >= 0)
                  .toList();
              if (indices.isNotEmpty) {
                _stageRemoval(messenger, indices);
              }
              // The grid clears its own selection first, and it unmounts
              // entirely when the last item goes, so it can never report the
              // count back down to zero itself.
              if (_selectionCount != 0) {
                setState(() => _selectionCount = 0);
              }
            },
            onBulkAction: (action, foods) =>
                _handleBulkAction(context, action, foods),
            onSelectionCountChanged: (selectedCount) {
              if (selectedCount != _selectionCount) {
                setState(() => _selectionCount = selectedCount);
              }
            },
            bottomPadding: barShowing ? 216 : 144,
          ),
        // Camera/add buttons. Lifted to clear the bottom selection toolbar
        // and the unsaved-changes bar.
        if (_drafts.isNotEmpty)
          Positioned(
            right: Spacing.margin,
            bottom: barShowing ? 88 : Spacing.s16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'addFood',
                  onPressed: () => _showAddFoodSheet(context),
                  tooltip: 'Add food',
                  backgroundColor: scheme.secondaryContainer,
                  foregroundColor: scheme.onSecondaryContainer,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: Spacing.s12),
                FloatingActionButton.extended(
                  heroTag: 'takeFridgePhoto',
                  onPressed: () => _takeFridgePhoto(context),
                  tooltip: 'Scan a fridge photo',
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Scan fridge'),
                ),
              ],
            ),
          ),
        // Unsaved-changes bar, in the same bottom slot as the selection toolbar
        // (which takes precedence while selecting).
        if (_isDirty && !selecting)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _FridgeSaveBar(
              pendingCount: _buildChangeSet().count,
              isSaving: _isSaving,
              onDiscard: _isSaving ? null : discard,
              onSave: _isSaving ? null : () => save(),
            ),
          ),
      ],
    );
  }

  Future<void> _handleBulkAction(
    BuildContext context,
    FoodBulkAction action,
    List<FoodItem> foods,
  ) async {
    if (action != FoodBulkAction.addToMeal) return;
    await widget.onAddSelectedToMeal?.call(foods);
  }

  Future<void> _takeFridgePhoto(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    // The sheet lets the user choose between taking a live picture and uploading
    // an existing screenshot/photo, so it handles both web and mobile.
    final photoBytes = await showModalBottomSheet<List<Uint8List>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const FridgeCameraSheet(),
    );

    if (photoBytes == null || photoBytes.isEmpty) {
      return;
    }

    if (!context.mounted) return;
    // Decode once and keep the pixels; a retry reuses them instead of
    // decoding the photo again. A failed decode is not cached.
    Future<List<PreparedPhoto>>? preparedPhotos;
    final result = await showDialog<FridgeScanResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => FridgeScanDialog(
        imageBytes: photoBytes.first,
        photos: photoBytes,
        detectPhotos: (photoBytes, abort, onProgress) async {
          final List<PreparedPhoto> photos;
          try {
            photos = await (preparedPhotos ??= Future.wait([
              for (final bytes in photoBytes) preparePhotoAsync(bytes),
            ]));
          } catch (error) {
            preparedPhotos = null;
            // The same bytes will never decode on a second try.
            throw AiRequestException(
              'Could not read the photo: $error',
              retryable: false,
            );
          }
          // Measured: one lean call takes ~27 s on a 1080p photo, a 2×2 grid
          // 33–39 s on a 24 MP one. Photos under 3072 px fall back to one
          // overview call. Replies stream so the dialog can show items early.
          // Several photos run their plans in parallel and merge by name and
          // zone.
          final scan = photos.length == 1
              ? await FridgeScanPipeline.scan(
                  photos.single,
                  plan: ScanPlan.grid,
                  style: ScanStyle.lean,
                  abortTrigger: abort,
                  onProgress: onProgress,
                )
              : await FridgeScanPipeline.scanPhotos(
                  photos,
                  style: ScanStyle.lean,
                  abortTrigger: abort,
                  onProgress: onProgress,
                );
          // Every item is added; unsure ones carry a review ("Maybe" badge).
          return [for (final item in scan.items) item.toFoodItem()];
        },
      ),
    );
    if (result == null) return; // Cancelled.

    // The dialog now retries and reports its own failure in place, so it
    // stops returning a failure result. Kept as a safety net.
    final error = result.error;
    if (error != null) {
      _showFridgeSnackBar(
        messenger,
        content: Text(FriendlyErrors.describe(error, context: 'fridge scan')),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () => _takeFridgePhoto(context),
        ),
      );
      return;
    }
    if (result.foods.isEmpty) {
      _showFridgeSnackBar(
        messenger,
        content: const Text('No foods found. Try a closer, well-lit photo.'),
      );
      return;
    }

    _addDrafts(result.foods);
    _showFridgeSnackBar(
      messenger,
      content: Text(scanAddedMessage(result.foods)),
    );
  }

  Future<void> _showAddFoodSheet(BuildContext context) async {
    final foodItem = await showModalBottomSheet<FoodItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const AddFoodSheet(),
    );

    if (foodItem != null) {
      _addDraft(foodItem);
    }
  }

  /// Stages the deletion of the draft at [index] and offers an Undo that puts
  /// the very same draft back where it was, so an undone delete leaves no
  /// pending change behind.
  void _stageDraftDeletion(ScaffoldMessengerState messenger, int index) {
    if (index < 0 || index >= _drafts.length) return;
    _stageRemoval(messenger, [index]);
  }

  /// Removes the drafts at [indices] under one message. The message and its
  /// Undo always belong to the latest removal; earlier ones stay staged until
  /// Discard.
  void _stageRemoval(ScaffoldMessengerState messenger, List<int> indices) {
    final removal = _removeDraftsRecorded(indices);
    final count = removal.removed.length;
    final label = count == 1 ? removal.removed.single.item.name : '$count items';
    _removedInBurst = (_removalSnack == null ? 0 : _removedInBurst) + count;
    final controller = _showFridgeSnackBar(
      messenger,
      content: Text(
        _removedInBurst > count
            ? 'Removed $label ($_removedInBurst removed). '
                  'Undo restores the last one.'
            : 'Removed $label. Save to make it final.',
      ),
      autoDismiss: true,
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => _restoreRemoval(removal),
      ),
    );
    _removalSnack = controller;
    controller.closed.then((_) {
      if (identical(_removalSnack, controller)) {
        _removalSnack = null;
        _removedInBurst = 0;
      }
    });
  }

  Future<void> _showEditFoodSheet(BuildContext context, int index) async {
    final messenger = ScaffoldMessenger.of(context);
    final foodItem = await showModalBottomSheet<FoodItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => AddFoodSheet(
        foodItem: _drafts[index].item,
        onDelete: () => _stageDraftDeletion(messenger, index),
      ),
    );

    if (foodItem != null) {
      _editDraft(index, foodItem);
    }
  }
}

/// The snackbar text after a scan added [foods]; unsure items are counted so
/// the user knows how many to check.
@visibleForTesting
String scanAddedMessage(List<FoodItem> foods) {
  final toCheck = foods.where((food) => food.scanReview != null).length;
  final added = foods.length == 1 ? '1 item' : '${foods.length} items';
  final check = toCheck == 0 ? '' : ', $toCheck to check';
  return 'Added $added$check — remember to save.';
}

bool _sameFoodItem(FoodItem a, FoodItem b) {
  return a.name == b.name &&
      a.amount == b.amount &&
      a.foodType == b.foodType &&
      a.description == b.description &&
      a.expiryDate == b.expiryDate &&
      a.scanReview == b.scanReview &&
      _sameBytes(a.imageBytes, b.imageBytes);
}

bool _sameBytes(Uint8List? a, Uint8List? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

/// First-run state for the core loop: says what the fridge is for and gives
/// both ways to fill it (NN/g empty-state guidelines).
class _FridgeEmptyState extends StatelessWidget {
  const _FridgeEmptyState({required this.onScan, required this.onAdd});

  final VoidCallback onScan;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.s24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.kitchen_outlined,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: Spacing.s16),
              Text(
                'Your fridge is empty',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Spacing.s8),
              Text(
                "Scan a photo of your fridge or add foods one by one — we'll suggest meals from them.",
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Spacing.s24),
              FilledButton.icon(
                key: const Key('fridgeEmptyScan'),
                onPressed: onScan,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Scan fridge'),
              ),
              const SizedBox(height: Spacing.s8),
              TextButton(
                key: const Key('fridgeEmptyAdd'),
                onPressed: onAdd,
                child: const Text('Add manually'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Save / Discard bar for staged fridge edits, full-width bar pinned to the
/// bottom while there are unsaved changes.
class _FridgeSaveBar extends StatelessWidget {
  const _FridgeSaveBar({
    required this.pendingCount,
    required this.isSaving,
    required this.onDiscard,
    required this.onSave,
  });

  final int pendingCount;
  final bool isSaving;
  final VoidCallback? onDiscard;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 3,
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.s16,
          vertical: Spacing.s8,
        ),
        child: Row(
          children: [
            Icon(Icons.edit_note, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: Spacing.s8),
            Expanded(
              child: Text(
                pendingCount == 1
                    ? '1 unsaved change'
                    : '$pendingCount unsaved changes',
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              key: const Key('fridgeDiscardBar'),
              onPressed: onDiscard,
              child: const Text('Discard'),
            ),
            const SizedBox(width: Spacing.s8),
            FilledButton(
              key: const Key('fridgeSaveBar'),
              onPressed: onSave,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              child: isSaving
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Most photos one scan can use.
const maxFridgePhotos = 3;

/// A photo in the sheet; [quality] arrives later from the background check.
class _SheetPhoto {
  _SheetPhoto(this.bytes);

  final Uint8List bytes;
  PhotoQuality? quality;
}

/// A small spinner for inside a button or tile.
class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 20,
    height: 20,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

/// Collects up to [maxFridgePhotos] photos for one scan and pops their bytes
/// as a `List<Uint8List>`.
class FridgeCameraSheet extends StatefulWidget {
  const FridgeCameraSheet({
    super.key,
    this.openCamera,
    this.pickPhoto,
    this.burst,
    this.assess,
  });

  /// Test seam: stands in for the camera plugin. Returns the function the
  /// shutter calls to take one picture.
  @visibleForTesting
  final Future<Future<XFile> Function()> Function()? openCamera;

  /// Test seam: stands in for the gallery picker.
  @visibleForTesting
  final Future<Uint8List?> Function()? pickPhoto;

  /// Test seam: stands in for [captureSharpest].
  @visibleForTesting
  final Future<BurstResult> Function(Future<XFile> Function() takePicture)?
  burst;

  /// Test seam: stands in for [assessPhotoFast].
  /// Its result only adds a note to the photo's thumbnail; it never gates it.
  @visibleForTesting
  final Future<PhotoQuality> Function(Uint8List bytes)? assess;

  @override
  State<FridgeCameraSheet> createState() => _FridgeCameraSheetState();
}

class _FridgeCameraSheetState extends State<FridgeCameraSheet> {
  final ImagePicker _imagePicker = ImagePicker();
  CameraController? _cameraController;
  Future<void>? _initializeCameraFuture;
  String? _cameraError;
  bool _isTakingPicture = false;

  /// Set instead of [_cameraController] when the test seam is used.
  Future<XFile> Function()? _seamTake;

  /// The photos accepted so far, in the order they were added.
  final List<_SheetPhoto> _photos = [];

  /// Photos whose bytes arrived but that aren't thumbnails yet; each shows a
  /// "Adding photo…" placeholder.
  int _pendingPhotos = 0;

  /// Whether the gallery picker is open, so a second tap can't open another.
  bool _isPicking = false;

  /// Whether the chooser is showing even though photos were already added
  /// (the user tapped "Add another photo").
  bool _adding = false;

  /// The sheet opens on a two-option chooser; the live camera is only started
  /// when the user explicitly taps "Take a picture".
  bool _cameraStarted = false;

  /// Bumped whenever the camera is stopped, so an initialization still in
  /// flight (e.g. the max-preset fallback) knows it no longer owns the sheet.
  int _cameraGeneration = 0;

  @override
  void dispose() {
    _cameraGeneration++;
    _cameraController?.dispose();
    super.dispose();
  }

  void _startCamera() {
    setState(() {
      _cameraStarted = true;
      _cameraError = null;
      _initializeCameraFuture = _initializeCamera();
    });
  }

  void _backToChooser() {
    _cameraGeneration++;
    _cameraController?.dispose();
    setState(() {
      _cameraStarted = false;
      _cameraController = null;
      _seamTake = null;
      _initializeCameraFuture = null;
      _cameraError = null;
    });
  }

  Future<void> _initializeCamera() async {
    final generation = _cameraGeneration;
    bool stale() => !mounted || generation != _cameraGeneration;
    final openCamera = widget.openCamera;
    if (openCamera != null) {
      try {
        final take = await openCamera();
        if (stale()) return;
        _seamTake = take;
      } catch (error) {
        _cameraError = error.toString();
      }
      if (mounted) setState(() {});
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No camera was found on this device.');
      }

      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      // The highest resolution the camera offers, so small labels stay
      // legible when the scanner zooms into tiles of the kept original. Some
      // devices refuse the max preset, so fall back once to veryHigh.
      var cameraController = CameraController(
        camera,
        ResolutionPreset.max,
        enableAudio: false,
      );

      _cameraController = cameraController;
      try {
        await cameraController.initialize();
      } catch (_) {
        await cameraController.dispose();
        // The sheet closed or went back to the chooser while max was
        // failing; whoever stopped it already cleaned up.
        if (stale()) return;
        cameraController = CameraController(
          camera,
          ResolutionPreset.veryHigh,
          enableAudio: false,
        );
        _cameraController = cameraController;
        await cameraController.initialize();
        if (stale()) {
          await cameraController.dispose();
          return;
        }
      }
    } catch (error) {
      _cameraError = error.toString();
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _capturePhoto() async {
    final cameraController = _cameraController;
    final initializeCameraFuture = _initializeCameraFuture;
    final seamTake = _seamTake;

    if ((cameraController == null && seamTake == null) ||
        initializeCameraFuture == null ||
        _isTakingPicture) {
      return;
    }

    setState(() {
      _isTakingPicture = true;
    });

    try {
      await initializeCameraFuture;
      Future<XFile> takePicture() =>
          seamTake != null ? seamTake() : cameraController!.takePicture();
      // Several frames back to back; the sharpest one is kept. Hand-shake
      // blur is the biggest accuracy loss on real photos.
      final Future<BurstResult> Function(Future<XFile> Function()) shoot =
          widget.burst ?? captureSharpest;
      final burst = await shoot(takePicture);

      if (!mounted) {
        return;
      }
      _isTakingPicture = false;
      _addPhoto(burst.bytes, fromCamera: true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _cameraError = error.toString();
        _isTakingPicture = false;
      });
    }
  }

  /// Reliable fallback that works on web and mobile even when the live camera
  /// can't be opened: pick an existing photo (or the OS camera-capture flow)
  /// and hand its bytes back to the scanner.
  Future<void> _uploadPhoto() async {
    if (_isTakingPicture || _isPicking) {
      return;
    }
    setState(() => _isPicking = true);
    try {
      // No maxWidth/maxHeight/imageQuality: the picker hands back the
      // original. The scanner keeps its pixels for zooming and only uploads a
      // 2048 px overview (see preparePhoto), so shrinking here would throw
      // away detail it needs.
      final pick = widget.pickPhoto;
      final Uint8List? imageBytes;
      if (pick != null) {
        imageBytes = await pick();
      } else {
        final picked = await _imagePicker.pickImage(
          source: ImageSource.gallery,
        );
        imageBytes = await picked?.readAsBytes();
      }
      if (!mounted) {
        return;
      }
      if (imageBytes == null) {
        setState(() => _isPicking = false);
        return;
      }
      // Show the placeholder for a frame before the thumbnail takes over, so
      // the tap is acknowledged even when the photo is huge.
      setState(() {
        _isPicking = false;
        _pendingPhotos++;
        _adding = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) {
        return;
      }
      setState(() => _pendingPhotos--);
      _addPhoto(imageBytes, fromCamera: false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPicking = false;
        _cameraError = error.toString();
      });
    }
  }

  /// A new photo is in hand: it is always used. The thumbnail appears first;
  /// the quality check then runs in the background and only adds a note to
  /// it, so a slow check never delays the photo or the Scan button.
  void _addPhoto(Uint8List bytes, {required bool fromCamera}) {
    if (fromCamera) _stopCamera();
    final photo = _SheetPhoto(bytes);
    setState(() {
      _isTakingPicture = false;
      _photos.add(photo);
      _adding = false;
    });
    unawaited(_checkQuality(photo));
  }

  Future<void> _checkQuality(_SheetPhoto photo) async {
    try {
      final quality = await (widget.assess ?? assessPhotoFast)(photo.bytes);
      if (!mounted || !_photos.contains(photo)) return;
      setState(() => photo.quality = quality);
    } on Object {
      // No note is better than a failed photo.
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _photos.removeAt(index);
      _adding = false;
    });
  }

  /// Stops the camera without touching the rest of the sheet's state.
  void _stopCamera() {
    _cameraGeneration++;
    _cameraController?.dispose();
    _cameraController = null;
    _seamTake = null;
    _initializeCameraFuture = null;
    _cameraStarted = false;
  }

  String get _title {
    if (_cameraStarted) return 'Take a picture';
    if (_hasStrip) return 'Your fridge photos';
    if (_photos.isNotEmpty) return 'Add another photo';
    return 'Add a fridge photo';
  }

  bool get _hasStrip =>
      (_photos.isNotEmpty || _pendingPhotos > 0) && !_adding;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (_cameraStarted)
                  IconButton(
                    onPressed: _backToChooser,
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back),
                  )
                else if (_adding)
                  IconButton(
                    onPressed: () => setState(() => _adding = false),
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back),
                  ),
                Expanded(
                  child: Text(
                    _title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: Spacing.s12),
            Expanded(
              child: _cameraStarted
                  ? _buildCameraMode(context)
                  : _hasStrip
                  ? _buildPhotoStrip(context)
                  : _buildChooser(context),
            ),
          ],
        ),
      ),
    );
  }

  /// The initial two-option screen: take a live picture, or upload an existing
  /// screenshot/photo.
  Widget _buildChooser(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: _startCamera,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Take a picture'),
          ),
          const SizedBox(height: Spacing.s12),
          OutlinedButton.icon(
            onPressed: _isPicking ? null : _uploadPhoto,
            icon: _isPicking
                ? const _ButtonSpinner()
                : const Icon(Icons.photo_library_outlined),
            label: const Text('Upload a photo'),
          ),
        ],
      ),
    );
  }

  /// What the quality check found, as a short note under the thumbnail.
  String? _noteFor(PhotoQuality? quality) {
    if (quality == null) return null;
    if (quality.isBlurry) return 'Looks blurry — retake if you can';
    if (quality.isOverExposed) return 'Bright light behind';
    return null;
  }

  Widget _buildThumb(BuildContext context, int i) {
    final theme = Theme.of(context);
    final note = _noteFor(_photos[i].quality);
    final noteColor = theme.brightness == Brightness.dark
        ? Colors.amber.shade300
        : Colors.amber.shade900;
    return SizedBox(
      key: Key('fridgePhotoThumb$i'),
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    top: Spacing.s8,
                    right: Spacing.s8,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Image.memory(
                      _photos[i].bytes,
                      fit: BoxFit.cover,
                      // A 120 px tile must not decode a 24 MP photo.
                      cacheWidth: 240,
                      semanticLabel: 'Photo ${i + 1}',
                      errorBuilder: (context, error, stackTrace) =>
                          const ColoredBox(color: Colors.black12),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton.filledTonal(
                    key: Key('fridgePhotoRemove$i'),
                    onPressed: () => _removePhoto(i),
                    tooltip: 'Remove photo ${i + 1}',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ),
              ],
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.s4),
              child: Semantics(
                key: Key('fridgePhotoNote$i'),
                label: 'Photo ${i + 1}: $note',
                child: ExcludeSemantics(
                  child: Text(
                    note,
                    style: theme.textTheme.bodySmall?.copyWith(color: noteColor),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Stands in for a photo whose bytes arrived but whose thumbnail isn't
  /// ready yet.
  Widget _buildPendingThumb(BuildContext context) {
    return SizedBox(
      key: const Key('fridgePhotoPending'),
      width: 120,
      height: 120,
      child: Semantics(
        liveRegion: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _ButtonSpinner(),
              const SizedBox(height: Spacing.s8),
              Text(
                'Adding photo…',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The photos so far as removable thumbnails, with the way to add more and
  /// to start the scan.
  Widget _buildPhotoStrip(BuildContext context) {
    final count = _photos.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Wrap(
              spacing: Spacing.s12,
              runSpacing: Spacing.s12,
              children: [
                for (var i = 0; i < count; i++) _buildThumb(context, i),
                for (var i = 0; i < _pendingPhotos; i++)
                  _buildPendingThumb(context),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.s12),
        if (count + _pendingPhotos < maxFridgePhotos) ...[
          OutlinedButton.icon(
            key: const Key('fridgeAddAnotherPhoto'),
            onPressed: () => setState(() => _adding = true),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Add another photo'),
          ),
          const SizedBox(height: Spacing.s8),
        ],
        FilledButton(
          key: const Key('fridgeScanPhotos'),
          onPressed: count == 0
              ? null
              : () => Navigator.of(context).pop([
                  for (final photo in _photos) photo.bytes,
                ]),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          child: Text(count == 1 ? 'Scan photo' : 'Scan $count photos'),
        ),
      ],
    );
  }

  /// The live-camera experience, with an upload fallback when the hardware
  /// cannot be opened.
  Widget _buildCameraMode(BuildContext context) {
    final cameraReady = _cameraError == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildCameraPreview(context)),
        const SizedBox(height: Spacing.s16),
        if (cameraReady)
          FilledButton.icon(
            onPressed: _isTakingPicture ? null : _capturePhoto,
            icon: _isTakingPicture
                ? const _ButtonSpinner()
                : const Icon(Icons.camera_alt),
            label: Text(_isTakingPicture ? 'Hold still…' : 'Take picture'),
          )
        else
          FilledButton.icon(
            onPressed: _isTakingPicture || _isPicking ? null : _uploadPhoto,
            icon: _isPicking
                ? const _ButtonSpinner()
                : const Icon(Icons.photo_library_outlined),
            label: const Text('Upload a photo instead'),
          ),
      ],
    );
  }

  Widget _buildCameraPreview(BuildContext context) {
    final cameraController = _cameraController;
    final initializeCameraFuture = _initializeCameraFuture;

    if (_cameraError != null) {
      final theme = Theme.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.videocam_off_outlined,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: Spacing.s12),
              Text(
                "Can't open the camera",
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Spacing.s8),
              Text(
                'Close other apps using it, or upload a photo instead.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_seamTake != null) {
      return const ColoredBox(color: Colors.black);
    }

    if (cameraController == null || initializeCameraFuture == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<void>(
      future: initializeCameraFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              child: AspectRatio(
                aspectRatio: cameraController.value.aspectRatio,
                child: CameraPreview(cameraController),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Shown in the edit sheet for a "Maybe" item: the scan's other guesses and
/// a one-tap confirm.
class _ScanReviewPanel extends StatelessWidget {
  const _ScanReviewPanel({
    required this.review,
    required this.onLooksRight,
    required this.onPickAlternative,
  });

  final ScanReview review;
  final VoidCallback onLooksRight;
  final ValueChanged<String> onPickAlternative;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'The scan wasn\'t sure about this one.',
          style: theme.textTheme.bodyMedium,
        ),
        if (review.alternatives.isNotEmpty) ...[
          const SizedBox(height: Spacing.s8),
          Wrap(
            spacing: Spacing.s8,
            runSpacing: Spacing.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Or:', style: theme.textTheme.labelLarge),
              for (final alternative in review.alternatives)
                ActionChip(
                  key: Key('scanAlternative_$alternative'),
                  label: Text(alternative),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onPressed: () => onPickAlternative(alternative),
                ),
            ],
          ),
        ],
        const SizedBox(height: Spacing.s8),
        OutlinedButton.icon(
          key: const Key('scanLooksRight'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: onLooksRight,
          icon: const Icon(Icons.check),
          label: const Text('Looks right'),
        ),
      ],
    );
  }
}

class AddFoodSheet extends StatefulWidget {
  const AddFoodSheet({super.key, this.foodItem, this.onDelete});

  final FoodItem? foodItem;

  /// Edit mode only: deletes the item (staged until the fridge is saved).
  final VoidCallback? onDelete;

  @override
  State<AddFoodSheet> createState() => _AddFoodSheetState();
}

class _AddFoodSheetState extends State<AddFoodSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _imagePicker = ImagePicker();

  Uint8List? _imageBytes;
  FoodType _foodType = FoodType.other;
  DateTime? _expiryDate;

  bool get _isEditing => widget.foodItem != null;

  @override
  void initState() {
    super.initState();

    final foodItem = widget.foodItem;
    if (foodItem == null) {
      return;
    }

    _nameController.text = foodItem.name;
    _amountController.text = foodItem.amount;
    _descriptionController.text = foodItem.description ?? '';
    _imageBytes = foodItem.imageBytes;
    _foodType = foodItem.foodType;
    _expiryDate = foodItem.expiryDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);

    if (image == null) {
      return;
    }

    final imageBytes = await image.readAsBytes();

    setState(() {
      _imageBytes = imageBytes;
    });
  }

  /// "Looks right": keeps the item as scanned and drops the Maybe mark.
  void _confirmScan() {
    Navigator.of(context).pop(widget.foodItem!.copyWith(clearScanReview: true));
  }

  /// Renames the item to one of the scan's other guesses and drops the mark.
  void _pickAlternative(String alternative) {
    Navigator.of(context).pop(
      widget.foodItem!.copyWith(name: alternative, clearScanReview: true),
    );
  }

  void _saveFoodItem() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(
      FoodItem(
        name: _nameController.text.trim(),
        amount: _amountController.text.trim(),
        foodType: _foodType,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        imageBytes: _imageBytes,
        expiryDate: _expiryDate,
      ),
    );
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final initial = _expiryDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );

    if (picked != null) {
      setState(() {
        _expiryDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.s16,
        Spacing.s16,
        Spacing.s16,
        bottomInset + Spacing.s16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEditing ? 'Edit food' : 'Add food',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  // Top-right delete, spelled out in the error colour so it
                  // never reads as a close button.
                  if (_isEditing && widget.onDelete != null)
                    TextButton.icon(
                      key: const Key('fridgeEditDelete'),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onDelete!();
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: Semantics(
                        label: 'Delete item',
                        excludeSemantics: true,
                        child: const Text('Delete'),
                      ),
                    ),
                ],
              ),
              if (widget.foodItem?.scanReview case final review?) ...[
                const SizedBox(height: Spacing.s12),
                _ScanReviewPanel(
                  review: review,
                  onLooksRight: _confirmScan,
                  onPickAlternative: _pickAlternative,
                ),
              ],
              const SizedBox(height: Spacing.s16),
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.add_photo_alternate),
                label: Text(_imageBytes == null ? 'Add photo' : 'Change photo'),
              ),
              if (_imageBytes != null) ...[
                const SizedBox(height: Spacing.s12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Image.memory(
                    _imageBytes!,
                    height: 160,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
              const SizedBox(height: Spacing.s16),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Food name'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter a food name';
                  }

                  return null;
                },
              ),
              const SizedBox(height: Spacing.s12),
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  hintText: 'Example: 2 cups, 1 carton, 12 eggs',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter amount';
                  }

                  return null;
                },
              ),
              const SizedBox(height: Spacing.s12),
              DropdownButtonFormField<FoodType>(
                initialValue: _foodType,
                decoration: const InputDecoration(labelText: 'Food type'),
                items: [
                  for (final foodType in FoodType.values)
                    DropdownMenuItem(
                      value: foodType,
                      child: Row(
                        children: [
                          Icon(foodType.icon),
                          const SizedBox(width: Spacing.s12),
                          Text(foodType.label),
                        ],
                      ),
                    ),
                ],
                onChanged: (foodType) {
                  if (foodType == null) {
                    return;
                  }

                  setState(() {
                    _foodType = foodType;
                  });
                },
              ),
              const SizedBox(height: Spacing.s12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Expiry date (optional)',
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _expiryDate == null
                            ? 'Not set'
                            : MaterialLocalizations.of(
                                context,
                              ).formatMediumDate(_expiryDate!),
                      ),
                    ),
                    if (_expiryDate != null)
                      IconButton(
                        tooltip: 'Clear expiry date',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _expiryDate = null),
                      ),
                    TextButton.icon(
                      onPressed: _pickExpiryDate,
                      icon: const Icon(Icons.event),
                      label: Text(_expiryDate == null ? 'Pick date' : 'Change'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.s12),
              TextFormField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
              ),
              const SizedBox(height: Spacing.s16),
              FilledButton(
                onPressed: _saveFoodItem,
                child: Text(_isEditing ? 'Save changes' : 'Save food'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AgentPage extends StatefulWidget {
  const AgentPage({
    super.key,
    required this.foodItems,
    this.onStartPostMealWalk,
    this.userId,
    this.geminiApiKey = '',
    this.sleepRepository,
    this.glucoseRepository,
    this.mealRepository,
    this.diabetesEnabled = AppFeatures.diabetesEnabled,
    this.preferencesRepository,
    this.savedRecipesStore,
    this.firstMealGuide = false,
    this.onFirstMealGuideDone,
  });

  /// How hard the meal request tries before giving up. Tests replace it with
  /// a zero-delay policy so they don't sit through four 2 s waits.
  @visibleForTesting
  static AiRetryPolicy retryPolicy = const AiRetryPolicy(
    attemptTimeout: Duration(seconds: 45),
  );

  final List<FoodItem> foodItems;
  final VoidCallback? onStartPostMealWalk;
  final String? userId;
  final String geminiApiKey;

  // Optional injection points for the F4 overnight-phenotype context. Real
  // repositories are created on demand when a userId is present.
  final SleepRepository? sleepRepository;
  final GlucoseRepository? glucoseRepository;
  final MealRepository? mealRepository;
  final bool diabetesEnabled;
  final AppPreferencesStore? preferencesRepository;

  /// Where "Save recipe" writes. Defaults to Firestore when signed in.
  final SavedRecipesStore? savedRecipesStore;

  /// Walks a brand-new user through their first recommendation: an example
  /// prompt, a coach card, and a highlighted "Recommend a meal".
  final bool firstMealGuide;

  /// Called once, when the guide has served its purpose (first recipe shown)
  /// or the user skipped it.
  final VoidCallback? onFirstMealGuideDone;

  @override
  State<AgentPage> createState() => AgentPageState();
}

/// Public so the shell can ask whether a recommendation is still in flight
/// (and stop it) before the user leaves the tab.
class AgentPageState extends State<AgentPage> {
  final _budgetController = TextEditingController();
  final _timeController = TextEditingController();
  final _preferencesController = TextEditingController();
  final _feedbackController = TextEditingController();

  bool _useFridgeItems = true;
  bool _hasBudget = false;
  bool _hasTimeShortage = false;
  bool _useMealBalance = false;
  int _recommendationCount = 1;
  late MealType _mealType;
  CookingExperience _cookingExperience = CookingExperience.beginner;
  AgentRequest? _lastRequest;
  List<MealRecommendation> _recommendations = const [];
  final List<String> _feedbackHistory = [];
  bool _isLoadingRecommendation = false;
  String? _recommendationError;

  /// Bumped on every new request and on cancel, so a result that arrives from
  /// an abandoned run can be recognised and dropped.
  int _requestGeneration = 0;

  /// 1-based attempt number of the run in flight. 1 looks like plain loading.
  int _retryAttempt = 1;
  AiCancellation? _cancellation;

  AppPreferencesStore? _preferencesRepository;
  StreamSubscription<bool>? _balancePreferenceSubscription;

  /// Nutrition priorities. [_nutritionPreferences] is what the boxes show and
  /// what a request snapshots; [_confirmedNutrition] is the last value the
  /// store confirmed, which a failed save rolls back to.
  MealNutritionPreferences _nutritionPreferences =
      MealNutritionPreferences.none;
  MealNutritionPreferences _confirmedNutrition = MealNutritionPreferences.none;
  StreamSubscription<MealNutritionPreferences>? _nutritionSubscription;

  /// True once the first saved value arrived (or there is no account to ask).
  bool _nutritionLoaded = false;
  bool _nutritionLoadFailed = false;
  bool _nutritionSaving = false;
  bool _nutritionSaveFailed = false;
  bool _preferencesSheetOpen = false;

  /// Bumped to rebuild the open preferences sheet, which is a separate route
  /// and doesn't rebuild when this state does.
  final _sheetRefresh = ValueNotifier<int>(0);

  /// The boxes are disabled while a save runs, which drops keyboard focus;
  /// these let the toggled box take it back once the save settles.
  final _highProteinFocus = FocusNode();
  final _highCarbsFocus = FocusNode();
  final _highFiberFocus = FocusNode();
  SavedRecipesStore? _savedRecipesStore;
  StreamSubscription<List<SavedRecipe>>? _savedRecipesSubscription;

  /// Fingerprints of the recipes already saved, so each card knows whether to
  /// show "Save recipe" or "Saved".
  Set<String> _savedFingerprints = const {};

  /// Whether the first-meal coach card is still on screen.
  bool _showFirstMealCoach = false;

  /// One-time nudge shown in place of the coach once the first recipe lands.
  bool _showSaveRecipeTip = false;

  static const _firstMealExamplePrompt = 'Something quick and easy';

  /// Ephemeral Q&A transcripts, keyed by dish name. Wiped whenever a new
  /// recommendation is generated, since the conversation no longer applies.
  final Map<String, List<MealQaTurn>> _qaHistory = {};

  /// Whether the one-time "tap any step to ask" tip has already been shown.
  bool _qaTipSeen = false;
  StreamSubscription<bool>? _qaTipSubscription;

  static const _eveningContextService = EveningFoodContextService();

  /// F4 · the user's recent overnight phenotype, loaded once. Null until the
  /// load finishes or when there is no user / no signal.
  OvernightPhenotypeSummary? _overnightSummary;

  static const _examplePrompts = [
    'Quick breakfast',
    "Use what's expiring",
    r'Under $5',
  ];

  @override
  void initState() {
    super.initState();
    _mealType = _defaultMealType(DateTime.now());
    if (widget.firstMealGuide) {
      _showFirstMealCoach = true;
      if (_preferencesController.text.trim().isEmpty) {
        _preferencesController.text = _firstMealExamplePrompt;
      }
    }
    final userId = widget.userId;
    _nutritionLoaded = userId == null;
    if (userId != null) {
      _preferencesRepository =
          widget.preferencesRepository ?? AppPreferencesRepository();
      _listenToNutritionPreferences(userId);
      _balancePreferenceSubscription = _preferencesRepository!
          .watchMealBalanceAgentEnabled(userId)
          .listen((enabled) {
            if (mounted && enabled != _useMealBalance) {
              setState(() => _useMealBalance = enabled);
            }
          });
      _qaTipSubscription = _preferencesRepository!
          .watchMealQaTipSeen(userId)
          .listen((seen) {
            if (mounted && seen != _qaTipSeen) {
              setState(() => _qaTipSeen = seen);
            }
          });
      // Without an injected store and without an initialized Firebase app
      // (widget tests), saving is simply unavailable and the button hides.
      _savedRecipesStore =
          widget.savedRecipesStore ??
          (Firebase.apps.isEmpty ? null : SavedRecipesRepository());
      _savedRecipesSubscription = _savedRecipesStore?.watchAll(userId).listen(
        (saved) {
          if (!mounted) return;
          setState(
            () => _savedFingerprints = {for (final recipe in saved) recipe.id},
          );
        },
        // Saving is a bonus on this screen: if the list can't load, the card
        // simply shows "Save recipe" and the write still works.
        onError: (Object error) => debugPrint('saved recipes stream: $error'),
      );
    }
    if (widget.diabetesEnabled && userId != null) {
      _loadOvernightSummary(userId);
    }
  }

  static MealType _defaultMealType(DateTime now) {
    if (now.hour < 11) return MealType.breakfast;
    if (now.hour < 16) return MealType.lunch;
    return MealType.dinner;
  }

  Future<void> _loadOvernightSummary(String userId) async {
    try {
      final summary = await _eveningContextService.loadRecent(
        userId,
        sleepRepository: widget.sleepRepository,
        glucoseRepository: widget.glucoseRepository,
        mealRepository: widget.mealRepository,
      );
      if (mounted && summary.hasSignal) {
        setState(() => _overnightSummary = summary);
      }
    } catch (_) {
      // Soft feature: if sleep/glucose data isn't available, the agent simply
      // falls back to its default behavior.
    }
  }

  @override
  void dispose() {
    _budgetController.dispose();
    _timeController.dispose();
    _preferencesController.dispose();
    _feedbackController.dispose();
    _balancePreferenceSubscription?.cancel();
    _nutritionSubscription?.cancel();
    _sheetRefresh.dispose();
    _highProteinFocus.dispose();
    _highCarbsFocus.dispose();
    _highFiberFocus.dispose();
    _qaTipSubscription?.cancel();
    _cancellation?.cancel();
    _savedRecipesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _setUseMealBalance(bool value) async {
    setState(() => _useMealBalance = value);
    final userId = widget.userId;
    final repository = _preferencesRepository;
    if (userId == null || repository == null) return;
    try {
      await repository.saveMealBalanceAgentEnabled(userId, value);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't save that preference. Try again."),
        ),
      );
    }
  }

  bool get _nutritionResolved => _nutritionLoaded || _nutritionLoadFailed;

  @visibleForTesting
  AgentRequest? get lastRequest => _lastRequest;

  void _updateNutrition(VoidCallback change) {
    setState(change);
    _sheetRefresh.value++;
  }

  void _listenToNutritionPreferences(String userId) {
    _nutritionSubscription?.cancel();
    _nutritionSubscription = _preferencesRepository!
        .watchMealNutritionPreferences(userId)
        .listen(
          (value) {
            if (!mounted) return;
            _updateNutrition(() {
              _nutritionLoaded = true;
              _nutritionLoadFailed = false;
              _confirmedNutrition = value;
              // A save in flight owns the displayed value until it settles.
              if (!_nutritionSaving) _nutritionPreferences = value;
            });
          },
          onError: (Object error) {
            debugPrint('nutrition preferences stream: $error');
            if (!mounted) return;
            _updateNutrition(() => _nutritionLoadFailed = true);
          },
        );
  }

  void _retryNutritionLoad() {
    final userId = widget.userId;
    if (userId == null || _preferencesRepository == null) return;
    _updateNutrition(() {
      _nutritionLoadFailed = false;
      _nutritionLoaded = false;
    });
    _listenToNutritionPreferences(userId);
  }

  /// Applies [next]. With an account and a successful read it is saved, one
  /// write at a time (the boxes are disabled while it runs) and rolled back
  /// to the last confirmed value if it fails. Without an account, or after a
  /// failed read, it only changes this picker: nothing is written, so an
  /// unread saved value can never be overwritten.
  Future<void> _setNutritionPreferences(
    MealNutritionPreferences next, {
    FocusNode? focusNode,
  }) async {
    if (_nutritionSaving || !_nutritionResolved) return;
    final userId = widget.userId;
    final repository = _preferencesRepository;
    if (userId == null || repository == null || _nutritionLoadFailed) {
      _updateNutrition(() {
        _nutritionPreferences = next;
        _nutritionSaveFailed = false;
      });
      return;
    }
    _updateNutrition(() {
      _nutritionPreferences = next;
      _nutritionSaving = true;
      _nutritionSaveFailed = false;
    });
    try {
      await repository.saveMealNutritionPreferences(userId, next);
      if (!mounted) return;
      _updateNutrition(() {
        _confirmedNutrition = next;
        _nutritionPreferences = next;
        _nutritionSaving = false;
      });
      _restoreNutritionFocus(focusNode);
    } catch (_) {
      if (!mounted) return;
      _updateNutrition(() {
        _nutritionPreferences = _confirmedNutrition;
        _nutritionSaving = false;
        if (_preferencesSheetOpen) _nutritionSaveFailed = true;
      });
      _restoreNutritionFocus(focusNode);
      if (!_preferencesSheetOpen) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_nutritionSaveErrorMessage)),
        );
      }
    }
  }

  /// Hands focus back to the toggled box once it is enabled again, so a
  /// keyboard user keeps their place in the sheet.
  void _restoreNutritionFocus(FocusNode? focusNode) {
    if (focusNode == null || !_preferencesSheetOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _preferencesSheetOpen && focusNode.context != null) {
        focusNode.requestFocus();
      }
    });
  }

  static const _nutritionSaveErrorMessage =
      "Couldn't save your nutrition priorities. Try again.";

  Widget _buildNutritionSection(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = _nutritionResolved && !_nutritionSaving;
    final preferences = _nutritionPreferences;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Nutrition priorities', style: theme.textTheme.titleMedium),
        Text(
          'Pick as many as you like. If they conflict with your budget, '
          "we'll show the tradeoff.",
          style: theme.textTheme.bodySmall,
        ),
        if (!_nutritionResolved)
          Text(
            'Loading your saved nutrition priorities…',
            style: theme.textTheme.bodySmall,
          ),
        if (_nutritionLoadFailed)
          Row(
            children: [
              Expanded(
                child: Text(
                  "Couldn't load your saved nutrition priorities",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
              TextButton(
                key: const Key('agentNutritionRetryButton'),
                onPressed: _retryNutritionLoad,
                child: const Text('Retry'),
              ),
            ],
          ),
        if (_nutritionSaveFailed)
          Text(
            _nutritionSaveErrorMessage,
            key: const Key('agentNutritionSaveError'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        CheckboxListTile(
          key: const Key('agentHighProteinCheckbox'),
          focusNode: _highProteinFocus,
          contentPadding: EdgeInsets.zero,
          title: const Text(MealNutritionPreferences.proteinLabel),
          value: preferences.highProtein,
          onChanged: enabled
              ? (value) => _setNutritionPreferences(
                  preferences.copyWith(highProtein: value ?? false),
                  focusNode: _highProteinFocus,
                )
              : null,
        ),
        CheckboxListTile(
          key: const Key('agentHighCarbsCheckbox'),
          focusNode: _highCarbsFocus,
          contentPadding: EdgeInsets.zero,
          title: const Text(MealNutritionPreferences.carbsLabel),
          value: preferences.highCarbs,
          onChanged: enabled
              ? (value) => _setNutritionPreferences(
                  preferences.copyWith(highCarbs: value ?? false),
                  focusNode: _highCarbsFocus,
                )
              : null,
        ),
        CheckboxListTile(
          key: const Key('agentHighFiberCheckbox'),
          focusNode: _highFiberFocus,
          contentPadding: EdgeInsets.zero,
          title: const Text(MealNutritionPreferences.fiberLabel),
          value: preferences.highFiber,
          onChanged: enabled
              ? (value) => _setNutritionPreferences(
                  preferences.copyWith(highFiber: value ?? false),
                  focusNode: _highFiberFocus,
                )
              : null,
        ),
      ],
    );
  }

  Future<void> _generateRecommendation() async {
    double? budgetPerServing;
    if (_hasBudget) {
      budgetPerServing = parseBudgetPerServing(_budgetController.text);
      if (budgetPerServing == null) {
        // Send the user to the field, with its error showing.
        await _showPreferences(validateBudget: true);
        return;
      }
    }
    final request = AgentRequest(
      useFridgeItems: _useFridgeItems,
      hasBudget: _hasBudget,
      budget: _hasBudget
          ? _budgetController.text.trim().replaceFirst(RegExp(r'^\$\s*'), '')
          : null,
      budgetPerServing: budgetPerServing,
      nutritionPreferences: _nutritionPreferences,
      hasTimeShortage: _hasTimeShortage,
      timeAvailable: _hasTimeShortage ? _timeController.text.trim() : null,
      foodPreferences: _preferencesController.text.trim(),
      mealType: _mealType,
      cookingExperience: _cookingExperience,
      recommendationCount: _recommendationCount,
      fridgeItems: _useFridgeItems ? List.of(widget.foodItems) : const [],
      feedbackHistory: List.of(_feedbackHistory),
      overnightSummary: widget.diabetesEnabled ? _overnightSummary : null,
      diabetesEnabled: widget.diabetesEnabled,
      useMealBalance: _useMealBalance,
    );

    await _loadRecommendation(request);
  }

  Future<void> _showPreferences({bool validateBudget = false}) async {
    final preferencesFormKey = GlobalKey<FormState>();
    _preferencesSheetOpen = true;
    _nutritionSaveFailed = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          void update(VoidCallback change) {
            setState(change);
            setSheetState(() {});
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              Spacing.s16,
              0,
              Spacing.s16,
              Spacing.s16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Form(
              key: preferencesFormKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Preferences',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: Spacing.s8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Use items from my fridge'),
                      subtitle: Text(
                        widget.foodItems.isEmpty
                            ? 'Your fridge is empty right now.'
                            : '${widget.foodItems.length} items available',
                      ),
                      value: _useFridgeItems,
                      onChanged: (value) =>
                          update(() => _useFridgeItems = value),
                    ),
                    CheckboxListTile(
                      key: const Key('agentMealBalanceCheckbox'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Balance my meal'),
                      subtitle: const Text(
                        'Include produce, protein, quality carbs, and fiber.',
                      ),
                      value: _useMealBalance,
                      onChanged: (value) {
                        _setUseMealBalance(value ?? false);
                        setSheetState(() {});
                      },
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: _sheetRefresh,
                      builder: (context, tick, child) =>
                          _buildNutritionSection(context),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Set a budget'),
                      value: _hasBudget,
                      onChanged: (value) => update(() => _hasBudget = value),
                    ),
                    if (_hasBudget) ...[
                      TextFormField(
                        key: const Key('agentBudgetField'),
                        controller: _budgetController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        autovalidateMode: validateBudget
                            ? AutovalidateMode.always
                            : AutovalidateMode.onUserInteraction,
                        decoration: const InputDecoration(
                          labelText: 'Budget per serving',
                          prefixText: r'$',
                        ),
                        validator: (value) =>
                            parseBudgetPerServing(value ?? '') == null
                            ? 'Enter a budget above 0, like 7.50, or turn '
                                  'budget off'
                            : null,
                      ),
                      const SizedBox(height: Spacing.s8),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("I'm in a hurry"),
                      value: _hasTimeShortage,
                      onChanged: (value) =>
                          update(() => _hasTimeShortage = value),
                    ),
                    if (_hasTimeShortage) ...[
                      TextFormField(
                        key: const Key('agentTimeField'),
                        controller: _timeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Time available',
                          suffixText: 'minutes',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter your available time or turn this off'
                            : null,
                      ),
                      const SizedBox(height: Spacing.s16),
                    ],
                    Text(
                      'Cooking difficulty',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: Spacing.s8),
                    Wrap(
                      spacing: Spacing.s8,
                      children: [
                        for (final experience in CookingExperience.values)
                          ChoiceChip(
                            label: Text(experience.label),
                            selected: _cookingExperience == experience,
                            onSelected: (_) =>
                                update(() => _cookingExperience = experience),
                          ),
                      ],
                    ),
                    const SizedBox(height: Spacing.s16),
                    Text(
                      'Number of recommendations',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: Spacing.s8),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 1, label: Text('1')),
                        ButtonSegment(value: 2, label: Text('2')),
                        ButtonSegment(value: 3, label: Text('3')),
                        ButtonSegment(value: 4, label: Text('4')),
                        ButtonSegment(value: 5, label: Text('5')),
                      ],
                      selected: {_recommendationCount},
                      onSelectionChanged: (selection) =>
                          update(() => _recommendationCount = selection.first),
                    ),
                    const SizedBox(height: Spacing.s24),
                    FilledButton(
                      onPressed: () {
                        if (preferencesFormKey.currentState!.validate()) {
                          Navigator.pop(sheetContext);
                        }
                      },
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    _preferencesSheetOpen = false;
  }

  /// F5 · keep this dish, ask for one small optional balancing tweak. Reuses the
  /// existing feedback flow rather than replacing the user's choice.
  Future<void> _makeMoreBalanced(MealRecommendation recommendation) async {
    final base = _lastRequest;
    if (base == null || _isLoadingRecommendation) {
      return;
    }

    final tweak =
        'Keep "${recommendation.dishName}" — do not replace it. Return that '
        'same dish with one small, optional balancing tweak (a protein or fiber '
        'pairing, or a slightly smaller portion of the refined carb) and explain '
        '${widget.diabetesEnabled ? 'the tweak in the glucoseNote.' : 'the tweak in the reason.'}';

    final request = base.copyWith(
      feedbackHistory: [...base.feedbackHistory, tweak],
      recommendationCount: 1,
    );

    await _loadRecommendation(request);
  }

  Future<void> _suggestAnotherMeal() async {
    final feedback = _feedbackController.text.trim();
    if (feedback.isEmpty || _lastRequest == null) {
      return;
    }

    _feedbackController.clear();
    _feedbackHistory.add(feedback);

    final request = _lastRequest!.copyWith(
      feedbackHistory: List.of(_feedbackHistory),
    );

    await _loadRecommendation(request);
  }

  /// Opens the Q&A sheet for [recommendation], scoped to what the user
  /// tapped. Transcripts are held here (not in the card or the sheet) so
  /// closing and reopening the sheet keeps the conversation.
  Future<void> _openQa(
    MealRecommendation recommendation,
    MealQuestionScope scope, {
    String? initialQuestion,
  }) async {
    final showTip = !_qaTipSeen;
    await showMealQaSheet(
      context,
      meal: MealQaContext(
        dishName: recommendation.dishName,
        reason: recommendation.reason,
        ingredients: recommendation.ingredients,
        instructions: recommendation.instructions,
        glucoseNote: widget.diabetesEnabled ? recommendation.glucoseNote : null,
        eveningScore: recommendation.eveningScore,
        usedFridgeItems: recommendation.usedFridgeItems,
        estimatedCostPerServing: recommendation.estimatedCostPerServing,
      ),
      scope: scope,
      // The widget param, not AppEnvironment, so tests can inject a fake key.
      apiKey: widget.geminiApiKey,
      history: _qaHistory[recommendation.dishName] ?? const [],
      onHistoryChanged: (turns) => _qaHistory[recommendation.dishName] = turns,
      showFirstRunTip: showTip,
      onTipSeen: _markQaTipSeen,
      initialQuestion: initialQuestion,
    );
  }

  /// Saves or removes [recommendation]. Writes are never retried
  /// automatically (that could duplicate data); the snackbar offers a manual
  /// `Try again` instead.
  Future<void> _toggleSavedRecipe(MealRecommendation recommendation) async {
    final store = _savedRecipesStore;
    final userId = widget.userId;
    if (store == null || userId == null) return;

    final id = recipeFingerprint(recommendation);
    final wasSaved = _savedFingerprints.contains(id);
    // Optimistic: the stream confirms a moment later.
    setState(
      () => _savedFingerprints = {
        for (final saved in _savedFingerprints)
          if (saved != id) saved,
        if (!wasSaved) id,
      },
    );

    try {
      if (wasSaved) {
        await store.remove(userId, id);
      } else {
        await store.save(userId, recommendation);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              wasSaved
                  ? 'Removed from saved recipes'
                  : 'Saved. Find it on Home under Saved recipes.',
            ),
            persist: false,
            duration: undoSnackBarDuration,
            action: wasSaved
                ? SnackBarAction(
                    label: 'Undo',
                    onPressed: () => _toggleSavedRecipe(recommendation),
                  )
                : null,
          ),
        );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _savedFingerprints = {
          for (final saved in _savedFingerprints)
            if (saved != id) saved,
          if (wasSaved) id,
        },
      );
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              FriendlyErrors.describe(error, context: 'saved recipes'),
            ),
            action: SnackBarAction(
              label: 'Try again',
              onPressed: () => _toggleSavedRecipe(recommendation),
            ),
          ),
        );
    }
  }

  void _markQaTipSeen() {
    if (_qaTipSeen) return;
    setState(() => _qaTipSeen = true);
    final userId = widget.userId;
    final repository = _preferencesRepository;
    if (userId == null || repository == null) return;
    // Best effort: a failed write only means the tip shows once more.
    unawaited(repository.saveMealQaTipSeen(userId).catchError((_) {}));
  }

  /// Whether a recommendation is still on its way. The shell asks this before
  /// letting the user leave the tab.
  bool get isLoadingRecommendation => _isLoadingRecommendation;

  /// Stops the run in flight: no more attempts, and whatever the last one
  /// eventually returns is ignored.
  void cancelRecommendation() {
    _requestGeneration++;
    _cancellation?.cancel();
    _cancellation = null;
    if (!_isLoadingRecommendation) return;
    setState(() {
      _isLoadingRecommendation = false;
      _retryAttempt = 1;
    });
  }

  Future<void> _loadRecommendation(AgentRequest request) async {
    // Anything that comes back tagged with an older generation belongs to a
    // request the user has already replaced or cancelled.
    final generation = ++_requestGeneration;
    final cancellation = AiCancellation();
    _cancellation = cancellation;
    setState(() {
      _lastRequest = request;
      _isLoadingRecommendation = true;
      _retryAttempt = 1;
      _recommendationError = null;
      _recommendations = const [];
      _qaHistory.clear();
    });

    var stale = false;
    try {
      final recommendations = await runWithAiRetry(
        () => GeminiMealService.generate(request),
        policy: AgentPage.retryPolicy,
        cancellation: cancellation,
        onAttempt: (attempt, _) {
          if (!mounted || generation != _requestGeneration) return;
          if (attempt == _retryAttempt) return;
          setState(() => _retryAttempt = attempt);
        },
      );
      stale = !mounted || generation != _requestGeneration;
      if (stale) return;
      setState(() => _recommendations = recommendations);
      if (recommendations.isNotEmpty) _onFirstRecommendationShown();
    } on AiCancelledException {
      stale = true;
    } catch (error) {
      stale = !mounted || generation != _requestGeneration;
      if (stale) return;
      setState(
        () => _recommendationError = FriendlyErrors.ai(
          error,
          action: 'a meal idea',
        ),
      );
    } finally {
      if (!stale && mounted && generation == _requestGeneration) {
        setState(() {
          _isLoadingRecommendation = false;
          _retryAttempt = 1;
        });
      }
    }
  }

  /// Asks before abandoning a recipe request that is still in flight. Returns
  /// true when it is fine to leave. Says nothing about the fridge or saved
  /// recipes: neither is at risk here.
  Future<bool> confirmLeave() async {
    if (!_isLoadingRecommendation) return true;

    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop waiting for your meal idea?'),
        content: const Text(
          "It's still on its way. If you leave now, we'll stop this request.",
        ),
        actions: [
          TextButton(
            key: const Key('agentKeepWaiting'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep waiting'),
          ),
          FilledButton(
            key: const Key('agentLeave'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (leave == true) {
      cancelRecommendation();
      return true;
    }
    return false;
  }

  /// The guide has done its job the moment a recipe is on screen.
  void _onFirstRecommendationShown() {
    if (!_showFirstMealCoach) return;
    setState(() {
      _showFirstMealCoach = false;
      _showSaveRecipeTip = true;
    });
    widget.onFirstMealGuideDone?.call();
  }

  void _skipFirstMealTour() {
    setState(() => _showFirstMealCoach = false);
    widget.onFirstMealGuideDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Spacing.margin),
      children: [
        if (_showFirstMealCoach) ...[
          FirstMealCoachCard(
            onSkipTour: _skipFirstMealTour,
            fridgeIsEmpty: widget.foodItems.isEmpty,
          ),
          const SizedBox(height: Spacing.s16),
        ],
        if (_showSaveRecipeTip) ...[
          _FirstMealDoneTip(
            onDismiss: () => setState(() => _showSaveRecipeTip = false),
          ),
          const SizedBox(height: Spacing.s16),
        ],
        TextFormField(
          key: const Key('agentFoodPrompt'),
          controller: _preferencesController,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What do you want to eat?',
            hintText: 'e.g., Something with eggs',
          ),
        ),
        if (_lastRequest == null) ...[
          const SizedBox(height: Spacing.s12),
          Wrap(
            spacing: Spacing.s8,
            runSpacing: Spacing.s8,
            children: [
              for (final prompt in _examplePrompts)
                ActionChip(
                  label: Text(prompt),
                  onPressed: () =>
                      setState(() => _preferencesController.text = prompt),
                ),
            ],
          ),
        ],
        const SizedBox(height: Spacing.s16),
        Text('Meal type', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: Spacing.s8),
        Wrap(
          spacing: Spacing.s8,
          runSpacing: Spacing.s8,
          children: [
            for (final mealType in MealType.values)
              ChoiceChip(
                key: Key('agentMealType_${mealType.name}'),
                label: Text(mealType.label),
                selected: _mealType == mealType,
                onSelected: (_) => setState(() => _mealType = mealType),
              ),
          ],
        ),
        const SizedBox(height: Spacing.s16),
        Builder(
          builder: (context) {
            final button = SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('recommendMealButton'),
                onPressed:
                    _isLoadingRecommendation ||
                        !_nutritionResolved ||
                        _nutritionSaving
                    ? null
                    : _generateRecommendation,
                icon: const Icon(Icons.auto_awesome),
                label: Text(
                  _isLoadingRecommendation ? 'Thinking…' : 'Recommend a meal',
                ),
              ),
            );
            return _showFirstMealCoach
                ? FirstMealSpotlight(child: button)
                : button;
          },
        ),
        const SizedBox(height: Spacing.s8),
        Align(
          alignment: Alignment.center,
          child: TextButton.icon(
            key: const Key('agentPreferencesButton'),
            onPressed: _isLoadingRecommendation ? null : _showPreferences,
            icon: const Icon(Icons.tune),
            label: const Text('Preferences'),
          ),
        ),
        if (_isLoadingRecommendation) ...[
          const SizedBox(height: Spacing.s24),
          AiRetryStatus(
            attempt: _retryAttempt,
            maxAttempts: AgentPage.retryPolicy.maxAttempts,
          ),
          const _RecommendationSkeleton(),
        ],
        if (_recommendationError != null && _lastRequest != null)
          LoadErrorView(
            message: _recommendationError!,
            onRetry: () => _loadRecommendation(_lastRequest!),
          ),
        if (_recommendations.isNotEmpty) ...[
          const SizedBox(height: Spacing.s24),
          for (final recommendation in _recommendations) ...[
            MealRecommendationCard(
              recommendation: recommendation,
              diabetesEnabled: widget.diabetesEnabled,
              showUnmetHeading: _recommendations.length == 1,
              timeLabel:
                  (_lastRequest?.hasTimeShortage ?? false) &&
                      (_lastRequest?.timeAvailable?.isNotEmpty ?? false)
                  ? '≤ ${_lastRequest!.timeAvailable} min'
                  : null,
              difficultyLabel: _lastRequest?.cookingExperience.label,
              onStartPostMealWalk: widget.onStartPostMealWalk,
              onMakeBalanced: _isLoadingRecommendation
                  ? null
                  : () => _makeMoreBalanced(recommendation),
              isSaved: _savedFingerprints.contains(
                recipeFingerprint(recommendation),
              ),
              onToggleSaved: _savedRecipesStore == null
                  ? null
                  : () => _toggleSavedRecipe(recommendation),
              onAsk: (scope, {String? initialQuestion}) => _openQa(
                recommendation,
                scope,
                initialQuestion: initialQuestion,
              ),
              onLogMeal: widget.userId == null
                  ? null
                  : () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (context) => MealLogPage(
                          userId: widget.userId!,
                          geminiApiKey: widget.geminiApiKey,
                          initialName: recommendation.dishName,
                          diabetesEnabled: widget.diabetesEnabled,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: Spacing.s16),
          ],
          if (widget.userId != null && widget.diabetesEnabled) ...[
            OutlinedButton.icon(
              key: const Key('agentMealLabButton'),
              onPressed: () => AppFeatureNavigation.pushDiabetesPage<void>(
                context,
                diabetesEnabled: widget.diabetesEnabled,
                builder: (context) => MealLabPage(
                  userId: widget.userId!,
                  diabetesEnabled: widget.diabetesEnabled,
                ),
              ),
              icon: const Icon(Icons.insights),
              label: const Text('Meal Lab'),
            ),
            const SizedBox(height: Spacing.s16),
          ],
          TextFormField(
            key: const Key('agentFeedbackField'),
            controller: _feedbackController,
            minLines: 2,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'What should be different?',
            ),
          ),
          const SizedBox(height: Spacing.s12),
          OutlinedButton.icon(
            onPressed: _suggestAnotherMeal,
            icon: const Icon(Icons.refresh),
            label: const Text('Suggest something else'),
          ),
        ],
      ],
    );
  }
}

/// One-time nudge that replaces the first-meal coach once a recipe is on
/// screen, pointing at the one action a new user won't discover on their own.
class _FirstMealDoneTip extends StatelessWidget {
  const _FirstMealDoneTip({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: const Key('firstMealDoneTip'),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.s16,
          Spacing.s8,
          Spacing.s8,
          Spacing.s8,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Nice! Tap Save recipe to keep it on Home.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
            IconButton(
              key: const Key('firstMealDoneTipDismiss'),
              tooltip: 'Dismiss tip',
              onPressed: onDismiss,
              icon: Icon(Icons.close, color: scheme.onSecondaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder shaped like a recipe card, shown while Gemini works so the wait
/// previews the result (NN/g skeleton screens).
class _RecommendationSkeleton extends StatelessWidget {
  const _RecommendationSkeleton();

  @override
  Widget build(BuildContext context) {
    final block = Theme.of(context).colorScheme.surfaceContainerHigh;
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: block,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
    return Semantics(
      liveRegion: true,
      label: 'Finding a meal for you',
      child: ExcludeSemantics(
        child: Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: 180, color: block),
              Padding(
                padding: const EdgeInsets.all(Spacing.s16),
                child: Column(
                  children: [
                    bar(0.6, 24),
                    const SizedBox(height: Spacing.s12),
                    bar(1, 16),
                    const SizedBox(height: Spacing.s8),
                    bar(0.8, 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MealRecommendationCard extends StatelessWidget {
  const MealRecommendationCard({
    super.key,
    required this.recommendation,
    this.diabetesEnabled = AppFeatures.diabetesEnabled,
    this.onStartPostMealWalk,
    this.onLogMeal,
    this.onMakeBalanced,
    this.onAsk,
    this.timeLabel,
    this.difficultyLabel,
    this.isSaved = false,
    this.onToggleSaved,
    this.showBalancingTweak = true,
    this.showUnmetHeading = true,
    this.budgetFromOriginalRequest = false,
  });

  final MealRecommendation recommendation;
  final bool diabetesEnabled;

  /// Whether the "I couldn't meet all your preferences" heading shows. The
  /// Meals tab turns it off when several results share the screen.
  final bool showUnmetHeading;

  /// True for a saved recipe: its budget fit belongs to the request it was
  /// suggested for, not to the user's current settings.
  final bool budgetFromOriginalRequest;
  final VoidCallback? onStartPostMealWalk;
  final VoidCallback? onLogMeal;

  /// Whether this recipe is already in the user's saved recipes.
  final bool isSaved;

  /// Saves or un-saves the recipe. Null hides the control entirely (for
  /// example when nobody is signed in).
  final VoidCallback? onToggleSaved;

  /// A saved recipe is opened from Home without a request behind it, so it
  /// hides "Add a balancing tweak" (which would need one).
  final bool showBalancingTweak;

  /// F5 · "Add a balancing tweak" — keeps this dish but asks for one small,
  /// optional tweak. Null hides the option.
  final VoidCallback? onMakeBalanced;

  /// Time budget the user asked for, e.g. "≤ 20 min". Null hides it.
  final String? timeLabel;

  /// Cooking difficulty the user asked for, e.g. "Beginner". Null hides it.
  final String? difficultyLabel;

  /// Opens the Q&A sheet scoped to whatever the user tapped. When null the
  /// card renders exactly as it did before the feature existed — no chip row
  /// and no tap targets.
  final void Function(MealQuestionScope scope, {String? initialQuestion})?
  onAsk;

  /// Horizontal space an ActionChip spends on its own padding and border,
  /// subtracted so the label constraint leaves room for the chip chrome.
  static const _chipChromeWidth = 48.0;

  /// Wraps a card line in a tap target that asks about that exact line.
  ///
  /// Section headers carry the visible 'Tap a line to ask' signifier.
  Widget _askable({
    required Widget child,
    required MealQuestionScope scope,
    required String semanticLabel,
    Key? key,
  }) {
    if (onAsk == null) return child;
    return InkWell(
      key: key,
      onTap: () => onAsk!(scope),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: Spacing.s4,
            horizontal: Spacing.s4,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Align(alignment: Alignment.centerLeft, child: child),
          ),
        ),
      ),
    );
  }

  /// Shown before there is a URL and when the load fails. Deliberately quiet:
  /// a missing photo is cosmetic, and the recipe below it is the real content.
  Widget _imagePlaceholder(BuildContext context) => Icon(
    Icons.rice_bowl,
    size: 76,
    color: Theme.of(context).colorScheme.onPrimaryContainer,
  );

  static String _money(double value) => value == value.roundToDouble()
      ? '\$${value.toStringAsFixed(0)}'
      : '\$${value.toStringAsFixed(2)}';

  static String _preferenceLabel(String key) => switch (key) {
    MealNutritionPreferences.proteinKey =>
      MealNutritionPreferences.proteinLabel,
    MealNutritionPreferences.carbsKey => MealNutritionPreferences.carbsLabel,
    MealNutritionPreferences.fiberKey => MealNutritionPreferences.fiberLabel,
    _ => key,
  };

  /// Budget and nutrition tradeoff facts, shown persistently under the cost
  /// pills. Empty on the happy path apart from the estimates note.
  List<Widget> _tradeoffs(BuildContext context) {
    final theme = Theme.of(context);
    final mode = recommendation.priorityMode;
    final budget = recommendation.requestBudgetPerServing;
    final upper = recommendation.estimatedCostUpperBoundPerServing;
    final notice = recommendation.constraintNotice?.trim() ?? '';
    final unmet = [
      for (final key in recommendation.unmetNutritionPreferences)
        _preferenceLabel(key),
    ];
    final budgetFirst = mode == priorityModeBudgetFirst;
    final groupLabel = budgetFirst
        ? 'Budget-first option'
        : mode == priorityModeNutritionFirst
        ? 'Nutrition-first option'
        : null;
    final overBudget = budget != null && upper != null && upper > budget;
    final showHeading = showUnmetHeading && budgetFirst && unmet.isNotEmpty;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return [
      if (showHeading) ...[
        const SizedBox(height: Spacing.s8),
        Semantics(
          container: true,
          label:
              "I couldn't meet all your preferences within your budget. Relaxed: ${unmet.join(', ')}",
          child: ExcludeSemantics(
            child: Container(
              key: const Key('mealUnmetHeading'),
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.s12,
                vertical: Spacing.s8,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: Spacing.s8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "I couldn't meet all your preferences within your budget",
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onTertiaryContainer,
                          ),
                        ),
                        const SizedBox(height: Spacing.s4),
                        Text(
                          'Relaxed: ${unmet.join(', ')}',
                          key: const Key('mealRelaxedPreferences'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      if (groupLabel != null || overBudget) ...[
        const SizedBox(height: Spacing.s8),
        Wrap(
          spacing: Spacing.s8,
          runSpacing: Spacing.s8,
          children: [
            if (groupLabel != null)
              Semantics(
                container: true,
                label: groupLabel,
                child: ExcludeSemantics(
                  child: KeyedSubtree(
                    key: const Key('mealPriorityModeLabel'),
                    child: _InfoPill(
                      icon: budgetFirst
                          ? Icons.savings_outlined
                          : Icons.restaurant_menu,
                      label: groupLabel,
                    ),
                  ),
                ),
              ),
            if (overBudget)
              Semantics(
                container: true,
                label: 'Over your budget',
                child: ExcludeSemantics(
                  child: KeyedSubtree(
                    key: const Key('mealOverBudgetLabel'),
                    child: const _InfoPill(
                      icon: Icons.warning_amber_rounded,
                      label: 'Over your budget',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
      if (notice.isNotEmpty) ...[
        const SizedBox(height: Spacing.s8),
        Semantics(
          container: true,
          label: 'Note: $notice',
          child: ExcludeSemantics(
            child: Text(
              notice,
              key: const Key('mealConstraintNotice'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      ],
      if (budget != null) ...[
        const SizedBox(height: Spacing.s8),
        Text(
          budgetFromOriginalRequest
              ? 'Costs are estimates. Budget fit is from when this was suggested (${_money(budget)} per serving).'
              : 'Costs are estimates.',
          key: const Key('mealCostEstimatesNote'),
          style: muted,
        ),
      ],
    ];
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Spacing.s4,
      runSpacing: Spacing.s4,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        if (onAsk != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: Spacing.s4),
              Flexible(
                child: Text(
                  'Tap a line to ask',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _bullet(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 9px top offset centers the dot on bodyLarge's first 24px line.
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 9, right: Spacing.s12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
      ],
    );
  }

  Widget _step(BuildContext context, int number, String text) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.only(right: Spacing.s12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 180,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: recommendation.imageUrl == null
                      ? _imagePlaceholder(context)
                      : Image.network(
                          recommendation.imageUrl!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          semanticLabel: 'Photo of ${recommendation.dishName}',
                          // On web this renders an <img> element instead of
                          // fetching the bytes, so the browser sends no
                          // `Origin` header — the header the image host
                          // answers with a 403.
                          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                              ? child
                              : Center(
                                  child: CircularProgressIndicator(
                                    value: progress.expectedTotalBytes == null
                                        ? null
                                        : progress.cumulativeBytesLoaded /
                                              progress.expectedTotalBytes!,
                                  ),
                                ),
                          errorBuilder: (context, error, stackTrace) =>
                              _imagePlaceholder(context),
                        ),
                ),
                if (recommendation.imageUrl != null)
                  Positioned(
                    left: Spacing.s8,
                    bottom: Spacing.s8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.s8,
                          vertical: Spacing.s4,
                        ),
                        child: Text(
                          'AI-generated image',
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Spacing.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recommendation.dishName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (timeLabel != null ||
                    recommendation.estimatedCostPerServing != null ||
                    difficultyLabel != null) ...[
                  const SizedBox(height: Spacing.s8),
                  Wrap(
                    spacing: Spacing.s8,
                    runSpacing: Spacing.s8,
                    children: [
                      if (timeLabel != null)
                        _InfoPill(icon: Icons.schedule, label: timeLabel!),
                      if (recommendation.estimatedCostPerServing != null)
                        _InfoPill(
                          icon: Icons.payments_outlined,
                          label: recommendation.estimatedCostPerServing!,
                        ),
                      if (difficultyLabel != null)
                        _InfoPill(
                          icon: Icons.signal_cellular_alt,
                          label: difficultyLabel!,
                        ),
                    ],
                  ),
                ],
                ..._tradeoffs(context),
                if (recommendation.eveningScore != null) ...[
                  const SizedBox(height: Spacing.s8),
                  _EveningFitChip(score: recommendation.eveningScore!),
                ],
                const SizedBox(height: Spacing.s8),
                _askable(
                  key: const Key('mealQaReason'),
                  scope: const MealQuestionScope(
                    kind: MealQuestionScopeKind.reason,
                  ),
                  semanticLabel: 'Ask why this meal was picked',
                  child: Text(recommendation.reason),
                ),
                if (recommendation.usedFridgeItems.isNotEmpty) ...[
                  const SizedBox(height: Spacing.s8),
                  _InfoPill(
                    icon: Icons.kitchen_outlined,
                    label:
                        'From your fridge: ${recommendation.usedFridgeItems.join(', ')}',
                  ),
                ],
                if (diabetesEnabled && recommendation.glucoseNote != null) ...[
                  const SizedBox(height: Spacing.s12),
                  _askable(
                    key: const Key('mealQaGlucoseNote'),
                    scope: MealQuestionScope(
                      kind: MealQuestionScopeKind.glucoseNote,
                      quote: recommendation.glucoseNote!,
                    ),
                    semanticLabel: 'Ask about this blood sugar tip',
                    child: _GlucoseNoteChip(note: recommendation.glucoseNote!),
                  ),
                ],
                const SizedBox(height: Spacing.s16),
                _sectionHeader(context, 'Ingredients'),
                const SizedBox(height: Spacing.s4),
                for (
                  var index = 0;
                  index < recommendation.ingredients.length;
                  index++
                )
                  _askable(
                    key: Key('mealQaIngredient_$index'),
                    scope: MealQuestionScope(
                      kind: MealQuestionScopeKind.ingredient,
                      quote: recommendation.ingredients[index],
                      ordinal: index + 1,
                    ),
                    semanticLabel:
                        'Ask about ${recommendation.ingredients[index]}',
                    child: _bullet(context, recommendation.ingredients[index]),
                  ),
                const SizedBox(height: Spacing.s16),
                _sectionHeader(context, 'Instructions'),
                const SizedBox(height: Spacing.s4),
                for (
                  var index = 0;
                  index < recommendation.instructions.length;
                  index++
                )
                  _askable(
                    key: Key('mealQaStep_$index'),
                    scope: MealQuestionScope(
                      kind: MealQuestionScopeKind.step,
                      quote: recommendation.instructions[index],
                      ordinal: index + 1,
                    ),
                    semanticLabel: 'Ask about step ${index + 1}',
                    child: _step(
                      context,
                      index + 1,
                      recommendation.instructions[index],
                    ),
                  ),
                if (onAsk != null &&
                    recommendation.suggestedQuestions.isNotEmpty) ...[
                  const SizedBox(height: Spacing.s16),
                  const Divider(height: 1),
                  const SizedBox(height: Spacing.s12),
                  Text(
                    'Ask about this meal',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: Spacing.s8),
                  // LayoutBuilder so a long question wraps inside its chip
                  // instead of being clipped at the card edge.
                  LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: Spacing.s8,
                      runSpacing: Spacing.s8,
                      children: [
                        for (
                          var index = 0;
                          index < recommendation.suggestedQuestions.length;
                          index++
                        )
                          ActionChip(
                            key: Key('mealQaChip_$index'),
                            label: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: math.max(
                                  0,
                                  constraints.maxWidth - _chipChromeWidth,
                                ),
                              ),
                              child: Text(
                                recommendation.suggestedQuestions[index],
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Submits immediately rather than prefilling — the
                            // whole point is that one tap gets an answer.
                            onPressed: () => onAsk!(
                              const MealQuestionScope.meal(),
                              initialQuestion:
                                  recommendation.suggestedQuestions[index],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.s12),
                  const Divider(height: 1),
                ],
                if (onStartPostMealWalk != null ||
                    (onMakeBalanced != null && showBalancingTweak) ||
                    onToggleSaved != null ||
                    onLogMeal != null) ...[
                  const SizedBox(height: Spacing.s24),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    overflowAlignment: OverflowBarAlignment.end,
                    spacing: Spacing.s8,
                    overflowSpacing: Spacing.s8,
                    children: [
                      if (onStartPostMealWalk != null)
                        TextButton.icon(
                          onPressed: onStartPostMealWalk,
                          icon: const Icon(Icons.directions_walk),
                          label: const Text('Start a 10-minute walk'),
                        ),
                      if (onToggleSaved != null)
                        _SaveRecipeButton(
                          isSaved: isSaved,
                          onPressed: onToggleSaved!,
                        ),
                      if (onMakeBalanced != null && showBalancingTweak)
                        FilledButton.tonalIcon(
                          onPressed: onMakeBalanced,
                          icon: const Icon(Icons.balance),
                          label: const Text('Add a balancing tweak'),
                        ),
                      if (onLogMeal != null)
                        FilledButton.icon(
                          onPressed: onLogMeal,
                          icon: const Icon(Icons.restaurant),
                          label: const Text('Log this meal'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Outlined toggle that keeps a recipe on Home so the user never has to ask
/// the agent for it again. Outlined, because the card already has one filled
/// action ("Log this meal").
class _SaveRecipeButton extends StatelessWidget {
  const _SaveRecipeButton({required this.isSaved, required this.onPressed});

  final bool isSaved;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isSaved
          ? 'Saved. Tap to remove from saved recipes'
          : 'Save recipe',
      child: ExcludeSemantics(
        child: OutlinedButton.icon(
          key: Key(isSaved ? 'recipeUnsaveButton' : 'recipeSaveButton'),
          onPressed: onPressed,
          icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
          label: Text(isSaved ? 'Saved' : 'Save recipe'),
        ),
      ),
    );
  }
}

/// F2 · soft glucose "heads-up" shown as an info chip — informative, never a
/// warning. Uses the tertiary container so it reads as a gentle aside.
class _GlucoseNoteChip extends StatelessWidget {
  const _GlucoseNoteChip({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_outline,
            size: 18,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// F1 · a small "evening fit" indicator for meals eaten close to sleep. Higher
/// scores read as more sleep-compatible; it informs the ordering, it never
/// blocks the user's choice.
class _EveningFitChip extends StatelessWidget {
  const _EveningFitChip({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = score >= 4
        ? 'Good evening fit'
        : score == 3
        ? 'Okay this close to bed'
        : 'Heavier this close to bed';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.bedtime_outlined,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          '$label · $score/5',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s12,
        vertical: Spacing.s4,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: Spacing.s4),
          // Flexible so a long fridge list wraps inside the pill instead of
          // overflowing the card on narrow phones.
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FoodItem {
  const FoodItem({
    required this.name,
    required this.amount,
    required this.foodType,
    this.description,
    this.imageBytes,
    this.expiryDate,
    this.scanReview,
  });

  final String name;
  final String amount;
  final FoodType foodType;
  final String? description;
  final Uint8List? imageBytes;

  /// Set while a fridge scan was unsure of this item; the tile shows a
  /// "Maybe" badge until the user confirms, renames or edits it.
  final ScanReview? scanReview;

  /// When this item is expected to spoil. Drives the neutral expiration-date
  /// ranking and the freshness status shown on the fridge card. Null when
  /// unknown (e.g. legacy items or an AI scan without an estimate).
  final DateTime? expiryDate;

  FoodItem copyWith({
    String? name,
    String? amount,
    FoodType? foodType,
    String? description,
    Uint8List? imageBytes,
    DateTime? expiryDate,
    ScanReview? scanReview,
    bool clearScanReview = false,
  }) {
    return FoodItem(
      scanReview: clearScanReview ? null : scanReview ?? this.scanReview,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      foodType: foodType ?? this.foodType,
      description: description ?? this.description,
      imageBytes: imageBytes ?? this.imageBytes,
      expiryDate: expiryDate ?? this.expiryDate,
    );
  }

  Map<String, dynamic> toFirestore({bool includeCreatedAt = true}) {
    return {
      'name': name,
      'amount': amount,
      'foodType': foodType.label,
      'description': description,
      'expiryDate': expiryDate == null ? null : Timestamp.fromDate(expiryDate!),
      if (scanReview != null) 'scanReview': scanReview!.toFirestore(),
      if (includeCreatedAt) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory FoodItem.fromFirestore(Map<String, dynamic> data) {
    final expiry = data['expiryDate'];
    return FoodItem(
      name: (data['name'] ?? '').toString(),
      amount: (data['amount'] ?? '').toString(),
      foodType: FoodType.fromLabel((data['foodType'] ?? '').toString()),
      description: (data['description'] ?? '').toString().trim().isEmpty
          ? null
          : (data['description'] ?? '').toString(),
      expiryDate: expiry is Timestamp ? expiry.toDate() : null,
      scanReview: ScanReview.fromFirestore(data['scanReview']),
    );
  }
}

class StoredFoodItem {
  const StoredFoodItem({required this.id, required this.foodItem});

  final String id;
  final FoodItem foodItem;

  factory StoredFoodItem.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return StoredFoodItem(
      id: document.id,
      foodItem: FoodItem.fromFirestore(document.data()),
    );
  }
}

enum FoodType {
  produce('Produce', Icons.eco),
  protein('Protein', Icons.egg_alt),
  dairy('Dairy', Icons.icecream),
  grain('Grain', Icons.grain),
  snack('Snack', Icons.cookie),
  drink('Drink', Icons.local_drink),
  other('Other', Icons.restaurant);

  const FoodType(this.label, this.icon);

  final String label;
  final IconData icon;

  static FoodType fromLabel(String label) {
    final normalizedLabel = label.toLowerCase();
    return FoodType.values.firstWhere(
      (foodType) => foodType.label.toLowerCase() == normalizedLabel,
      orElse: () => FoodType.other,
    );
  }
}

enum CookingExperience {
  beginner('Beginner'),
  intermediate('Intermediate'),
  advanced('Advanced');

  const CookingExperience(this.label);

  final String label;
}

enum MealType {
  breakfast('Breakfast'),
  lunch('Lunch'),
  dinner('Dinner'),
  snack('Snack'),
  drink('Drink');

  const MealType(this.label);

  final String label;
}

/// Parses a per-serving budget: a positive, finite decimal with an optional
/// leading `$`. Returns null for anything else (empty, text, zero, negative,
/// NaN, infinity, exponents, separators).
double? parseBudgetPerServing(String input) {
  var text = input.trim();
  if (text.startsWith(r'$')) text = text.substring(1).trimLeft();
  if (!RegExp(r'^(\d+\.?\d*|\.\d+)$').hasMatch(text)) return null;
  final value = double.tryParse(text);
  if (value == null || !value.isFinite || value <= 0) return null;
  return value;
}

class AgentRequest {
  const AgentRequest({
    required this.useFridgeItems,
    required this.hasBudget,
    required this.budget,
    required this.hasTimeShortage,
    required this.timeAvailable,
    required this.foodPreferences,
    required this.mealType,
    required this.cookingExperience,
    required this.recommendationCount,
    required this.fridgeItems,
    required this.feedbackHistory,
    this.overnightSummary,
    this.diabetesEnabled = AppFeatures.diabetesEnabled,
    this.useMealBalance = false,
    this.budgetPerServing,
    this.nutritionPreferences = MealNutritionPreferences.none,
  });

  final bool useFridgeItems;
  final bool hasBudget;
  final String? budget;

  /// The validated numeric form of [budget]; null when no budget is set.
  final double? budgetPerServing;

  /// Snapshot of the user's nutrition priorities when the request was made.
  final MealNutritionPreferences nutritionPreferences;
  final bool hasTimeShortage;
  final String? timeAvailable;
  final String foodPreferences;
  final MealType mealType;
  final CookingExperience cookingExperience;
  final int recommendationCount;
  final List<FoodItem> fridgeItems;
  final List<String> feedbackHistory;

  /// F4 · the user's recent overnight glucose phenotype, when available, so the
  /// agent can softly tailor evening meals. Null when there is no signal.
  final OvernightPhenotypeSummary? overnightSummary;
  final bool diabetesEnabled;
  final bool useMealBalance;

  /// Meals eaten close to sleep, where overnight glucose is most sensitive.
  /// Drives the evening ranking (F1) and time-of-day awareness (F3).
  bool get isEveningMeal =>
      mealType == MealType.dinner || mealType == MealType.snack;

  AgentRequest copyWith({
    List<String>? feedbackHistory,
    bool? hasTimeShortage,
    String? timeAvailable,
    int? recommendationCount,
  }) {
    return AgentRequest(
      useFridgeItems: useFridgeItems,
      hasBudget: hasBudget,
      budget: budget,
      budgetPerServing: budgetPerServing,
      nutritionPreferences: nutritionPreferences,
      hasTimeShortage: hasTimeShortage ?? this.hasTimeShortage,
      timeAvailable: timeAvailable ?? this.timeAvailable,
      foodPreferences: foodPreferences,
      mealType: mealType,
      cookingExperience: cookingExperience,
      recommendationCount: recommendationCount ?? this.recommendationCount,
      fridgeItems: fridgeItems,
      feedbackHistory: feedbackHistory ?? this.feedbackHistory,
      overnightSummary: overnightSummary,
      diabetesEnabled: diabetesEnabled,
      useMealBalance: useMealBalance,
    );
  }
}

class GeminiMealService {
  static String get _apiKey => debugApiKey ?? AppEnvironment.geminiApiKey;
  static const _textModel = 'gemini-3-flash-preview';

  @visibleForTesting
  static http.Client httpClient = http.Client();

  /// Tests set this so `generate` gets past the key check and reaches the
  /// MockClient. Null in production, where the key comes from `.env`.
  @visibleForTesting
  static String? debugApiKey;

  static const _imageHost = 'image.pollinations.ai';

  static Future<List<MealRecommendation>> generate(AgentRequest request) async {
    if (_apiKey.isEmpty) {
      throw const AiRequestException(
        'Missing GEMINI_API_KEY',
        retryable: false,
      );
    }

    final response = await httpClient.post(
      Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_textModel:generateContent',
      ),
      headers: {'Content-Type': 'application/json', 'x-goog-api-key': _apiKey},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': _buildPrompt(request)},
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.7,
          'responseMimeType': 'application/json',
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiRequestException.fromStatus(response.statusCode, response.body);
    }

    // A missing field or an odd shape is the model misbehaving, not a broken
    // request: it comes back as a FormatException so the retry loop tries
    // again. A refusal is typed non-retryable instead.
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final blockReason = _blockReason(data);
      if (blockReason != null) {
        throw AiRequestException(
          'Gemini blocked the request: $blockReason',
          retryable: false,
        );
      }
      final candidates = data['candidates'] as List<dynamic>? ?? [];
      if (candidates.isEmpty) {
        throw const FormatException('Gemini returned no candidates');
      }

      final content = candidates.first as Map<String, dynamic>;
      if (content['finishReason'] == 'SAFETY') {
        throw const AiRequestException(
          'Gemini blocked the answer: SAFETY',
          retryable: false,
        );
      }
      final parts =
          (content['content'] as Map<String, dynamic>)['parts']
              as List<dynamic>;
      if (parts.isEmpty) {
        throw const FormatException('Gemini returned no content');
      }
      final text = (parts.first as Map<String, dynamic>)['text'] as String;
      if (text.trim().isEmpty) {
        throw const FormatException('Gemini returned no text');
      }
      final jsonText = _stripJsonFence(text);

      final decodedJson = jsonDecode(jsonText);
      // A lone object is only an answer to a one-dish request; any other
      // count mismatch is rejected below instead of silently trimmed.
      final List<dynamic> items;
      if (decodedJson is List<dynamic>) {
        items = decodedJson;
      } else if (request.recommendationCount == 1) {
        items = [decodedJson];
      } else {
        throw const FormatException('Gemini returned a single object');
      }
      final recommendations = [
        for (final item in items)
          MealRecommendation.fromJson(item as Map<String, dynamic>),
      ];

      validateMealResponse(
        [for (final r in recommendations) r.priorityData],
        requestedCount: request.recommendationCount,
        preferences: request.nutritionPreferences,
        budgetPerServing: request.budgetPerServing,
      );
      final ordered = request.nutritionPreferences.hasAny
          ? orderByPriorityGroup(recommendations, (r) => r.priorityMode)
          : recommendations;

      final budget = request.budgetPerServing;
      return _attachImages(
        budget == null
            ? ordered
            : [
                for (final r in ordered)
                  r.copyWith(requestBudgetPerServing: budget),
              ],
      );
    } on TypeError catch (error) {
      throw FormatException('Gemini returned an odd shape: $error');
    }
  }

  /// `promptFeedback.blockReason` means the prompt was refused outright;
  /// resending it would be refused again.
  static String? _blockReason(Map<String, dynamic> data) {
    final feedback = data['promptFeedback'];
    if (feedback is! Map<String, dynamic>) return null;
    final reason = feedback['blockReason'];
    return reason is String && reason.isNotEmpty ? reason : null;
  }

  @visibleForTesting
  static String buildPromptForTesting(AgentRequest request) =>
      _buildPrompt(request);

  @visibleForTesting
  static List<MealRecommendation> attachImagesForTesting(
    List<MealRecommendation> recommendations,
  ) => _attachImages(recommendations);

  /// Only builds URLs. The widget layer loads them, which on web means an
  /// `<img>` element rather than a Dart fetch — the fetch is what carried a
  /// localhost `Origin` header and drew an immediate 403 from the host.
  static List<MealRecommendation> _attachImages(
    List<MealRecommendation> recommendations,
  ) => [for (final r in recommendations) _withImageUrl(r)];

  static MealRecommendation _withImageUrl(MealRecommendation recommendation) {
    if (recommendation.imagePrompt.isEmpty) {
      return recommendation;
    }
    return recommendation.copyWith(
      imageUrl: _imageUrl(recommendation.imagePrompt),
    );
  }

  /// Width and height are stated in the prompt as well as the query string:
  /// the host crops to the requested size regardless, so the model has to be
  /// told the shape it is composing for or it centres for a square and loses
  /// the dish to the crop.
  static const _imageWidth = 1280;
  static const _imageHeight = 512;

  static String _imageUrl(String prompt) {
    return Uri(
      scheme: 'https',
      host: _imageHost,
      pathSegments: ['prompt', _imageInstruction(prompt)],
      queryParameters: const {
        'width': '$_imageWidth',
        'height': '$_imageHeight',
        'nologo': 'true',
        'referrer': 'diabetes-app',
      },
    ).toString();
  }

  /// The dish goes first on purpose. With the framing notes in front, the
  /// subject sat ~120 words in and the model drifted off it — same seed, same
  /// size, it returned a cheese tart for a lentil curry. Leading with the
  /// dish and keeping the rest short holds the subject.
  static String _imageInstruction(String prompt) =>
      '$prompt. '
      'Appetizing, realistic photo of this finished dish, for a recipe card — '
      'it shows the cook how their own result will look, so make it genuinely '
      'good: natural light, careful plating, the food clearly the subject. '
      'Compose for a $_imageWidth x $_imageHeight wide banner '
      '(2.5:1 landscape) — a short, wide frame, not a square. Fill that '
      'frame. Keep the dish itself comfortably inside it, but parts of the '
      'wider scene may run past the edges where a tighter crop simply looks '
      'better — a well-framed close-up beats shrinking everything to fit. '
      'No text, labels, logos, or watermarks.';

  static String _buildPrompt(AgentRequest request) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final fridgeItems = request.fridgeItems.isEmpty
        ? 'None. User wants to buy fresh or the fridge is empty.'
        : request.fridgeItems
              .map((item) {
                final description = item.description == null
                    ? ''
                    : ', description: ${item.description}';
                final expiry = item.expiryDate;
                String freshness;
                if (expiry == null) {
                  freshness = ', no expiry date given';
                } else {
                  final expiryDay = DateTime(
                    expiry.year,
                    expiry.month,
                    expiry.day,
                  );
                  final daysLeft = expiryDay.difference(today).inDays;
                  if (daysLeft < 0) {
                    freshness =
                        ', expired ${-daysLeft} day(s) ago — use with judgment or skip';
                  } else if (daysLeft == 0) {
                    freshness = ', expires today — use soon';
                  } else if (daysLeft <= 2) {
                    freshness = ', expires in $daysLeft day(s) — use soon';
                  } else {
                    freshness = ', expires in $daysLeft day(s)';
                  }
                }
                final unconfirmed = item.scanReview == null
                    ? ''
                    : ' (unconfirmed)';
                return '- ${item.name}: ${item.amount}, type: ${item.foodType.label}$description$freshness$unconfirmed';
              })
              .join('\n');
    final feedback = request.feedbackHistory.isEmpty
        ? 'None.'
        : request.feedbackHistory.map((item) => '- $item').join('\n');

    final prefs = request.nutritionPreferences;
    final hasPriorities = prefs.hasAny;
    final budgetLimit = request.budgetPerServing;
    final priorityGuidance = hasPriorities
        ? _nutritionPriorityGuidance(request)
        : '';
    final costBoundField = budgetLimit != null
        ? '\n    "estimatedCostUpperBoundPerServing": 3.5,'
        : '';
    final priorityFields = hasPriorities
        ? '\n    "priorityMode": "allPreferences",\n    "unmetNutritionPreferences": [],\n    "constraintNotice": null,'
        : '';
    final priorityFieldNotes = [
      if (budgetLimit != null)
        ' Set "estimatedCostUpperBoundPerServing" to a finite number of at least 0: the same estimate as "estimatedCostPerServing", taken as its upper end, in the budget\'s currency.',
      if (budgetLimit != null && !hasPriorities)
        ' Keep every dish\'s estimatedCostUpperBoundPerServing at or under the budget per serving.',
      if (hasPriorities)
        ' Set "priorityMode", "unmetNutritionPreferences" (only values from: ${prefs.selectedKeys.join(', ')}) and "constraintNotice" (a string, or null when there is nothing to explain) exactly as the nutrition priority rules above describe.',
    ].join();

    final balanceGuidance = request.useMealBalance
        ? '''

The user chose meal-balance guidance. Honor their requested food, preferences, allergies, budget, time, and available ingredients first. When practical, build each recommendation around these flexible wellness anchors:
- About 20-30 g protein.
- About 7-8 g fiber.
- About 1.5 cups of produce or half the plate as produce, emphasizing vegetables while still counting fruit.
- About 250-500 mL water or another unsweetened drink with or near the meal.
- A plate or mixed-dish equivalent near 50% produce, 25% protein, and 25% quality carbohydrate.
- Keep added sugar and saturated fat as a minority of the meal's calories, favoring whole ingredients over heavily processed or sugary ones when it fits the request.
Briefly explain the balance in the reason. Do not reject a requested food or make medical claims if every target cannot be met.${hasPriorities ? '\nThese anchors are soft. When nutrition priorities are active, the selected nutrition priorities and any fallback groups below take precedence over them.' : ''}'''
        : '';

    final substitutionGuidance = request.useFridgeItems
        ? '''

If a recipe would normally call for an ingredient not present in the fridge list, prefer a reasonable substitute that is already in the fridge when it keeps the dish practical (for example, any bean for another bean, yogurt for sour cream, any leafy green for another). Only fall back to a new ingredient to buy when no reasonable substitute exists. When you make a substitution, mention it briefly in "reason".'''
        : '';

    // F1 + F3 · evening ranking and time-of-day awareness. Only for meals eaten
    // close to sleep; never refuses the request, just orders and annotates.
    final eveningGuidance = request.diabetesEnabled && request.isEveningMeal
        ? '''

This is an evening meal, eaten within a few hours of sleep, when overnight glucose is most sensitive to what and how much is eaten. Without refusing or replacing what they asked for:
- Gently prefer options built around fiber, protein, and unsaturated fats (legumes, yogurt, fish, tofu, oats, vegetables, olive oil), and lightly downrank late refined carbs and heavy saturated-fat plates.${hasPriorities ? ' This is soft guidance: it never overrides the selected nutrition priorities (for example, do not downrank a dish for being carbohydrate-forward when High carbs is selected) or the fallback groups.' : ''}
- ${hasPriorities ? 'The order of the list follows the fallback groups when they apply (budget-first group first, then nutrition-first); within a group, or when no fallback applies, you may put the most sleep-compatible option first.' : 'Order the recommendations so the most sleep-compatible option comes first.'}
- Lean slightly toward lighter, earlier-friendly portions, but still honor the user's request.
- For each dish, set "eveningScore" from 1 (heavy or late-carb-forward) to 5 (light and sleep-friendly).
- When a dish is carb-forward or heavy this close to bed, keep it in the list and add a short, friendly "glucoseNote" suggesting an optional pairing or tweak that softens the overnight rise (for example, pairing with something already in the fridge). Frame it as a helpful heads-up, never a warning or a rule.${hasPriorities ? ' The glucoseNote stays optional and never vetoes a selected nutrition priority.' : ''}'''
        : '';

    // F4 · soft personalization from the user's recent overnight phenotype.
    final overnightContext =
        request.diabetesEnabled &&
            request.isEveningMeal &&
            (request.overnightSummary?.hasSignal ?? false)
        ? '''

Personal overnight context (soft, observational — do not diagnose or alarm):
${request.overnightSummary!.promptContext}
Use this only to gently tailor the evening ordering and the glucoseNote. The user's requested dish always stays available.'''
        : '';

    return '''
You are a supportive meal companion inside a dieting, wellness, and budgeting app.

Honor what the user actually wants to eat first, then — only when it genuinely helps — add gentle, optional insight. Never refuse a reasonable request, lecture, or swap the user's dish for something they did not ask for.

Recommend exactly ${request.recommendationCount} affordable, homemade dishes that match the request. Favor protein, vegetables or fruit, fiber-rich carbs, and reasonable portions when it fits what they asked for, and lean away from mostly fried, sugary, or ultra-processed meals — but the user's request always comes first.

The user selected this meal type:
${request.mealType.label}

Match the selected meal type and the user's preferences closely. If the user asks for drinks, smoothies, fruit, bananas, or snacks, do not default to chicken, rice, turkey, or dinner food unless the user's other requirements clearly ask for that.

User food preferences:
${request.foodPreferences}

Cooking experience:
${request.cookingExperience.label}

Budget:
${request.hasBudget ? '\$${request.budget}' : 'No budget selected, but still keep it affordable.'}
As a rough cost anchor: legumes, eggs, rice, pasta, oats, and seasonal produce tend to be cheap per serving; fresh meat, fish, seafood, and out-of-season produce tend to be pricier. Use this only as a loose guide for affordability language and the estimatedCostPerServing field below, not a strict rule.

Time availability:
${request.hasTimeShortage ? '${request.timeAvailable}. If needed, prefer quick, simple meals that can be made in this time.' : 'No time shortage specified. Any reasonable cooking time is fine.'}

Use fridge items:
${request.useFridgeItems ? 'Yes, use fridge items when helpful.' : 'No, recommend buying everything fresh.'}

Pantry staples:
Assume common long-shelf staples are already available even if not listed or scanned — salt, pepper, cooking oil, common dried spices/herbs, sugar, flour, rice, and pasta (use reasonable judgment for what counts as a staple). Do not penalize a recipe, call these "missing," or list them as items the user needs to buy.

Fridge items:
Use the amount exactly as the user wrote it when they include a measurement. If the amount is only a number, use the default unit of the item. For example, "2 cups" stays 2 cups, but "12" for eggs means 12 eggs. When it fits the user's request, prefer using items marked "use soon" or already expired-but-usable so less food goes to waste; never force an item that doesn't fit the dish.
$fridgeItems

Feedback from the user about earlier suggestions:
$feedback$priorityGuidance$balanceGuidance$eveningGuidance$overnightContext$substitutionGuidance

Return only valid JSON as an array with exactly ${request.recommendationCount} objects. Each object must use this exact shape:
[
  {
    "dishName": "string",
    "imagePrompt": "short realistic food photo prompt for this dish",
    "reason": "string",
    "ingredients": ["string"],
    "instructions": ["string"],
    "usedFridgeItems": ["string"],
    "estimatedCostPerServing": "string, e.g. \\"\$2-3/serving\\"",
    "suggestedQuestions": ["string"],$costBoundField$priorityFields
    ${request.diabetesEnabled ? '"glucoseNote": "optional short friendly heads-up, or empty string",' : ''}
    "eveningScore": 4
  }
]
${request.diabetesEnabled ? 'Only include a glucoseNote when it genuinely helps; otherwise use an empty string.' : 'Do not include glucose or diabetes advice.'} Only set eveningScore for evening meals; otherwise use null. Set "usedFridgeItems" to the exact names (from the fridge items list above) that this recipe actually uses; use an empty array if none apply or fridge items were not used. Set "estimatedCostPerServing" to a short rough estimate like "\$2-3/serving"; use your best judgment even without exact prices. Set "suggestedQuestions" to exactly 3 short questions this user would plausibly ask about this dish, written in their own casual first-person voice, that the rest of this card does not already answer; keep each under 8 words and never ask about medication or dosing.$priorityFieldNotes
''';
  }

  static String _formatAmount(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

  /// The single authoritative conflict order plus the nutrition priority and
  /// budget-fallback rules. Only built when priorities are selected.
  static String _nutritionPriorityGuidance(AgentRequest request) {
    final prefs = request.nutritionPreferences;
    final count = request.recommendationCount;
    final limit = request.budgetPerServing;
    final lines = <String>[
      if (prefs.highProtein)
        '- High protein: build the meal around practical protein ingredients (for example eggs, legumes, tofu, yogurt, fish, poultry). Do not promise gram amounts.',
      if (prefs.highCarbs)
        '- High carbs: make the meal more carbohydrate-forward using suitable grains, legumes, fruit, or starchy vegetables, not added sugar.',
      if (prefs.highFiber)
        '- High fiber: favor practical fiber-rich ingredients (for example beans, lentils, whole grains, vegetables, fruit, oats). Do not promise gram amounts.',
    ];
    final hierarchy = [
      'The user\'s explicitly requested dishes, allergies, food safety, and practical time limits.',
      if (limit != null) 'The budget and the fallback groups described below.',
      'The selected nutrition priorities.',
      'Soft guidance: meal balance and evening suggestions. They never override anything above.',
    ];
    final buffer = StringBuffer('''


Nutrition priorities (selected: ${prefs.selectedLabels.join(', ')}). All selected priorities are equal; none outranks another.
${lines.join('\n')}

When requirements conflict, this order is authoritative and overrides any softer guidance elsewhere in this prompt:
${[for (var i = 0; i < hierarchy.length; i++) '${i + 1}. ${hierarchy[i]}'].join('\n')}
''');
    if (limit == null) {
      buffer.write(
        '\nNo budget limit applies, so there is no fallback split: keep exactly $count recommendations, prioritize the selected nutrients, and set "priorityMode" to "allPreferences" for every meal. If a meal still does not meet a selected priority, list it in "unmetNutritionPreferences" and explain briefly in "constraintNotice".',
      );
    } else {
      final split = fallbackSplit(count);
      final budgetText = '\$${_formatAmount(limit)}';
      buffer.write('''

The per-serving budget is $budgetText. "priorityMode" for each meal is one of "allPreferences", "nutritionFirst", or "budgetFirst". "unmetNutritionPreferences" lists which selected priorities (${prefs.selectedKeys.map((key) => '"$key"').join(', ')}) the meal does not meet.
- If every one of the $count meals can satisfy all selected priorities within the budget, set every meal to "allPreferences" with an empty "unmetNutritionPreferences" and a null "constraintNotice". Do not force a fallback.
- Otherwise use exactly ${split.budgetFirst} "budgetFirst" and ${split.nutritionFirst} "nutritionFirst" meal(s), no "allPreferences" meals, and every one of them needs a non-empty "constraintNotice".
- "budgetFirst": stays at or under the budget (its estimatedCostUpperBoundPerServing must not exceed $budgetText) and may relax some selected priorities. List the relaxed ones in "unmetNutritionPreferences"; the notice names them and says you couldn't find a meal meeting all the preferences within the budget.
- "nutritionFirst": meets all selected priorities even if it costs more than the budget. The notice states how far it goes over the budget. List nothing in "unmetNutritionPreferences" unless a priority is still unmet.
- Write notices in a friendly first-person voice, for example "I couldn't find a meal meeting all your preferences within your budget". Never claim that no such meal exists.
- Put the "budgetFirst" meals first in the array, then the "nutritionFirst" meals.
- Never use a fallback just because the budget is tight if a fitting meal exists. Do not decide which priorities are unreachable from dish names alone; estimate the cost of the actual recipe.
''');
    }
    return buffer.toString();
  }

  static String _stripJsonFence(String text) {
    return text
        .trim()
        .replaceFirst(RegExp(r'^```json\s*'), '')
        .replaceFirst(RegExp(r'^```\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
  }
}

class MealRecommendation {
  const MealRecommendation({
    required this.dishName,
    required this.imagePrompt,
    required this.reason,
    required this.ingredients,
    required this.instructions,
    this.glucoseNote,
    this.eveningScore,
    this.usedFridgeItems = const [],
    this.estimatedCostPerServing,
    this.suggestedQuestions = const [],
    this.imageUrl,
    this.priorityMode,
    this.unmetNutritionPreferences = const [],
    this.constraintNotice,
    this.estimatedCostUpperBoundPerServing,
    this.requestBudgetPerServing,
  });

  final String dishName;
  final String imagePrompt;
  final String reason;
  final List<String> ingredients;
  final List<String> instructions;

  /// F2 · optional soft "heads-up" note, shown as an info chip — never a
  /// warning. Null or empty when the agent had nothing helpful to add.
  final String? glucoseNote;

  /// F1 · how sleep-compatible this dish is for an evening meal, 1 (heavy) to
  /// 5 (light and sleep-friendly). Null for non-evening meals.
  final int? eveningScore;

  /// Fridge items (matching the names sent in the prompt) that this recipe
  /// actually uses. Empty when fridge items weren't offered or none apply.
  final List<String> usedFridgeItems;

  /// Free-text rough per-serving cost estimate, e.g. "$2-3/serving". Null
  /// when the model omitted it or it couldn't be parsed as a string.
  final String? estimatedCostPerServing;

  /// Three short questions the user is likely to ask about this dish, used to
  /// seed the "Ask about this meal" chip row. Empty when the model omitted
  /// them, which simply hides the row.
  final List<String> suggestedQuestions;

  /// Where the dish photo lives, loaded by the platform's own image loader
  /// rather than fetched here. On web that matters: a Dart fetch is a CORS
  /// request, and the image host rejects a localhost `Origin` outright.
  final String? imageUrl;

  /// "allPreferences", "nutritionFirst" or "budgetFirst"; null for meals made
  /// without nutrition priorities and for recipes saved before they existed.
  final String? priorityMode;

  /// Selected priorities this meal does not meet ("protein", "carbs", "fiber").
  final List<String> unmetNutritionPreferences;

  /// Friendly explanation shown when a fallback meal relaxes the budget or a
  /// priority.
  final String? constraintNotice;

  /// Numeric per-serving cost ceiling behind [estimatedCostPerServing].
  final double? estimatedCostUpperBoundPerServing;

  /// Per-serving budget of the request this meal was suggested for. Null when
  /// the request had no budget and for recipes saved before it existed.
  final double? requestBudgetPerServing;

  MealPriorityData get priorityData => MealPriorityData(
    priorityMode: priorityMode,
    unmetNutritionPreferences: unmetNutritionPreferences,
    constraintNotice: constraintNotice,
    estimatedCostUpperBoundPerServing: estimatedCostUpperBoundPerServing,
  );

  MealRecommendation copyWith({
    String? imageUrl,
    double? requestBudgetPerServing,
  }) {
    return MealRecommendation(
      dishName: dishName,
      imagePrompt: imagePrompt,
      reason: reason,
      ingredients: ingredients,
      instructions: instructions,
      glucoseNote: glucoseNote,
      eveningScore: eveningScore,
      usedFridgeItems: usedFridgeItems,
      estimatedCostPerServing: estimatedCostPerServing,
      suggestedQuestions: suggestedQuestions,
      imageUrl: imageUrl ?? this.imageUrl,
      priorityMode: priorityMode,
      unmetNutritionPreferences: unmetNutritionPreferences,
      constraintNotice: constraintNotice,
      estimatedCostUpperBoundPerServing: estimatedCostUpperBoundPerServing,
      requestBudgetPerServing:
          requestBudgetPerServing ?? this.requestBudgetPerServing,
    );
  }

  factory MealRecommendation.fromJson(Map<String, dynamic> json) {
    final note = (json['glucoseNote'] as String?)?.trim();
    final score = (json['eveningScore'] as num?)?.toInt();
    final usedItems =
        (json['usedFridgeItems'] as List<dynamic>?)
            ?.map((item) => item.toString())
            .where((item) => item.trim().isNotEmpty)
            .toList() ??
        const [];
    final cost = (json['estimatedCostPerServing'] as String?)?.trim();
    final questions =
        (json['suggestedQuestions'] as List<dynamic>?)
            ?.whereType<String>()
            .map((question) => question.trim())
            .where((question) => question.isNotEmpty)
            .take(3)
            .toList() ??
        const <String>[];
    final mode = (json['priorityMode'] as String?)?.trim();
    final rawUnmet = json['unmetNutritionPreferences'];
    if (rawUnmet != null && rawUnmet is! List) {
      throw const FormatException('unmetNutritionPreferences is not a list');
    }
    final unmet = [
      for (final key in (rawUnmet as List<dynamic>?) ?? const [])
        key.toString().trim(),
    ];
    final notice = (json['constraintNotice'] as String?)?.trim();
    return MealRecommendation(
      dishName: json['dishName'] as String,
      imagePrompt: json['imagePrompt'] as String? ?? '',
      reason: json['reason'] as String,
      ingredients: (json['ingredients'] as List<dynamic>)
          .map((item) => item.toString())
          .toList(),
      instructions: (json['instructions'] as List<dynamic>)
          .map((item) => item.toString())
          .toList(),
      glucoseNote: note == null || note.isEmpty ? null : note,
      eveningScore: score?.clamp(1, 5).toInt(),
      usedFridgeItems: usedItems,
      estimatedCostPerServing: cost == null || cost.isEmpty ? null : cost,
      suggestedQuestions: questions,
      imageUrl: (json['imageUrl'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['imageUrl'] as String).trim(),
      priorityMode: mode == null || mode.isEmpty ? null : mode,
      unmetNutritionPreferences: unmet,
      constraintNotice: notice == null || notice.isEmpty ? null : notice,
      estimatedCostUpperBoundPerServing:
          (json['estimatedCostUpperBoundPerServing'] as num?)?.toDouble(),
      requestBudgetPerServing: (json['requestBudgetPerServing'] as num?)
          ?.toDouble(),
    );
  }

  /// The inverse of [MealRecommendation.fromJson], plus [imageUrl], so a saved
  /// recipe can be reopened later without asking the model again.
  Map<String, dynamic> toJson() => {
    'dishName': dishName,
    'imagePrompt': imagePrompt,
    'reason': reason,
    'ingredients': ingredients,
    'instructions': instructions,
    if (glucoseNote != null) 'glucoseNote': glucoseNote,
    if (eveningScore != null) 'eveningScore': eveningScore,
    'usedFridgeItems': usedFridgeItems,
    if (estimatedCostPerServing != null)
      'estimatedCostPerServing': estimatedCostPerServing,
    'suggestedQuestions': suggestedQuestions,
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (priorityMode != null) 'priorityMode': priorityMode,
    if (unmetNutritionPreferences.isNotEmpty)
      'unmetNutritionPreferences': unmetNutritionPreferences,
    if (constraintNotice != null) 'constraintNotice': constraintNotice,
    if (estimatedCostUpperBoundPerServing != null)
      'estimatedCostUpperBoundPerServing': estimatedCostUpperBoundPerServing,
    if (requestBudgetPerServing != null)
      'requestBudgetPerServing': requestBudgetPerServing,
  };
}
