/*************************************************
 * ESP32 INKUBATOR -- MQTT VERSION (TUGAS AKHIR)
 * AUTO + MANUAL + SPRAYER + ONLINE STATUS
 * MQTT (EMQX) + FUZZY MAMDANI CONTROLLER
 *
 * PERUBAHAN v2 (fokus TA):
 *   - Fuzzy disederhanakan: 2 input (suhu + tanah), 9 rules
 *   - Cahaya/lampu: konstan via jadwal (dimmer belum tersedia)
 *   - Kipas    : dikendalikan fuzzy (suhu x tanah)
 *   - Sprayer  : dikendalikan jadwal rutin + notifikasi fuzzy advisory (proteksi sensor)
 *   - Lampu    : ON/OFF berdasar fase gelap/terang + window jam
 *************************************************/

// ── Struct output fuzzy (dideklarasikan sebelum #include) ───────
struct FuzzyOutput {
  float pompa;   // 0=OFF, 1=singkat, 2=sedang, 3=panjang
  float kipas;   // 0=OFF, 1=nyala
  // catatan: lampu dikeluarkan dari fuzzy karena diatur jadwal konstan
};

#define MQTT_AREA      "incubator"
#define MQTT_DEVICE_ID "inkubator_1"

#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <DHT.h>
#include <time.h>
#include <sys/time.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <RTClib.h>
#include <math.h>
#include <Preferences.h>
#include "esp_system.h"
#include "esp_task_wdt.h"

/* =================================================================
 *  FUZZY MAMDANI — 2 INPUT (SUHU + TANAH), 9 RULES
 *
 *  Mengapa 9 rules?
 *  Karena input cahaya dikeluarkan (lampu konstan, dimmer belum ada).
 *  2 input × 3 himpunan masing-masing = 3² = 9 kombinasi rules.
 *
 *  Input:
 *    suhu  : suhu udara dari DHT22 (°C)
 *    tanah : kelembaban tanah dari soil moisture (%)
 *  Output:
 *    pompa : 0=OFF, 1=singkat(5s), 2=sedang(15s), 3=panjang(30s)
 *    kipas : 0=OFF, 1=nyala
 * ================================================================= */

// ── Fungsi keanggotaan ──────────────────────────────────────────
static inline float fzy_trapLeft(float x, float a, float b) {
  if (x <= a) return 1.0f;
  if (x >= b) return 0.0f;
  return (b - x) / (b - a);
}
static inline float fzy_triangle(float x, float a, float b, float c) {
  if (x <= a || x >= c) return 0.0f;
  if (x <= b) return (x - a) / (b - a);
  return (c - x) / (c - b);
}
static inline float fzy_trapRight(float x, float a, float b) {
  if (x <= a) return 0.0f;
  if (x >= b) return 1.0f;
  return (x - a) / (b - a);
}
static inline float fzy_min(float a, float b) { return a < b ? a : b; }

/*
 * runFuzzy() — Mamdani 2-input, 9 rules, defuzzifikasi centroid
 *
 * Tabel himpunan fuzzy:
 *   Suhu  : DINGIN [trapLeft 20-25] | NORMAL [tri 20-26-30] | PANAS [trapRight 27-32]
 *   Tanah : KERING [trapLeft 25-35] | LEMBAB [tri 30-40-55] | BASAH [trapRight 50-60]
 *
 * Output crisp:
 *   Pompa: 0=OFF, 1=singkat, 2=sedang, 3=panjang
 *   Kipas: 0=OFF, 1=nyala
 */
static FuzzyOutput runFuzzy(float suhu, float tanah) {

  // ── Step 1: Fuzzifikasi ─────────────────────────────────────
  float s_dingin = fzy_trapLeft (suhu,  20.0f, 25.0f);
  float s_normal = fzy_triangle (suhu,  20.0f, 26.0f, 30.0f);
  float s_panas  = fzy_trapRight(suhu,  27.0f, 32.0f);

  float t_kering = fzy_trapLeft (tanah, 25.0f, 35.0f);
  float t_lembab = fzy_triangle (tanah, 30.0f, 40.0f, 55.0f);
  float t_basah  = fzy_trapRight(tanah, 50.0f, 60.0f);

  // ── Step 2 & 3: Inferensi + Agregasi (weighted average) ────
  float wPompa = 0.0f, sumPompa = 0.0f;
  float wKipas = 0.0f, sumKipas = 0.0f;

  // Macro: AND = minimum, lalu akumulasi weighted sum
  // Argumen: (S=suhu, T=tanah, P=nilai_pompa, K=nilai_kipas)
  #define RULE(S, T, P, K) { \
    float _w = fzy_min((S), (T)); \
    wPompa += _w; sumPompa += _w * (P); \
    wKipas += _w; sumKipas += _w * (K); }

  // ── 9 Rules Fuzzy Mamdani ──────────────────────────────────
  //         S           T          P  K
  //                               pompa kipas
  RULE(s_normal, t_lembab, 0, 0)  // R1: Normal+Lembab  → OFF, Kipas OFF
  RULE(s_normal, t_kering, 2, 0)  // R2: Normal+Kering  → Sedang, Kipas OFF
  RULE(s_normal, t_basah,  0, 0)  // R3: Normal+Basah   → OFF, Kipas OFF
  RULE(s_panas,  t_lembab, 0, 1)  // R4: Panas+Lembab   → OFF, Kipas ON
  RULE(s_panas,  t_kering, 3, 1)  // R5: Panas+Kering   → Panjang, Kipas ON
  RULE(s_panas,  t_basah,  0, 1)  // R6: Panas+Basah    → OFF, Kipas ON
  RULE(s_dingin, t_lembab, 0, 0)  // R7: Dingin+Lembab  → OFF, Kipas OFF
  RULE(s_dingin, t_kering, 1, 0)  // R8: Dingin+Kering  → Singkat, Kipas OFF
  RULE(s_dingin, t_basah,  0, 0)  // R9: Dingin+Basah   → OFF, Kipas OFF

  #undef RULE

  // ── Step 4: Defuzzifikasi (centroid = weighted average) ─────
  FuzzyOutput out;
  out.pompa = (wPompa > 0.001f) ? sumPompa / wPompa : 0.0f;
  out.kipas = (wKipas > 0.001f) ? sumKipas / wKipas : 0.0f;
  return out;
}
/* ── akhir fuzzy engine ─────────────────────────────────────────── */


/* ================= RECONNECT CONFIG ================= */
#define WDT_TIMEOUT_S        30
#define WIFI_CONNECT_TIMEOUT 10000
#define WIFI_MAX_FAILURES    5
#define HEAP_MIN_BYTES       20000

/* ================= WIFI ================= */
#define WIFI_SSID     "Buncop 3"
#define WIFI_PASSWORD "Petrokimia@2024"

/* ================= KONFIGURASI BROKER MQTT ================= */
// Mode Broker:
// true  = DUAL CLIENT AKTIF (Kirim paralel ke Server Perusahaan & EMQX Cloud secara bersamaan)
// false = SINGLE CLIENT (Hanya kirim ke EMQX Cloud)
#define ENABLE_DUAL_MQTT true

// 1) Parameter EMQX Cloud (Mode Internet Publik / TA)
#define CLOUD_MQTT_HOST "z101725a.ala.asia-southeast1.emqxsl.com"
#define CLOUD_MQTT_PORT 8883
#define CLOUD_MQTT_USER "Semaiku"
#define CLOUD_MQTT_PASS "semaiku123"

// 2) Parameter Intranet Perusahaan (Mode Lokal Greenhouse)
#define LOCAL_MQTT_HOST "10.14.41.20"
#define LOCAL_MQTT_PORT 1773
#define LOCAL_MQTT_USER "buncop_esp"
#define LOCAL_MQTT_PASS "Kinds123"

/* ================= PIN ================= */
// Konfigurasi Pin Relay (Active LOW)
#define RELAY_FAN     16  // Kipas / Fan
#define RELAY_SPRAYER 19  // Sprayer / Pompa Air (GPIO 19)

// Konfigurasi 2 Lampu Grow Light
// Lampu 1 = GPIO 17, Lampu 2 = GPIO 18
const int NUM_LAMPS = 2;
const int lampPins[NUM_LAMPS] = {17, 18};
bool lampPinsState[NUM_LAMPS] = {false, false};

// Di mode auto: default 1 lampu aktif masa terang (bisa diset 1 atau 2 via edit tanaman)
int autoLampsActive = 1;
bool etiolasiOverride = false;

// RTC DS3231 (I2C Bus Sekunder / Wire1)
#define RTC_I2C_SDA_PIN 27
#define RTC_I2C_SCL_PIN 14

// Sensor Intensitas Cahaya BH1750 (Bit-Bang I2C)
#define LUX_SCL_PIN 25
#define LUX_DAT_PIN 26

#define DHTPIN  4
#define DHTTYPE DHT22

// Sensor Kelembaban Tanah (A0: GPIO 34, D0: GPIO 35)
#define SOIL_MOISTURE_AO_PIN 34
#define SOIL_MOISTURE_DO_PIN 35
#define SOIL_DO_ACTIVE_LOW   1

// Relay Module: Active LOW (LOW = ON, HIGH = OFF)
#define RELAY_ACTIVE_LOW 1

/* ================= DISPLAY CONFIGURATION (I2C LCD vs TFT SERIAL) ================= */
// Pin Display di header yang sama (GPIO 32 & GPIO 33):
// Jika mode I2C LCD   : GPIO 32 = SDA, GPIO 33 = SCL
// Jika mode TFT Serial: GPIO 32 = RXD, GPIO 33 = TXD (Hubungkan TXD GPIO 33 ke RXD2 GPIO 25 pada ESP32 TFT)
#define DISPLAY_PIN_RX_SDA  32
#define DISPLAY_PIN_TX_SCL  33

#define LCD_I2C_SDA_PIN     DISPLAY_PIN_RX_SDA
#define LCD_I2C_SCL_PIN     DISPLAY_PIN_TX_SCL
#define LCD_I2C_ADDR        0x27
#define LCD_COLS            20
#define LCD_ROWS            4

#define TFT_SERIAL_RX_PIN   DISPLAY_PIN_RX_SDA
#define TFT_SERIAL_TX_PIN   DISPLAY_PIN_TX_SCL
#define TFT_SERIAL_BAUD     9600

// Opsi Mode Display:
// 0 = AUTO_DETECT (Cek apakah ada I2C LCD di pin 32 & 33. Jika ada, pakai LCD I2C. Jika tidak ada, otomatis aktifkan TFT Serial!)
// 1 = TFT_SERIAL_ONLY (Paksa pin 32/33 sebagai UART Serial2 untuk LCD TFT)
// 2 = I2C_LCD_ONLY (Paksa pin 32/33 sebagai I2C untuk LCD 20x4)
// 3 = DUAL_DISPLAY (LCD I2C aktif di pin 32/33 DAN TFT Serial aktif di pin cadangan misal TX=GPIO 23)
#define DISPLAY_MODE_AUTO   0
#define DISPLAY_MODE_TFT    1
#define DISPLAY_MODE_I2C    2
#define DISPLAY_MODE_DUAL   3

#define DISPLAY_CONFIG      DISPLAY_MODE_AUTO // Default: Otomatis mendeteksi keberadaan LCD I2C
#define DUAL_TFT_TX_PIN     23                // Khusus jika memilih DISPLAY_MODE_DUAL (keduanya aktif bersamaan)

/* ================= CONSTANTS ================= */
#define MAX_SCHEDULE 10

const int    LAMP_OFF_THRESHOLD   = 8;
const int    LAMP_MIN_STABLE      = 28;
const float  LAMP_GAMMA           = 1.2f;
const float  faktorKalibrasi      = 2.75; // Faktor kalibrasi sensor intensitas cahaya BH1750
const int    SOIL_ADC_DRY_VALUE   = 3200;
const int    SOIL_ADC_WET_VALUE   = 1400;

// ── Konversi crisp pompa → durasi semprot (detik) ──────────────
// Sesuaikan durasi jika perlu, misalnya tray 72 titik butuh lebih lama
const int SPRAY_SINGKAT_S  = 2;   // R2 fallback, tanah agak kering + suhu dingin
const int SPRAY_SEDANG_S   = 4;   // tanah kering + suhu normal
const int SPRAY_PANJANG_S  = 6;   // tanah kering + suhu panas (kondisi kritis)

// Cooldown sprayer setelah penyiraman otomatis (mencegah banjir)
// Cooldown sprayer setelah penyiraman otomatis (mencegah overwatering & memberi waktu air meresap)
// Murni interval jeda waktu, tanpa terikat slot waktu (Pagi/Siang/Malam)
const unsigned long SPRAYER_COOLDOWN_MS = 10UL * 60UL * 1000UL; // 10 menit jeda antar semprot

/* ================= TIMING ================= */
const unsigned long SENSOR_PUSH_INTERVAL  = 5000;
const unsigned long STATUS_PUSH_INTERVAL  = 10000;
const unsigned long AUTO_LOGIC_INTERVAL   = 10000;
const unsigned long HEARTBEAT_INTERVAL    = 15000;
const unsigned long SCHEDULE_CHECK_MS     = 1000;
const unsigned long HEAP_CHECK_INTERVAL   = 10000;
const unsigned long LCD_UPDATE_INTERVAL   = 1000;
const unsigned long LOOP_DELAY_MS         = 20;
const unsigned long AUTO_SOIL_GRACE_MS    = 60UL * 1000UL;

/* ================= TOPICS ================= */
String topicTelemetry;
String topicStatus;
String topicCommand;
String topicAlert;

