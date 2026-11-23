/*
 * ==============================================================================
 * Proyek: CekTandon v2.0 - Hybrid (Standalone Offline + Online MQTT)
 * Mikrokontroler: ESP32
 * Sensor: 2x HY-SRF05 (Dual Redundant Ultrasonic)
 * Output: 2x Modul Relay Pompa:
 *         - Relay 1 (GPIO 18): Pompa 1 (Pengisi Tandon / Inlet)
 *         - Relay 2 (GPIO 27): Pompa 2 (Distribusi / Outlet)
 * Broker: EMQX Local Server (10.14.41.20:1773)
 * Waktu : NTP Server (WIB - UTC+7)
 *
 * Sifat Sistem:
 * - JIKA ADA WIFI/MQTT   : Mengirim telemetri ke server & bisa dikontrol dari Web/App.
 * - JIKA TIDAK ADA WIFI  : Tetap 100% beroperasi mandiri (STANDALONE) menjaga level air.
 * ==============================================================================
 */


#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <time.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>


// ================= 1. KONFIGURASI WIFI & BROKER MQTT =================
const char* WIFI_SSID     = "Hotspot Petrokimia";
const char* WIFI_PASSWORD = "123@PetrokimiaJaya!";


// Konfigurasi Broker MQTT EMQX Lokal BunCOP
const char* MQTT_BROKER   = "10.14.41.20";      // IP Server EMQX Lokal
const int   MQTT_PORT     = 1773;               // Port TCP Standard (Non-TLS)
const char* MQTT_USER     = "buncop_esp";       // Username MQTT
const char* MQTT_PASS     = "Kinds123";         // Password MQTT


// Topik MQTT Komunikasi Tandon Air
const char* MQTT_TOPIC_DATA = "tandon/water_level"; // Publish status sensor & level air
const char* MQTT_TOPIC_CTRL = "tandon/control";     // Subscribe perintah kontrol dari Web/App


// ================= 2. KONFIGURASI PIN HARDWARE =================
// Pin I2C LCD (SDA & SCL)
#define LCD_SDA_PIN 25  // SDA LCD I2C (GPIO 25)
#define LCD_SCL_PIN 26  // SCL LCD I2C (GPIO 26)
#define LCD_ADDR    0x27 // Alamat I2C umum (0x27 atau 0x3F)
#define LCD_COLS    16   // 16 Kolom karakter (juga kompatibel untuk LCD 20x4)
#define LCD_ROWS    2    // 2 Baris

// Inisialisasi Modul LCD I2C
LiquidCrystal_I2C lcd(LCD_ADDR, LCD_COLS, LCD_ROWS);

// Pin Sensor 1 (HY-SRF05 - Utama)
#define TRIG1 13
#define ECHO1 12

// Pin Sensor 2 (HY-SRF05 - Opsional / Sekunder)
// Catatan: Pin 25 & 26 dialokasikan untuk LCD I2C. Sensor 2 dialihkan ke GPIO 32 & 33 (jika digunakan).
#define TRIG2 32
#define ECHO2 33


// Pin Relay Pompa Air
#define RELAY1_PIN 18  // Relay 1 (GPIO 18): Pompa Pengisi Tandon (Inlet)
#define RELAY2_PIN 27  // Relay 2 (GPIO 27): Pompa Distribusi / Outlet


// Logika Aktif Relay (Sesuaikan jika modul relay Anda Aktif-LOW)
#define RELAY_ON  LOW   // LOW = Relay ON (Jika relay aktif-LOW, ubah ke HIGH jika aktif-HIGH)
#define RELAY_OFF HIGH  // HIGH = Relay OFF


// ================= 3. PARAMETER TANDON 570 LITER =================
const float TINGGI_DASAR_TANDON_CM    = 100.0; // Jarak sensor ke dasar saat tandon kosong (cm)
const float JARAK_SENSOR_AIR_PENUH_CM = 15.0;  // Jarak sensor ke air saat penuh (blind zone cm)
const float KAPASITAS_MAX_LITER       = 570.0; // Kapasitas maksimal tandon (Liter)


// ================= 4. STATE SISTEM & VARIABEL JARINGAN =================
// State Relay Pompa 1 (Inlet / Pengisi)
bool pump1State = false;
bool manualOverride1 = false;
String pump1Reason = "Inisialisasi Sistem";


// State Relay Pompa 2 (Outlet / Distribusi)
bool pump2State = false;
bool manualOverride2 = false;
String pump2Reason = "Inisialisasi Sistem";


