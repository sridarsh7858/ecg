import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_widgets.dart';
import '../../state/auth_controller.dart';
import 'auth_form_fields.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _age = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final navigator = Navigator.of(context);
    final success = await context.read<AuthController>().register(
      name: _name.text,
      email: _email.text,
      password: _password.text,
      age: int.parse(_age.text.trim()),
    );

    // Pop back to the gate, which now resolves to the app shell.
    if (success && mounted) navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          child: PageBody(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'A few details and you are set. NeuroPulse only asks for '
                    'what it needs.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AuthField(
                    label: 'Name',
                    controller: _name,
                    hint: 'Your name',
                    validator: AuthValidators.name,
                    keyboardType: TextInputType.name,
                    prefixIcon: Icons.person_outline_rounded,
                    autofillHints: const [AutofillHints.name],
                  ),
                  const SizedBox(height: AppSpacing.lg),
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
                  AuthField(
                    label: 'Age',
                    controller: _age,
                    hint: 'e.g. 21',
                    validator: AuthValidators.age,
                    keyboardType: TextInputType.number,
                    prefixIcon: Icons.cake_outlined,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PasswordField(
                    label: 'Password',
                    controller: _password,
                    validator: AuthValidators.password,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    onSubmitted: (_) => _submit(),
                  ),
                  if (auth.error != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    AuthErrorBanner(message: auth.error!),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton(
                    onPressed: auth.isBusy ? null : _submit,
                    child: auth.isBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : const Text('CREATE ACCOUNT'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Your account and sessions are stored on this device only.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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