/* ================= OBJECTS ================= */
#include <WiFiClientSecure.h>

WiFiClient       localWifiClient;
WiFiClientSecure cloudWifiClient;

PubSubClient mqttCloud(cloudWifiClient);
#if ENABLE_DUAL_MQTT
PubSubClient mqttLocal(localWifiClient);
#endif
DHT               dht(DHTPIN, DHTTYPE);
LiquidCrystal_I2C lcd(LCD_I2C_ADDR, LCD_COLS, LCD_ROWS);
RTC_DS3231        rtc;
Preferences       preferences;

/* ================= STATE ================= */
String mode = "manual";

float temperature            = NAN;
float humidity               = NAN;
int   soilMoistureRaw        = -1;
int   soilMoisturePercent    = -1;
bool  soilMoistureDigitalWet = false;
float luxValue               = -1.0f;
bool  luxAvailable           = false;
bool  rtcAvailable           = false;
bool  lcdAvailable           = false;
bool  tftSerialAvailable     = false;

bool lampRelayOn   = false;
bool fanRelayOn    = false;
bool sprayerActive = false;
bool lastManualSprayerCommand = false;
bool tempNotified  = false;
bool humNotified   = false;

int sprayerDuration   = 30;  // Default durasi semprot 30 detik
int sprayerRunDuration = 0;

unsigned long sprayerStart          = 0;
unsigned long lastSprayerAutoMs     = 0;  // cooldown sprayer otomatis
String        lastSprayerTriggerMinute = "";

// ── Proteksi Penyiraman Berulang (Fail-safe Sensor Tanah Rusak / Kering Palsu) ──
// Proteksi Fail-Safe Sensor Tanah (Tanpa batasan slot waktu):
// 1) Deteksi kabel lepas / korslet (ADC out of range: raw < 100 atau raw > 4050)
// 2) Deteksi sensor macet / probe tercabut (maksimal 3x semprot berturut-turut jika tanah tetap kering)
const int MAX_CONSECUTIVE_SPRAYS = 1;     // Maksimal 3x semprot berturut-turut tanpa kenaikan kelembaban
int       consecutiveSoilSprays  = 0;     // Counter semprot berturut-turut
bool      soilSensorFaultLocked  = false; // Terkunci jika 3x semprot berturut-turut tapi sensor tidak naik
bool      soilSensorNotified     = false;

const int MAX_AUTO_SPRAY_PER_WINDOW = 0;
int       autoSprayCountInWindow    = 0;
int       currentSprayWindowSlot    = 0;
bool      soilLimitNotified         = false;

// ── Output fuzzy (disimpan untuk MQTT & log TA) ──────────────
float fuzzyOutPompa = 0.0f;
float fuzzyOutKipas = 0.0f;

/* ================= MANUAL SCHEDULE ================= */
// Jadwal bawaan penyiraman: Jam 07:00, 12:00, dan 16:00
String manualSchedule[MAX_SCHEDULE] = {"07:00", "12:00", "16:00"};
int    scheduleCount = 3;

/* ================= AUTO MODE ================= */
String activePlantId          = "pakcoy_01";
String activePlantName        = "Pakcoy";
float  plantMaxTemp           = 35.0f;
String plantLightStart        = "05:30";  // Jam nyala reguler harian (pagi)
String plantLightEnd          = "18:00";  // Jam mati harian (malam)
String plantFirstLightStart   = "15:00";  // Khusus Hari ke-1 (saat penutup semai dibuka di sore hari)
int    plantDarkDays          = 2;
int    plantLightDays         = 12;
String plantCycleStartDate    = "";
String plantCycleStartPhase   = "dark";
int    plantAllowedDays[7];
int    plantAllowedDaysCount  = 0;

// Jadwal bawaan mode auto: Jam 07:00, 12:00, dan 16:00 (Durasi 30 detik)
String autoSchedule[MAX_SCHEDULE] = {"07:00", "12:00", "16:00"};
int    autoScheduleCount   = 3;
int    autoSprayerDuration = 30;

/* ================= TIMING VARS ================= */
unsigned long lastSensorPush    = 0;
unsigned long lastStatusPush    = 0;
unsigned long lastAutoLogic     = 0;
unsigned long lastHeartbeat     = 0;
unsigned long lastScheduleCheck = 0;
unsigned long lastHeapCheck     = 0;
unsigned long lastStatusLog     = 0;
unsigned long lastLcdUpdate     = 0;
int           wifiFailCount     = 0;
unsigned long autoSoilGraceUntilMs = 0;

/* ================= FORWARD DECLARATIONS ================= */
void applyLampOutput();
void logAutoScheduleConfig();
int  readSoilMoistureSmoothed();
int  readSoilMoisturePercent(int rawValue);
bool readSoilMoistureDigitalWet();
void updateLcd();
void recoverLcd();
void initDisplaySubsystem();
void sendDataToTft();
bool initLuxSensor();
float readLuxSensor();
bool syncTimeFromRtc();
#define ENABLE_NTP_BACKUP       true   // Otomatis sinkronkan jam via internet NTP saat WiFi terhubung
#define FORCE_RTC_COMPILE_TIME  false  // Set false agar jam RTC tidak ter-reset ke waktu kompilasi laptop saat ESP32 restart
#if ENABLE_NTP_BACKUP
bool syncRtcFromNtp();
#endif
void handleSerialCommands();
void processSerialCommand(String cmd);
String buildPhaseBadge();
bool isLightPhaseToday(int &phaseDay, int &phaseLength, String &phaseName);
void lcdBootScreen(const String &l1, const String &l2 = "",
                   const String &l3 = "", const String &l4 = "");
void saveConfig();
void loadConfig();
void startSprayerCountdown(int duration);
void checkScheduledWatering();

/* ================= BH1750 LUX SENSOR (BIT-BANG I2C on GPIO 25, 26) ================= */
static inline void luxDelay() { delayMicroseconds(5); }
static inline void luxSclHigh() { pinMode(LUX_SCL_PIN, INPUT_PULLUP); luxDelay(); }
static inline void luxSclLow()  { pinMode(LUX_SCL_PIN, OUTPUT); digitalWrite(LUX_SCL_PIN, LOW); luxDelay(); }
static inline void luxSdaHigh() { pinMode(LUX_DAT_PIN, INPUT_PULLUP); luxDelay(); }
static inline void luxSdaLow()  { pinMode(LUX_DAT_PIN, OUTPUT); digitalWrite(LUX_DAT_PIN, LOW); luxDelay(); }
static inline int  luxSdaRead() { pinMode(LUX_DAT_PIN, INPUT_PULLUP); return digitalRead(LUX_DAT_PIN); }

static void luxI2cStart() {
  luxSdaHigh();
  luxSclHigh();
  luxSdaLow();
  luxSclLow();
}

static void luxI2cStop() {
  luxSdaLow();
  luxSclHigh();
  luxSdaHigh();
}

static bool luxI2cWrite(uint8_t data) {
  for (int i = 0; i < 8; i++) {
    if (data & 0x80) luxSdaHigh();
    else luxSdaLow();
    data <<= 1;
    luxSclHigh();
    luxSclLow();
  }
  luxSdaHigh();
  luxSclHigh();
  bool ack = (luxSdaRead() == LOW);
  luxSclLow();
  return ack;
}

static uint8_t luxI2cRead(bool ack) {
  uint8_t data = 0;
  luxSdaHigh();
  for (int i = 0; i < 8; i++) {
    data <<= 1;
    luxSclHigh();
    if (luxSdaRead() == HIGH) data |= 1;
    luxSclLow();
  }
  if (ack) luxSdaLow();
  else luxSdaHigh();
  luxSclHigh();
  luxSclLow();
  luxSdaHigh();
  return data;
}

bool initLuxSensor() {
  pinMode(LUX_SCL_PIN, INPUT_PULLUP);
  pinMode(LUX_DAT_PIN, INPUT_PULLUP);
  luxI2cStart();
  bool ack = luxI2cWrite(0x23 << 1);
  if (!ack) {
    luxI2cStop();
    luxI2cStart();
    ack = luxI2cWrite(0x5C << 1);
    if (!ack) {
      luxI2cStop();
      Serial.println("[LUX] BH1750 not responding on GPIO 25/26");
      return false;
    }
    luxI2cWrite(0x10);
    luxI2cStop();
    Serial.printf("[LUX] BH1750 ready on addr 0x5C (GPIO 25/26) | Faktor Kalibrasi=%.2f\n", faktorKalibrasi);
    return true;
  }
  luxI2cWrite(0x10); // Continuous H-Resolution Mode
  luxI2cStop();
  Serial.printf("[LUX] BH1750 ready on addr 0x23 (GPIO 25/26) | Faktor Kalibrasi=%.2f\n", faktorKalibrasi);
  return true;
}

float readLuxSensor() {
  if (!luxAvailable) {
    luxAvailable = initLuxSensor();
    if (!luxAvailable) return -1.0f;
  }
  uint8_t addr = 0x23;
  luxI2cStart();
  if (!luxI2cWrite((addr << 1) | 1)) {
    luxI2cStop();
    addr = 0x5C;
    luxI2cStart();
    if (!luxI2cWrite((addr << 1) | 1)) {
      luxI2cStop();
      return -1.0f;
    }
  }
  uint8_t msb = luxI2cRead(true);
  uint8_t lsb = luxI2cRead(false);
  luxI2cStop();
  uint16_t raw = ((uint16_t)msb << 8) | lsb;
  float rawLux = (float)raw / 1.2f; // Rumus standar BH1750FVI
  return rawLux * faktorKalibrasi;  // Dikalibrasi dengan faktorKalibrasi (3.30)
}

// Alias fungsi agar kompatibel penuh jika dipanggil sebagai readLightLevel()
float readLightLevel() {
  return readLuxSensor();
}

/* ================= RTC DS3231 HELPERS ================= */
bool syncTimeFromRtc() {
  if (!rtcAvailable) return false;
  DateTime dt = rtc.now();
  if (dt.year() < 2024 || dt.year() > 2099) {
    Serial.printf("[RTC] Waktu RTC tidak valid: %04d-%02d-%02d\n", dt.year(), dt.month(), dt.day());
    return false;
  }
  setenv("TZ", "WIB-7", 1);
  tzset();

  struct tm t = {};
  t.tm_year = dt.year() - 1900;
  t.tm_mon  = dt.month() - 1;
  t.tm_mday = dt.day();
  t.tm_hour = dt.hour();
  t.tm_min  = dt.minute();
  t.tm_sec  = dt.second();
  t.tm_isdst = 0;
  time_t epoch = mktime(&t);
  if (epoch > 0) {
    struct timeval tv = { epoch, 0 };
    settimeofday(&tv, NULL);
    Serial.printf("[RTC] Sinkronisasi jam internal dari DS3231: %04d-%02d-%02d %02d:%02d:%02d (epoch=%ld)\n",
      dt.year(), dt.month(), dt.day(), dt.hour(), dt.minute(), dt.second(), (long)epoch);
    return true;
  }
  return false;
}

#if ENABLE_NTP_BACKUP
const char* ntpServer1 = "pool.ntp.org";
const char* ntpServer2 = "id.pool.ntp.org";
const char* ntpServer3 = "time.google.com";

bool syncRtcFromNtp() {
  if (WiFi.status() != WL_CONNECTED) return false;
  Serial.println("[TIME] Menghubungi server NTP untuk kalibrasi jam (WIB / GMT+7)...");
  // Set offset GMT+7 untuk WIB (7 * 3600 = 25200 detik, daylight offset 0)
  configTime(7 * 3600, 0, ntpServer1, ntpServer2, ntpServer3);
  struct tm timeinfo;
  if (getLocalTime(&timeinfo, 4000)) {
    if (timeinfo.tm_year + 1900 >= 2024) {
      if (rtcAvailable) {
        rtc.adjust(DateTime(timeinfo.tm_year + 1900,
                            timeinfo.tm_mon + 1,
                            timeinfo.tm_mday,
                            timeinfo.tm_hour,
                            timeinfo.tm_min,
                            timeinfo.tm_sec));
        Serial.printf("[RTC] DS3231 berhasil disinkronkan dari NTP (WIB): %04d-%02d-%02d %02d:%02d:%02d\n",
          timeinfo.tm_year + 1900, timeinfo.tm_mon + 1, timeinfo.tm_mday,
          timeinfo.tm_hour, timeinfo.tm_min, timeinfo.tm_sec);
      }
      setenv("TZ", "WIB-7", 1);
      tzset();
      return true;
    }
  }
  Serial.println("[TIME] Gagal mendapatkan respon dari server NTP");
  return false;
}
#endif

/* ================= SERIAL COMMANDS (SET TIME VIA SERIAL MONITOR) ================= */
static String serialCmdBuffer = "";

