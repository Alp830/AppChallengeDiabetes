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

import 'app_features.dart';
import 'cgm/data/glucose_repository.dart';
import 'cgm/screens/glucose_settings_page.dart';
import 'design/app_motion.dart';
import 'design/app_radius.dart';
import 'design/app_theme.dart';
import 'design/friendly_errors.dart';
import 'design/load_error.dart';
import 'design/spacing.dart';
import 'firebase_options.dart';
import 'fridge/fridge_scan_dialog.dart';
import 'fridge/selectable_fridge_grid.dart';
import 'home/mvp_home_page.dart';
import 'meals/data/meal_repository.dart';
import 'meals/models/meal_qa_models.dart';
import 'meals/screens/meal_lab_page.dart';
import 'meals/screens/meal_log_page.dart';
import 'meals/screens/meal_qa_sheet.dart';
import 'navigation/app_feature_navigation.dart';
import 'sleep/data/sleep_repository.dart';
import 'sleep/services/evening_food_context_service.dart';
import 'settings/data/app_preferences_repository.dart';

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
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.mark_email_unread_outlined, size: 64),
                const SizedBox(height: 20),
                Text(
                  'Check your inbox',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'We sent a verification link to ${widget.user.email ?? 'your email address'}. Open it before continuing.',
                  textAlign: TextAlign.center,
                ),
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Text(_message!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: isBusy ? null : _checkVerification,
                  child: Text(
                    _isChecking ? 'Checking...' : 'I verified my email',
                  ),
                ),
                TextButton(
                  onPressed: isBusy ? null : _resendVerification,
                  child: Text(_isSending ? 'Sending...' : 'Resend email'),
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
                        _isSignUp ? 'Create account' : 'Sign in',
                        style: Theme.of(context).textTheme.titleLarge,
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
                              : 'Sign in',
                        ),
                      ),
                      const SizedBox(height: Spacing.s12),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
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
  });

  final User user;
  final bool diabetesEnabled;

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

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _fridgeSubscription;

  /// Latest fridge contents; null until the first snapshot arrives.
  List<StoredFoodItem>? _fridgeItems;

  /// Plain-language load error, or null.
  String? _fridgeError;

  @override
  void initState() {
    super.initState();
    _subscribeToFridge();
  }

  @override
  void dispose() {
    _fridgeSubscription?.cancel();
    super.dispose();
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

  Future<void> _goToPage(int index) async {
    if (index == _selectedIndex) {
      return;
    }

    // Guard unsaved fridge edits when leaving the Fridge tab.
    if (_selectedIndex == _fridgeTabIndex) {
      final fridgeState = _fridgeKey.currentState;
      if (fridgeState != null && !await fridgeState.confirmLeave()) {
        return;
      }
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

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: Spacing.s16,
        toolbarHeight: 76,
        title: _HeaderTitle(
          eyebrow: _headerEyebrow(user),
          title: _headerTitle(user),
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

  /// Runs the same unsaved-fridge guard as a tab switch before signing out.
  Future<void> _signOut() async {
    if (_selectedIndex == _fridgeTabIndex) {
      final fridgeState = _fridgeKey.currentState;
      if (fridgeState != null && !await fridgeState.confirmLeave()) return;
    }
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
        if (hour < 12) return 'Good morning';
        if (hour < 17) return 'Good afternoon';
        return 'Good evening';
    }
  }

  String _headerTitle(User user) {
    switch (_selectedIndex) {
      case _fridgeTabIndex:
        return 'Your fridge';
      case _agentTabIndex:
        return 'Meal ideas';
      default:
        return _userDisplayName(user) ?? 'Welcome back';
    }
  }

  Widget _selectedPage(User user) {
    if (_selectedIndex == _homeTabIndex) {
      final displayName = user.displayName?.trim();
      final emailName = user.email?.split('@').first.trim();
      return MvpHomePage(
        userId: user.uid,
        userName: displayName?.isNotEmpty == true ? displayName : emailName,
        onOpenFridge: () => _goToPage(_fridgeTabIndex),
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
      foodItems: [for (final stored in storedItems) stored.foodItem],
      userId: user.uid,
      geminiApiKey: AppEnvironment.geminiApiKey,
      diabetesEnabled: widget.diabetesEnabled,
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
      batch.update(
        collection.doc(id),
        foodItem.toFirestore(includeCreatedAt: false),
      );
    });
    for (final id in changes.deletions) {
      batch.delete(collection.doc(id));
    }

    await batch.commit();
  }
}

/// Two-line contextual header title: a small muted eyebrow over a bold title.
class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle({required this.eyebrow, required this.title});

  final String eyebrow;
  final String title;

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
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge,
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

  /// Items ranked by earliest expiration date (nulls last). The index into the
  /// working [_drafts] list is preserved so edit/remove callbacks address the
  /// correct draft.
  List<MapEntry<int, FoodItem>> get _rankedItems {
    final entries = [
      for (var index = 0; index < _drafts.length; index++)
        MapEntry(index, _drafts[index].item),
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

  void _editDraft(int index, FoodItem item) {
    _mutate(() => _drafts[index].item = item);
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
      messenger.showSnackBar(
        SnackBar(
          content: Text(FriendlyErrors.describe(error, context: 'fridge save')),
          action: SnackBarAction(label: 'Retry', onPressed: save),
        ),
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

    final choice = await showDialog<_UnsavedChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save fridge changes?'),
        content: const Text(
          'You have unsaved changes to your fridge. Do you want to save them '
          'before leaving?',
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
            child: const Text('Save'),
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
            onEdit: (index) => _showEditFoodSheet(context, index),
            onRemoveSelected: (indices) async => _removeDrafts(indices),
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
    if (action == FoodBulkAction.addToMeal ||
        action == FoodBulkAction.saveMeal) {
      final callback = widget.onAddSelectedToMeal;
      if (callback != null) {
        await callback(foods);
        return;
      }
    }

    final messenger = ScaffoldMessenger.of(context);
    final message = switch (action) {
      FoodBulkAction.compareCarbs ||
      FoodBulkAction.totalCarbs ||
      FoodBulkAction.totalCalories =>
        'Nutrition values are not stored for these fridge items yet.',
      FoodBulkAction.groceryList =>
        'A grocery list has not been configured for this app yet.',
      FoodBulkAction.addToMeal ||
      FoodBulkAction.saveMeal => 'Sign in to add these foods to a saved meal.',
      FoodBulkAction.delete => '',
    };
    if (message.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _takeFridgePhoto(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    // The sheet lets the user choose between taking a live picture and uploading
    // an existing screenshot/photo, so it handles both web and mobile.
    final imageBytes = await showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const FridgeCameraSheet(),
    );

    if (imageBytes == null) {
      return;
    }

    if (!context.mounted) return;
    final result = await showDialog<FridgeScanResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => FridgeScanDialog(
        imageBytes: imageBytes,
        detect: FridgePhotoFoodAgent.detectFoods,
      ),
    );
    if (result == null) return; // Cancelled.

    final error = result.error;
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(FriendlyErrors.describe(error, context: 'fridge scan')),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _takeFridgePhoto(context),
          ),
        ),
      );
      return;
    }
    if (result.foods.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No foods found. Try a closer, well-lit photo.'),
        ),
      );
      return;
    }

    _addDrafts(result.foods);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.foods.length == 1
              ? 'Added 1 item — remember to save.'
              : 'Added ${result.foods.length} items — remember to save.',
        ),
      ),
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

  Future<void> _showEditFoodSheet(BuildContext context, int index) async {
    final foodItem = await showModalBottomSheet<FoodItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => AddFoodSheet(
        foodItem: _drafts[index].item,
        onDelete: () => _removeDrafts([index]),
      ),
    );

    if (foodItem != null) {
      _editDraft(index, foodItem);
    }
  }
}