WiFiClient netClient;
PubSubClient mqttClient(netClient);


unsigned long lastSend = 0;
const unsigned long intervalSend = 2000; // Evaluasi logika & sensor tiap 2 detik


// Variabel Non-Blocking Reconnect Network
unsigned long lastWiFiRetry = 0;
const unsigned long intervalWiFiRetry = 15000; // Coba sambung ulang WiFi tiap 15 detik jika offline
unsigned long lastMqttRetry = 0;
const unsigned long intervalMqttRetry = 10000; // Coba sambung ulang MQTT tiap 10 detik jika offline
bool wifiConnectedBefore = false;


// ================= 5. FUNGSI SENSOR, RELAY & LCD =================
// Update Tampilan LCD 16x2 / 20x4
void updateLCD(float persen, float liter, String status, bool p1, bool p2, bool online) {
  char line1[17];
  char line2[17];

  // Baris 1: Level Air & Volume (contoh: "Air: 85%  484L  ")
  snprintf(line1, sizeof(line1), "Air:%4.1f%% %4.0fL", persen, liter);

  // Baris 2: Status Pompa 1 & 2 serta Status Jaringan (contoh: "P1:ON P2:OFF ONL")
  snprintf(line2, sizeof(line2), "P1:%s P2:%s %s",
           p1 ? "ON " : "OFF",
           p2 ? "ON " : "OFF",
           online ? "ONL" : "OFL");

  lcd.setCursor(0, 0);
  lcd.print(line1);
  lcd.setCursor(0, 1);
  lcd.print(line2);
}

// Membaca jarak sensor ultrasonik HY-SRF05
float bacaJarak(int trigPin, int echoPin) {
  if (trigPin < 0 || echoPin < 0) return -1;

  digitalWrite(trigPin, LOW);
  delayMicroseconds(2);


  digitalWrite(trigPin, HIGH);
  delayMicroseconds(10);
  digitalWrite(trigPin, LOW);


  long duration = pulseIn(echoPin, HIGH, 30000); // Timeout 30ms (~5 meter)
  if (duration == 0) return -1;


  float distance = duration * 0.0343 / 2.0;
  return distance;
}


// Kontrol Fisik Relay Pompa 1 (Inlet)
void setPump1(bool state, String reason) {
  pump1State = state;
  pump1Reason = reason;
  digitalWrite(RELAY1_PIN, state ? RELAY_ON : RELAY_OFF);
  Serial.printf("[POMPA 1 (GPIO 18)] %s | Alasan: %s\n", state ? "MENYALA (ON)" : "MATI (OFF)", reason.c_str());
}


// Kontrol Fisik Relay Pompa 2 (Outlet)
void setPump2(bool state, String reason) {
  pump2State = state;
  pump2Reason = reason;
  digitalWrite(RELAY2_PIN, state ? RELAY_ON : RELAY_OFF);
  Serial.printf("[POMPA 2 (GPIO 27)] %s | Alasan: %s\n", state ? "MENYALA (ON)" : "MATI (OFF)", reason.c_str());
}


// Handle Perintah Manual lewat Serial Monitor (Ketik '1' atau '2')
void handleSerialInput() {
  if (Serial.available() > 0) {
    char cmd = Serial.read();
    if (cmd == '1') {
      manualOverride1 = true;
      setPump1(!pump1State, !pump1State ? "Manual Serial (Pompa 1 ON)" : "Manual Serial (Pompa 1 OFF)");
    } else if (cmd == '2') {
      manualOverride2 = true;
      setPump2(!pump2State, !pump2State ? "Manual Serial (Pompa 2 ON)" : "Manual Serial (Pompa 2 OFF)");
    }
  }
}


// ================= 6. SINKRONISASI NTP TIME (OPSIONAL) =================
void setupNTP() {
  Serial.println("Menyinkronkan waktu dengan NTP Server (WIB)...");
  configTime(7 * 3600, 0, "pool.ntp.org", "time.google.com");
 
  struct tm timeinfo;
  if (getLocalTime(&timeinfo, 3000)) {
    Serial.printf("Waktu sekarang: %02d:%02d:%02d WIB\n", timeinfo.tm_hour, timeinfo.tm_min, timeinfo.tm_sec);
  } else {
    Serial.println("Sinkronisasi waktu NTP dilewati / gagal.");
  }
}