void processSerialCommand(String cmd) {
  cmd.trim();
  if (cmd.length() == 0) return;

  Serial.println("\n[CMD] Perintah serial diterima: \"" + cmd + "\"");

  if (cmd.equalsIgnoreCase("TIME?") || cmd.equalsIgnoreCase("TIME")) {
    time_t now = time(nullptr);
    struct tm *t = localtime(&now);
    if (t) {
      Serial.printf("[TIME] Jam ESP32 saat ini: %04d-%02d-%02d %02d:%02d:%02d WIB\n",
        t->tm_year + 1900, t->tm_mon + 1, t->tm_mday, t->tm_hour, t->tm_min, t->tm_sec);
    }
    if (rtcAvailable) {
      DateTime dt = rtc.now();
      Serial.printf("[TIME] Jam RTC DS3231:     %04d-%02d-%02d %02d:%02d:%02d\n",
        dt.year(), dt.month(), dt.day(), dt.hour(), dt.minute(), dt.second());
    }
    return;
  }

#if ENABLE_NTP_BACKUP
  if (cmd.equalsIgnoreCase("SYNC_NTP") || cmd.equalsIgnoreCase("NTP")) {
    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("[CMD] Memaksa kalibrasi NTP server (WIB)...");
      if (syncRtcFromNtp()) {
        syncTimeFromRtc();
        updateLcd();
        Serial.println("[CMD] SUKSES! Jam RTC & ESP32 kini tersinkron ke WIB.");
      } else {
        Serial.println("[CMD] Gagal mendapatkan respon dari server NTP.");
      }
    } else {
      Serial.println("[CMD] WiFi belum terhubung, tidak dapat menghubungi NTP.");
    }
    return;
  }
#endif

  String timeStr = cmd;
  if (timeStr.startsWith("SET_TIME=")) {
    timeStr = timeStr.substring(9);
    timeStr.trim();
  }

  int y = 0, mo = 0, d = 0, h = 0, mi = 0, s = 0;
  // Format lengkap: YYYY-MM-DD HH:MM:SS atau YYYY-MM-DD HH:MM
  if (sscanf(timeStr.c_str(), "%d-%d-%d %d:%d:%d", &y, &mo, &d, &h, &mi, &s) >= 5) {
    if (y >= 2024 && mo >= 1 && mo <= 12 && d >= 1 && d <= 31 && h >= 0 && h <= 23 && mi >= 0 && mi <= 59) {
      if (rtcAvailable) {
        rtc.adjust(DateTime(y, mo, d, h, mi, s));
      }
      syncTimeFromRtc();
      updateLcd();
      Serial.printf("[CMD] SUKSES! Jam RTC DS3231 berhasil disetel ke: %04d-%02d-%02d %02d:%02d:%02d WIB\n",
        y, mo, d, h, mi, s);
      return;
    }
  }

  // Format jam saja: HH:MM:SS atau HH:MM (tanggal diambil dari tanggal RTC saat ini)
  if (sscanf(timeStr.c_str(), "%d:%d:%d", &h, &mi, &s) >= 2) {
    if (h >= 0 && h <= 23 && mi >= 0 && mi <= 59) {
      DateTime cur = rtcAvailable ? rtc.now() : DateTime(2026, 10, 21, 0, 0, 0);
      int curY = (cur.year() >= 2024) ? cur.year() : 2026;
      int curM = (cur.month() >= 1 && cur.month() <= 12) ? cur.month() : 10;
      int curD = (cur.day() >= 1 && cur.day() <= 31) ? cur.day() : 21;
      if (rtcAvailable) {
        rtc.adjust(DateTime(curY, curM, curD, h, mi, s));
      }
      syncTimeFromRtc();
      updateLcd();
      Serial.printf("[CMD] SUKSES! Jam RTC DS3231 berhasil disetel ke: %04d-%02d-%02d %02d:%02d:%02d WIB\n",
        curY, curM, curD, h, mi, s);
      return;
    }
  }

  if (cmd.equalsIgnoreCase("STATUS") || cmd.equalsIgnoreCase("STATUS?") ||
      cmd.equalsIgnoreCase("PLANT")  || cmd.equalsIgnoreCase("PLANT?") ||
      cmd.equalsIgnoreCase("CONFIG") || cmd.equalsIgnoreCase("CONFIG?")) {
    Serial.println("\n==================== STATUS SISTEM & TANAMAN ====================");
    Serial.printf("Mode Operasi          : %s\n", mode.c_str());
    Serial.printf("Tanaman Aktif (NVS)   : %s (ID: %s)\n", activePlantName.c_str(), activePlantId.c_str());
    Serial.printf("Suhu Optimal Maks     : %.1f °C\n", plantMaxTemp);
    Serial.printf("Penyinaran            : %s s/d %s\n", plantLightStart.c_str(), plantLightEnd.c_str());
    Serial.printf("Siklus Fase           : Gelap %d hari, Terang %d hari\n", plantDarkDays, plantLightDays);
    Serial.printf("Durasi Sprayer        : %d detik (Auto: %d detik)\n", sprayerDuration, autoSprayerDuration);
    Serial.printf("Jadwal Siram Auto (%d) : ", autoScheduleCount);
    for (int i = 0; i < autoScheduleCount; i++) {
      Serial.printf("%s%s", autoSchedule[i].c_str(), (i < autoScheduleCount - 1) ? ", " : "\n");
    }
    Serial.println("------------------------- SENSOR AKTIF --------------------------");
    Serial.printf("Suhu Udara (DHT22)    : %.1f °C\n", isnan(temperature) ? 0.0f : temperature);
    Serial.printf("Kelembaban Udara      : %.1f %%\n", isnan(humidity) ? 0.0f : humidity);
    Serial.printf("Kelembaban Tanah      : %d %% (Raw ADC: %d, Basah: %s)\n",
      soilMoisturePercent, soilMoistureRaw, soilMoistureDigitalWet ? "YA" : "TIDAK");
    Serial.printf("Intensitas Cahaya     : %.1f Lux\n", luxValue);
    time_t now = time(nullptr);
    struct tm *t = localtime(&now);
    if (t) {
      Serial.printf("Waktu Saat Ini        : %04d-%02d-%02d %02d:%02d:%02d WIB\n",
        t->tm_year + 1900, t->tm_mon + 1, t->tm_mday, t->tm_hour, t->tm_min, t->tm_sec);
    }
    Serial.println("------------------------- STATUS RELAY --------------------------");
    Serial.printf("Lampu Grow Light      : %s (%s, %d Lampu)\n", lampRelayOn ? "ON" : "OFF", mode.c_str(), autoLampsActive);
    Serial.printf("Kipas / Fan           : %s\n", fanRelayOn ? "ON" : "OFF");
    Serial.printf("Sprayer / Pompa       : %s\n", sprayerActive ? "ON (MENYEMPROT)" : "OFF");
    Serial.println("=================================================================\n");
    return;
  }

  if (cmd.startsWith("SET_PLANT=") || cmd.startsWith("SET_PLANT ")) {
    String p = cmd.startsWith("SET_PLANT=") ? cmd.substring(10) : cmd.substring(10);
    p.trim();
    if (p.length() > 0) {
      activePlantName = p;
      activePlantId = p;
      activePlantId.toLowerCase();
      activePlantId.replace(" ", "_");
      saveConfig();
      publishStatus();
      updateLcd();
      Serial.printf("[CMD] SUKSES! Tanaman berhasil diubah & disimpan ke NVS: %s (%s)\n",
        activePlantName.c_str(), activePlantId.c_str());
    }
    return;
  }

  if (cmd.equalsIgnoreCase("MODE=AUTO")) {
    mode = "auto";
    saveConfig();
    publishStatus();
    updateLcd();
    Serial.println("[CMD] Mode diubah ke: AUTO & disimpan ke NVS.");
    return;
  }
  if (cmd.equalsIgnoreCase("MODE=MANUAL")) {
    mode = "manual";
    forceAllTogglesOff();
    saveConfig();
    publishStatus();
    updateLcd();
    Serial.println("[CMD] Mode diubah ke: MANUAL & disimpan ke NVS.");
    return;
  }

  Serial.println("[CMD] Format tidak dikenal!");
  Serial.println("  Perintah yang tersedia di Serial Monitor:");
  Serial.println("  - Cek Status & Tanaman: STATUS  (atau PLANT? atau CONFIG?)");
  Serial.println("  - Ubah Tanaman & Simpan: SET_PLANT=Pakcoy (atau Selada, Bayam, dll)");
  Serial.println("  - Ubah Mode Operasi   : MODE=AUTO  atau  MODE=MANUAL");
  Serial.println("  - Cek Jam Sekarang    : TIME?");
  Serial.println("  - Paksa Sync Jam NTP  : SYNC_NTP");
  Serial.println("  - Set Jam Manual      : 15:25:00  (atau 2026-10-22 15:25:00)");
}

void handleSerialCommands() {
  while (Serial.available()) {
    char c = (char)Serial.read();
    if (c == '\r') continue;
    if (c == '\n') {
      serialCmdBuffer.trim();
      if (serialCmdBuffer.length() > 0) {
        processSerialCommand(serialCmdBuffer);
        serialCmdBuffer = "";
      }
    } else {
      if (serialCmdBuffer.length() < 64) {
        serialCmdBuffer += c;
      }
    }
  }
}

/* ================= LCD RECOVERY & HELPERS ================= */
void recoverLcd() {
  if (!lcdAvailable) return;
  Serial.println("[LCD] Melakukan recovery & reset HD44780 controller...");
  Wire.begin(LCD_I2C_SDA_PIN, LCD_I2C_SCL_PIN);
  delay(20);
  lcd.init();
  lcd.backlight();
  if (lcdAvailable) lcd.clear();
}

String lcdPad(String text) {
  while ((int)text.length() < LCD_COLS) text += " ";
  if ((int)text.length() > LCD_COLS) text = text.substring(0, LCD_COLS);
  return text;
}
String lcdOnOff(bool v) { return v ? "ON " : "OFF"; }

String lcdTimeNow() {
  time_t now = time(nullptr);
  struct tm *t = localtime(&now);
  if (!t) return "--:--";
  char buf[6];
  sprintf(buf, "%02d:%02d", t->tm_hour, t->tm_min);
  return String(buf);
}
String lcdDateNow() {
  time_t now = time(nullptr);
  struct tm *t = localtime(&now);
  if (!t) return "--/--";
  char buf[6];
  sprintf(buf, "%02d/%02d", t->tm_mday, t->tm_mon + 1);
  return String(buf);
}

void lcdBootScreen(const String &l1, const String &l2 = "",
                   const String &l3 = "", const String &l4 = "") {
  if (!lcdAvailable) return;
  lcd.setCursor(0,0); lcd.print(lcdPad(l1));
  if (l2.length()) { lcd.setCursor(0,1); lcd.print(lcdPad(l2)); }
  if (l3.length()) { lcd.setCursor(0,2); lcd.print(lcdPad(l3)); }
  if (l4.length()) { lcd.setCursor(0,3); lcd.print(lcdPad(l4)); }
}

void updateLcd() {
  if (!lcdAvailable) return;
  // Cek apakah I2C LCD merespons atau bus error (terkena glitch/EMI relay)
  Wire.beginTransmission(LCD_I2C_ADDR);
  if (Wire.endTransmission() != 0) {
    recoverLcd();
  }

  // Baris 1: Su:xx.x Ku:xx% Kt:xx%
  String line1 = "Su:";
  line1 += isnan(temperature) ? "--.-" : String(temperature, 1);
  line1 += " Ku:";
  line1 += isnan(humidity) ? "--" : String((int)roundf(humidity));
  line1 += "% Kt:";
  line1 += (soilMoisturePercent >= 0) ? String(soilMoisturePercent) : "--";
  line1 += "%";

  // Baris 2: Mode + badge fase
  String line2;
  String badge = "";
  if (mode == "auto") {
    String pName = activePlantName.length() > 0 ? activePlantName : activePlantId;
    if (pName.isEmpty()) pName = "Pakcoy";
    line2 = "AUTO(" + pName + ")";
    badge = buildPhaseBadge();
  } else {
    String pName = activePlantName.length() > 0 ? activePlantName : activePlantId;
    line2 = (pName.length() > 0) ? ("MAN(" + pName + ")") : "MANUAL";
  }
  if (badge.length() > 0) {
    int leftMax = LCD_COLS - (int)badge.length() - 1;
    if (leftMax < 0) leftMax = 0;
    if ((int)line2.length() > leftMax) line2 = line2.substring(0, leftMax);
    while ((int)line2.length() < leftMax) line2 += " ";
    line2 += " " + badge;
  }

  // Baris 3: status relay + lux (Format grid simetris 4 kolom @ 5 karakter = 20 char)
  char bufLine3[22];
  char bufLux[6];
  if (luxValue >= 0.0f) {
    if (luxValue >= 10000.0f) {
      snprintf(bufLux, sizeof(bufLux), "%2dkl", (int)(luxValue / 1000.0f));
    } else if (luxValue >= 1000.0f) {
      snprintf(bufLux, sizeof(bufLux), "%4dx", (int)roundf(luxValue));
    } else {
      snprintf(bufLux, sizeof(bufLux), "%3dlx", (int)roundf(luxValue));
    }
  } else {
    snprintf(bufLux, sizeof(bufLux), " --lx");
  }

  snprintf(bufLine3, sizeof(bufLine3), "%-5s%-5s%-5s%5s",
    lampRelayOn   ? "L:ON " : "L:-- ",
    fanRelayOn    ? "K:ON " : "K:-- ",
    sprayerActive ? "S:ON " : ((soilMoisturePercent < 0 || soilSensorFaultLocked) ? "S:ERR" : "S:-- "),
    bufLux
  );
  String line3 = String(bufLine3);

  // Baris 4: tanggal, jam, status RTC, dan status WiFi (Pas 20 karakter, tanpa terpotong)
  // Format: "DD/MM HH:MM RTC WiFi" atau "DD/MM HH:MM RTC  Off"
  char bufLine4[22];
  snprintf(bufLine4, sizeof(bufLine4), "%-5s %-5s %-3s %-4s",
    lcdDateNow().c_str(),
    lcdTimeNow().c_str(),
    rtcAvailable ? "RTC" : "---",
    WiFi.status() == WL_CONNECTED ? "WiFi" : "Off "
  );
  String line4 = String(bufLine4);

  lcd.setCursor(0,0); lcd.print(lcdPad(line1));
  lcd.setCursor(0,1); lcd.print(lcdPad(line2));
  lcd.setCursor(0,2); lcd.print(lcdPad(line3));
  lcd.setCursor(0,3); lcd.print(lcdPad(line4));
}