bool _sameFoodItem(FoodItem a, FoodItem b) {
  return a.name == b.name &&
      a.amount == b.amount &&
      a.foodType == b.foodType &&
      a.description == b.description &&
      a.expiryDate == b.expiryDate &&
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

class FridgeCameraSheet extends StatefulWidget {
  const FridgeCameraSheet({super.key});

  @override
  State<FridgeCameraSheet> createState() => _FridgeCameraSheetState();
}

class _FridgeCameraSheetState extends State<FridgeCameraSheet> {
  final ImagePicker _imagePicker = ImagePicker();
  CameraController? _cameraController;
  Future<void>? _initializeCameraFuture;
  String? _cameraError;
  bool _isTakingPicture = false;

  /// The sheet opens on a two-option chooser; the live camera is only started
  /// when the user explicitly taps "Take a picture".
  bool _cameraStarted = false;

  @override
  void dispose() {
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
    _cameraController?.dispose();
    setState(() {
      _cameraStarted = false;
      _cameraController = null;
      _initializeCameraFuture = null;
      _cameraError = null;
    });
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No camera was found on this device.');
      }

      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final cameraController = CameraController(
        camera,
        // High resolution so small labels stay legible for the food scanner.
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );

      _cameraController = cameraController;
      await cameraController.initialize();
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

    if (cameraController == null ||
        initializeCameraFuture == null ||
        _isTakingPicture) {
      return;
    }

    setState(() {
      _isTakingPicture = true;
    });

    try {
      await initializeCameraFuture;
      final photo = await cameraController.takePicture();
      final imageBytes = await photo.readAsBytes();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(imageBytes);
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
    if (_isTakingPicture) {
      return;
    }
    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked == null) {
        return;
      }
      final imageBytes = await picked.readAsBytes();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(imageBytes);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _cameraError = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                  ),
                Expanded(
                  child: Text(
                    _cameraStarted ? 'Take a picture' : 'Add a fridge photo',
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
            const SizedBox(height: 12),
            Expanded(
              child: _cameraStarted
                  ? _buildCameraMode(context)
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
            onPressed: _uploadPhoto,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Upload a screenshot/picture'),
          ),
        ],
      ),
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
        const SizedBox(height: 16),
        if (cameraReady)
          FilledButton.icon(
            onPressed: _isTakingPicture ? null : _capturePhoto,
            icon: const Icon(Icons.camera_alt),
            label: Text(_isTakingPicture ? 'Scanning...' : 'Take Picture'),
          )
        else
          FilledButton.icon(
            onPressed: _isTakingPicture ? null : _uploadPhoto,
            icon: const Icon(Icons.photo_library_outlined),
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
                'The camera is usually in use by another app (video call, '
                'Spotify, OBS…) or blocked by your browser/OS. Close those and '
                'reopen, or just upload a photo below — it works the same for '
                'the food scanner.',
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
          borderRadius: BorderRadius.circular(8),
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

  String _formatExpiryDate(DateTime date) {
    final two = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$two-$day';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEditing ? 'Edit Food' : 'Add Food',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.add_photo_alternate),
                label: Text(
                  _imageBytes == null ? 'Add Picture' : 'Change Picture',
                ),
              ),
              if (_imageBytes != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _imageBytes!,
                    height: 160,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
              const SizedBox(height: 16),
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
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
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
                          const SizedBox(width: 12),
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
              const SizedBox(height: 12),
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
                            : _formatExpiryDate(_expiryDate!),
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saveFoodItem,
                child: Text(_isEditing ? 'Save Changes' : 'Save Food'),
              ),
              if (_isEditing && widget.onDelete != null) ...[
                const SizedBox(height: Spacing.s8),
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
                  label: const Text('Delete item'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class FoodItemTile extends StatelessWidget {
  const FoodItemTile({
    super.key,
    required this.foodItem,
    required this.onEdit,
    required this.onRemove,
  });

  final FoodItem foodItem;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: FoodImage(
          imageBytes: foodItem.imageBytes,
          foodType: foodItem.foodType,
        ),
        title: Text(foodItem.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(foodItem.amount),
            Text(foodItem.foodType.label),
            if (foodItem.description != null) Text(foodItem.description!),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onEdit,
              tooltip: 'Edit food',
              icon: const Icon(Icons.edit),
            ),
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remove food',
              icon: const Icon(Icons.delete),
            ),
          ],
        ),
      ),
    );
  }
}

