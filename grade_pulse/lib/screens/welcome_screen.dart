import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../services/auth_service.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.controller});

  final AppController controller;

  void _open(BuildContext context, {required bool signUp}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AuthScreen(controller: controller, startInSignUp: signUp),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget feature(IconData icon, String label) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: cs.onSurface, fontSize: 14),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Icon(
                        Icons.analytics_rounded,
                        size: 38,
                        color: cs.onPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Grade Pulse',
                    textAlign: TextAlign.center,
                    style: text.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Track your grades, plan your study schedule and stay on top of every term.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                  ),
                  const SizedBox(height: 28),
                  feature(Icons.school_outlined, 'Subjects, units and assessment scores'),
                  feature(Icons.calendar_today_outlined, 'Exams and deadlines on your calendar'),
                  feature(Icons.groups_outlined, 'Study groups and a target-grade calculator'),
                  const SizedBox(height: 28),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () => _open(context, signUp: true),
                    child: const Text(
                      'Create an account',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () => _open(context, signUp: false),
                    child: const Text(
                      'Sign in',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Accounts and data are stored on this device only (local demo mode).',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.controller,
    required this.startInSignUp,
  });

  final AppController controller;
  final bool startInSignUp;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  late bool _isSignUp = widget.startInSignUp;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _setMode(bool signUp) {
    setState(() {
      _isSignUp = signUp;
      _error = null;
      _passwordCtrl.clear();
      _confirmCtrl.clear();
    });
    _formKey.currentState?.reset();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);

    try {
      if (_isSignUp) {
        await widget.controller.signUp(
          name: _nameCtrl.text,
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
        );
        messenger.showSnackBar(
          const SnackBar(content: Text('Account created. Welcome to Grade Pulse!')),
        );
      } else {
        await widget.controller.signIn(
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
        );
        messenger.showSnackBar(
          const SnackBar(content: Text('Signed in successfully.')),
        );
      }
      // The app has swapped to the main screen; remove this auth page.
      navigator.popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Something went wrong. Please try again.';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: cs.onSurface,
        title: Text(_isSignUp ? 'Create account' : 'Sign in'),
      ),
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
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Sign In')),
                        ButtonSegment(value: true, label: Text('Sign Up')),
                      ],
                      selected: {_isSignUp},
                      onSelectionChanged: _busy ? null : (s) => _setMode(s.first),
                    ),
                    const SizedBox(height: 20),
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, size: 18, color: cs.onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_isSignUp) ...[
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          prefixIcon: Icon(Icons.person_outline, size: 20),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please enter your name';
                          if (v.trim().length < 2) return 'Name is too short';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email Address',
                        prefixIcon: Icon(Icons.email_outlined, size: 20),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Please enter your email';
                        if (!AuthService.isValidEmail(v)) return 'Enter a valid email address';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      textInputAction:
                          _isSignUp ? TextInputAction.next : TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (!_isSignUp && !_busy) _submit();
                      },
                      decoration: InputDecoration(
                        labelText: _isSignUp ? 'Create Password' : 'Password',
                        helperText: _isSignUp ? 'At least 8 characters' : null,
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Please enter your password';
                        if (_isSignUp && v.length < 8) {
                          return 'Use at least 8 characters';
                        }
                        return null;
                      },
                    ),
                    if (_isSignUp) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirmCtrl,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) {
                          if (!_busy) _submit();
                        },
                        decoration: const InputDecoration(
                          labelText: 'Confirm Password',
                          prefixIcon: Icon(Icons.lock_outline, size: 20),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Please confirm your password';
                          if (v != _passwordCtrl.text) return 'Passwords do not match';
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.onSurfaceVariant,
                              ),
                            )
                          : Text(
                              _isSignUp ? 'Create Account' : 'Sign In',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Local demo accounts: stored only on this device and not '
                      'suitable for protecting sensitive information. There is no '
                      'password recovery.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
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