String buildPhaseBadge() {
  if (mode != "auto") return "";
  int phaseDay = 0, phaseLength = 0;
  String phaseName = "";
  bool inLight = isLightPhaseToday(phaseDay, phaseLength, phaseName);
  if (phaseLength <= 0 || phaseDay <= 0) return "";
  int rem = constrain(phaseLength - phaseDay + 1, 0, 999);
  return (inLight ? "TRG " : "GLP ") + String(rem);
}

/* ================= TFT SERIAL TRANSMITTER ================= */
void sendDataToTft() {
  if (!tftSerialAvailable) return;

  float s  = isnan(temperature) ? 0.0f : temperature;
  float ku = isnan(humidity) ? 0.0f : humidity;
  int   kt = (soilMoisturePercent < 0) ? 0 : constrain(soilMoisturePercent, 0, 100);
  int   lx = (luxValue < 0.0f) ? 0 : (int)luxValue;
  int   md = (mode == "auto") ? 1 : 0;
  int   kp = fanRelayOn ? 1 : 0;
  int   sp = sprayerActive ? 1 : 0;
  int   lp = lampRelayOn ? 1 : 0;

  // Format CSV persis sesuai sscanf di penerima TFT:
  // sscanf(masuk.c_str(), "%f,%f,%d,%d,%d,%d,%d,%d", &s, &ku, &kt, &lx, &md, &kp, &sp, &lp) == 8
  Serial2.printf("%.1f,%.1f,%d,%d,%d,%d,%d,%d\n", s, ku, kt, lx, md, kp, sp, lp);
}

/* ================= DISPLAY SUBSYSTEM INIT ================= */
void initDisplaySubsystem() {
#if (DISPLAY_CONFIG == DISPLAY_MODE_TFT)
  // Mode Paksa TFT Serial pada GPIO 32 (RX) dan GPIO 33 (TX)
  lcdAvailable = false;
  tftSerialAvailable = true;
  Serial2.begin(TFT_SERIAL_BAUD, SERIAL_8N1, TFT_SERIAL_RX_PIN, TFT_SERIAL_TX_PIN);
  Serial.printf("[DISPLAY] Mode TFT SERIAL aktif di RX=%d & TX=%d (Baud: %d)\n",
    TFT_SERIAL_RX_PIN, TFT_SERIAL_TX_PIN, TFT_SERIAL_BAUD);

#elif (DISPLAY_CONFIG == DISPLAY_MODE_I2C)
  // Mode Paksa LCD I2C 20x4 pada GPIO 32 (SDA) dan GPIO 33 (SCL)
  Wire.begin(LCD_I2C_SDA_PIN, LCD_I2C_SCL_PIN);
  delay(50);
  lcd.init();
  lcd.backlight();
  if (lcdAvailable) lcd.clear();
  lcdAvailable = true;
  tftSerialAvailable = false;
  Serial.printf("[DISPLAY] Mode I2C LCD aktif di SDA=%d & SCL=%d (Addr: 0x%02X)\n",
    LCD_I2C_SDA_PIN, LCD_I2C_SCL_PIN, LCD_I2C_ADDR);

#elif (DISPLAY_CONFIG == DISPLAY_MODE_DUAL)
  // Mode Dual: LCD I2C di pin 32/33 DAN TFT Serial di pin lain (DUAL_TFT_TX_PIN)
  Wire.begin(LCD_I2C_SDA_PIN, LCD_I2C_SCL_PIN);
  delay(50);
  lcd.init();
  lcd.backlight();
  if (lcdAvailable) lcd.clear();
  lcdAvailable = true;
  tftSerialAvailable = true;
  Serial2.begin(TFT_SERIAL_BAUD, SERIAL_8N1, -1, DUAL_TFT_TX_PIN);
  Serial.printf("[DISPLAY] DUAL DISPLAY AKTIF! LCD I2C di SDA=%d/SCL=%d & TFT Serial di TX=%d\n",
    LCD_I2C_SDA_PIN, LCD_I2C_SCL_PIN, DUAL_TFT_TX_PIN);

#else // DISPLAY_MODE_AUTO (Deteksi Otomatis keberadaan LCD I2C)
  Serial.println("[DISPLAY] Memindai bus I2C pada pin 32 & 33...");
  Wire.begin(LCD_I2C_SDA_PIN, LCD_I2C_SCL_PIN);
  Wire.setTimeOut(60);
  delay(30);

  bool foundI2c = false;
  byte testAddrs[] = {LCD_I2C_ADDR, 0x3F, 0x26, 0x38};
  for (byte addr : testAddrs) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      foundI2c = true;
      Serial.printf("[DISPLAY] LCD I2C terdeteksi di alamat: 0x%02X!\n", addr);
      break;
    }
  }

  if (foundI2c) {
    lcdAvailable = true;
    tftSerialAvailable = false;
    lcd.init();
    lcd.backlight();
    if (lcdAvailable) lcd.clear();
    Serial.println("[DISPLAY] LCD I2C 20x4 terpasang & aktif.");
  } else {
    // LCD I2C tidak terdeteksi -> alihkan pin 32 & 33 menjadi UART Serial2 untuk TFT!
    Wire.end();
    delay(20);
    lcdAvailable = false;
    tftSerialAvailable = true;
    Serial2.begin(TFT_SERIAL_BAUD, SERIAL_8N1, TFT_SERIAL_RX_PIN, TFT_SERIAL_TX_PIN);
    Serial.printf("[DISPLAY] LCD I2C tidak terpasang. Otomatis mengaktifkan TFT Serial pada RX=%d, TX=%d (Baud: %d)\n",
      TFT_SERIAL_RX_PIN, TFT_SERIAL_TX_PIN, TFT_SERIAL_BAUD);
  }
#endif

  if (lcdAvailable) {
    lcd.setCursor(0,0); lcd.print(lcdPad("INKUBATOR SMART"));
    lcd.setCursor(0,1); lcd.print(lcdPad("Mode: " + mode));
    lcd.setCursor(0,2); lcd.print(lcdPad("Plt : " + activePlantName));
    lcd.setCursor(0,3); lcd.print(lcdPad("PT PETROKIMIA GRESIK"));
  }
}

/* ================= RELAY ================= */
void relayWrite(int pin, bool on) {
  digitalWrite(pin, RELAY_ACTIVE_LOW ? (on ? LOW : HIGH) : (on ? HIGH : LOW));
  Serial.printf("[RELAY] pin=%d %s\n", pin, on ? "ON" : "OFF");
  delay(15); // Jeda peredam transient EMI relay sebelum I2C diakses
}

void forceAllTogglesOff() {
  Serial.println("[SAFE] forceAllTogglesOff");
  lampRelayOn   = false;
  for (int i = 0; i < NUM_LAMPS; i++) {
    lampPinsState[i] = false;
  }
  fanRelayOn    = false;
  sprayerActive = false;
  etiolasiOverride = false;
  lastSprayerTriggerMinute = "";
  lastManualSprayerCommand = false;
  applyLampOutput();
  relayWrite(RELAY_FAN,     false);
  relayWrite(RELAY_SPRAYER, false);
}

/* ================= LAMP ================= */
void applyLampOutput() {
  bool turnOn = lampRelayOn; // Lampu menggunakan relay ON/OFF murni

  if (mode == "auto") {
    // Mode Auto:
    // Lampu 1 (GPIO 17): Lampu utama masa terang (menyala jika turnOn dan autoLampsActive >= 1)
    // Lampu 2 (GPIO 18): Lampu tambahan/booster (menyala jika autoLampsActive >= 2 ATAU etiolasiOverride aktif)
    bool l1 = turnOn && (autoLampsActive >= 1);
    bool l2 = turnOn && ((autoLampsActive >= 2) || etiolasiOverride);
    lampPinsState[0] = l1;
    lampPinsState[1] = l2;
    relayWrite(lampPins[0], l1);
    relayWrite(lampPins[1], l2);
  } else {
    // Mode Manual: kendalikan sesuai status tes masing-masing lampu (lampPinsState)
    bool anyOn = false;
    for (int i = 0; i < NUM_LAMPS; i++) {
      bool on = lampPinsState[i];
      relayWrite(lampPins[i], on);
      if (on) anyOn = true;
    }
    lampRelayOn = anyOn;
  }
}

/* ================= TIME (RTC DS3231 MANDIRI) ================= */
// Referensi waktu utama sepenuhnya mengandalkan RTC DS3231 fisik berdaya baterai.
// Tidak ada delay blocking tunggu koneksi/server NTP saat boot.
void initTime() {
  Serial.println("[TIME] Menginisialisasi waktu dari RTC DS3231...");
  if (rtcAvailable) {
    if (syncTimeFromRtc()) {
      Serial.println("[TIME] Sinkronisasi waktu internal ESP32 dari RTC DS3231 BERHASIL.");
    } else {
      Serial.println("[TIME] PERINGATAN: Nilai RTC DS3231 tidak valid/baterai habis!");
    }
  } else {
    Serial.println("[TIME] ERROR: Modul RTC DS3231 tidak terdeteksi!");
  }

#if ENABLE_NTP_BACKUP
  if (WiFi.status() == WL_CONNECTED) {
    syncRtcFromNtp();
  }
#endif
}

String nowHHMM() {
  time_t now = time(nullptr);
  struct tm *t = localtime(&now);
  char buf[6];
  sprintf(buf, "%02d:%02d", t->tm_hour, t->tm_min);
  return String(buf);
}
String nowMinuteKey() {
  time_t now = time(nullptr);
  struct tm *t = localtime(&now);
  if (!t) return "";
  char buf[17];
  sprintf(buf, "%04d-%02d-%02d %02d:%02d",
    t->tm_year+1900, t->tm_mon+1, t->tm_mday, t->tm_hour, t->tm_min);
  return String(buf);
}

bool isValidHHMM(const String &s) {
  if (s.length() != 5 || s.charAt(2) != ':') return false;
  int hh = s.substring(0,2).toInt(), mm = s.substring(3,5).toInt();
  return hh>=0 && hh<=23 && mm>=0 && mm<=59;
}
String normalizeTimeToken(String token) {
  token.trim();
  if (token.length()==8 && token.charAt(2)==':' && token.charAt(5)==':')
    token = token.substring(0,5);
  return token;
}
int hhmmToMinutes(const String &hhmm, int fallback) {
  if (!isValidHHMM(hhmm)) return fallback;
  return hhmm.substring(0,2).toInt()*60 + hhmm.substring(3,5).toInt();
}
bool minutesInRange(int now, int start, int end) {
  if (start==end) return false;
  if (start<end) return now>=start && now<end;
  return now>=start || now<end;
}
bool parseYmd(const String &v, int &y, int &m, int &d) {
  if (v.length()<10 || v.charAt(4)!='-' || v.charAt(7)!='-') return false;
  y=v.substring(0,4).toInt(); m=v.substring(5,7).toInt(); d=v.substring(8,10).toInt();
  return y>=1970 && m>=1 && m<=12 && d>=1 && d<=31;
}
long dayNum(int y, int m, int d) {
  struct tm t = {}; t.tm_year=y-1900; t.tm_mon=m-1; t.tm_mday=d;
  return (long)(mktime(&t)/86400);
}
int weekdayToday() {
  time_t now = time(nullptr);
  struct tm *t = localtime(&now);
  return t ? t->tm_wday : 0;
}

/* ================= LIGHT PHASE ================= */
bool isLightPhaseToday(int &phaseDay, int &phaseLength, String &phaseName) {
  int dark = constrain(plantDarkDays,1,365), light = constrain(plantLightDays,1,365);
  time_t now = time(nullptr);
  struct tm *tn = localtime(&now);
  int y=tn?tn->tm_year+1900:1970, m=tn?tn->tm_mon+1:1, d=tn?tn->tm_mday:1;
  int sy,sm,sd;
  if (!parseYmd(plantCycleStartDate,sy,sm,sd)) { sy=y; sm=m; sd=d; }
  long elapsed = dayNum(y,m,d) - dayNum(sy,sm,sd);
  if (elapsed<0) elapsed=0;
  int cycle=dark+light, cday=(int)(elapsed%cycle);
  bool startLight = (plantCycleStartPhase=="light");
  bool inLight;
  if (startLight) {
    inLight=(cday<light);
    phaseDay=inLight?(cday+1):(cday-light+1);
    phaseLength=inLight?light:dark;
    phaseName=inLight?"light":"dark";
  } else {
    inLight=(cday>=dark);
    phaseDay=inLight?(cday-dark+1):(cday+1);
    phaseLength=inLight?light:dark;
    phaseName=inLight?"light":"dark";
  }
  return inLight;
}
bool isTodayAllowed() {
  if (plantAllowedDaysCount==0) return true;
  int today=weekdayToday();
  for (int i=0;i<plantAllowedDaysCount;i++) if (plantAllowedDays[i]==today) return true;
  return false;
}

/* ── Helper Window Waktu Penyiraman (Fail-Safe Soil Sensor) ── */
int getSprayTimeWindowSlot(int hour) {
  if (hour >= 6 && hour < 12)  return 0; // Pagi: 06:00 - 11:59
  if (hour >= 12 && hour < 18) return 1; // Siang: 12:00 - 17:59
  return 2;                              // Malam: 18:00 - 05:59
}

