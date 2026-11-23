import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';

import 'mqtt_client_stub.dart'
    if (dart.library.io) 'mqtt_client_io.dart'
    if (dart.library.html) 'mqtt_client_web.dart';

enum MqttConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class IncubatorTelemetry {
  final double? temperature;
  final double? humidity;
  final double? soilMoisture;
  final double? lux;
  final bool? fanRelay;
  final bool? sprayerRelay;
  final bool? lampRelay;
  final bool? lamp1Relay;
  final bool? lamp2Relay;
  final String? mode;
  final String? activePlant;
  final DateTime receivedAt;
  final Map<String, dynamic> rawJson;

  const IncubatorTelemetry({
    this.temperature,
    this.humidity,
    this.soilMoisture,
    this.lux,
    this.fanRelay,
    this.sprayerRelay,
    this.lampRelay,
    this.lamp1Relay,
    this.lamp2Relay,
    this.mode,
    this.activePlant,
    required this.receivedAt,
    required this.rawJson,
  });

  factory IncubatorTelemetry.fromJson(Map<String, dynamic> json) {
    double? parseDouble(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString());
    }

    bool? parseBool(dynamic val) {
      if (val == null) return null;
      if (val is bool) return val;
      if (val is num) return val != 0;
      final str = val.toString().toLowerCase();
      if (str == 'true' || str == '1' || str == 'on') return true;
      if (str == 'false' || str == '0' || str == 'off') return false;
      return null;
    }

    final relayMap = json['relay'] is Map<String, dynamic>
        ? json['relay'] as Map<String, dynamic>
        : null;

    return IncubatorTelemetry(
      temperature: parseDouble(json['temperature']),
      humidity: parseDouble(json['humidity']),
      soilMoisture: parseDouble(json['soil_moisture']),
      lux: parseDouble(json['lux']),
      fanRelay: relayMap != null
          ? parseBool(relayMap['fan'])
          : parseBool(json['fan']),
      sprayerRelay: relayMap != null
          ? parseBool(relayMap['sprayer'])
          : parseBool(json['sprayer']),
      lampRelay: relayMap != null
          ? parseBool(relayMap['lamp'])
          : parseBool(json['lamp']),
      lamp1Relay: relayMap != null
          ? parseBool(relayMap['lamp1'])
          : parseBool(json['lamp1']),
      lamp2Relay: relayMap != null
          ? parseBool(relayMap['lamp2'])
          : parseBool(json['lamp2']),
      mode: json['mode']?.toString(),
      activePlant: json['active_plant']?.toString() ??
          json['active_plant_name']?.toString(),
      receivedAt: DateTime.now(),
      rawJson: json,
    );
  }
}

class MqttService {
  static final MqttService instance = MqttService._internal();

  MqttService._internal();

  // Broker Credentials
  static const String brokerHost =
      'z101725a.ala.asia-southeast1.emqxsl.com';
  static const int portMobile = 8883;
  static const int portWeb = 8084;
  static const String brokerUser = 'Semaiku';
  static const String brokerPass = 'semaiku123';

  // Topics
  static const String topicPrefix = 'buncop/incubator/inkubator_1';
  static const String topicTelemetry = '$topicPrefix/telemetry';
  static const String topicStatus = '$topicPrefix/status';
  static const String topicCommand = '$topicPrefix/command';
  static const String topicAlert = '$topicPrefix/alert';

  MqttClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;

  final _statusController =
      StreamController<MqttConnectionStatus>.broadcast();
  Stream<MqttConnectionStatus> get statusStream => _statusController.stream;

  MqttConnectionStatus _currentStatus = MqttConnectionStatus.disconnected;
  MqttConnectionStatus get currentStatus => _currentStatus;

  final _telemetryController =
      StreamController<IncubatorTelemetry>.broadcast();
  Stream<IncubatorTelemetry> get telemetryStream => _telemetryController.stream;

  IncubatorTelemetry? _latestTelemetry;
  IncubatorTelemetry? get latestTelemetry => _latestTelemetry;

  bool _isConnecting = false;

  void _setStatus(MqttConnectionStatus status) {
    if (_currentStatus != status) {
      _currentStatus = status;
      _statusController.add(status);
    }
  }

