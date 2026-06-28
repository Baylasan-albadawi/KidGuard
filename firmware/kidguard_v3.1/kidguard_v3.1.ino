#include <Wire.h>
#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <addons/TokenHelper.h>

// ─── Display + Sensors ───────────────────────────────────────────
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Adafruit_MLX90614.h>
#include "MAX30105.h"
#include "spo2_algorithm.h"

// ─── WiFi ─────────────────────────────────────────────────────────
#define WIFI_SSID     "YOUR_WIFI_SSID"
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"

// ─── Firebase ─────────────────────────────────────────────────────
#define FIREBASE_URL    "https://kidguard-fadf9-default-rtdb.firebaseio.com"
#define FIREBASE_SECRET "your_database_secret_here"   // Firebase Console → RTDB → Legacy secret

// ─── Child ID — must match what was registered in the Flutter app ──
#define CHILD_ID "c1"

// ─── Pin Definitions ──────────────────────────────────────────────
#define SIM_PWR_PIN    25 

// ─── OLED ─────────────────────────────────────────────────────────
#define SCREEN_WIDTH  128
#define SCREEN_HEIGHT  64
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

// ─── Sensor objects ────────────────────────────────────────────────
Adafruit_MLX90614 mlx;
MAX30105          pulseSensor;

void max30102Sleep() { pulseSensor.shutDown(); }
void max30102Wake()  { pulseSensor.wakeUp(); delay(50); }

// ─── SpO2 / HR buffer ─────────────────────────────────────────────
#define SPO2_BUF_SIZE 100
uint32_t irBuffer [SPO2_BUF_SIZE];
uint32_t redBuffer[SPO2_BUF_SIZE];
int32_t  spo2Value;      int8_t spo2Valid;
int32_t  heartRateValue; int8_t hrValid;

// ─── Alert thresholds (Chapter 4.7) ───────────────────────────────
#define HR_MILD_DELTA     25.0f
#define HR_SEVERE_DELTA   50.0f
#define SPO2_MILD         92.0f
#define SPO2_SEVERE       90.0f
#define TEMP_MILD_DELTA    1.5f
#define TEMP_SEVERE_DELTA  2.5f

// ─── Timing ───────────────────────────────────────────────────────
#define BASELINE_SAMPLES    500      
#define BASELINE_INTERVAL_MS 120     
#define OLED_REFRESH_MS    1000
#define WIFI_CHECK_MS     30000

// ─── State ────────────────────────────────────────────────────────
float current_hr = 0, current_spo2 = 0, current_temp = 0;
float hr_base = 0, spo2_base = 0, temp_base = 0;
int   baseline_count = 0;
bool  baseline_done  = false;
int   alert_state    = 0;    // 0=NORMAL  1=MILD  2=SEVERE
bool  severe_sms_sent = false;

String parent_phone   = "";
bool   sim800l_ready  = false;
bool   wifi_ok        = false;

// ─── Firebase objects ─────────────────────────────────────────────
FirebaseData   fbdo;
FirebaseConfig fbConfig;
FirebaseAuth   fbAuth;
bool           fbReady = false;

// ─── Forward declarations ─────────────────────────────────────────
void fillSpO2Buffer();
void updateSpO2();
void classifyAndAlert();
void updateDisplay();
void pushToFirebase();
void fetchParentPhone();
void connectWiFi();
void initializeSIM800L();
bool checkSIM800LReady();
bool checkNetworkRegistration();
bool sendAT(const char* cmd, const char* expect, unsigned long timeoutMs);
String readSerialResponse(unsigned long timeout);
void sendSMS(const String& msg);
void oledMsg(const char* line1, const char* line2);