const char* getSprayWindowName(int slot) {
  if (slot == 0) return "Pagi (06:00-12:00)";
  if (slot == 1) return "Siang (12:00-18:00)";
  return "Malam (18:00-06:00)";
}

/* ================= SPRAYER ================= */
void startSprayerCountdown(int duration) {
  sprayerRunDuration = constrain(duration,1,600);
  sprayerDuration    = sprayerRunDuration;
  sprayerStart       = millis();
  sprayerActive      = true;
  lastManualSprayerCommand = true;
  relayWrite(RELAY_SPRAYER, true);
  Serial.printf("[SPRAYER] START dur=%ds\n", sprayerRunDuration);
}
int readSoilMoistureSmoothed() {
  if (SOIL_MOISTURE_AO_PIN < 0) return -1;
  long sum = 0;
  for (int i = 0; i < 8; i++) {
    sum += analogRead(SOIL_MOISTURE_AO_PIN);
    delay(2);
  }
  return (int)(sum / 8);
}

int readSoilMoisturePercent(int raw) {
  if (raw < 0) return -1;
  // Deteksi anomali fisik sensor:
  // - raw < 100  : Kabel analog terhubung singkat ke GND / korslet
  // - raw > 4050 : Kabel lepas (open circuit) / probe tidak terpasang
  if (raw < 100 || raw > 4050) {
    return -1; // -1 mengindikasikan sensor tanah tidak valid / tidak terbaca
  }
  int dry = SOIL_ADC_DRY_VALUE, wet = SOIL_ADC_WET_VALUE;
  if (dry == wet) return -1;
  if (dry < wet) { int t = dry; dry = wet; wet = t; }
  return constrain(map(raw, dry, wet, 0, 100), 0, 100);
}
bool readSoilMoistureDigitalWet() {
  if (SOIL_MOISTURE_DO_PIN < 0) return (soilMoisturePercent >= 50);
  int v = digitalRead(SOIL_MOISTURE_DO_PIN);
  return SOIL_DO_ACTIVE_LOW ? (v==LOW) : (v==HIGH);
}

/* ================= MQTT PUBLISH ================= */
void publishJson(const String &topic, JsonDocument &doc) {
  char buf[1024];
  size_t len = serializeJson(doc, buf, sizeof(buf));

  // 1) Publish ke EMQX Cloud (Internet Publik / Aplikasi SemaiKu)
  if (mqttCloud.connected()) {
    mqttCloud.publish(topic.c_str(), (const uint8_t*)buf, len, true);
  }

#if ENABLE_DUAL_MQTT
  // 2) Publish ke Broker Intranet Perusahaan (10.14.41.20)
  if (mqttLocal.connected()) {
    mqttLocal.publish(topic.c_str(), (const uint8_t*)buf, len, true);
  }
#endif
}

void publishTelemetry() {
  StaticJsonDocument<512> doc;
  bool has = false;
  if (!isnan(temperature)) { doc["temperature"]=temperature; has=true; }
  if (!isnan(humidity))    { doc["humidity"]=humidity;       has=true; }
  if (soilMoistureRaw>=0) { doc["soil_moisture_raw"]=soilMoistureRaw; has=true; }
  if (soilMoisturePercent>=0) { doc["soil_moisture"]=soilMoisturePercent; has=true; }
  doc["soil_moisture_wet"] = soilMoistureDigitalWet;
  if (luxValue >= 0.0f) { doc["lux"] = luxValue; has = true; }

  // Output fuzzy -- penting untuk data TA
  if (mode=="auto") {
    JsonObject fz = doc.createNestedObject("fuzzy");
    fz["pompa"] = serialized(String(fuzzyOutPompa,2));
    fz["kipas"] = serialized(String(fuzzyOutKipas,2));
  }
  time_t e = time(nullptr);
  if (e > 100000) {
    doc["timestamp"] = (long)e;
  }
  if (!has) return;
  publishJson(topicTelemetry, doc);
  if (tftSerialAvailable) sendDataToTft();
}

void publishStatus() {
  StaticJsonDocument<1024> doc;
  doc["mode"]   = mode;
  doc["online"] = true;
  if (!isnan(temperature))       doc["temperature"]      = temperature;
  if (!isnan(humidity))          doc["humidity"]          = humidity;
  if (soilMoistureRaw>=0)        doc["soil_moisture_raw"] = soilMoistureRaw;
  if (soilMoisturePercent>=0)    doc["soil_moisture"]     = soilMoisturePercent;
  doc["soil_moisture_wet"] = soilMoistureDigitalWet;
  if (luxValue >= 0.0f)          doc["lux"]               = luxValue;
  doc["rtc_available"]     = rtcAvailable;
  doc["relay"]["lamp"]     = lampRelayOn;
  doc["relay"]["lamp1"]    = lampPinsState[0];
  doc["relay"]["lamp2"]    = lampPinsState[1];
  doc["relay"]["lamp3"]    = false;
  doc["relay"]["lamp4"]    = false;
  doc["relay"]["fan"]      = fanRelayOn;
  doc["relay"]["sprayer"]  = sprayerActive;
  doc["auto_lamps_count"]  = autoLampsActive;
  doc["etiolasi_override"] = etiolasiOverride;
  doc["active_plant"] = activePlantId;
  doc["active_plant_name"] = activePlantName;
  doc["sprayer_duration"] = sprayerDuration;
  JsonArray mt = doc.createNestedArray("sprayer_times");
  for (int i=0;i<scheduleCount;i++) mt.add(manualSchedule[i]);
  doc["auto_spray_count"]   = autoSprayCountInWindow;
  doc["auto_spray_max"]     = MAX_AUTO_SPRAY_PER_WINDOW;
  doc["spray_window_slot"]  = currentSprayWindowSlot;
  doc["soil_limit_reached"] = soilLimitNotified;
  doc["lighting_start"]           = plantLightStart;
  doc["lighting_end"]             = plantLightEnd;
  doc["lighting_first_day_start"] = plantFirstLightStart;
  time_t e = time(nullptr);
  if (e>100000) doc["last_seen"] = (long)e;
  publishJson(topicStatus, doc);
  if (tftSerialAvailable) sendDataToTft();
}

void publishAlert(const char *type, int duration = 0, const char *msg = nullptr) {
  StaticJsonDocument<384> doc;
  doc["type"]        = type;
  if (msg) doc["message"] = msg;
  doc["temperature"] = temperature;
  doc["humidity"]    = humidity;
  if (soilMoisturePercent>=0) doc["soil_moisture"] = soilMoisturePercent;
  doc["soil_moisture_wet"] = soilMoistureDigitalWet;
  if (duration > 0) doc["duration"] = duration;
  time_t e = time(nullptr);
  if (e>100000) doc["timestamp"] = (long)e;
  publishJson(topicAlert, doc);
}

/* ================= AUTO LOGIC ================= */
/*
 * autoLogic() — dipanggil tiap 10 detik saat mode=auto
 *
 * Alur:
 *  1. Hitung fase (gelap/terang) dan window jam → shouldLampOn
 *  2. Jalankan fuzzy 2-input (suhu, tanah) → fOut.pompa, fOut.kipas
 *  3. LAMPU  → ON/OFF berdasar jadwal dan fase tanaman
 *  4. KIPAS  → ON jika fuzzy kipas >= 0.5 (dominan nyala)
 *  5. SPRAYER→ fuzzy pompa → konversi ke durasi; cooldown 15 menit
 *              + jadwal backup tetap berjalan
 */
void autoLogic() {
  if (mode != "auto") return;
  if (activePlantId.isEmpty()) { forceAllTogglesOff(); return; }


  // ── Fase & window lampu ──────────────────────────────────────
  int phaseDay, phaseLength;
  String phaseName;
  bool inLightPhase  = isLightPhaseToday(phaseDay, phaseLength, phaseName);
  bool allowedDay    = isTodayAllowed();

  String nowStr    = nowHHMM();
  String minuteKey = nowMinuteKey();
  int nowMin   = hhmmToMinutes(nowStr, 0);

  // ── Penentuan Jam Mulai Penyinaran ────────────────────────────
  // Hari ke-1 fase terang (saat penutup semai dibuka di sore hari):
  // Menggunakan plantFirstLightStart (misal jam 15:00) s/d jam malam (18:00).
  // Hari ke-2 dan seterusnya: Otomatis kembali ke jadwal pagi reguler (misal 05:30 s/d 18:00).
  int startMin;
  if (inLightPhase && phaseDay == 1 && plantFirstLightStart.length() > 0 && isValidHHMM(plantFirstLightStart)) {
    startMin = hhmmToMinutes(plantFirstLightStart, 900); // 15:00 = 900 menit
  } else {
    startMin = hhmmToMinutes(plantLightStart, 330);      // 05:30 = 330 menit
  }
  int endMin   = hhmmToMinutes(plantLightEnd, 1080);     // 18:00 = 1080 menit
  bool inWindow     = minutesInRange(nowMin, startMin, endMin);
  bool shouldLampOn = inLightPhase && inWindow && allowedDay;

  // Waktu saat ini (digunakan untuk jadwal backup jika jam tersinkron)
  time_t rawNow = time(nullptr);
  struct tm *tNow = localtime(&rawNow);
  int curHour = tNow ? tNow->tm_hour : 0;

  // ── Evaluasi Status Sensor Tanah & Fail-Safe ────────────────
  bool soilSensorValid = (soilMoisturePercent >= 0);

  // Jika kelembaban tanah sudah naik kembali normal (>= 50%), reset counter semprot berturut-turut & buka kunci
  if (soilSensorValid && soilMoisturePercent >= 50) {
    if (consecutiveSoilSprays > 0 || soilSensorFaultLocked) {
      consecutiveSoilSprays = 0;
      soilSensorFaultLocked = false;
      soilSensorNotified    = false;
      Serial.println("[FAIL-SAFE] Tanah lembab/normal kembali (>=50%). Kunci pengaman semprot dibuka.");
    }
  }

  // ── Jalankan Fuzzy Mamdani 2-input ──────────────────────────
  float suhuIn  = isnan(temperature) ? 26.0f : temperature;
  // Jika sensor tanah rusak/lepas (-1), berikan nilai netral 45% agar fuzzy tidak mengira tanah kering
  float tanahIn = soilSensorValid ? (float)soilMoisturePercent : 45.0f;

  FuzzyOutput fOut = runFuzzy(suhuIn, tanahIn);

  // Simpan ke variabel global (untuk MQTT telemetry & log TA)
  fuzzyOutPompa = fOut.pompa;
  fuzzyOutKipas = fOut.kipas;

  Serial.printf(
    "[FUZZY] suhu=%.1f tanah=%.1f fase=%s | pompa=%.2f kipas=%.2f\n",
    suhuIn, tanahIn,
    inLightPhase ? "TERANG" : "GELAP",
    fOut.pompa, fOut.kipas
  );

  // ── 1) LAMPU ─────────────────────────────────────────────────
  // Selalu sinkronkan relay fisik Lampu (GPIO 17 & 18) dengan logika jadwal & fase
  bool prevLamp = lampRelayOn;
  lampRelayOn   = shouldLampOn;
  applyLampOutput();
  if (prevLamp != lampRelayOn) {
    Serial.printf("[LAMP] %s (jadwal, fase=%s, %d lampu menyala%s)\n",
      shouldLampOn ? "ON" : "OFF", phaseName.c_str(), autoLampsActive,
      etiolasiOverride ? " + BOOSTER ETIOLASI" : "");
    publishStatus();
  }

  // ── 2) KIPAS ─────────────────────────────────────────────────
  // Selalu sinkronkan relay fisik Kipas (GPIO 16) dengan output fuzzy kipas
  bool nextFan = (fOut.kipas >= 0.5f);
  bool prevFan = fanRelayOn;
  fanRelayOn   = nextFan;
  relayWrite(RELAY_FAN, fanRelayOn);
  if (prevFan != fanRelayOn) {
    Serial.printf("[FAN] %s (fuzzy_kipas=%.2f, suhu=%.1f)\n",
      fanRelayOn ? "ON" : "OFF", fOut.kipas, suhuIn);
    if (fanRelayOn) {
      publishAlert("fuzzy_fan_on");
    }
    publishStatus();
  }

  // ── 3) SPRAYER — fuzzy pompa → durasi ─────────────────────────
  // Konversi crisp pompa → durasi semprot:
  //   < 0.5  → OFF
  //   0.5–1.5 → singkat (5s)   ← R8: dingin+kering
  //   1.5–2.5 → sedang  (15s)  ← R2: normal+kering
  //   ≥ 2.5  → panjang (30s)   ← R5: panas+kering
  int fuzzySprayDur = 0;
  if      (fOut.pompa >= 2.5f) fuzzySprayDur = SPRAY_PANJANG_S;
  else if (fOut.pompa >= 1.5f) fuzzySprayDur = SPRAY_SEDANG_S;
  else if (fOut.pompa >= 0.5f) fuzzySprayDur = SPRAY_SINGKAT_S;

  unsigned long curMs = millis();
  bool cooldownOK  = (lastSprayerAutoMs == 0) ||
                     (curMs - lastSprayerAutoMs >= SPRAYER_COOLDOWN_MS);
  bool graceOver   = (autoSoilGraceUntilMs == 0) ||
                     (curMs >= autoSoilGraceUntilMs);

  if (fuzzySprayDur > 0 && !sprayerActive && cooldownOK && graceOver) {
    // PROTEKSI 1: Jika sensor tanah tidak valid (kabel lepas/rusak), JANGAN semprot otomatis!
    if (!soilSensorValid) {
      if (!soilSensorNotified) {
        soilSensorNotified = true;
        Serial.printf("[FAIL-SAFE] SENSOR TANAH RUSAK/LEPAS! (raw=%d). Sprayer otomatis ditahan.\n", soilMoistureRaw);
        publishAlert("soil_sensor_fault", 0, "Sensor tanah tidak terbaca (kabel lepas atau rusak). Sprayer otomatis ditahan demi keamanan.");
        publishStatus();
      }
      return;
    }

    // PROTEKSI 2: Jika sensor macet (sudah semprot 3x berturut-turut tapi tanah tetap terdeteksi kering)
    if (consecutiveSoilSprays >= MAX_CONSECUTIVE_SPRAYS) {
      if (!soilSensorFaultLocked) {
        soilSensorFaultLocked = true;
        Serial.printf("[FAIL-SAFE] PERINGATAN: Sprayer sudah menyemprot %d kali berturut-turut tapi tanah tetap kering (%d%%)! Sensor macet/probe lepas. Pompa DIKUNCI!\n",
          MAX_CONSECUTIVE_SPRAYS, soilMoisturePercent);
        publishAlert("soil_sensor_stuck", 0, "Batas 3x semprot berturut-turut tercapai tanpa kenaikan kelembaban. Pompa dikunci mencegah banjir.");
        publishStatus();
      }
      return;
    }

    // ── ADVISORY FUZZY NOTIFIKASI (Proteksi Sensor Rusak) ───────
    // Logika Fuzzy Mamdani tetap 100% aktif & dihitung untuk keperluan data & pengujian TA.
    // Namun pompa fisik TIDAK dinyalakan otomatis demi menjaga bibit tidak banjir jika sensor soil bermasalah.
    // Sistem hanya mengirim notifikasi / alert ke Web & App bahwa tanah kering dan aturan fuzzy aktif,
    // sedangkan aksi penyiraman fisik sepenuhnya dieksekusi berdasarkan jam jadwal rutin.
    lastSprayerAutoMs = curMs;
    Serial.printf("[FUZZY-ADVISORY] Rekomendasi Fuzzy: Pompa %.2f (dur=%ds, tanah=%d%%, suhu=%.1f). Pompa fisik ditahan (Mode Jadwal Rutin).\n",
      fOut.pompa, fuzzySprayDur, soilMoisturePercent, suhuIn);
    publishAlert("soil_moisture_low", fuzzySprayDur, "Kelembaban tanah rendah. Aturan Fuzzy aktif (rekomendasi siram), aksi fisik diserahkan ke jadwal rutin.");
    publishStatus();
    // Catatan: Jadwal penyiraman independen dieksekusi setiap detik oleh checkScheduledWatering() di loop()
    return;
  }

  // Selesai evaluasi autoLogic. Jadwal penyiraman diproses mandiri oleh checkScheduledWatering().
}

