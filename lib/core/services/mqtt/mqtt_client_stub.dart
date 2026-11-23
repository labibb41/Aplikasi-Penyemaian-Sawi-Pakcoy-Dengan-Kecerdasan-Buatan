import 'package:mqtt_client/mqtt_client.dart';

MqttClient createMqttClient(String server, String clientId, int port) {
  throw UnsupportedError('Cannot create an MQTT client on this platform.');
}