// ══════════════════════════════════════════════════════════════════
//  SETUP
// ══════════════════════════════════════════════════════════════════
void setup() {
  Serial.begin(115200);
  Serial2.begin(9600, SERIAL_8N1, 16, 17);   // SIM800L: TX=17, RX=16

  pinMode(SIM_PWR_PIN,   OUTPUT);
  digitalWrite(SIM_PWR_PIN,   LOW);   // SIM800L off until initializeSIM800L()

  delay(100);
  Wire.begin(21, 22);
  Wire.setClock(100000);
  delay(100);

  // ── OLED ────────────────────────────────────────────────────────
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("OLED not found");
  }
  display.setTextColor(SSD1306_WHITE);
  oledMsg("KidGuard v3.2", "Starting...");
  delay(1000);

  // ── MLX90614 (skin temperature) ─────────────────────────────────
  if (!mlx.begin()) {
    Serial.println("MLX90614 FAILED — check SDA:21 SCL:22");
    oledMsg("MLX90614", "FAILED!");
    delay(2000);
  } else {
    Serial.println("MLX90614 OK");
    oledMsg("MLX90614", "OK");
    delay(500);
  }

  // ── MAX30102 (HR + SpO2) ────────────────────────────────────────
  if (!pulseSensor.begin(Wire, I2C_SPEED_STANDARD)) {
    Serial.println("MAX30102 FAILED — check SDA:21 SCL:22 and 3.3V supply");
    oledMsg("MAX30102", "FAILED!");
    delay(2000);
  } else {
    pulseSensor.setup(
      0x1F,   // LED amplitude
      4,      // samples averaged
      2,      // mode: SpO2 (Red + IR)
      400,    // sample rate (sps)
      411,    // pulse width (µs)
      4096    // ADC range
    );
    pulseSensor.setPulseAmplitudeGreen(0);
    Serial.println("MAX30102 OK");
    oledMsg("MAX30102", "OK");
    delay(500);
  }

  // ── WiFi ────────────────────────────────────────────────────────
  connectWiFi();

  // ── Firebase ────────────────────────────────────────────────────
  if (wifi_ok) {
    fbConfig.database_url               = FIREBASE_URL;
    fbConfig.signer.tokens.legacy_token = FIREBASE_SECRET;
    fbConfig.token_status_callback      = tokenStatusCallback;

    Firebase.begin(&fbConfig, &fbAuth);
    Firebase.reconnectNetwork(true);
    fbdo.setResponseSize(4096);

    unsigned long fbWait = millis();
    while (!Firebase.ready() && millis() - fbWait < 8000) delay(100);

    fbReady = Firebase.ready();
    if (fbReady) {
      Serial.println("Firebase OK");
      oledMsg("Firebase", "Connected");
      delay(500);
      fetchParentPhone();
    } else {
      Serial.println("Firebase FAILED: " + fbdo.errorReason());
      oledMsg("Firebase", "FAILED");
      delay(1000);
    }
  }

  // ── SIM800L ─────────────────────────────────────────────────────
  oledMsg("SIM800L", "Initializing...");
  initializeSIM800L();

  // ── Fill SpO2 sensor buffer once before calibration ─────────────
  oledMsg("Sensor", "Warming up...");
  fillSpO2Buffer();

  // ── Begin baseline calibration ──────────────────────────────────
  oledMsg("Calibrating", "Keep still 60s");
  Serial.println("\n=== Baseline calibration started (60s) ===");
  xTaskCreatePinnedToCore(taskSensorFusion,  "SensorFusion",  8192, NULL, 1, NULL, 0);
  xTaskCreatePinnedToCore(taskCommunication, "Communication", 8192, NULL, 1, NULL, 1);
}