// ================= 7. CALLBACK PENERIMAAN MQTT =================
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String message = "";
  for (unsigned int i = 0; i < length; i++) {
    message += (char)payload[i];
  }
  Serial.println("\n[MQTT MASUK] Topic: " + String(topic) + " | Payload: " + message);


  StaticJsonDocument<256> doc;
  DeserializationError err = deserializeJson(doc, message);
  if (err) {
    Serial.println("Gagal parse JSON MQTT");
    return;
  }


  const char* cmd = doc["cmd"] | "";


  // 1. Perintah Toggle Manual Pompa dari Web/MQTT
  if (strcmp(cmd, "toggle_pump") == 0 || strcmp(cmd, "toggle_pump1") == 0) {
    int pumpId = doc["pump_id"] | 1;
    bool targetState = doc["pump_power"] | doc["power"] | false;


    if (pumpId == 2) {
      manualOverride2 = true;
      setPump2(targetState, targetState ? "Manual Web/MQTT (Pompa 2 ON)" : "Manual Web/MQTT (Pompa 2 OFF)");
    } else {
      manualOverride1 = true;
      setPump1(targetState, targetState ? "Manual Web/MQTT (Pompa 1 ON)" : "Manual Web/MQTT (Pompa 1 OFF)");
    }
  } else if (strcmp(cmd, "toggle_pump2") == 0) {
    bool targetState = doc["pump_power"] | doc["power"] | false;
    manualOverride2 = true;
    setPump2(targetState, targetState ? "Manual Web/MQTT (Pompa 2 ON)" : "Manual Web/MQTT (Pompa 2 OFF)");
  }
}


// ================= 8. KONEKSI NON-BLOCKING (WIFI & MQTT) =================
// Inisialisasi awal saat booting tanpa memblokir sistem jika WiFi tidak ada
void initWiFi() {
  Serial.print("[WiFi] Menghubungkan ke: ");
  Serial.println(WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);


  // Tunggu maksimal 3 detik agar booting cepat & langsung kontrol tandon
  unsigned long startWait = millis();
  while (WiFi.status() != WL_CONNECTED && (millis() - startWait < 3000)) {
    delay(200);
    Serial.print(".");
  }


  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n[WiFi] Terhubung! IP ESP32: " + WiFi.localIP().toString());
    wifiConnectedBefore = true;
    setupNTP();
  } else {
    Serial.println("\n[INFO] WiFi belum terhubung. Sistem pompa TETAP BERJALAN normal secara offline (Standalone)!");
  }
}


// Cek & sambung ulang jaringan di latar belakang tanpa menghentikan loop utama
void checkConnections() {
  unsigned long now = millis();


  // 1. Cek status WiFi
  if (WiFi.status() == WL_CONNECTED) {
    if (!wifiConnectedBefore) {
      wifiConnectedBefore = true;
      Serial.println("\n[WiFi] Berhasil tersambung kembali! IP: " + WiFi.localIP().toString());
      setupNTP();
    }


    // 2. Hubungkan ke Broker MQTT jika WiFi tersambung
    if (!mqttClient.connected()) {
      if (now - lastMqttRetry >= intervalMqttRetry) {
        lastMqttRetry = now;
        Serial.printf("[MQTT] Mencoba koneksi ke Broker EMQX (%s:%d)...\n", MQTT_BROKER, MQTT_PORT);
        String clientId = "CekTandon-570L-" + String(random(0xffff), HEX);
        if (mqttClient.connect(clientId.c_str(), MQTT_USER, MQTT_PASS)) {
          Serial.println("[MQTT] Berhasil terhubung ke Broker!");
          mqttClient.subscribe(MQTT_TOPIC_CTRL);
        } else {
          Serial.printf("[MQTT] Gagal (rc=%d), akan dicoba lagi di background.\n", mqttClient.state());
        }
      }
    } else {
      mqttClient.loop();
    }
  } else {
    wifiConnectedBefore = false;
    // Coba koneksi ulang WiFi secara berkala tanpa delay
    if (now - lastWiFiRetry >= intervalWiFiRetry) {
      lastWiFiRetry = now;
      Serial.println("[WiFi] Mencoba menyambung kembali di background...");
      WiFi.reconnect();
    }
  }
}


