import 'dart:async';
import 'package:flutter/material.dart';

const kPollingInterval = Duration(seconds: 9);

mixin PollingMixin<T extends StatefulWidget> on State<T> {
  Timer? _pollingTimer;
  bool _isFetching = false;
  DateTime? _lastFetch;

  @protected
  Duration get pollingInterval => kPollingInterval;

  @protected
  Future<void> onPoll() async {}

  @protected
  void startPolling() {
    _lastFetch = DateTime.now();
    _schedulePoll();
  }

  void _schedulePoll() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer(pollingInterval, () {
      _fetch();
    });
  }

  Future<void> _fetch() async {
    if (_isFetching) return;
    _isFetching = true;
    try {
      await onPoll();
      _lastFetch = DateTime.now();
    } finally {
      _isFetching = false;
    }
    if (mounted) {
      _schedulePoll();
    }
  }

  @protected
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  bool get isPolling => _pollingTimer != null;

  DateTime? get lastFetchTime => _lastFetch;

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}