// ══════════════════════════════════════════════════════════════════
//  MAIN LOOP
// ══════════════════════════════════════════════════════════════════
// ── Task A: Sensor Fusion (Core 0) ────────────────────────────────
void taskSensorFusion(void* pvParameters) {
  static unsigned long lastBaseline = 0;
  static unsigned long lastOLED     = 0;

  for (;;) {
    unsigned long now = millis();

    // Read sensors
    max30102Wake();
    updateSpO2();
    current_temp = mlx.readObjectTempC();
    max30102Sleep();

    // Baseline collection
    if (!baseline_done && (now - lastBaseline >= BASELINE_INTERVAL_MS)) {
      lastBaseline = now;
      hr_base   += current_hr;
      spo2_base += current_spo2;
      temp_base += current_temp;
      baseline_count++;

      if (baseline_count % 12 == 0) {
        int pct = baseline_count * 100 / BASELINE_SAMPLES;
        Serial.printf("Calibrating... %d%%\n", pct);
      }

      if (baseline_count >= BASELINE_SAMPLES) {
        hr_base   /= BASELINE_SAMPLES;
        spo2_base /= BASELINE_SAMPLES;
        temp_base /= BASELINE_SAMPLES;
        baseline_done = true;
        Serial.println("\n=== BASELINE COMPLETE ===");
        Serial.printf("HR: %.0f BPM | SpO2: %.0f%% | Temp: %.1f C\n",
                      hr_base, spo2_base, temp_base);
        oledMsg("Calibration", "Done!");
        delay(1000);
        if (fbReady && Firebase.ready()) {
          Firebase.RTDB.setFloat(&fbdo, "/sensor_data/" CHILD_ID "/hr_baseline",   hr_base);
          Firebase.RTDB.setFloat(&fbdo, "/sensor_data/" CHILD_ID "/spo2_baseline", spo2_base);
          Firebase.RTDB.setFloat(&fbdo, "/sensor_data/" CHILD_ID "/temp_baseline", temp_base);
        }
      }
    }

    // Classification
    if (baseline_done) {
      classifyAndAlert();
      Serial.printf("HR:%.0f SpO2:%.0f Temp:%.1f → %s\n",
                    current_hr, current_spo2, current_temp,
                    alert_state == 0 ? "NORMAL" :
                    alert_state == 1 ? "MILD"   : "SEVERE");
    }

    // OLED update (every 1s)
    if (now - lastOLED >= OLED_REFRESH_MS) {
      lastOLED = now;
      updateDisplay();
    }

    vTaskDelay(10 / portTICK_PERIOD_MS);
  }
}

// ── Task B: Communication (Core 1) ────────────────────────────────
void taskCommunication(void* pvParameters) {
  static unsigned long lastFirebase  = 0;
  static unsigned long lastWifiCheck = 0;

  for (;;) {
    unsigned long now = millis();

    // WiFi watchdog (every 30s)
    if (now - lastWifiCheck >= WIFI_CHECK_MS) {
      lastWifiCheck = now;
      if (WiFi.status() != WL_CONNECTED) {
        wifi_ok = false;
        fbReady = false;
        Serial.println("WiFi lost — reconnecting...");
        connectWiFi();
        if (wifi_ok && !fbReady) {
          Firebase.begin(&fbConfig, &fbAuth);
          Firebase.reconnectNetwork(true);
          unsigned long fbWait = millis();
          while (!Firebase.ready() && millis() - fbWait < 5000) delay(100);
          fbReady = Firebase.ready();
          if (fbReady && parent_phone.length() < 7) fetchParentPhone();
        }
      }
    }

    // Firebase push (every 2s, after baseline)
    if (baseline_done && fbReady && Firebase.ready() &&
        (now - lastFirebase >= FIREBASE_PUSH_MS)) {
      lastFirebase = now;
      pushToFirebase();
    }

    // Drain SIM800L serial
    while (Serial2.available()) Serial.write(Serial2.read());

    vTaskDelay(10 / portTICK_PERIOD_MS);
  }
}

// ── Empty loop — tasks do all the work ────────────────────────────
void loop() {}

// ══════════════════════════════════════════════════════════════════
//  SENSOR FUNCTIONS
// ══════════════════════════════════════════════════════════════════

void fillSpO2Buffer() {
  for (int i = 0; i < SPO2_BUF_SIZE; i++) {
    while (!pulseSensor.available()) pulseSensor.check();
    redBuffer[i] = pulseSensor.getRed();
    irBuffer[i]  = pulseSensor.getIR();
    pulseSensor.nextSample();
  }
  maxim_heart_rate_and_oxygen_saturation(
      irBuffer, SPO2_BUF_SIZE, redBuffer,
      &spo2Value, &spo2Valid,
      &heartRateValue, &hrValid);
  if (hrValid)   current_hr   = heartRateValue;
  if (spo2Valid) current_spo2 = spo2Value;
}

