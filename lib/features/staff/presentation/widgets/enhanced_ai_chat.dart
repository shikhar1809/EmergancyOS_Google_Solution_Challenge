import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

class AiMessage {
  final bool isUser;
  final String text;
  final DateTime timestamp;

  AiMessage(this.isUser, this.text, {DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();
}

class EnhancedAiChat extends StatefulWidget {
  const EnhancedAiChat({
    super.key,
    required this.messages,
    required this.onSend,
    required this.isLoading,
    this.suggestions = const [],
    this.onSuggestionTap,
    this.header,
    this.description,
  });

  final List<AiMessage> messages;
  final Future<void> Function(String text) onSend;
  final bool isLoading;
  final List<String> suggestions;
  final void Function(String suggestion)? onSuggestionTap;
  final Widget? header;
  final String? description;

  @override
  State<EnhancedAiChat> createState() => _EnhancedAiChatState();
}

class _EnhancedAiChatState extends State<EnhancedAiChat>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  late final AnimationController _typingCtrl;

  @override
  void initState() {
    super.initState();
    _typingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _typingCtrl.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || widget.isLoading) return;
    _ctrl.clear();
    await widget.onSend(text);
    _scrollToEnd();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border(
          left: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          if (widget.description != null) _buildDescription(),
          if (widget.suggestions.isNotEmpty) _buildSuggestions(),
          Expanded(child: _buildMessageList()),
          if (widget.isLoading) _buildTypingIndicator(),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return widget.header ??
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accentBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.smart_toy,
                  color: AppColors.accentBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(context.opsTr('Analytics AI Assistant'), style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        );
  }

  Widget _buildDescription() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        widget.description!,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 10,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _buildSuggestions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: widget.suggestions.map((s) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.isLoading
                  ? null
                  : () {
                      widget.onSuggestionTap?.call(s);
                      _sendSuggestion(s);
                    },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.accentBlue.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  s,
                  style: const TextStyle(
                    color: AppColors.accentBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _sendSuggestion(String s) async {
    _ctrl.text = s;
    await _send();
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: widget.messages.length,
      itemBuilder: (_, i) {
        final m = widget.messages[i];
        final showTimestamp =
            i == 0 ||
            widget.messages[i - 1].timestamp.difference(m.timestamp).inMinutes >
                5;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showTimestamp) _timeSeparator(m.timestamp),
            const SizedBox(height: 6),
            _messageBubble(m),
          ],
        );
      },
    );
  }

  Widget _timeSeparator(DateTime t) {
    final fmt = DateFormat('HH:mm');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            fmt.format(t),
            style: const TextStyle(color: Colors.white30, fontSize: 10),
          ),
        ),
      ),
    );
  }

  Widget _messageBubble(AiMessage m) {
    return Align(
      alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: m.isUser
              ? AppColors.accentBlue.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: m.isUser
                ? AppColors.accentBlue.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: _buildRichText(m.text, isUser: m.isUser),
      ),
    );
  }

  Widget _buildRichText(String text, {required bool isUser}) {
    final style = TextStyle(
      color: Colors.white.withValues(alpha: 0.92),
      fontSize: 12.5,
      height: 1.45,
    );

    if (!isUser &&
        (text.contains('**') || text.contains('- ') || text.contains('\n'))) {
      return _parseMarkdown(text, style);
    }

    return Text(text, style: style);
  }

  Widget _parseMarkdown(String text, TextStyle baseStyle) {
    final spans = <TextSpan>[];
    final lines = text.split('\n');

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];

      if (line.startsWith('- ') || line.startsWith('• ')) {
        spans.add(
          TextSpan(
            text: '  • ',
            style: baseStyle.copyWith(color: AppColors.accentBlue),
          ),
        );
        line = line.substring(2);
      } else if (line.startsWith('**') && line.endsWith('**')) {
        spans.add(
          TextSpan(
            text: '\n${line.replaceAll('**', '')}\n',
            style: baseStyle.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        );
        continue;
      }

      final parts = line.split('**');
      for (var j = 0; j < parts.length; j++) {
        if (parts[j].isEmpty) continue;
        spans.add(
          TextSpan(
            text: parts[j],
            style: j.isOdd
                ? baseStyle.copyWith(fontWeight: FontWeight.w700)
                : baseStyle,
          ),
        );
      }

      if (i < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    return RichText(text: TextSpan(children: spans));
  }

  Widget _buildTypingIndicator() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.accentBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 12,
              color: AppColors.accentBlue,
            ),
          ),
          const SizedBox(width: 8),
          Text(context.opsTr('AI is analyzing live data...'), style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(width: 8),
          AnimatedBuilder(
            animation: _typingCtrl,
            builder: (context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  return Container(
                    margin: const EdgeInsets.only(right: 3),
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.accentBlue.withValues(
                        alpha:
                            0.3 + (_typingCtrl.value * 0.7 * (1 - (i * 0.25))),
                      ),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: context.opsTr('Ask about the live feed...'),
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: widget.isLoading
                  ? Colors.white.withValues(alpha: 0.06)
                  : AppColors.accentBlue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: widget.isLoading ? null : _send,
              icon: widget.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
              tooltip: context.opsTr('Send'),
            ),
          ),
        ],
      ),
    );
  }
}