/* ================= COMMAND HANDLER ================= */
void handleCommand(const char *payload, unsigned int length) {
  StaticJsonDocument<1024> doc;
  if (deserializeJson(doc, payload, length)) return;
  const char *type = doc["type"];
  if (!type) return;
  Serial.printf("[CMD] %s\n", type);

  // Proteksi perintah usang / retained dari broker MQTT
  if (doc.containsKey("timestamp")) {
    long cmdTs = doc["timestamp"].as<long>();
    time_t curTime = time(nullptr);
    if (curTime > 1700000000 && cmdTs > 1700000000) {
      if (curTime - cmdTs > 300) { // Jika perintah sudah lebih dari 5 menit lalu
        Serial.printf("[CMD] Abaikan perintah usang/retained (selisih %ld detik)\n", (long)(curTime - cmdTs));
        return;
      }
    }
  }

  if (strcmp(type, "set_time") == 0 || strcmp(type, "set_rtc") == 0) {
    long epoch = doc["epoch"] | 0;
    if (epoch > 1700000000) {
      struct timeval tv = { epoch, 0 };
      settimeofday(&tv, NULL);
      // RTC DS3231 menyimpan waktu lokal WIB (UTC + 7 jam)
      time_t wibSec = epoch + (7 * 3600);
      if (rtcAvailable) {
        rtc.adjust(DateTime((uint32_t)wibSec));
      }
      Serial.printf("[RTC] Waktu disinkronkan via MQTT: epoch=%ld (WIB=%ld)\n", epoch, wibSec);
      publishStatus();
      publishAlert("rtc_synced");
    } else if (doc.containsKey("datetime") || doc.containsKey("value")) {
      String dtStr = doc.containsKey("datetime") ? doc["datetime"].as<String>() : doc["value"].as<String>();
      int y, m, d, hr, mn, sc;
      if (sscanf(dtStr.c_str(), "%d-%d-%d %d:%d:%d", &y, &m, &d, &hr, &mn, &sc) == 6) {
        if (rtcAvailable) {
          rtc.adjust(DateTime(y, m, d, hr, mn, sc));
        }
        syncTimeFromRtc();
        publishStatus();
        publishAlert("rtc_synced");
      }
    }
    return;
  }

  if (strcmp(type,"sync_state")==0) {
    JsonObject val = doc["value"]; if (val.isNull()) return;
    if (val.containsKey("sprayer_duration"))
      sprayerDuration = constrain(val["sprayer_duration"].as<int>(),1,600);
    if (val.containsKey("mode")) {
      String nm = val["mode"].as<String>(); nm.toLowerCase();
      if ((nm=="auto"||nm=="manual") && nm!=mode) {
        String prev=mode; mode=nm;
        if (prev=="manual"&&mode=="auto") {
          lastSprayerTriggerMinute=nowMinuteKey();
          autoSoilGraceUntilMs=millis()+AUTO_SOIL_GRACE_MS;
        }
        if (prev=="auto"&&mode=="manual") { forceAllTogglesOff(); }
      }
    }
    if (val.containsKey("relay") && mode=="manual") {
      JsonObject r=val["relay"];
      if (r.containsKey("lamp")) {
        lampRelayOn=r["lamp"]|false;
        for (int i=0; i<NUM_LAMPS; i++) lampPinsState[i] = lampRelayOn;
      }
      if (r.containsKey("lamp1")) lampPinsState[0]=r["lamp1"]|false;
      if (r.containsKey("lamp2")) lampPinsState[1]=r["lamp2"]|false;
      applyLampOutput();
      if (r.containsKey("fan"))     { fanRelayOn=r["fan"]|false; relayWrite(RELAY_FAN,fanRelayOn); }
      if (r.containsKey("sprayer")) {
        bool sv=r["sprayer"]|false;
        if (sv&&!sprayerActive) { int d=val["sprayer_duration"]|sprayerDuration; if(d<=0)d=10; startSprayerCountdown(d); }
        else if (!sv) { relayWrite(RELAY_SPRAYER,false); sprayerActive=false; lastManualSprayerCommand=false; }
      }
    }
    if (val.containsKey("sprayer_times")) {
      JsonArray times=val["sprayer_times"]; scheduleCount=0;
      for (JsonVariant t:times) { if(scheduleCount>=MAX_SCHEDULE)break; String ts=normalizeTimeToken(t.as<String>()); if(isValidHHMM(ts))manualSchedule[scheduleCount++]=ts; }
    }
    saveConfig(); publishStatus(); return;
  }

  if (strcmp(type,"set_mode")==0) {
    String m=doc["value"].as<String>(); m.toLowerCase();
    if (m=="auto"||m=="manual") {
      String prev=mode; mode=m;
      if (prev=="manual"&&mode=="auto") { lastSprayerTriggerMinute=nowMinuteKey(); autoSoilGraceUntilMs=millis()+AUTO_SOIL_GRACE_MS; }
      if (prev=="auto"&&mode=="manual") { forceAllTogglesOff(); }
      saveConfig(); publishStatus();
    } return;
  }

  if (strcmp(type,"set_relay")==0) {
    if (mode!="manual") return;
    const char *r=doc["relay"]; bool v=doc["value"]|false; if (!r) return;
    if (strcmp(r,"lamp")==0) {
      lampRelayOn=v;
      for (int i=0; i<NUM_LAMPS; i++) lampPinsState[i] = v;
      applyLampOutput();
    }
    else if (strcmp(r,"lamp1")==0) { lampPinsState[0]=v; applyLampOutput(); }
    else if (strcmp(r,"lamp2")==0) { lampPinsState[1]=v; applyLampOutput(); }
    else if (strcmp(r,"fan")==0){ fanRelayOn=v; relayWrite(RELAY_FAN,fanRelayOn); }
    else if (strcmp(r,"sprayer")==0) {
      if (v) { int d=doc["duration"]|sprayerDuration; if(d<=0)d=10; startSprayerCountdown(d); }
      else   { relayWrite(RELAY_SPRAYER,false); sprayerActive=false; lastManualSprayerCommand=false; }
    }
    saveConfig(); publishStatus(); return;
  }

  if (strcmp(type,"etiolasi_detected")==0 || strcmp(type,"set_etiolasi")==0 || strcmp(type,"etiolasi_alert")==0) {
    bool active = true;
    if (doc.containsKey("active")) active = doc["active"].as<bool>();
    else if (doc.containsKey("value")) active = doc["value"].as<bool>();
    else if (doc.containsKey("alert")) active = doc["alert"].as<bool>();
    etiolasiOverride = active;
    Serial.printf("[VISION] Sinyal Etiolasi diterima: override=%s (Lampu 2 %s)\n",
      etiolasiOverride ? "ON" : "OFF",
      etiolasiOverride ? "MENYALA (BOOSTER)" : "NORMAL");
    applyLampOutput();
    publishStatus();
    return;
  }


  if (strcmp(type,"set_active_plant")==0) {
    if (doc["value"].is<const char*>() || doc["value"].is<String>()) {
      String pid = doc["value"].as<String>();
      pid.trim();
      if (pid.length() > 0) {
        activePlantId = pid;
        activePlantName = pid;
        if (activePlantName.equalsIgnoreCase("pakcoy_01") || activePlantName.equalsIgnoreCase("pakcoy")) {
          activePlantName = "Pakcoy";
        }
        Serial.printf("[CMD] Tanaman aktif diset: %s (%s)\n", activePlantName.c_str(), activePlantId.c_str());
        saveConfig(); publishStatus(); return;
      } else {
        activePlantId = ""; activePlantName = ""; forceAllTogglesOff();
        saveConfig(); publishStatus(); return;
      }
    }
    JsonObject p=doc["value"];
    if (p.isNull()) { activePlantId=""; activePlantName=""; forceAllTogglesOff(); saveConfig(); publishStatus(); return; }
    activePlantId=p["id"]|""; activePlantName=p["name"]|"";
    if (activePlantName.isEmpty()) {
      if (activePlantId.equalsIgnoreCase("pakcoy_01") || activePlantId.equalsIgnoreCase("pakcoy")) {
        activePlantName = "Pakcoy";
      } else {
        activePlantName = activePlantId;
      }
    }
    if (activePlantId.isEmpty()) { activePlantName=""; forceAllTogglesOff(); saveConfig(); publishStatus(); return; }
    plantMaxTemp   = p["temp_optimal_max"]|35.0f;
    String ls=p["lighting_start"]|"05:30", le=p["lighting_end"]|"18:00";
    plantLightStart=isValidHHMM(normalizeTimeToken(ls))?normalizeTimeToken(ls):"05:30";
    plantLightEnd  =isValidHHMM(normalizeTimeToken(le))?normalizeTimeToken(le):"18:00";
    if (p.containsKey("lighting_first_day_start")) {
      String lfs=p["lighting_first_day_start"].as<String>();
      if (isValidHHMM(normalizeTimeToken(lfs))) plantFirstLightStart = normalizeTimeToken(lfs);
    }
    plantDarkDays  =constrain(p["dark_days"]|2,1,365);
    plantLightDays =constrain(p["light_days"]|12,1,365);
    plantCycleStartDate =p["cycle_start_date"]|"";
    plantCycleStartPhase=p["cycle_start_phase"]|"dark";
    if (p.containsKey("auto_lamps_count")) {
      autoLampsActive = constrain(p["auto_lamps_count"].as<int>(), 1, NUM_LAMPS);
    }
    plantAllowedDaysCount=0;
    if (p.containsKey("lighting_days")) {
      JsonArray d=p["lighting_days"];
      for (JsonVariant v:d) { if(plantAllowedDaysCount>=7)break; int n=v.as<int>(); if(n>=0&&n<=6)plantAllowedDays[plantAllowedDaysCount++]=n; }
    }
    autoScheduleCount=0;
    if (p.containsKey("watering_times")) {
      JsonArray t=p["watering_times"];
      for (JsonVariant v:t) { if(autoScheduleCount>=MAX_SCHEDULE)break; String ts=normalizeTimeToken(v.as<String>()); if(isValidHHMM(ts))autoSchedule[autoScheduleCount++]=ts; }
    }
    autoSprayerDuration=constrain(p["watering_duration"]|10,1,600);
    lastSprayerTriggerMinute=nowMinuteKey();
    Serial.printf("[CMD] Tanaman aktif diset & disimpan: %s (%s) | MaxTemp=%.1f | Light=%s-%s | %d Lampu Aktif | Siram=%ds\n",
      activePlantName.c_str(), activePlantId.c_str(), plantMaxTemp, plantLightStart.c_str(), plantLightEnd.c_str(), autoLampsActive, autoSprayerDuration);
    saveConfig(); publishStatus(); return;
  }

  if (strcmp(type,"set_schedule")==0) {
    JsonArray t=doc["value"];
    scheduleCount=0;
    autoScheduleCount=0;
    for (JsonVariant v:t) {
      if(scheduleCount>=MAX_SCHEDULE) break;
      String ts=normalizeTimeToken(v.as<String>());
      if(isValidHHMM(ts)) {
        manualSchedule[scheduleCount++] = ts;
        autoSchedule[autoScheduleCount++] = ts;
      }
    }
    if (doc.containsKey("sprayer_duration")) {
      int dur = constrain(doc["sprayer_duration"].as<int>(), 1, 600);
      sprayerDuration = dur;
      autoSprayerDuration = dur;
    }
    lastSprayerTriggerMinute=nowMinuteKey();
    Serial.printf("[CMD] Jadwal siram diset: %d waktu, durasi=%ds\n", scheduleCount, sprayerDuration);
    saveConfig(); publishStatus(); return;
  }
  if (strcmp(type,"set_sprayer_times")==0) {
    scheduleCount=0;
    autoScheduleCount=0;
    JsonObject to=doc["value"];
    if (!to.isNull()) {
      for (JsonPair kv:to) {
        if(scheduleCount>=MAX_SCHEDULE) break;
        String ts=normalizeTimeToken(kv.value().as<String>());
        if(isValidHHMM(ts)) {
          manualSchedule[scheduleCount++] = ts;
          autoSchedule[autoScheduleCount++] = ts;
        }
      }
    }
    lastSprayerTriggerMinute=nowMinuteKey(); saveConfig(); publishStatus(); return;
  }
  if (strcmp(type,"set_sprayer_duration")==0) {
    int dur = constrain(doc["value"].as<int>(), 1, 600);
    sprayerDuration = dur;
    autoSprayerDuration = dur;
    saveConfig(); publishStatus(); return;
  }

  if (strcmp(type,"set_light_schedule")==0) {
    JsonObject val = doc.is<JsonObject>() ? doc["value"].as<JsonObject>() : JsonObject();
    if (val.isNull() && doc.containsKey("start_time")) {
      val = doc.as<JsonObject>();
    }
    if (val.containsKey("start_time")) {
      String ls = normalizeTimeToken(val["start_time"].as<String>());
      if (isValidHHMM(ls)) plantLightStart = ls;
    }
    if (val.containsKey("end_time")) {
      String le = normalizeTimeToken(val["end_time"].as<String>());
      if (isValidHHMM(le)) plantLightEnd = le;
    }
    if (val.containsKey("first_day_start_time")) {
      String lfs = normalizeTimeToken(val["first_day_start_time"].as<String>());
      if (isValidHHMM(lfs)) plantFirstLightStart = lfs;
    }
    Serial.printf("[CMD] Jadwal Penyinaran diset: Reguler=%s-%s | Hari-1 Mulai=%s\n",
      plantLightStart.c_str(), plantLightEnd.c_str(), plantFirstLightStart.c_str());
    saveConfig(); publishStatus(); return;
  }

  Serial.printf("[CMD] unknown: %s\n", type);
}