// ================= 9. SETUP =================
void setup() {
  Serial.begin(115200);
  delay(1000);


  Serial.println("\n========================================================");
  Serial.println("  SISTEM OTOMASI TANDON 570L (HYBRID OFFLINE/ONLINE)");
  Serial.println("========================================================");
  Serial.println("Ketik '1' di Serial Monitor untuk Toggle Manual Pompa 1");
  Serial.println("Ketik '2' di Serial Monitor untuk Toggle Manual Pompa 2\n");


  // Inisialisasi I2C LCD di pin 25 (SDA) dan pin 26 (SCL)
  Wire.begin(LCD_SDA_PIN, LCD_SCL_PIN);
  delay(50);

  // Scanner otomatis alamat I2C di Serial Monitor
  Serial.println("[I2C SCANNER] Memindai bus I2C pada SDA=GPIO 25 & SCL=GPIO 26...");
  byte foundCount = 0;
  for (byte addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      Serial.printf("[I2C SCANNER] >> Ditemukan perangkat I2C di alamat: 0x%02X\n", addr);
      foundCount++;
    }
  }

  if (foundCount == 0) {
    Serial.println("[I2C SCANNER] PERINGATAN: Tidak ada modul I2C yang terdeteksi!");
    Serial.println("  -> Cek kabel SDA ke GPIO 25 dan SCL ke GPIO 26 (jangan terbalik)");
    Serial.println("  -> Cek VCC modul LCD terhubung ke 5V / VIN (BUKAN 3.3V)");
    Serial.println("  -> Pastikan GND terhubung ke GND ESP32");
  }

  lcd.init();
  lcd.backlight();
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print(" CekTandon v2.0 ");
  lcd.setCursor(0, 1);
  lcd.print(" Inisialisasi...");

  // Inisialisasi Pin Ultrasonik
  pinMode(TRIG1, OUTPUT);
  pinMode(ECHO1, INPUT);
  digitalWrite(TRIG1, LOW);

  if (TRIG2 >= 0 && ECHO2 >= 0) {
    pinMode(TRIG2, OUTPUT);
    pinMode(ECHO2, INPUT);
    digitalWrite(TRIG2, LOW);
  }


  // Inisialisasi Pin Relay Pompa
  pinMode(RELAY1_PIN, OUTPUT);
  digitalWrite(RELAY1_PIN, RELAY_OFF); // Default awal OFF


  pinMode(RELAY2_PIN, OUTPUT);
  digitalWrite(RELAY2_PIN, RELAY_OFF); // Default awal OFF


  // Inisialisasi WiFi Non-Blocking
  initWiFi();


  // Konfigurasi Client MQTT
  mqttClient.setServer(MQTT_BROKER, MQTT_PORT);
  mqttClient.setBufferSize(512);
  mqttClient.setCallback(mqttCallback);


  Serial.println("Hardware siap. Memulai pemantauan logika...");
}


