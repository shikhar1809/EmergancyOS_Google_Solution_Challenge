import 'package:flutter/material.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

Future<String?> showBridgeCreateChannelDialog(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF161B22),
      title: Text(context.opsTr('Create Channel'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      content: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: context.opsTr('channel-name'),
          hintStyle: TextStyle(color: Colors.white38),
          filled: true,
          fillColor: Color(0xFF0D1117),
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(context.opsTr('Cancel'), style: TextStyle(color: Colors.white54)),
        ),
        FilledButton(
          onPressed: () {
            final name = controller.text.trim().toLowerCase().replaceAll(
              RegExp(r'[^a-z0-9\-]'),
              '-',
            );
            if (name.isNotEmpty) {
              Navigator.pop(ctx, name);
            }
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF5865F2),
          ),
          child: Text(context.opsTr('Create')),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
