import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'exercise/data/exercise_repository.dart';
import 'exercise/models/workout_session.dart';
import 'exercise/screens/exercise_page.dart';
import 'exercise/screens/today_dashboard.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      title: 'Diabetes App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
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
          return const NonLoggedInPage();
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
          _message = error.message ?? 'Could not check your email status.';
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
          _message = error.message ?? 'Could not send a verification email.';
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
        _authError = error.message ?? 'Authentication failed.';
      });
    } catch (error) {
      setState(() {
        _authError = 'Authentication failed: $error';
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
                'No account was found. Sign up with email and password first.';
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
          _authError = error.message ?? 'Google sign-in failed.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _authError = 'Google sign-in failed: $error';
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
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isSignUp ? 'Create Account' : 'Sign In',
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Email',
                      ),
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
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Password',
                      ),
                      validator: (value) {
                        if (value == null || value.length < 6) {
                          return 'Use at least 6 characters';
                        }

                        return null;
                      },
                    ),
                    if (_authError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _authError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _isLoading ? null : _submit,
                      child: Text(
                        _isLoading
                            ? 'Please wait...'
                            : _isSignUp
                            ? 'Sign Up'
                            : 'Log In',
                      ),
                    ),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _signInWithGoogle,
                      icon: const Icon(Icons.account_circle_outlined),
                      label: const Text('Log in with Google'),
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
                            ? 'Already have an account? Log in'
                            : 'Need an account? Sign up',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NonLoggedInPage extends StatelessWidget {
  const NonLoggedInPage({super.key});

  void _showLoginPage(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const AuthPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Welcome'),
        actions: [
          TextButton.icon(
            onPressed: () => _showLoginPage(context),
            icon: const Icon(Icons.login),
            label: const Text('Log in'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topCenter,
          child: Column(
            children: [
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) =>
                    const LinearGradient(
                      colors: [
                        Color.fromARGB(255, 25, 118, 210),
                        Color.fromARGB(255, 144, 202, 249),
                        Colors.white,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.topRight,
                    ).createShader(
                      Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                    ),
                child: const Text(
                  'Smarter eating starts here',
                  style: TextStyle(color: Colors.white, fontSize: 32),
                ),
              ),

              Image(
                image: const AssetImage('assets/Placeholder.png'),
                width: MediaQuery.sizeOf(context).width,
                height: MediaQuery.sizeOf(context).height * 0.4,
                fit: BoxFit.contain,
              ),
              Text(
                'Filler filler filler Filler filler filler Filler filler filler',
              ),
              const SizedBox(height: 32),
              Image(
                image: const AssetImage('assets/Placeholder.png'),
                width: MediaQuery.sizeOf(context).width,
                height: MediaQuery.sizeOf(context).height * 0.4,
                fit: BoxFit.contain,
              ),
              Text(
                'Filler filler filler Filler filler filler Filler filler filler',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key, required this.user});

  final User user;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 1;

  static const List<_AppPage> _pages = [
    _AppPage(title: 'Fridge', icon: Icons.kitchen),
    _AppPage(title: 'Home', icon: Icons.home),
    _AppPage(title: 'Exercise', icon: Icons.directions_run),
    _AppPage(title: 'Agent', icon: Icons.smart_toy),
  ];

  void _goToPage(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(_pages[_selectedIndex].title),
        actions: [
          IconButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _selectedPage(user),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < _pages.length; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: CirclePageButton(
                    icon: _pages[index].icon,
                    label: _pages[index].title,
                    isSelected: _selectedIndex == index,
                    onTap: () => _goToPage(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectedPage(User user) {
    if (_selectedIndex == 1) {
      final displayName = user.displayName?.trim();
      final emailName = user.email?.split('@').first.trim();
      return TodayDashboard(
        userId: user.uid,
        userName: displayName?.isNotEmpty == true ? displayName : emailName,
        onOpenExercise: () => _goToPage(2),
      );
    }
    if (_selectedIndex == 2) {
      return ExercisePage(userId: user.uid);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _fridgeItemsCollection(
        user.uid,
      ).orderBy('createdAt', descending: false).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Could not load fridge items: ${snapshot.error}',
              textAlign: TextAlign.center,
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final fridgeItems =
            snapshot.data?.docs.map(StoredFoodItem.fromDocument).toList() ??
            const <StoredFoodItem>[];
        final foodItems = fridgeItems
            .map((storedFoodItem) => storedFoodItem.foodItem)
            .toList();

        if (_selectedIndex == 0) {
          return FridgePage(
            foodItems: foodItems,
            onAddFood: (foodItem) => _addFoodItem(user.uid, foodItem),
            onAddFoods: (foodItems) => _addFoodItems(user.uid, foodItems),
            onEditFood: (index, foodItem) =>
                _editFoodItem(user.uid, fridgeItems[index].id, foodItem),
            onRemoveFood: (index) =>
                _removeFoodItem(user.uid, fridgeItems[index].id),
          );
        }

        return AgentPage(
          foodItems: foodItems,
          onStartPostMealWalk: () => Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (context) => WorkoutSetupPage(
                userId: user.uid,
                repository: ExerciseRepository(),
                initialActivity: WorkoutActivityType.walking,
                source: WorkoutSource.postMealWalk,
              ),
            ),
          ),
        );
      },
    );
  }

  CollectionReference<Map<String, dynamic>> _fridgeItemsCollection(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('fridgeItems');
  }

  Future<void> _addFoodItem(String uid, FoodItem foodItem) {
    return _fridgeItemsCollection(uid).add(foodItem.toFirestore());
  }

  Future<void> _addFoodItems(String uid, List<FoodItem> foodItems) async {
    final batch = FirebaseFirestore.instance.batch();
    final collection = _fridgeItemsCollection(uid);

    for (final foodItem in foodItems) {
      batch.set(collection.doc(), foodItem.toFirestore());
    }

    await batch.commit();
  }

  Future<void> _editFoodItem(String uid, String id, FoodItem foodItem) {
    return _fridgeItemsCollection(
      uid,
    ).doc(id).update(foodItem.toFirestore(includeCreatedAt: false));
  }

  Future<void> _removeFoodItem(String uid, String id) {
    return _fridgeItemsCollection(uid).doc(id).delete();
  }
}

class FridgePage extends StatelessWidget {
  const FridgePage({
    super.key,
    required this.foodItems,
    required this.onAddFood,
    required this.onAddFoods,
    required this.onEditFood,
    required this.onRemoveFood,
  });

  final List<FoodItem> foodItems;
  final Future<void> Function(FoodItem foodItem) onAddFood;
  final Future<void> Function(List<FoodItem> foodItems) onAddFoods;
  final Future<void> Function(int index, FoodItem foodItem) onEditFood;
  final Future<void> Function(int index) onRemoveFood;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (foodItems.isEmpty)
          const Center(child: Text('No food added yet.'))
        else
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (foodItems.isNotEmpty) ...[
                Text(
                  'Food Items',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (var index = 0; index < foodItems.length; index++) ...[
                  FoodItemTile(
                    foodItem: foodItems[index],
                    onEdit: () => _showEditFoodSheet(context, index),
                    onRemove: () => onRemoveFood(index),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ],
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton(
                heroTag: 'takeFridgePhoto',
                onPressed: () => _takeFridgePhoto(context),
                tooltip: 'Take fridge photo',
                child: const Icon(Icons.camera_alt),
              ),
              const SizedBox(height: 12),
              FloatingActionButton(
                heroTag: 'addFood',
                onPressed: () => _showAddFoodSheet(context),
                tooltip: 'Add food',
                child: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _takeFridgePhoto(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final imageBytes = await showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const FridgeCameraSheet(),
    );

    if (imageBytes == null) {
      return;
    }

    messenger.showSnackBar(
      const SnackBar(content: Text('Scanning fridge photo...')),
    );

    try {
      final detectedFoods = await FridgePhotoFoodAgent.detectFoods(imageBytes);
      if (detectedFoods.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No food items were found.')),
        );
        return;
      }

      await onAddFoods(detectedFoods);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            detectedFoods.length == 1
                ? 'Added 1 food item to your fridge.'
                : 'Added ${detectedFoods.length} food items to your fridge.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not scan fridge photo: $error')),
      );
    }
  }

  Future<void> _showAddFoodSheet(BuildContext context) async {
    final foodItem = await showModalBottomSheet<FoodItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const AddFoodSheet(),
    );

    if (foodItem != null) {
      await onAddFood(foodItem);
    }
  }

  Future<void> _showEditFoodSheet(BuildContext context, int index) async {
    final foodItem = await showModalBottomSheet<FoodItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => AddFoodSheet(foodItem: foodItems[index]),
    );

    if (foodItem != null) {
      await onEditFood(index, foodItem);
    }
  }
}

class FridgeCameraSheet extends StatefulWidget {
  const FridgeCameraSheet({super.key});

  @override
  State<FridgeCameraSheet> createState() => _FridgeCameraSheetState();
}

class _FridgeCameraSheetState extends State<FridgeCameraSheet> {
  CameraController? _cameraController;
  Future<void>? _initializeCameraFuture;
  String? _cameraError;
  bool _isTakingPicture = false;

  @override
  void initState() {
    super.initState();
    _initializeCameraFuture = _initializeCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
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
        ResolutionPreset.medium,
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
                Expanded(
                  child: Text(
                    'Take Fridge Photo',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close camera',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildCameraPreview(context)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isTakingPicture ? null : _capturePhoto,
              icon: const Icon(Icons.camera_alt),
              label: Text(_isTakingPicture ? 'Scanning...' : 'Take Picture'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview(BuildContext context) {
    final cameraController = _cameraController;
    final initializeCameraFuture = _initializeCameraFuture;

    if (_cameraError != null) {
      return Center(
        child: Text(
          'Camera unavailable: $_cameraError',
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
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
  const AddFoodSheet({super.key, this.foodItem});

  final FoodItem? foodItem;

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
      ),
    );
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
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Food name',
                ),
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
                  border: OutlineInputBorder(),
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
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Food type',
                ),
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
              TextFormField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Description (optional)',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saveFoodItem,
                child: Text(_isEditing ? 'Save Changes' : 'Save Food'),
              ),
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
  });

  final List<FoodItem> foodItems;
  final VoidCallback? onStartPostMealWalk;

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  final _formKey = GlobalKey<FormState>();
  final _budgetController = TextEditingController();
  final _timeController = TextEditingController();
  final _preferencesController = TextEditingController();
  final _feedbackController = TextEditingController();

  bool _useFridgeItems = true;
  bool _hasBudget = false;
  bool _hasTimeShortage = false;
  int _recommendationCount = 1;
  MealType _mealType = MealType.breakfast;
  CookingExperience _cookingExperience = CookingExperience.beginner;
  AgentRequest? _lastRequest;
  List<MealRecommendation> _recommendations = const [];
  final List<String> _feedbackHistory = [];
  bool _isLoadingRecommendation = false;
  String? _recommendationError;

  @override
  void dispose() {
    _budgetController.dispose();
    _timeController.dispose();
    _preferencesController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _generateRecommendation() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

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

  Future<void> _loadRecommendation(AgentRequest request) async {
    setState(() {
      _lastRequest = request;
      _isLoadingRecommendation = true;
      _recommendationError = null;
      _recommendations = const [];
    });

    try {
      final results = await Future.wait([
        GeminiMealService.generate(request),
        Future<void>.delayed(const Duration(seconds: 1)),
      ]);
      final recommendations = results.first as List<MealRecommendation>;

      setState(() {
        _recommendations = recommendations;
      });
    } catch (error) {
      setState(() {
        _recommendationError =
            'Gemini was not available. Check your API key and try again. ($error)';
      });
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
      padding: const EdgeInsets.all(16),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use items from my fridge'),
                subtitle: Text(
                  widget.foodItems.isEmpty
                      ? 'Your fridge is empty right now.'
                      : widget.foodItems.length == 1
                      ? '1 item in your Fridge'
                      : "${widget.foodItems.length} items in your Fridge",
                ),
                value: _useFridgeItems,
                onChanged: (value) {
                  setState(() {
                    _useFridgeItems = value;
                  });
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Set a budget'),
                subtitle: const Text('Turn this off if there is no budget.'),
                value: _hasBudget,
                onChanged: (value) {
                  setState(() {
                    _hasBudget = value;
                  });
                },
              ),

              if (_hasBudget) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _budgetController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Budget',
                    prefixText: r'$',
                  ),
                  validator: (value) {
                    if (!_hasBudget) {
                      return null;
                    }

                    if (value == null || value.trim().isEmpty) {
                      return 'Enter a budget or turn budget off';
                    }

                    return null;
                  },
                ),
              ],

              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Set a time shortage'),
                subtitle: const Text('Turn this on if you have limited time.'),
                value: _hasTimeShortage,
                onChanged: (value) {
                  setState(() {
                    _hasTimeShortage = value;
                  });
                },
              ),

              if (_hasTimeShortage) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _timeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Time available',
                    suffixText: 'minutes',
                  ),
                  validator: (value) {
                    if (!_hasTimeShortage) {
                      return null;
                    }

                    if (value == null || value.trim().isEmpty) {
                      return 'Enter the time you have or turn this off';
                    }

                    return null;
                  },
                ),
              ],

              const SizedBox(height: 16),
              TextFormField(
                controller: _preferencesController,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'What do you want to eat?',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Tell the agent what kinds of food you like';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text(
                'What are you planning for?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final mealType in MealType.values)
                    ChoiceChip(
                      label: Text(mealType.label),
                      selected: _mealType == mealType,
                      onSelected: (selected) {
                        if (!selected) {
                          return;
                        }

                        setState(() {
                          _mealType = mealType;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'What difficulty of food do you want to cook?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final experience in CookingExperience.values)
                    ChoiceChip(
                      label: Text(experience.label),
                      selected: _cookingExperience == experience,
                      onSelected: (selected) {
                        if (!selected) {
                          return;
                        }

                        setState(() {
                          _cookingExperience = experience;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'How many recommendations do you want?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('1')),
                  ButtonSegment(value: 2, label: Text('2')),
                  ButtonSegment(value: 3, label: Text('3')),
                  ButtonSegment(value: 4, label: Text('4')),
                  ButtonSegment(value: 5, label: Text('5')),
                ],
                selected: {_recommendationCount},
                onSelectionChanged: (selection) {
                  setState(() {
                    _recommendationCount = selection.first;
                  });
                },
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('recommendMealButton'),
                onPressed: _isLoadingRecommendation
                    ? null
                    : _generateRecommendation,
                icon: const Icon(Icons.auto_awesome),
                label: Text(
                  _isLoadingRecommendation ? 'Thinking...' : 'Recommend a Meal',
                ),
              ),
              if (_isLoadingRecommendation) ...[
                const SizedBox(height: 12),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Choosing a healthy budget meal...'),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (_recommendationError != null) ...[
          const SizedBox(height: 16),
          Text(
            _recommendationError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_recommendations.isNotEmpty) ...[
          const SizedBox(height: 24),
          for (final recommendation in _recommendations) ...[
            MealRecommendationCard(
              recommendation: recommendation,
              onStartPostMealWalk: widget.onStartPostMealWalk,
            ),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('agentFeedbackField'),
            controller: _feedbackController,
            minLines: 2,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'What should be different?',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _suggestAnotherMeal,
            icon: const Icon(Icons.refresh),
            label: const Text('Suggest Something Else'),
          ),
        ],
      ],
    );
  }
}

class MealRecommendationCard extends StatelessWidget {
  const MealRecommendationCard({
    super.key,
    required this.recommendation,
    this.onStartPostMealWalk,
  });

  final MealRecommendation recommendation;
  final VoidCallback? onStartPostMealWalk;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 180,
            color: Theme.of(context).colorScheme.primaryContainer,
            child: recommendation.imageBytes == null
                ? Icon(
                    Icons.rice_bowl,
                    size: 76,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  )
                : Image.memory(
                    recommendation.imageBytes!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
          ),
          if (recommendation.imageError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Image could not be generated: ${recommendation.imageError}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recommendation.dishName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(recommendation.reason),
                const SizedBox(height: 16),
                Text(
                  'Ingredients',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final ingredient in recommendation.ingredients)
                  Text('- $ingredient'),
                const SizedBox(height: 16),
                Text(
                  'Instructions',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (
                  var index = 0;
                  index < recommendation.instructions.length;
                  index++
                )
                  Text('${index + 1}. ${recommendation.instructions[index]}'),
                if (onStartPostMealWalk != null) ...[
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: onStartPostMealWalk,
                    icon: const Icon(Icons.directions_walk),
                    label: const Text('Start a 10-minute post-meal walk'),
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

class CirclePageButton extends StatelessWidget {
  const CirclePageButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = isSelected
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest;
    final foregroundColor = isSelected
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 34,
        customBorder: const CircleBorder(),
        child: CircleAvatar(
          radius: 28,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          child: Icon(icon),
        ),
      ),
    );
  }
}

class _AppPage {
  const _AppPage({required this.title, required this.icon});

  final String title;
  final IconData icon;
}

class FoodItem {
  const FoodItem({
    required this.name,
    required this.amount,
    required this.foodType,
    this.description,
    this.imageBytes,
  });

  final String name;
  final String amount;
  final FoodType foodType;
  final String? description;
  final Uint8List? imageBytes;

  Map<String, dynamic> toFirestore({bool includeCreatedAt = true}) {
    return {
      'name': name,
      'amount': amount,
      'foodType': foodType.label,
      'description': description,
      if (includeCreatedAt) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory FoodItem.fromFirestore(Map<String, dynamic> data) {
    return FoodItem(
      name: (data['name'] ?? '').toString(),
      amount: (data['amount'] ?? '').toString(),
      foodType: FoodType.fromLabel((data['foodType'] ?? '').toString()),
      description: (data['description'] ?? '').toString().trim().isEmpty
          ? null
          : (data['description'] ?? '').toString(),
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

  AgentRequest copyWith({
    List<String>? feedbackHistory,
    bool? hasTimeShortage,
    String? timeAvailable,
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
      recommendationCount: recommendationCount,
      fridgeItems: fridgeItems,
      feedbackHistory: feedbackHistory ?? this.feedbackHistory,
    );
  }
}

class FridgePhotoFoodAgent {
  static String get _apiKey => AppEnvironment.geminiApiKey;
  static const _model = 'gemini-3-flash-preview';

  static Future<List<FoodItem>> detectFoods(Uint8List imageBytes) async {
    if (_apiKey.isEmpty) {
      throw Exception('Missing GEMINI_API_KEY');
    }

    final response = await http.post(
      Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent',
      ),
      headers: {'Content-Type': 'application/json', 'x-goog-api-key': _apiKey},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': _buildPrompt()},
              {
                'inlineData': {
                  'mimeType': 'image/jpeg',
                  'data': base64Encode(imageBytes),
                },
              },
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.2,
          'responseMimeType': 'application/json',
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Food scan failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>? ?? [];
    if (candidates.isEmpty) {
      throw Exception('Food scan returned no candidates');
    }

    final candidate = candidates.first as Map<String, dynamic>;
    final content = candidate['content'] as Map<String, dynamic>;
    final parts = content['parts'] as List<dynamic>? ?? [];
    final textPart = parts.cast<Map<String, dynamic>>().firstWhere(
      (part) => part['text'] is String,
      orElse: () => const <String, dynamic>{},
    );
    final text = textPart['text'] as String?;
    if (text == null || text.trim().isEmpty) {
      throw Exception('Food scan returned no text');
    }

    final decodedJson = jsonDecode(_stripJsonFence(text));
    final foodJson = decodedJson is List<dynamic>
        ? decodedJson
        : (decodedJson as Map<String, dynamic>)['foods'] as List<dynamic>? ??
              const [];

    return foodJson
        .whereType<Map<String, dynamic>>()
        .map(_foodItemFromJson)
        .where((foodItem) => foodItem.name.isNotEmpty)
        .toList();
  }

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
    );
  }

  static String _buildPrompt() {
    final foodTypes = FoodType.values
        .map((foodType) => foodType.label)
        .join(', ');

    return '''
You are a fridge inventory assistant. Look at the image and identify the visible food items.

Add only foods you can identify from the image. Do not include unknown, possible, maybe, or uncertain items.

Use count-based amounts as the primary measurement style. Examples:
- 3 bananas
- 2 apples
- 1 milk carton
- 1 bag of spinach
- 6 eggs

Use one of these foodType values:
$foodTypes

Return only valid JSON as an array. Each object must use this exact shape:
[
  {
    "name": "Bananas",
    "amount": "3 bananas",
    "foodType": "Produce",
    "description": "optional short detail, or empty string"
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
  static const _imageModel = 'gemini-3.1-flash-image';

  static Future<List<MealRecommendation>> generate(AgentRequest request) async {
    if (_apiKey.isEmpty) {
      throw Exception('Missing GEMINI_API_KEY');
    }

    final response = await http.post(
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

    return Future.wait(recommendations.map(_withGeneratedImage));
  }

  static Future<MealRecommendation> _withGeneratedImage(
    MealRecommendation recommendation,
  ) async {
    if (recommendation.imagePrompt.isEmpty) {
      return recommendation;
    }

    try {
      final imageBytes = await _generateImage(recommendation.imagePrompt);
      return recommendation.copyWith(imageBytes: imageBytes);
    } catch (error) {
      return recommendation.copyWith(imageError: error.toString());
    }
  }

  static Future<Uint8List> _generateImage(String prompt) async {
    final response = await http.post(
      Uri.parse(
        'https://generativelanguage.googleapis.com/v1/models/$_imageModel:generateContent',
      ),
      headers: {'Content-Type': 'application/json', 'x-goog-api-key': _apiKey},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {
                'text':
                    'Generate a realistic appetizing food photo. No text, labels, logos, or watermarks. $prompt',
              },
            ],
          },
        ],
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Gemini image request failed: ${response.statusCode} ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>? ?? [];
    if (candidates.isEmpty) {
      throw Exception('Gemini image returned no candidates');
    }

    final candidate = candidates.first as Map<String, dynamic>;
    final content = candidate['content'] as Map<String, dynamic>;
    final parts = content['parts'] as List<dynamic>? ?? [];

    for (final part in parts.cast<Map<String, dynamic>>()) {
      final inlineData =
          part['inlineData'] as Map<String, dynamic>? ??
          part['inline_data'] as Map<String, dynamic>?;
      final encodedImage = inlineData?['data'] as String?;
      if (encodedImage != null && encodedImage.isNotEmpty) {
        return base64Decode(encodedImage);
      }
    }

    throw Exception('Gemini image returned no image data');
  }

  static String _buildPrompt(AgentRequest request) {
    final fridgeItems = request.fridgeItems.isEmpty
        ? 'None. User wants to buy fresh or the fridge is empty.'
        : request.fridgeItems
              .map((item) {
                final description = item.description == null
                    ? ''
                    : ', description: ${item.description}';
                return '- ${item.name}: ${item.amount}, type: ${item.foodType.label}$description';
              })
              .join('\n');
    final feedback = request.feedbackHistory.isEmpty
        ? 'None.'
        : request.feedbackHistory.map((item) => '- $item').join('\n');

    return '''
You are a healthy budget meal assistant for a diabetes and budgeting app.

Recommend exactly ${request.recommendationCount} affordable, healthy homemade dishes. Each dish should be much healthier than fast food and similar to a normal healthy homemade meal: include protein, vegetables or fruit, fiber-rich carbs when possible, reasonable portions, and avoid mostly fried, sugary, or ultra-processed meals.

The user selected this meal type:
${request.mealType.label}

Match the selected meal type and the user's preferences closely. If the user asks for drinks, smoothies, fruit, bananas, or snacks, do not default to chicken, rice, turkey, or dinner food unless the user's other requirements clearly ask for that.

User food preferences:
${request.foodPreferences}

Cooking experience:
${request.cookingExperience.label}

Budget:
${request.hasBudget ? '\$${request.budget}' : 'No budget selected, but still keep it affordable.'}

Time availability:
${request.hasTimeShortage ? '${request.timeAvailable}. If needed, prefer quick, simple meals that can be made in this time.' : 'No time shortage specified. Any reasonable cooking time is fine.'}

Use fridge items:
${request.useFridgeItems ? 'Yes, use fridge items when helpful.' : 'No, recommend buying everything fresh.'}

Fridge items:
Use the amount exactly as the user wrote it when they include a measurement. If the amount is only a number, use the default unit of the item. For example, "2 cups" stays 2 cups, but "12" for eggs means 12 eggs.
$fridgeItems

Feedback from dishes the user rejected:
$feedback

Return only valid JSON as an array with exactly ${request.recommendationCount} objects. Each object must use this exact shape:
[
  {
    "dishName": "string",
    "imagePrompt": "short realistic food photo prompt for this dish",
    "reason": "string",
    "ingredients": ["string"],
    "instructions": ["string"]
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

class MealRecommendation {
  const MealRecommendation({
    required this.dishName,
    required this.imagePrompt,
    required this.reason,
    required this.ingredients,
    required this.instructions,
    this.imageBytes,
    this.imageError,
  });

  final String dishName;
  final String imagePrompt;
  final String reason;
  final List<String> ingredients;
  final List<String> instructions;
  final Uint8List? imageBytes;
  final String? imageError;

  MealRecommendation copyWith({Uint8List? imageBytes, String? imageError}) {
    return MealRecommendation(
      dishName: dishName,
      imagePrompt: imagePrompt,
      reason: reason,
      ingredients: ingredients,
      instructions: instructions,
      imageBytes: imageBytes ?? this.imageBytes,
      imageError: imageError ?? this.imageError,
    );
  }

  factory MealRecommendation.fromJson(Map<String, dynamic> json) {
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
    );
  }
}