void mqttCallbackHandler(const char *source, char *topic, byte *payload, unsigned int length) {
  if (String(topic) == topicCommand) {
    Serial.printf("[CMD RECV via %s]\n", source);
    handleCommand((const char*)payload, length);
  }
}

void mqttCloudCallback(char *topic, byte *payload, unsigned int length) {
  mqttCallbackHandler("EMQX_CLOUD", topic, payload, length);
}

#if ENABLE_DUAL_MQTT
void mqttLocalCallback(char *topic, byte *payload, unsigned int length) {
  mqttCallbackHandler("LOCAL_INTRANET", topic, payload, length);
}
#endif

/* ================= SCHEDULED WATERING (INDEPENDENT) ================= */
void checkScheduledWatering() {
  time_t rawNow = time(nullptr);
  if (rawNow < 1700000000) return; // Mencegah false trigger 07:00 jika waktu belum tersinkron RTC/NTP
  String now=nowHHMM(), mk=nowMinuteKey();

  int activeCount = (mode == "auto") ? autoScheduleCount : scheduleCount;
  String *activeTimes = (mode == "auto") ? autoSchedule : manualSchedule;
  int activeDuration = (mode == "auto") ? autoSprayerDuration : sprayerDuration;
  if (activeDuration <= 0) activeDuration = 20;

  for (int i=0; i<activeCount; i++) {
    if (activeTimes[i]==now && !sprayerActive && lastSprayerTriggerMinute!=mk) {
      Serial.printf("[SCHEDULE] Trigger jadwal penyiraman: %s (%s) dur=%ds\n", now.c_str(), mode.c_str(), activeDuration);
      startSprayerCountdown(activeDuration);
      lastSprayerTriggerMinute=mk;
      publishAlert("sprayer_on", activeDuration, "Jadwal penyiraman sedang berjalan.");
      publishStatus();
      break;
    }
  }
}

/* ================= CONFIG PERSISTENCE ================= */
void saveConfig() {
  DynamicJsonDocument doc(2048);
  doc["mode"]=mode;
  doc["sprayerDuration"]=sprayerDuration;
  doc["lampRelayOn"]=lampRelayOn;
  doc["lamp1"]=lampPinsState[0]; doc["lamp2"]=lampPinsState[1];
  doc["lamp3"]=false; doc["lamp4"]=false;
  doc["fanRelayOn"]=fanRelayOn;
  JsonArray mt=doc.createNestedArray("manualSchedule");
  for (int i=0;i<scheduleCount;i++) mt.add(manualSchedule[i]);
  doc["activePlantId"]=activePlantId; doc["activePlantName"]=activePlantName;
  doc["plantMaxTemp"]=plantMaxTemp;
  doc["plantLightStart"]=plantLightStart; doc["plantLightEnd"]=plantLightEnd;
  doc["plantFirstLightStart"]=plantFirstLightStart;
  doc["plantDarkDays"]=plantDarkDays; doc["plantLightDays"]=plantLightDays;
  doc["plantCycleStartDate"]=plantCycleStartDate; doc["plantCycleStartPhase"]=plantCycleStartPhase;
  JsonArray pd=doc.createNestedArray("plantAllowedDays");
  for (int i=0;i<plantAllowedDaysCount;i++) pd.add(plantAllowedDays[i]);
  JsonArray at=doc.createNestedArray("autoSchedule");
  for (int i=0;i<autoScheduleCount;i++) at.add(autoSchedule[i]);
  doc["autoSprayerDuration"]=autoSprayerDuration;
  doc["autoLampsActive"]=autoLampsActive;
  String out; serializeJson(doc,out);
  preferences.begin("inkubator",false); preferences.putString("config",out); preferences.end();
  Serial.printf("[PREF] Disimpan ke NVS: Mode=%s | Tanaman=%s (%s) | AutoLamps=%d\n",
    mode.c_str(), activePlantName.c_str(), activePlantId.c_str(), autoLampsActive);
}

void loadConfig() {
  preferences.begin("inkubator",true);
  String inp=preferences.getString("config",""); preferences.end();
  if (inp.length()>0) {
    DynamicJsonDocument doc(2048);
    if (!deserializeJson(doc,inp)) {
      mode=doc["mode"]|"manual";
      sprayerDuration=doc["sprayerDuration"]|30;
      lampRelayOn=doc["lampRelayOn"]|false; fanRelayOn=doc["fanRelayOn"]|false;
      lampPinsState[0]=doc.containsKey("lamp1") ? doc["lamp1"].as<bool>() : lampRelayOn;
      lampPinsState[1]=doc.containsKey("lamp2") ? doc["lamp2"].as<bool>() : lampRelayOn;
      autoLampsActive=doc.containsKey("autoLampsActive") ? doc["autoLampsActive"].as<int>() : 1;
      scheduleCount=0; JsonArray mt=doc["manualSchedule"];
      for (JsonVariant v:mt) if(scheduleCount<MAX_SCHEDULE) manualSchedule[scheduleCount++]=v.as<String>();
      
      activePlantId=doc["activePlantId"]|"pakcoy_01";
      if (activePlantId.isEmpty() || activePlantId == "null") activePlantId = "pakcoy_01";
      activePlantName=doc["activePlantName"]|"";
      if (activePlantName.isEmpty() || activePlantName == "null") {
        if (activePlantId.equalsIgnoreCase("pakcoy_01") || activePlantId.equalsIgnoreCase("pakcoy")) {
          activePlantName = "Pakcoy";
        } else {
          activePlantName = activePlantId;
        }
      }

      plantMaxTemp=doc["plantMaxTemp"]|35.0f;
      plantLightStart=doc["plantLightStart"]|"05:30"; plantLightEnd=doc["plantLightEnd"]|"18:00";
      plantFirstLightStart=doc["plantFirstLightStart"]|"15:00";
      plantDarkDays=doc["plantDarkDays"]|2; plantLightDays=doc["plantLightDays"]|12;
      plantCycleStartDate=doc["plantCycleStartDate"]|""; plantCycleStartPhase=doc["plantCycleStartPhase"]|"dark";
      plantAllowedDaysCount=0; JsonArray pd=doc["plantAllowedDays"];
      for (JsonVariant v:pd) if(plantAllowedDaysCount<7) plantAllowedDays[plantAllowedDaysCount++]=v.as<int>();
      autoScheduleCount=0; JsonArray at=doc["autoSchedule"];
      for (JsonVariant v:at) if(autoScheduleCount<MAX_SCHEDULE) autoSchedule[autoScheduleCount++]=v.as<String>();
      autoSprayerDuration=doc["autoSprayerDuration"]|30;

      if (autoScheduleCount == 0) {
        autoSchedule[0] = "07:00"; autoSchedule[1] = "12:00"; autoSchedule[2] = "16:00";
        autoScheduleCount = 3;
      }
      if (scheduleCount == 0) {
        manualSchedule[0] = "07:00"; manualSchedule[1] = "12:00"; manualSchedule[2] = "16:00";
        scheduleCount = 3;
      }
      if (sprayerDuration <= 0) sprayerDuration = 30;
      if (autoSprayerDuration <= 0) autoSprayerDuration = 30;

      Serial.println("\n========================================================");
      Serial.println("[PREF] PENGATURAN TERAKHIR BERHASIL DIMUAT DARI MEMORI NVS:");
      Serial.printf("  - Mode Operasi       : %s\n", mode.c_str());
      Serial.printf("  - Tanaman Tersimpan  : %s (ID: %s)\n", activePlantName.c_str(), activePlantId.c_str());
      Serial.printf("  - Suhu Optimal Max   : %.1f C\n", plantMaxTemp);
      Serial.printf("  - Penyinaran         : %s s/d %s\n", plantLightStart.c_str(), plantLightEnd.c_str());
      Serial.printf("  - Siklus Fase        : Gelap %d hari, Terang %d hari\n", plantDarkDays, plantLightDays);
      Serial.printf("  - Durasi Sprayer Auto: %d detik\n", autoSprayerDuration);
      Serial.printf("  - Jadwal Auto (%d)   : ", autoScheduleCount);
      for (int i = 0; i < autoScheduleCount; i++) {
        Serial.printf("%s%s", autoSchedule[i].c_str(), (i < autoScheduleCount - 1) ? ", " : "\n");
      }
      Serial.println("========================================================\n");
    }
  } else {
    Serial.println("[PREF] Belum ada konfigurasi di NVS Flash. Inisialisasi default Pakcoy...");
    activePlantId = "pakcoy_01";
    activePlantName = "Pakcoy";
    saveConfig();
  }
}

/* ================= LOG ================= */
void logAutoScheduleConfig() {
  Serial.printf("[AUTO CFG] plant=%s tempMax=%.1f light=%s-%s dur=%d dark=%d light=%d\n",
    activePlantId.c_str(), plantMaxTemp,
    plantLightStart.c_str(), plantLightEnd.c_str(),
    autoSprayerDuration, plantDarkDays, plantLightDays);
}

/* ================= WIFI & MQTT ================= */
void connectWiFiBoot() {
  Serial.println("[WIFI] Menghubungkan WiFi saat boot...");
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  lcdBootScreen("WIFI Connecting...", WIFI_SSID, "Wait 12s...", "MAC:"+WiFi.macAddress());
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 12000) {
    delay(100); esp_task_wdt_reset();
  }
  if (WiFi.status() == WL_CONNECTED) {
    wifiFailCount = 0;
    Serial.printf("[WIFI] OK IP=%s\n", WiFi.localIP().toString().c_str());
    lcdBootScreen("WIFI Connected!", "IP:" + WiFi.localIP().toString(), "", "");
    delay(1000);
#if ENABLE_NTP_BACKUP
    syncRtcFromNtp();
#endif
  } else {
    Serial.println("[WIFI] WiFi tidak ditemukan, masuk ke mode mandiri offline.");
    lcdBootScreen("WIFI OFFLINE", "Mode Mandiri Aktif", "RTC & Jadwal Jalan", "");
    delay(1200);
  }
  if (lcdAvailable) lcd.clear();
}

void connectMqttCloud() {
  if (mqttCloud.connected()) return;
  String cid = String("esp-cloud-") + MQTT_DEVICE_ID;
  if (mqttCloud.connect(cid.c_str(), CLOUD_MQTT_USER, CLOUD_MQTT_PASS,
      topicStatus.c_str(), 1, true, "{\"online\":false}")) {
    mqttCloud.subscribe(topicCommand.c_str(), 1);
    publishStatus();
    Serial.println("[MQTT CLOUD] Terhubung ke EMQX Cloud (Internet Publik)");
  } else {
    Serial.printf("[MQTT CLOUD] Gagal konek rc=%d\n", mqttCloud.state());
  }
}

