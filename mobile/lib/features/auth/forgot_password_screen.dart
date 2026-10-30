import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_widgets.dart';
import '../../state/auth_controller.dart';
import 'auth_form_fields.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final success = await context.read<AuthController>().requestPasswordReset(
      _email.text,
    );
    if (!mounted) return;
    if (success) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: PageBody(
            child: _sent ? _confirmation(theme) : _form(theme, auth),
          ),
        ),
      ),
    );
  }

  Widget _form(ThemeData theme, AuthController auth) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter the email you signed up with and we will get you back in.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AuthField(
            label: 'Email',
            controller: _email,
            hint: 'you@example.com',
            validator: AuthValidators.email,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.mail_outline_rounded,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          if (auth.error != null) ...[
            const SizedBox(height: AppSpacing.lg),
            AuthErrorBanner(message: auth.error!),
          ],
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: auth.isBusy ? null : _submit,
            child: const Text('SEND RESET LINK'),
          ),
        ],
      ),
    );
  }

  Widget _confirmation(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xxl),
        Icon(
          Icons.mark_email_read_outlined,
          size: 64,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Check your email',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'If an account exists for ${_email.text.trim()}, a reset link is on '
          'its way.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Honest about what the prototype actually does, rather than implying
        // an email was really sent.
        AppCard(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'This build has no email backend, so nothing is actually '
                  'sent. Password reset goes live with Firebase Auth.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('BACK TO SIGN IN'),
        ),
      ],
    );
  }
}