void updateSpO2() {
  // Slide the buffer forward by 25 samples, collect 25 new ones
  for (int i = 25; i < SPO2_BUF_SIZE; i++) {
    redBuffer[i - 25] = redBuffer[i];
    irBuffer[i - 25]  = irBuffer[i];
  }
  for (int i = SPO2_BUF_SIZE - 25; i < SPO2_BUF_SIZE; i++) {
    while (!pulseSensor.available()) pulseSensor.check();
    redBuffer[i] = pulseSensor.getRed();
    irBuffer[i]  = pulseSensor.getIR();
    pulseSensor.nextSample();
  }
  maxim_heart_rate_and_oxygen_saturation(
      irBuffer, SPO2_BUF_SIZE, redBuffer,
      &spo2Value, &spo2Valid,
      &heartRateValue, &hrValid);

  // Only accept physiologically plausible values
  if (hrValid   && heartRateValue > 20  && heartRateValue < 250)
    current_hr   = heartRateValue;
  if (spo2Valid && spo2Value      >= 70 && spo2Value      <= 100)
    current_spo2 = spo2Value;
}

// ══════════════════════════════════════════════════════════════════
//  CLASSIFICATION (from Chapter 4.7 of report)
// ══════════════════════════════════════════════════════════════════

void classifyAndAlert() {
  if (!baseline_done) return;

  int mild_score = 0, severe_score = 0;

  // Heart rate check
  if (current_hr > hr_base + HR_MILD_DELTA)   mild_score++;
  if (current_hr > hr_base + HR_SEVERE_DELTA) severe_score++;

  // SpO2 check
  if (current_spo2 < SPO2_MILD)   mild_score++;
  if (current_spo2 < SPO2_SEVERE) severe_score++;

  // Temperature check
  float dT = current_temp - temp_base;
  if (dT > TEMP_MILD_DELTA)   mild_score++;
  if (dT > TEMP_SEVERE_DELTA) severe_score++;

  // 2/3 signals mild → MILD, 3/3 signals severe → SEVERE
  int prev = alert_state;
  if      (severe_score >= 3) alert_state = 2;
  else if (mild_score   >= 2) alert_state = 1;
  else                        alert_state = 0;

  // Only act on state changes
  if (alert_state != prev) {
    // Send SMS on first SEVERE transition
    if (alert_state == 2 && !severe_sms_sent) {
      if (parent_phone.length() > 7) {
        severe_sms_sent = true;
        sendSMS("KIDGUARD ALERT: Child " CHILD_ID " — SEVERE reaction detected. "
                "HR=" + String((int)current_hr) +
                " SpO2=" + String((int)current_spo2) +
                " Temp=" + String(current_temp, 1));
      } else {
        Serial.println("WARNING: No parent phone stored — register child in app");
      }
    }

    // Reset SMS flag when reaction clears
    if (alert_state < 2) severe_sms_sent = false;
  }
}


// ══════════════════════════════════════════════════════════════════
//  WIFI
// ══════════════════════════════════════════════════════════════════

void connectWiFi() {
  oledMsg("WiFi", "Connecting...");
  WiFi.mode(WIFI_STA);
  WiFi.disconnect(true);
  delay(200);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  WiFi.setSleep(false);

  int tries = 0;
  while (WiFi.status() != WL_CONNECTED && tries < 40) {
    delay(500);
    Serial.print(".");
    tries++;
  }

  wifi_ok = (WiFi.status() == WL_CONNECTED);
  if (wifi_ok) {
    Serial.println("\nWiFi OK — " + WiFi.localIP().toString());
    oledMsg("WiFi OK", WiFi.localIP().toString().c_str());
  } else {
    Serial.println("\nWiFi FAILED — running offline (SMS still works)");
    oledMsg("WiFi", "OFFLINE");
  }
  delay(800);
}