// ================= 10. LOOP UTAMA =================
void loop() {
  // 1. Cek & kelola koneksi di latar belakang (tanpa memblokir eksekusi sensor/pompa)
  checkConnections();


  // 2. Handle input manual dari Serial Monitor
  handleSerialInput();


  // 3. Evaluasi siklus pembacaan & logika tiap 2 detik
  if (millis() - lastSend >= intervalSend) {
    lastSend = millis();


    // Baca sensor ultrasonik
    float jarak1 = bacaJarak(TRIG1, ECHO1);
    delay(40); // Jeda mencegah tabrakan pantulan akustik
    float jarak2 = (TRIG2 >= 0 && ECHO2 >= 0) ? bacaJarak(TRIG2, ECHO2) : -1;


    // Dual Sensor Redundancy
    float jarakAvg = -1;
    if (jarak1 > 0 && jarak2 > 0) {
      jarakAvg = (jarak1 + jarak2) / 2.0;
    } else if (jarak1 > 0) {
      jarakAvg = jarak1;
    } else if (jarak2 > 0) {
      jarakAvg = jarak2;
    }


    if (jarakAvg > 0) {
      // Perhitungan Ketinggian & Volume Air
      float tinggiAir = TINGGI_DASAR_TANDON_CM - jarakAvg;
      if (tinggiAir < 0) tinggiAir = 0;


      float tinggiMaksimum = TINGGI_DASAR_TANDON_CM - JARAK_SENSOR_AIR_PENUH_CM; // 85.0 cm
      if (tinggiMaksimum <= 0) tinggiMaksimum = 1;


      float persen = (tinggiAir / tinggiMaksimum) * 100.0;
      if (persen > 100.0) persen = 100.0;
      if (persen < 0.0) persen = 0.0;


      float liter = (persen / 100.0) * KAPASITAS_MAX_LITER;


      // Kategori Status Level Air
      String levelStatus = "Low";
      if (persen >= 80.0) {
        levelStatus = "Penuh";
      } else if (persen >= 30.0) {
        levelStatus = "Mid";
      } else {
        levelStatus = "Low";
      }


      // ================= LOGIKA KONTROL RELAY & KEAMANAN =================


      // PRIORITAS 1: PROTEKSI ANTI-MELUBER UNTUK POMPA 1 (PENGISI AIR)
      if (persen >= 80.0 || jarakAvg <= (JARAK_SENSOR_AIR_PENUH_CM + 2.0)) {
        if (pump1State) {
          setPump1(false, "Proteksi Meluber: Air Tandon Penuh!");
        }
        manualOverride1 = false; // Reset override untuk keselamatan tandon
      }
      // PRIORITAS 2: PENGISIAN OTOMATIS SAAT AIR LOW (<= 30%)
      else if (persen <= 30.0) {
        manualOverride1 = false;
        if (!pump1State) {
          setPump1(true, "Auto: Level Air Low (<=30%), Mulai Pengisian");
        }
      }
      // PRIORITAS 3: HISTERESIS PENGISIAN (30% s/d 80%)
      else if (pump1State) {
        // Tetap ON mengisi sampai mencapai 80%
      }


      // PRIORITAS 4: PROTEKSI DRY-RUN POMPA 2 (OUTLET / DISTRIBUSI)
      if (persen < 10.0 && pump2State) {
        setPump2(false, "Proteksi Dry-Run: Air Kritis (<10%), Pompa 2 Dimatikan");
        manualOverride2 = false;
      }


      // ================= TELEMETRI MQTT & SERIAL =================
      StaticJsonDocument<512> doc;
      doc["jarak1"]        = serialized(String(jarak1, 1));
      doc["jarak2"]        = serialized(String(jarak2, 1));
      doc["jarak_avg"]      = serialized(String(jarakAvg, 1));
      doc["tinggi_air"]     = serialized(String(tinggiAir, 1));
      doc["persen"]         = serialized(String(persen, 1));
      doc["liter"]          = serialized(String(liter, 1));
      doc["status"]         = levelStatus;


      // Status Pompa 1 & 2
      doc["pump1_state"]    = pump1State;
      doc["pump1_reason"]   = pump1Reason;
      doc["pump2_state"]    = pump2State;
      doc["pump2_reason"]   = pump2Reason;
     
      // Fallback kompatibilitas dengan Web Valve / Pump generic
      doc["pump_state"]     = pump1State;
      doc["pump_reason"]    = pump1Reason;


      struct tm timeinfo;
      if (getLocalTime(&timeinfo, 50)) {
        char timeBuf[12];
        snprintf(timeBuf, sizeof(timeBuf), "%02d:%02d:%02d", timeinfo.tm_hour, timeinfo.tm_min, timeinfo.tm_sec);
        doc["device_time"] = timeBuf;
      }


      char buffer[512];
      serializeJson(doc, buffer);


      if (mqttClient.connected()) {
        bool pubSuccess = mqttClient.publish(MQTT_TOPIC_DATA, buffer);
        Serial.printf("[ONLINE-MQTT %s] S1: %.1f | S2: %.1f | Avg: %.1f cm (%.1f%%) | P1: %s | P2: %s\n",
                      pubSuccess ? "OK" : "ERR", jarak1, jarak2, jarakAvg, persen,
                      pump1State ? "ON" : "OFF", pump2State ? "ON" : "OFF");
      } else {
        Serial.printf("[STANDALONE] S1: %.1f | S2: %.1f | Avg: %.1f cm (%.1f%%) | P1: %s | P2: %s | Offline\n",
                      jarak1, jarak2, jarakAvg, persen,
                      pump1State ? "ON" : "OFF", pump2State ? "ON" : "OFF");
      }

      // Update Tampilan LCD I2C (Pin 25 SDA & Pin 26 SCL)
      updateLCD(persen, liter, levelStatus, pump1State, pump2State, mqttClient.connected());

    } else {
      Serial.println("[PERINGATAN] Sensor gagal membaca pantulan ultrasonik!");
      lcd.setCursor(0, 0);
      lcd.print("  Sensor Error! ");
      lcd.setCursor(0, 1);
      lcd.print(" Cek Ultrasonik ");
    }
  }
}