class FoodImage extends StatelessWidget {
  const FoodImage({
    super.key,
    required this.imageBytes,
    required this.foodType,
  });

  final Uint8List? imageBytes;
  final FoodType foodType;

  @override
  Widget build(BuildContext context) {
    if (imageBytes == null) {
      return CircleAvatar(child: Icon(foodType.icon));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        imageBytes!,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
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
  });

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

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
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
  AppPreferencesStore? _preferencesRepository;
  StreamSubscription<bool>? _balancePreferenceSubscription;

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
    final userId = widget.userId;
    if (userId != null) {
      _preferencesRepository =
          widget.preferencesRepository ?? AppPreferencesRepository();
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
    _qaTipSubscription?.cancel();
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
        const SnackBar(content: Text('Could not save that Agent preference.')),
      );
    }
  }

  Future<void> _generateRecommendation() async {
    final request = AgentRequest(
      useFridgeItems: _useFridgeItems,
      hasBudget: _hasBudget,
      budget: _hasBudget ? _budgetController.text.trim() : null,
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

  Future<void> _showPreferences() async {
    final preferencesFormKey = GlobalKey<FormState>();
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
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Budget',
                          prefixText: r'$',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter a budget or turn budget off'
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

  void _markQaTipSeen() {
    if (_qaTipSeen) return;
    setState(() => _qaTipSeen = true);
    final userId = widget.userId;
    final repository = _preferencesRepository;
    if (userId == null || repository == null) return;
    // Best effort: a failed write only means the tip shows once more.
    unawaited(repository.saveMealQaTipSeen(userId).catchError((_) {}));
  }

  Future<void> _loadRecommendation(AgentRequest request) async {
    setState(() {
      _lastRequest = request;
      _isLoadingRecommendation = true;
      _recommendationError = null;
      _recommendations = const [];
      _qaHistory.clear();
    });

    try {
      final recommendations = await GeminiMealService.generate(request);
      if (!mounted) return;
      setState(() => _recommendations = recommendations);
    } catch (error) {
      debugPrint('meal recommendation: $error');
      if (!mounted) return;
      setState(
        () => _recommendationError = "Couldn't get a meal idea right now.",
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRecommendation = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Spacing.margin),
      children: [
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
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('recommendMealButton'),
            onPressed: _isLoadingRecommendation
                ? null
                : _generateRecommendation,
            icon: const Icon(Icons.auto_awesome),
            label: Text(
              _isLoadingRecommendation ? 'Thinking…' : 'Recommend a meal',
            ),
          ),
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
  });

  final MealRecommendation recommendation;
  final bool diabetesEnabled;
  final VoidCallback? onStartPostMealWalk;
  final VoidCallback? onLogMeal;

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

  Widget _sectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        if (onAsk != null) ...[
          Icon(
            Icons.chat_bubble_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: Spacing.s4),
          Text(
            'Tap a line to ask',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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
                    onMakeBalanced != null ||
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
                      if (onMakeBalanced != null)
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
  });

  final String name;
  final String amount;
  final FoodType foodType;
  final String? description;
  final Uint8List? imageBytes;

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
  }) {
    return FoodItem(
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
  });

  final bool useFridgeItems;
  final bool hasBudget;
  final String? budget;
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

class FridgePhotoFoodAgent {
  static String get _apiKey => AppEnvironment.geminiApiKey;

  /// Gemini 3.1 Pro — strongest vision + label-reading on the Gemini API
  /// (official gemini-2.5-pro successor). Needed because flash-tier models
  /// misread uncommon foods (e.g. dried linden flowers as "bread").
  /// Fallback if this preview ID is retired or costs must drop:
  /// 'gemini-3.6-flash' (stable, ~10x cheaper).
  static const model = 'gemini-3.1-pro-preview';
  static const endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';

  static Future<List<FoodItem>> detectFoods(
    Uint8List imageBytes, {
    http.Client? client,
    String? apiKey,
  }) async {
    final token = apiKey ?? _apiKey;
    if (token.isEmpty) {
      throw Exception('Missing GEMINI_API_KEY');
    }

    final response = await (client ?? http.Client()).post(
      Uri.parse(endpoint),
      headers: {'Content-Type': 'application/json', 'x-goog-api-key': token},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {
                'inline_data': {
                  'mime_type': 'image/jpeg',
                  'data': base64Encode(imageBytes),
                },
              },
              {'text': _buildPrompt()},
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.1,
          // High media resolution spends more image tokens so fine texture
          // (rice grains vs flour powder) and small label text stay visible.
          'mediaResolution': 'MEDIA_RESOLUTION_HIGH',
          // Deep reasoning helps with unlabeled/ambiguous containers.
          'thinkingConfig': {'thinkingLevel': 'high'},
          // Large enough that thinking plus a full grocery bag enumeration
          // cannot truncate the JSON list mid-array.
          'maxOutputTokens': 16384,
          // Force a clean, schema-validated JSON array on the way back.
          'responseMimeType': 'application/json',
          'responseSchema': _responseSchema,
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Gemini food scan failed: ${response.statusCode} ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>? ?? const [];
    if (candidates.isEmpty) {
      throw Exception('Gemini food scan returned no candidates');
    }
    final content =
        (candidates.first as Map<String, dynamic>)['content']
            as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>? ?? const [];
    if (parts.isEmpty) {
      throw Exception('Gemini food scan returned no content');
    }
    final text = (parts.first as Map<String, dynamic>)['text'] as String?;
    if (text == null || text.trim().isEmpty) {
      throw Exception('Gemini food scan returned no text');
    }

    final decodedJson = jsonDecode(_stripJsonFence(text));
    final foodJson = decodedJson is List<dynamic>
        ? decodedJson
        : (decodedJson as Map<String, dynamic>)['foods'] as List<dynamic>? ??
              const [];

    return foodJson
        .whereType<Map<String, dynamic>>()
        .map(_foodItemFromJson)
        .where(
          (foodItem) =>
              foodItem.name.isNotEmpty && !_isPlaceholderName(foodItem.name),
        )
        .toList();
  }

  /// The prompt forbids placeholder items, but guard in code too so an
  /// "Unknown" entry can never reach the fridge UI.
  static bool _isPlaceholderName(String name) {
    final normalized = name.toLowerCase().trim();
    const placeholders = {
      'unknown',
      'unknown item',
      'unknown food',
      'unidentified',
      'unidentified item',
      'unclear',
      'not sure',
      'n/a',
      'none',
    };
    return placeholders.contains(normalized) ||
        normalized.startsWith('unknown ') ||
        normalized.startsWith('unidentified ');
  }

  /// Structured-output schema so Gemini returns a strict JSON array of items,
  /// each with a valid [FoodType] label.
  static Map<String, dynamic> get _responseSchema => {
    'type': 'ARRAY',
    'items': {
      'type': 'OBJECT',
      'properties': {
        'name': {'type': 'STRING'},
        'amount': {'type': 'STRING'},
        'foodType': {
          'type': 'STRING',
          'enum': [for (final foodType in FoodType.values) foodType.label],
        },
        'description': {'type': 'STRING'},
        'expiryEstimateDays': {'type': 'INTEGER', 'nullable': true},
      },
      'required': ['name', 'amount', 'foodType'],
    },
  };

  static FoodItem _foodItemFromJson(Map<String, dynamic> json) {
    final name = (json['name'] ?? '').toString().trim();
    final amount = (json['amount'] ?? '').toString().trim();
    final type = (json['foodType'] ?? '').toString().trim();

    return FoodItem(
      name: name,
      amount: amount.isEmpty ? '1 $name' : amount,
      foodType: FoodType.fromLabel(type),
      description: (json['description'] ?? '').toString().trim().isEmpty
          ? null
          : (json['description'] ?? '').toString().trim(),
      expiryDate: _expiryFromEstimate(json['expiryEstimateDays']),
    );
  }

  /// Maps an estimated fridge shelf-life (in days from today) to a concrete
  /// expiry date. Tolerates ints, numeric strings, and missing/invalid values
  /// (which yield null, keeping older prompts backward compatible).
  static DateTime? _expiryFromEstimate(Object? value) {
    if (value == null) {
      return null;
    }
    final days = value is num ? value.toInt() : int.tryParse(value.toString());
    if (days == null || days < 0) {
      return null;
    }
    return DateTime.now().add(Duration(days: days));
  }

  static String _buildPrompt() {
    final foodTypes = FoodType.values
        .map((foodType) => foodType.label)
        .join(', ');

    return '''
You are a fridge inventory assistant. Inspect the entire image and identify every visible food and drink item.

Include only items you can identify with reasonable confidence. Do not include shelves, containers whose contents are unknown, or uncertain guesses. Combine repeated identical items into one entry.

Identification rules:
- Systematically examine every bag, jar, box, and container — including partially visible, opaque, or nested ones (a bag inside a bag) and items at the edges of the image.
- Consider the full range of foods, including dried herbs and herbal teas (e.g. linden/ihlamur, chamomile, mint), spices, and regional or international items. Do not default to a common lookalike food (e.g. never call dried flowers or herbs "bread").
- For packaged or labeled items, READ any visible text on the packaging and identify the product from its label rather than its shape or color.
- For unlabeled bags of dry staples, identify by texture and by what is common in a home pantry: fine matte white powder = flour; crystalline white = sugar or salt; small oblong translucent grains = rice; golden cracked grains = bulgur; round dried seeds = beans, chickpeas, or lentils; also consider pasta, semolina, and oats.
- If you cannot identify an item with reasonable confidence, OMIT it entirely. Never output "Unknown", "Unidentified", or any placeholder name.

Use count-based amounts as the primary measurement style. Examples:
- 3 bananas
- 2 apples
- 1 milk carton
- 1 bag of spinach
- 6 eggs

Use one of these foodType values:
$foodTypes

For each item, estimate "expiryEstimateDays": the typical number of days from
today until it spoils in a fridge (a whole number). Use null if you cannot
reasonably estimate it.

Return only valid JSON as an array, with no Markdown or explanation. Each object must use this exact shape:
[
  {
    "name": "Bananas",
    "amount": "3 bananas",
    "foodType": "Produce",
    "description": "optional short detail, or empty string",
    "expiryEstimateDays": 5
  }
]
''';
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

class GeminiMealService {
  static String get _apiKey => AppEnvironment.geminiApiKey;
  static const _textModel = 'gemini-3-flash-preview';

  @visibleForTesting
  static http.Client httpClient = http.Client();

  static const _imageHost = 'image.pollinations.ai';

  static Future<List<MealRecommendation>> generate(AgentRequest request) async {
    if (_apiKey.isEmpty) {
      throw Exception('Missing GEMINI_API_KEY');
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
      throw Exception('Gemini request failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>? ?? [];
    if (candidates.isEmpty) {
      throw Exception('Gemini returned no candidates');
    }

    final content = candidates.first as Map<String, dynamic>;
    final parts =
        (content['content'] as Map<String, dynamic>)['parts'] as List<dynamic>;
    final text = (parts.first as Map<String, dynamic>)['text'] as String;
    final jsonText = _stripJsonFence(text);

    final decodedJson = jsonDecode(jsonText);
    final recommendations = <MealRecommendation>[];
    if (decodedJson is List<dynamic>) {
      recommendations.addAll(
        decodedJson
            .map(
              (item) =>
                  MealRecommendation.fromJson(item as Map<String, dynamic>),
            )
            .take(request.recommendationCount),
      );
    } else {
      recommendations.add(
        MealRecommendation.fromJson(decodedJson as Map<String, dynamic>),
      );
    }

    return _attachImages(recommendations);
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
                return '- ${item.name}: ${item.amount}, type: ${item.foodType.label}$description$freshness';
              })
              .join('\n');
    final feedback = request.feedbackHistory.isEmpty
        ? 'None.'
        : request.feedbackHistory.map((item) => '- $item').join('\n');

    final balanceGuidance = request.useMealBalance
        ? '''

The user chose meal-balance guidance. Honor their requested food, preferences, allergies, budget, time, and available ingredients first. When practical, build each recommendation around these flexible wellness anchors:
- About 20-30 g protein.
- About 7-8 g fiber.
- About 1.5 cups of produce or half the plate as produce, emphasizing vegetables while still counting fruit.
- About 250-500 mL water or another unsweetened drink with or near the meal.
- A plate or mixed-dish equivalent near 50% produce, 25% protein, and 25% quality carbohydrate.
- Keep added sugar and saturated fat as a minority of the meal's calories, favoring whole ingredients over heavily processed or sugary ones when it fits the request.
Briefly explain the balance in the reason. Do not reject a requested food or make medical claims if every target cannot be met.'''
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
- Gently prefer options built around fiber, protein, and unsaturated fats (legumes, yogurt, fish, tofu, oats, vegetables, olive oil), and lightly downrank late refined carbs and heavy saturated-fat plates.
- Order the recommendations so the most sleep-compatible option comes first.
- Lean slightly toward lighter, earlier-friendly portions, but still honor the user's request.
- For each dish, set "eveningScore" from 1 (heavy or late-carb-forward) to 5 (light and sleep-friendly).
- When a dish is carb-forward or heavy this close to bed, keep it in the list and add a short, friendly "glucoseNote" suggesting an optional pairing or tweak that softens the overnight rise (for example, pairing with something already in the fridge). Frame it as a helpful heads-up, never a warning or a rule.'''
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
$feedback$balanceGuidance$eveningGuidance$overnightContext$substitutionGuidance

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
    "suggestedQuestions": ["string"],
    ${request.diabetesEnabled ? '"glucoseNote": "optional short friendly heads-up, or empty string",' : ''}
    "eveningScore": 4
  }
]
${request.diabetesEnabled ? 'Only include a glucoseNote when it genuinely helps; otherwise use an empty string.' : 'Do not include glucose or diabetes advice.'} Only set eveningScore for evening meals; otherwise use null. Set "usedFridgeItems" to the exact names (from the fridge items list above) that this recipe actually uses; use an empty array if none apply or fridge items were not used. Set "estimatedCostPerServing" to a short rough estimate like "\$2-3/serving"; use your best judgment even without exact prices. Set "suggestedQuestions" to exactly 3 short questions this user would plausibly ask about this dish, written in their own casual first-person voice, that the rest of this card does not already answer; keep each under 8 words and never ask about medication or dosing.
''';
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

  MealRecommendation copyWith({String? imageUrl}) {
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
    );
  }
}