  Future<void> connect() async {
    if (_isConnecting || _currentStatus == MqttConnectionStatus.connected) {
      return;
    }

    _isConnecting = true;
    _setStatus(MqttConnectionStatus.connecting);

    final port = kIsWeb ? portWeb : portMobile;
    final randomSuffix = Random().nextInt(99999);
    final clientId = 'semaiku_app_$randomSuffix';

    debugPrint('[MQTT] Menghubungkan ke $brokerHost:$port (ClientId: $clientId)...');

    try {
      final client = createMqttClient(brokerHost, clientId, port);
      _client = client;

      client.logging(on: false);
      client.keepAlivePeriod = 60;
      client.autoReconnect = true;
      client.resubscribeOnAutoReconnect = true;

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .authenticateAs(brokerUser, brokerPass)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);

      client.connectionMessage = connMessage;

      client.onConnected = () {
        debugPrint('[MQTT] Terhubung ke EMQX Cloud!');
        _setStatus(MqttConnectionStatus.connected);
        _subscribeToTopics();
      };

      client.onDisconnected = () {
        debugPrint('[MQTT] Terputus dari broker.');
        _setStatus(MqttConnectionStatus.disconnected);
      };

      client.onAutoReconnect = () {
        debugPrint('[MQTT] Auto-reconnecting...');
        _setStatus(MqttConnectionStatus.connecting);
      };

      client.onAutoReconnected = () {
        debugPrint('[MQTT] Auto-reconnected!');
        _setStatus(MqttConnectionStatus.connected);
      };

      final connStatus = await client.connect();

      if (connStatus?.state == MqttConnectionState.connected) {
        _setStatus(MqttConnectionStatus.connected);
        _subscribeToTopics();
      } else {
        debugPrint('[MQTT] Koneksi gagal dengan status: ${connStatus?.state}');
        _setStatus(MqttConnectionStatus.error);
        client.disconnect();
      }
    } catch (e) {
      debugPrint('[MQTT] Exception saat koneksi: $e');
      _setStatus(MqttConnectionStatus.error);
    } finally {
      _isConnecting = false;
    }
  }

  void _subscribeToTopics() {
    if (_client == null ||
        _client!.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }

    // Subscribe to telemetry, status, and alert
    final topics = [
      topicTelemetry,
      topicStatus,
      topicAlert,
      'buncop/+/inkubator_1/telemetry',
      'buncop/+/inkubator_1/status',
    ];

    for (final t in topics) {
      _client!.subscribe(t, MqttQos.atLeastOnce);
      debugPrint('[MQTT] Subscribed to $t');
    }

    _updatesSub?.cancel();
    _updatesSub = _client!.updates?.listen(_onMessageReceived);
  }

  void _onMessageReceived(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final msg in messages) {
      final recMess = msg.payload as MqttPublishMessage;
      final payloadString =
          utf8.decode(recMess.payload.message);

      debugPrint('[MQTT RECV] [${msg.topic}] $payloadString');

      try {
        final decoded = jsonDecode(payloadString);
        if (decoded is Map<String, dynamic>) {
          final telemetry = IncubatorTelemetry.fromJson(decoded);
          _latestTelemetry = telemetry;
          _telemetryController.add(telemetry);
        }
      } catch (e) {
        debugPrint('[MQTT] Gagal parse JSON dari topic ${msg.topic}: $e');
      }
    }
  }

  // --------------------------------------------------------------------------
  // PUBLISH COMMANDS
  // --------------------------------------------------------------------------

  bool publishRawCommand(Map<String, dynamic> command) {
    if (_client == null ||
        _client!.connectionStatus?.state != MqttConnectionState.connected) {
      debugPrint('[MQTT] Gagal publish: Belum terhubung ke broker');
      return false;
    }

    // Pastikan timestamp selalu ada untuk proteksi perintah usang
    if (!command.containsKey('timestamp')) {
      command['timestamp'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }

    final payload = jsonEncode(command);
    final builder = MqttClientPayloadBuilder();
    builder.addUTF8String(payload);

    _client!.publishMessage(
      topicCommand,
      MqttQos.atLeastOnce,
      builder.payload!,
    );

    debugPrint('[MQTT SEND] [$topicCommand] $payload');
    return true;
  }

  bool setMode(String mode) {
    return publishRawCommand({
      'type': 'set_mode',
      'value': mode.toLowerCase(),
    });
  }

  bool setRelay(String relay, bool value, {int? duration}) {
    final payload = <String, dynamic>{
      'type': 'set_relay',
      'relay': relay,
      'value': value,
    };
    if (duration != null && duration > 0) {
      payload['duration'] = duration;
    }
    return publishRawCommand(payload);
  }

  bool setActivePlant(String plantId) {
    return publishRawCommand({
      'type': 'set_active_plant',
      'value': plantId,
    });
  }

  bool setSprayerDuration(int seconds) {
    return publishRawCommand({
      'type': 'set_sprayer_duration',
      'value': seconds,
    });
  }

  void disconnect() {
    _updatesSub?.cancel();
    _updatesSub = null;
    _client?.disconnect();
    _setStatus(MqttConnectionStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _statusController.close();
    _telemetryController.close();
  }
}
