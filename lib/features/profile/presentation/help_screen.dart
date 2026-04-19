import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(l10n.help),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ExpansionTile(
              title: const Text(
                'How to trigger SOS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: const [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'You can trigger an SOS alert in multiple ways:\n\n'
                    '1. Press the large SOS button on the home screen for 3 seconds\n'
                    '2. Quickly press the power button 5 times\n'
                    '3. Shake your device vigorously 3 times\n'
                    '4. Use the voice command "Help" or "Emergency"\n\n'
                    'Once triggered, the app will immediately send your location to your emergency contacts and nearby volunteers.',
                    style: TextStyle(color: Colors.white70, height: 1.5),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: const Text(
                'What happens when I trigger SOS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: const [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'When you trigger an SOS alert:\n\n'
                    '1. Your precise location is captured and sent to the server\n'
                    '2. All your emergency contacts receive an SMS with your location\n'
                    '3. Nearby volunteers are notified through push notifications\n'
                    '4. A countdown begins before authorities are contacted\n'
                    '5. Your phone starts recording audio as evidence\n'
                    '6. The screen displays your emergency information for first responders\n\n'
                    'You can cancel the alert within the countdown period if it was triggered accidentally.',
                    style: TextStyle(color: Colors.white70, height: 1.5),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: const Text(
                'Volunteer mode',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: const [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Volunteer mode allows you to help others in your area:\n\n'
                    '• Enable volunteer mode in Settings to receive nearby SOS alerts\n'
                    '• You will see the location and type of emergency\n'
                    '• You can accept or decline to respond to alerts\n'
                    '• Your location is shared with the person in distress\n'
                    '• You can communicate through the in-app chat\n'
                    '• Volunteer mode can be toggled on/off at any time\n\n'
                    'Volunteers are not expected to put themselves in danger. Always prioritize your safety and contact authorities when appropriate.',
                    style: TextStyle(color: Colors.white70, height: 1.5),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: const Text(
                'Offline mode',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: const [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'The app works even with limited connectivity:\n\n'
                    '• SOS alerts are queued and sent when connection is restored\n'
                    '• Your emergency profile is stored locally on your device\n'
                    '• SMS fallback works without internet connection\n'
                    '• Location data is cached and transmitted when possible\n'
                    '• Offline maps show your last known area\n'
                    '• Medical information is always accessible offline\n\n'
                    'For best results, ensure SMS permissions are granted so alerts can be sent via text when data is unavailable.',
                    style: TextStyle(color: Colors.white70, height: 1.5),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: const Text(
                'Contact support',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: const [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Need additional help? Reach out to us:\n\n'
                    '• Email: support@emergencyos.com\n'
                    '• In-app feedback: Settings > Send Feedback\n'
                    '• Emergency hotline: 1-800-EMERGENCY\n'
                    '• Website: www.emergencyos.com/support\n\n'
                    'For technical issues, please include your device model and app version when contacting support. We aim to respond within 24 hours.',
                    style: TextStyle(color: Colors.white70, height: 1.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
