import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/bridge_repository.dart';
import '../domain/bridge_server_model.dart';
import '../domain/bridge_channel_model.dart';
import '../providers/bridge_state_provider.dart';
import 'bridge_create_channel_dialog.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

class BridgeHomeScreen extends ConsumerStatefulWidget {
  const BridgeHomeScreen({super.key});

  @override
  ConsumerState<BridgeHomeScreen> createState() => _BridgeHomeScreenState();
}

class _BridgeHomeScreenState extends ConsumerState<BridgeHomeScreen> {
  final _chatController = TextEditingController();

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  void _selectServer(BridgeServer server) {
    ref.read(selectedServerProvider.notifier).state = server;
    ref.read(selectedChannelProvider.notifier).state = null;
  }

  void _selectChannel(BridgeChannel channel) async {
    ref.read(selectedChannelProvider.notifier).state = channel;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    final displayName = ref.read(bridgeDisplayNameProvider);
    if (userId == null) return;

    final server = ref.read(selectedServerProvider);
    if (server == null) return;

    try {
      await ref
          .read(bridgeServiceProvider)
          .connect(
            serverId: server.id,
            channelId: channel.id,
            userId: userId,
            displayName: displayName,
            hospitalId: null,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to join channel: $e')));
      }
    }
  }

  Future<void> _leaveChannel() async {
    await ref.read(bridgeServiceProvider).disconnect();
    ref.read(selectedChannelProvider.notifier).state = null;
  }

  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    final displayName = ref.read(bridgeDisplayNameProvider);
    if (userId == null) return;

    ref
        .read(bridgeServiceProvider)
        .sendChatMessage(
          userId: userId,
          displayName: displayName,
          content: text,
        );
    _chatController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final selectedServer = ref.watch(selectedServerProvider);
    final selectedChannel = ref.watch(selectedChannelProvider);
    final bridgeService = ref.watch(bridgeServiceProvider);
    final isConnected = bridgeService.isConnected;
    final micOn = bridgeService.micOn;
    final deafened = bridgeService.deafened;
    final messages = bridgeService.messages;
    final voiceStates = bridgeService.getVoiceStates();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Row(
        children: [
          _ServerRail(
            serversAsync: ref.watch(bridgeServersProvider),
            selectedServer: selectedServer,
            onSelectServer: _selectServer,
          ),
          if (selectedServer != null)
            _ChannelList(
              server: selectedServer,
              channelsAsync: ref.watch(
                bridgeChannelsProvider(selectedServer.id),
              ),
              selectedChannel: selectedChannel,
              onSelectChannel: _selectChannel,
            ),
          Expanded(
            child: selectedChannel != null
                ? Column(
                    children: [
                      _ChannelHeader(
                        channel: selectedChannel,
                        onLeave: _leaveChannel,
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  Expanded(
                                    child: _VoiceStrip(states: voiceStates),
                                  ),
                                  const Divider(
                                    height: 1,
                                    color: Color(0xFF21262D),
                                  ),
                                  Expanded(
                                    child: _ChatView(
                                      messages: messages,
                                      controller: _chatController,
                                      onSend: _sendMessage,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 240,
                              child: _MemberList(states: voiceStates),
                            ),
                          ],
                        ),
                      ),
                      _VoiceControls(
                        micOn: micOn,
                        deafened: deafened,
                        isConnected: isConnected,
                        onToggleMic: () =>
                            ref.read(bridgeServiceProvider).toggleMic(),
                        onToggleDeafen: () =>
                            ref.read(bridgeServiceProvider).toggleDeafen(),
                        onDisconnect: _leaveChannel,
                      ),
                    ],
                  )
                : const _EmptyChannelView(),
          ),
        ],
      ),
    );
  }
}

class _ServerRail extends StatelessWidget {
  final AsyncValue<List<BridgeServer>> serversAsync;
  final BridgeServer? selectedServer;
  final void Function(BridgeServer) onSelectServer;

