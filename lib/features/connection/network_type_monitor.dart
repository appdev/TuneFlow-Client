import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';

enum NetworkTransport { bluetooth, wifi, ethernet, mobile, vpn, other, none }

enum NetworkRoute { lan, external, offline }

NetworkRoute classifyNetwork(Set<NetworkTransport> transports) {
  if (transports.contains(NetworkTransport.wifi) ||
      transports.contains(NetworkTransport.ethernet)) {
    return NetworkRoute.lan;
  }
  if (transports.isEmpty ||
      transports.every((transport) => transport == NetworkTransport.none)) {
    return NetworkRoute.offline;
  }
  return NetworkRoute.external;
}

abstract interface class NetworkTypeMonitor {
  Future<Set<NetworkTransport>> current();

  Stream<Set<NetworkTransport>> get changes;
}

final class ConnectivityNetworkTypeMonitor implements NetworkTypeMonitor {
  ConnectivityNetworkTypeMonitor([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<Set<NetworkTransport>> current() async {
    try {
      return _normalize(
        await _connectivity.checkConnectivity().timeout(
          const Duration(seconds: 1),
        ),
      );
    } on Object {
      return const {NetworkTransport.other};
    }
  }

  @override
  Stream<Set<NetworkTransport>> get changes {
    try {
      ServicesBinding.instance;
    } on Object {
      return const Stream.empty();
    }
    return _changes();
  }

  Stream<Set<NetworkTransport>> _changes() async* {
    try {
      await for (final results in _connectivity.onConnectivityChanged) {
        yield _normalize(results);
      }
    } on Object {
      // Reachability probes remain authoritative when transport APIs fail.
    }
  }

  static Set<NetworkTransport> _normalize(List<ConnectivityResult> results) {
    final transports = results.map(_mapResult).toSet();
    if (transports.length > 1) transports.remove(NetworkTransport.none);
    return Set.unmodifiable(transports);
  }

  static NetworkTransport _mapResult(ConnectivityResult result) {
    return switch (result) {
      ConnectivityResult.bluetooth => NetworkTransport.bluetooth,
      ConnectivityResult.wifi => NetworkTransport.wifi,
      ConnectivityResult.ethernet => NetworkTransport.ethernet,
      ConnectivityResult.mobile => NetworkTransport.mobile,
      ConnectivityResult.vpn => NetworkTransport.vpn,
      ConnectivityResult.satellite => NetworkTransport.other,
      ConnectivityResult.other => NetworkTransport.other,
      ConnectivityResult.none => NetworkTransport.none,
    };
  }
}