// ══════════════════════════════════════════════════════════════════
//  SIM800L
// ══════════════════════════════════════════════════════════════════

// Send AT command, wait for expected string in response
bool sendAT(const char* cmd, const char* expect, unsigned long timeoutMs) {
  while (Serial2.available()) Serial2.read();   // flush
  Serial2.println(cmd);
  String r = readSerialResponse(timeoutMs);
  return r.indexOf(expect) >= 0;
}

// Read everything from SIM800L serial for 'timeout' ms
String readSerialResponse(unsigned long timeout) {
  unsigned long t = millis();
  String r = "";
  while (millis() - t < timeout) {
    while (Serial2.available()) {
      char c = Serial2.read();
      r += c;
      Serial.write(c);    // mirror to Serial Monitor for debugging
    }
  }
  return r;
}

void initializeSIM800L() {
  Serial.println("Powering SIM800L...");
  digitalWrite(SIM_PWR_PIN, HIGH);
  delay(7000);   // SIM800L needs ~3-5s to fully boot — don't reduce this

  // Ping up to 5 times before giving up
  bool atOk = false;
  for (int i = 0; i < 5; i++) {
    Serial.printf("AT ping attempt %d/5\n", i + 1);
    if (sendAT("AT", "OK", 1500)) { atOk = true; break; }
    delay(500);
  }

  if (!atOk) {
    Serial.println("ERROR: SIM800L not responding");
    oledMsg("SIM800L", "NO RESPONSE");
    sim800l_ready = false;
    return;
  }

  if (!checkSIM800LReady()) {
    oledMsg("SIM800L", "SIM FAIL");
    sim800l_ready = false;
    return;
  }

  checkNetworkRegistration();          // warning only — not fatal
  sendAT("AT+CMGF=1", "OK", 1500);   // SMS text mode

  Serial.println("SIM800L ready");
  oledMsg("SIM800L", "Ready");
  sim800l_ready = true;
  delay(800);
}

bool checkSIM800LReady() {
  while (Serial2.available()) Serial2.read();
  Serial2.println("AT+CPIN?");
  String r = readSerialResponse(3000);
  Serial.println("CPIN: " + r);

  if (r.indexOf("READY") >= 0) {
    Serial.println("SIM card READY");
    return true;
  }
  if (r.indexOf("SIM PIN") >= 0)  Serial.println("SIM card needs PIN code");
  else if (r.indexOf("SIM PUK") >= 0) Serial.println("SIM card BLOCKED (PUK needed)");
  else Serial.println("SIM status unknown — check card insertion");
  return false;
}

bool checkNetworkRegistration() {
  while (Serial2.available()) Serial2.read();
  Serial2.println("AT+CREG?");
  String r = readSerialResponse(5000);
  Serial.println("CREG: " + r);

  if (r.indexOf("+CREG: 0,1") >= 0 || r.indexOf("+CREG: 0,5") >= 0) {
    Serial.println("Registered on GSM network");
    return true;
  }
  Serial.println("Not registered on network yet (searching...)");
  return false;
}

// ══════════════════════════════════════════════════════════════════
//  FIREBASE
// ══════════════════════════════════════════════════════════════════

void pushToFirebase() {
  if (!fbReady || !wifi_ok || WiFi.status() != WL_CONNECTED) return;

  const char* stateStr =
      alert_state == 0 ? "NORMAL" :
      alert_state == 1 ? "MILD"   : "SEVERE";

  FirebaseJson json;
  json.set("hr",        current_hr);
  json.set("spo2",      current_spo2);
  json.set("temp",      current_temp);
  json.set("state",     stateStr);
  json.set("childId",   CHILD_ID);
  json.set("ts/.sv",    "timestamp");    // server timestamp

  if (!Firebase.RTDB.updateNode(&fbdo, "/sensor_data/" CHILD_ID, &json)) {
    Serial.println("Firebase push failed: " + fbdo.errorReason());
  }
}