  const _ServerRail({
    required this.serversAsync,
    required this.selectedServer,
    required this.onSelectServer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      color: const Color(0xFF010409),
      child: Column(
        children: [
          const SizedBox(height: 12),
          serversAsync.when(
            data: (servers) => Expanded(
              child: ListView(
                children: servers.map((server) {
                  final isSelected = selectedServer?.id == server.id;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: _ServerIcon(
                      label: server.iconLabel,
                      isSelected: isSelected,
                      onTap: () => onSelectServer(server),
                    ),
                  );
                }).toList(),
              ),
            ),
            loading: () => const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF5865F2)),
              ),
            ),
            error: (_, __) => const Expanded(
              child: Center(
                child: Icon(Icons.error, color: Colors.redAccent, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerIcon extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ServerIcon({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(isSelected ? 16 : 24),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF5865F2)
                : const Color(0xFF2F3136),
            borderRadius: BorderRadius.circular(isSelected ? 16 : 24),
          ),
          child: Center(
            child: Text(label, style: const TextStyle(fontSize: 20)),
          ),
        ),
      ),
    );
  }
}

class _ChannelList extends StatelessWidget {
  final BridgeServer server;
  final AsyncValue<List<BridgeChannel>> channelsAsync;
  final BridgeChannel? selectedChannel;
  final void Function(BridgeChannel) onSelectChannel;

