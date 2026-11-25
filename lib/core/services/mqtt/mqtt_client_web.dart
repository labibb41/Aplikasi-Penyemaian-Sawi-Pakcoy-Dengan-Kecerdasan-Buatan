import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

MqttClient createMqttClient(String server, String clientId, int port) {
  final client = MqttBrowserClient.withPort('wss://$server/mqtt', clientId, port);
  client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  client.setProtocolV311();
  return client;
}