void fetchParentPhone() {
  if (!fbReady) { Serial.println("Firebase not ready"); return; }
  Serial.println("Fetching parent phone for child: " CHILD_ID);
  parent_phone = "";

  // Direct path — confirmed in Firebase: /children/c1/parentNo
  String path = "/children/" CHILD_ID "/parentNo";

  if (!Firebase.RTDB.getString(&fbdo, path)) {
    Serial.println("Failed to read parentNo: " + fbdo.errorReason());
    return;
  }

  String num = fbdo.stringData();
  num.trim();
  Serial.println("Raw number from Firebase: " + num);

  if (num.length() < 7) {
    Serial.println("Invalid phone number (too short)");
    return;
  }

  // Palestinian number formatting
  // "0599123456"  → "+970599123456"
  // "599123456"   → "+970599123456"
  // "+970..."     → keep as is
  // "970..."      → "+970..."
  if      (num.startsWith("+"))   { /* already good */ }
  else if (num.startsWith("00"))  { num = "+" + num.substring(2); }
  else if (num.startsWith("0"))   { num = "+970" + num.substring(1); }
  else if (num.startsWith("970")) { num = "+" + num; }
  else                            { num = "+970" + num; }

  parent_phone = num;
  Serial.println("Parent phone ready: " + parent_phone);
}

// ══════════════════════════════════════════════════════════════════
//  SMS
// ══════════════════════════════════════════════════════════════════

void sendSMS(const String& msg) {
  if (parent_phone.length() < 7) {
    Serial.println("SMS skipped — no parent phone");
    return;
  }
  if (!sim800l_ready) {
    Serial.println("SMS skipped — SIM800L not ready");
    return;
  }

  Serial.println("Sending SMS to: " + parent_phone);
  Serial.println("Message: " + msg);

  // Verify SIM still ready
  while (Serial2.available()) Serial2.read();
  Serial2.println("AT+CPIN?");
  String pinCheck = readSerialResponse(2000);
  if (pinCheck.indexOf("READY") < 0) {
    Serial.println("SMS failed — SIM not responding");
    return;
  }

  // Text mode
  if (!sendAT("AT+CMGF=1", "OK", 1500)) {
    Serial.println("SMS failed — CMGF rejected");
    return;
  }

  // Send command
  Serial2.print("AT+CMGS=\"");
  Serial2.print(parent_phone);
  Serial2.println("\"");
  delay(500);   // wait for '>' prompt

  // Message body + Ctrl+Z
  Serial2.print(msg);
  Serial2.write(26);

  // Wait for delivery confirmation (up to 8 seconds)
  String resp = readSerialResponse(8000);
  if (resp.indexOf("+CMGS") >= 0 || resp.indexOf("OK") >= 0) {
    Serial.println("SMS sent successfully");
  } else {
    Serial.println("SMS delivery uncertain: " + resp);
  }
}

// ══════════════════════════════════════════════════════════════════
//  OLED
// ══════════════════════════════════════════════════════════════════

void oledMsg(const char* line1, const char* line2) {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.println(line1);
  display.println(line2);
  display.display();
}

void updateDisplay() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);

  // Line 1: status
  display.print("KidGuard ");
  if (!baseline_done) {
    int pct = baseline_count * 100 / BASELINE_SAMPLES;
    display.printf("CAL %d%%\n", pct);
  } else {
    display.println(alert_state == 0 ? "NORMAL" :
                    alert_state == 1 ? "MILD"   : "SEVERE!");
  }

  // Lines 2–4: live vitals
  display.printf("HR  : %.0f BPM\n", current_hr);
  display.printf("SpO2: %.0f%%\n",    current_spo2);
  display.printf("Temp: %.1f C\n",    current_temp);

  // Line 5: baseline or connectivity status
  if (baseline_done) {
    display.printf("Base HR:%.0f T:%.1f", hr_base, temp_base);
  } else {
    display.printf("W:%s F:%s S:%s",
                   wifi_ok       ? "OK" : "--",
                   fbReady       ? "OK" : "--",
                   sim800l_ready ? "OK" : "--");
  }

  display.display();
}
