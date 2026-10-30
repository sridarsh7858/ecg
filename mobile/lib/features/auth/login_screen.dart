import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_widgets.dart';
import '../../state/auth_controller.dart';
import 'auth_form_fields.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthController>();
    final success = await auth.signIn(
      email: _email.text,
      password: _password.text,
    );

    // The root gate swaps to the shell once the controller reports signed in,
    // so there is nothing to navigate to here on success.
    if (!success && mounted) FocusScope.of(context).unfocus();
  }

  void _open(Widget screen) {
    context.read<AuthController>().clearError();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: PageBody(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthBrandHeader(
                    title: 'Welcome back',
                    subtitle: 'Sign in to pick up where you left off.',
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  AuthField(
                    label: 'Email',
                    controller: _email,
                    hint: 'you@example.com',
                    validator: AuthValidators.email,
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: Icons.mail_outline_rounded,
                    autofillHints: const [AutofillHints.email],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PasswordField(
                    label: 'Password',
                    controller: _password,
                    validator: AuthValidators.password,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => _open(const ForgotPasswordScreen()),
                      child: const Text('Forgot password?'),
                    ),
                  ),
                  if (auth.error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AuthErrorBanner(message: auth.error!),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    onPressed: auth.isBusy ? null : _submit,
                    child: auth.isBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : const Text('SIGN IN'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // Wrap so the prompt and the link stack on narrow screens
                  // rather than overflowing.
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'New here?',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      TextButton(
                        onPressed: () => _open(const RegisterScreen()),
                        child: const Text('Create an account'),
                      ),
                    ],
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