#if ENABLE_DUAL_MQTT
void connectMqttLocal() {
  if (mqttLocal.connected()) return;
  String cid = String("esp-local-") + MQTT_DEVICE_ID;
  if (mqttLocal.connect(cid.c_str(), LOCAL_MQTT_USER, LOCAL_MQTT_PASS,
      topicStatus.c_str(), 1, true, "{\"online\":false}")) {
    mqttLocal.subscribe(topicCommand.c_str(), 1);
    publishStatus();
    Serial.println("[MQTT LOCAL] Terhubung ke Server Perusahaan (10.14.41.20)");
  } else {
    Serial.printf("[MQTT LOCAL] Gagal konek rc=%d\n", mqttLocal.state());
  }
}
#endif

void connectMqtt() {
  connectMqttCloud();
#if ENABLE_DUAL_MQTT
  connectMqttLocal();
#endif
}

/* ================= SETUP ================= */
void setup() {
  Serial.begin(115200);
  Serial.println("\n[BOOT] ESP32 INKUBATOR PAKCOY v2 (Fuzzy 9-Rules + RTC + Lux)");
  Serial.println("[CMD] Untuk set jam di Serial Monitor, ketik: 15:25:00 atau 2026-10-21 15:25:00 lalu tekan Enter");
  Serial.println("[CMD] Ketik STATUS atau PLANT? untuk cek tanaman yang disimpan");

  // Set default timezone ke Asia/Jakarta (WIB = GMT+7)
  setenv("TZ", "WIB-7", 1);
  tzset();

  esp_task_wdt_init(WDT_TIMEOUT_S, true);
  esp_task_wdt_add(NULL);

  String prefix  = "buncop/"+String(MQTT_AREA)+"/"+String(MQTT_DEVICE_ID);
  topicTelemetry = prefix+"/telemetry";
  topicStatus    = prefix+"/status";
  topicCommand   = prefix+"/command";
  topicAlert     = prefix+"/alert";

  // ── Inisialisasi Relay (Active-LOW) dengan Aman ─────────────────
  // WAJIB: Tulis HIGH sebelum pinMode OUTPUT agar relay TIDAK aktif sesaat / menyentak saat boot
  digitalWrite(RELAY_FAN,     HIGH);
  pinMode(RELAY_FAN,          OUTPUT);
  digitalWrite(RELAY_FAN,     HIGH);

  digitalWrite(RELAY_SPRAYER, HIGH);
  pinMode(RELAY_SPRAYER,      OUTPUT);
  digitalWrite(RELAY_SPRAYER, HIGH);

  for (int i = 0; i < NUM_LAMPS; i++) {
    digitalWrite(lampPins[i], HIGH);
    pinMode(lampPins[i],      OUTPUT);
    digitalWrite(lampPins[i], HIGH);
  }

  if (SOIL_MOISTURE_DO_PIN >= 0) pinMode(SOIL_MOISTURE_DO_PIN, INPUT);

  analogReadResolution(12);
  analogSetPinAttenuation(SOIL_MOISTURE_AO_PIN, ADC_11db);

  loadConfig();
  forceAllTogglesOff(); // Pastikan relay fisik dan variabel memori sama-sama mulai dari OFF

  // Inisialisasi proteksi sprayer saat boot (mencegah semprot saat startup)
  unsigned long bootMs = millis();
  lastSprayerAutoMs = bootMs;                         // Aktifkan cooldown saat boot
  autoSoilGraceUntilMs = bootMs + AUTO_SOIL_GRACE_MS; // Grace period 60 detik (tunggu pembacaan tanah stabil)
  lastSprayerTriggerMinute = nowMinuteKey();        // Cegah eksekusi jadwal pada menit boot

  // 1. Inisialisasi Subsystem Display (Auto Detect LCD I2C 20x4 vs TFT Serial pada pin 32 & 33)
  initDisplaySubsystem();

  // 2. Inisialisasi I2C Bus Sekunder (RTC DS3231) di GPIO 27 (SDA) & 14 (SCL)
  Wire1.begin(RTC_I2C_SDA_PIN, RTC_I2C_SCL_PIN);
  if (rtc.begin(&Wire1)) {
    rtcAvailable = true;
    Serial.println("[RTC] DS3231 berhasil terdeteksi di Wire1 (SDA:27, SCL:14)");
#if FORCE_RTC_COMPILE_TIME
    Serial.println("[RTC] FORCE_RTC_COMPILE_TIME aktif: menyetel jam RTC ke waktu kompilasi laptop...");
    rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
#else
    if (rtc.lostPower() || rtc.now().year() < 2024) {
      Serial.println("[RTC] Daya RTC sempat putus / waktu belum valid, inisialisasi waktu kompilasi...");
      rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
    }
#endif
    initTime();
    lcdBootScreen("RTC DS3231 OK", "Waktu: " + lcdTimeNow(), "Tgl  : " + lcdDateNow(), "Plt: " + activePlantName);
  } else {
    rtcAvailable = false;
    Serial.println("[RTC] DS3231 TIDAK ditemukan di Wire1 (SDA:27, SCL:14)!");
    lcdBootScreen("RTC TIDAK KONEK!", "Periksa Wire1", "SDA:27 SCL:14", "");
  }
  delay(1200);

  // 3. Inisialisasi Sensor Intensitas Cahaya BH1750 di GPIO 25 (SCL) & 26 (DAT)
  luxAvailable = initLuxSensor();

  if (mode=="manual") applyLampOutput();

  dht.begin();
  delay(500);

  // Baca awal sensor untuk inisialisasi state sebelum loop berjalan
  soilMoistureRaw        = readSoilMoistureSmoothed();
  soilMoisturePercent    = readSoilMoisturePercent(soilMoistureRaw);
  soilMoistureDigitalWet = readSoilMoistureDigitalWet();
  float initTemp = dht.readTemperature();
  float initHum  = dht.readHumidity();
  if (!isnan(initTemp)) temperature = initTemp;
  if (!isnan(initHum))  humidity = initHum;
  Serial.printf("[BOOT] Initial Sensor: Temp=%.1fC Hum=%.1f%% SoilRaw=%d Soil=%d%%\n",
    temperature, humidity, soilMoistureRaw, soilMoisturePercent);

  connectWiFiBoot();
  WiFi.setSleep(false);
  esp_task_wdt_reset();

  cloudWifiClient.setInsecure(); // Bypass verifikasi sertifikat root CA untuk port SSL/TLS 8883

  mqttCloud.setServer(CLOUD_MQTT_HOST, CLOUD_MQTT_PORT);
  mqttCloud.setCallback(mqttCloudCallback);
  mqttCloud.setBufferSize(1024);
  mqttCloud.setKeepAlive(60);

#if ENABLE_DUAL_MQTT
  mqttLocal.setServer(LOCAL_MQTT_HOST, LOCAL_MQTT_PORT);
  mqttLocal.setCallback(mqttLocalCallback);
  mqttLocal.setBufferSize(1024);
  mqttLocal.setKeepAlive(60);
  Serial.printf("[MQTT] Mode: DUAL CLIENT AKTIF (Server Perusahaan: %s:%d + EMQX Cloud: %s:%d)\n",
    LOCAL_MQTT_HOST, LOCAL_MQTT_PORT, CLOUD_MQTT_HOST, CLOUD_MQTT_PORT);
#else
  Serial.printf("[MQTT] Mode: EMQX CLOUD ONLY (%s:%d)\n", CLOUD_MQTT_HOST, CLOUD_MQTT_PORT);
#endif

  connectMqtt();

  Serial.println("[BOOT] READY — Fuzzy 9-Rules + RTC + Lux + Dual MQTT active");
}

/* ================= LOOP ================= */
void loop() {
  esp_task_wdt_reset();
  handleSerialCommands();
  unsigned long now = millis();

  // 1) WiFi check (Background reconnect non-blocking, tanpa membekukan sistem atau LCD)
  if (WiFi.status() != WL_CONNECTED) {
    static unsigned long lwr = 0;
    if (now - lwr >= 20000 || lwr == 0) {
      lwr = now;
      Serial.println("[WIFI] Background reconnecting...");
      WiFi.reconnect();
    }
  } else {
#if ENABLE_NTP_BACKUP
    // Otomatis sinkronkan jam dari NTP internet saat WiFi terhubung atau setiap 1 jam sekali
    static bool prevWifiState = false;
    static unsigned long lastHourlyNtp = 0;
    if (!prevWifiState || (now - lastHourlyNtp >= 3600000UL)) {
      lastHourlyNtp = now;
      syncRtcFromNtp();
    }
    prevWifiState = true;
#endif

    // 1.1) MQTT Cloud (EMQX) Loop & Non-blocking Reconnect
    static unsigned long lastCloudRetry = 0;
    if (!mqttCloud.connected()) {
      if (now - lastCloudRetry >= 10000 || lastCloudRetry == 0) {
        lastCloudRetry = now;
        connectMqttCloud();
      }
    } else {
      mqttCloud.loop();
    }

#if ENABLE_DUAL_MQTT
    // 1.2) MQTT Local Intranet Loop & Non-blocking Reconnect
    static unsigned long lastLocalRetry = 0;
    if (!mqttLocal.connected()) {
      if (now - lastLocalRetry >= 10000 || lastLocalRetry == 0) {
        lastLocalRetry = now;
        connectMqttLocal();
      }
    } else {
      mqttLocal.loop();
    }
#endif
  }

  // 2) Sensor push (tiap 5 detik)
  if (now-lastSensorPush>=SENSOR_PUSH_INTERVAL) {
    lastSensorPush=now;
    float nt=dht.readTemperature(), nh=dht.readHumidity();
    soilMoistureRaw        = readSoilMoistureSmoothed();
    soilMoisturePercent    = readSoilMoisturePercent(soilMoistureRaw);
    soilMoistureDigitalWet = readSoilMoistureDigitalWet();
    luxValue               = readLuxSensor();

    Serial.printf("[SENSOR] Temp=%.1fC Hum=%.1f%% | SoilRaw=%d Soil=%d%% Wet=%s | Lux=%.1f\n",
      isnan(nt)?0.0f:nt, isnan(nh)?0.0f:nh,
      soilMoistureRaw, soilMoisturePercent, soilMoistureDigitalWet?"YES":"NO",
      luxValue);

    if (!isnan(nt)&&!isnan(nh)) {
      temperature=nt; humidity=nh;
      if (temperature>35&&!tempNotified) { publishAlert("temp_high"); tempNotified=true; }
      if (temperature<=35) tempNotified=false;
      if (humidity<40&&!humNotified) { publishAlert("humidity_low"); humNotified=true; }
      if (humidity>=40) humNotified=false;
    } else {
      Serial.println("[SENSOR] DHT fail");
    }
    publishTelemetry();
  }

  // 3) Status push (tiap 10 detik)
  if (now-lastStatusPush>=STATUS_PUSH_INTERVAL) { lastStatusPush=now; publishStatus(); }

  // 4) Heartbeat (tiap 15 detik)
  if (now-lastHeartbeat>=HEARTBEAT_INTERVAL)    { lastHeartbeat=now; publishStatus(); }

  // 5) Auto logic + Fuzzy (tiap 10 detik)
  if (now-lastAutoLogic>=AUTO_LOGIC_INTERVAL)   { lastAutoLogic=now; autoLogic(); }

  // 6) Scheduled watering check (tiap 1 detik, mandiri & aktif di mode auto maupun manual)
  if (now-lastScheduleCheck>=SCHEDULE_CHECK_MS) { lastScheduleCheck=now; checkScheduledWatering(); }

  // 7) Sprayer countdown
  if (sprayerActive && now>=sprayerStart &&
      now-sprayerStart >= (unsigned long)sprayerRunDuration*1000UL) {
    relayWrite(RELAY_SPRAYER, false);
    sprayerActive=false; lastManualSprayerCommand=false;
    Serial.printf("[SPRAYER] OFF elapsed=%lus\n", (now-sprayerStart)/1000);
    publishAlert("sprayer_off"); publishStatus();
  }

  // 8) Heap monitor (tiap 10 detik)
  if (now-lastHeapCheck>=HEAP_CHECK_INTERVAL) {
    lastHeapCheck=now;
    uint32_t fh=ESP.getFreeHeap();
    Serial.printf("[HEAP] free=%u\n", fh);
    if (fh<HEAP_MIN_BYTES) { Serial.println("[FATAL] low heap, reboot"); delay(100); ESP.restart(); }
  }

  // 9) Status log (tiap 10 detik)
  if (now-lastStatusLog>=10000) {
    lastStatusLog=now;
    Serial.printf("[STATE] mode=%s temp=%.1f hum=%.1f soil=%d%% lux=%.1f lamp=%s fan=%s spr=%s\n",
      mode.c_str(), temperature, humidity, soilMoisturePercent, luxValue,
      lampRelayOn?"ON":"OFF", fanRelayOn?"ON":"OFF", sprayerActive?"YES":"NO");
  }

  // 10) Refresh Display LCD 20x4 / TFT Serial (tiap 1 detik)
  if (now-lastLcdUpdate>=LCD_UPDATE_INTERVAL) { 
    lastLcdUpdate=now; 
    if (lcdAvailable) {
      updateLcd(); 
    }
    if (tftSerialAvailable) {
      sendDataToTft();
    }
  }

  // 11) Resync jam internal ESP32 dari RTC DS3231 tiap 10 menit (mencegah drift kristal)
  static unsigned long lastRtcResync = 0;
  if (now - lastRtcResync >= 600000UL) {
    lastRtcResync = now;
    if (rtcAvailable) {
      syncTimeFromRtc();
    }
  }

  delay(LOOP_DELAY_MS);
}