  const _ChannelList({
    required this.server,
    required this.channelsAsync,
    required this.selectedChannel,
    required this.onSelectChannel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: const Color(0xFF161B22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              server.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'VOICE CHANNELS',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: channelsAsync.when(
              data: (channels) {
                if (channels.isEmpty) {
                  return const Center(
                    child: Text(
                      'No channels yet',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  );
                }
                return ListView(
                  children: [
                    ...channels.map((ch) {
                      final isSelected = selectedChannel?.id == ch.id;
                      return _ChannelTile(
                        channel: ch,
                        isSelected: isSelected,
                        onTap: () => onSelectChannel(ch),
                      );
                    }),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: TextButton.icon(
                        onPressed: () async {
                          final name = await showBridgeCreateChannelDialog(
                            context,
                          );
                          if (name != null && context.mounted) {
                            final repo = BridgeRepository();
                            final userId =
                                FirebaseAuth.instance.currentUser?.uid ?? '';
                            await repo.createChannel(
                              serverId: server.id,
                              name: name,
                              createdBy: userId,
                              position: channels.length,
                            );
                          }
                        },
                        icon: const Icon(
                          Icons.add,
                          color: Colors.white54,
                          size: 18,
                        ),
                        label: Text(context.opsTr('Create Channel'), style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFF5865F2)),
              ),
              error: (_, __) => const Center(
                child: Text(
                  'Error loading channels',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final BridgeChannel channel;
  final bool isSelected;
  final VoidCallback onTap;

  const _ChannelTile({
    required this.channel,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? const Color(0xFF21262D) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              Icon(
                Icons.headset_mic_rounded,
                color: isSelected ? Colors.white : Colors.white54,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  channel.name.replaceAll('-', ' '),
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelHeader extends StatelessWidget {
  final BridgeChannel channel;
  final VoidCallback onLeave;

  const _ChannelHeader({required this.channel, required this.onLeave});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        border: Border(bottom: BorderSide(color: Color(0xFF21262D))),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.headset_mic_rounded,
            color: Colors.white54,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              channel.name.replaceAll('-', ' '),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.call_end, color: Color(0xFFDA3634)),
            onPressed: onLeave,
            tooltip: context.opsTr('Leave channel'),
          ),
        ],
      ),
    );
  }
}

class _VoiceStrip extends StatelessWidget {
  final List<dynamic> states;

  const _VoiceStrip({required this.states});

  @override
  Widget build(BuildContext context) {
    if (states.isEmpty) {
      return const Center(
        child: Text(
          'No one here yet',
          style: TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: states.map((state) {
          final isSpeaking = state.isSpeaking == true;
          final isLocal = state.isLocal == true;
          final isMuted = state.mic?.toString().endsWith('.muted') ?? false;
          final isDeafened =
              state.hearing?.toString().endsWith('.deafened') ?? false;

          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isLocal
                  ? const Color(0xFF134E4A)
                  : const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSpeaking ? const Color(0xFF22C55E) : Colors.white12,
                width: isSpeaking ? 2 : 1,
              ),
              boxShadow: isSpeaking
                  ? [
                      BoxShadow(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.3),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: isDeafened
                      ? Colors.grey.shade800
                      : (isLocal
                            ? const Color(0xFF0D4F4F)
                            : const Color(0xFF1E293B)),
                  child: Text(
                    (state.displayName ?? '?')
                        .split(' ')
                        .map((s) => s.isNotEmpty ? s[0] : '')
                        .take(2)
                        .join()
                        .toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  state.displayName ?? 'Unknown',
                  style: TextStyle(
                    color: isSpeaking ? Colors.white : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (isMuted || isDeafened) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isMuted)
                        const Icon(
                          Icons.mic_off,
                          color: Colors.redAccent,
                          size: 12,
                        ),
                      if (isDeafened) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.headset_off,
                          color: Colors.redAccent,
                          size: 12,
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ChatView extends StatelessWidget {
  final List<dynamic> messages;
  final TextEditingController controller;
  final VoidCallback onSend;

  const _ChatView({
    required this.messages,
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? const Center(
                  child: Text(
                    'No messages yet.\nStart the conversation!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return _ChatBubble(message: msg);
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Color(0xFF161B22),
            border: Border(top: BorderSide(color: Color(0xFF21262D))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: context.opsTr('Message #channel'),
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF0D1117),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send, color: Color(0xFF5865F2)),
                onPressed: onSend,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final dynamic message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isLocal = message.isLocal == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isLocal
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isLocal) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFF5865F2),
              child: Text(
                (message.displayName ?? '?')
                    .split(' ')
                    .map((s) => s.isNotEmpty ? s[0] : '')
                    .take(1)
                    .join()
                    .toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isLocal
                    ? const Color(0xFF5865F2)
                    : const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isLocal)
                    Text(
                      message.displayName ?? 'Unknown',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    message.content ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          if (isLocal) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _MemberList extends StatelessWidget {
  final List<dynamic> states;

  const _MemberList({required this.states});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1117),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.opsTr('ONLINE'), style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: states.map((state) {
                final isSpeaking = state.isSpeaking == true;
                final isMuted =
                    state.mic?.toString().endsWith('.muted') ?? false;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: isSpeaking
                                ? const Color(0xFF22C55E)
                                : const Color(0xFF21262D),
                            child: Text(
                              (state.displayName ?? '?')
                                  .split(' ')
                                  .map((s) => s.isNotEmpty ? s[0] : '')
                                  .take(1)
                                  .join()
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (isMuted)
                            Positioned(
                              bottom: -2,
                              right: -2,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFDA3634),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.mic_off,
                                  color: Colors.white,
                                  size: 8,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.displayName ?? 'Unknown',
                          style: TextStyle(
                            color: isSpeaking ? Colors.white : Colors.white70,
                            fontSize: 12,
                            fontWeight: isSpeaking
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceControls extends StatelessWidget {
  final bool micOn;
  final bool deafened;
  final bool isConnected;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleDeafen;
  final VoidCallback onDisconnect;

  const _VoiceControls({
    required this.micOn,
    required this.deafened,
    required this.isConnected,
    required this.onToggleMic,
    required this.onToggleDeafen,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        border: Border(top: BorderSide(color: Color(0xFF21262D))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ControlButton(
            icon: micOn ? Icons.mic : Icons.mic_off,
            label: micOn ? 'Mic On' : 'Muted',
            isActive: micOn,
            onTap: onToggleMic,
          ),
          const SizedBox(width: 16),
          _ControlButton(
            icon: deafened ? Icons.headset_off : Icons.headset,
            label: deafened ? 'Deafened' : 'Hearing',
            isActive: !deafened,
            onTap: onToggleDeafen,
          ),
          const SizedBox(width: 16),
          if (isConnected)
            _ControlButton(
              icon: Icons.call_end,
              label: 'Leave',
              isActive: false,
              onTap: onDisconnect,
              color: const Color(0xFFDA3634),
            ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final Color? color;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final btnColor = color ?? (isActive ? Colors.white : Colors.redAccent);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: btnColor, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: btnColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChannelView extends StatelessWidget {
  const _EmptyChannelView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.headset_mic_rounded, color: Colors.white24, size: 64),
          SizedBox(height: 16),
          Text(
            'Select a channel to join',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Voice channels let you talk in real-time with other hospitals and master admin.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
