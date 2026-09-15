// Four BMM350 magnetometers on the side faces of a 3 cm cube, behind a TCA9548A
// mux. One CSV row per tick at 115200.
//
// Uses the Bosch driver bundled inside DFRobot_BMM350, not the C++ wrapper: the
// wrapper keeps device state in a file-scope static, so instances would share one
// set of per-chip OTP trim values.
#include <Arduino.h>
#include <Wire.h>
#include <DFRobot_BMM350.h>  // for the bundled bmm350.h / bmm350_defs.h

constexpr int      PIN_SDA   = 21;
constexpr int      PIN_SCL   = 22;
constexpr uint32_t I2C_HZ    = 400000;
constexpr uint8_t  MUX_ADDR  = 0x70;  // A0/A1/A2 low; 0x71..0x77 when strapped high
constexpr uint8_t  MAG_ADDR  = 0x14;  // ADSEL low on every breakout, the mux separates them
constexpr uint32_t PERIOD_MS = 40;    // 25 Hz, matches BMM350_DATA_RATE_25HZ below
constexpr float    ODR_HZ    = 25.0f;
constexpr uint32_t RETRY_MS  = 2000;  // re-init cadence for a sensor that dropped off

// Mux channel -> cube face. Names become the CSV column prefixes.
struct SensorConfig {
  uint8_t     channel;
  const char *name;
};

constexpr SensorConfig SENSORS[] = {
  {2, "East"},
  {3, "North"},
  {4, "West"},
  {5, "South"},
};
constexpr size_t N_SENSORS = sizeof(SENSORS) / sizeof(SENSORS[0]);

struct MagSensor {
  uint8_t     channel;
  const char *name;
  uint8_t     addr;
  bmm350_dev  dev;  // per-chip state, including this chip's OTP trim
  bool        ok;
};

static MagSensor sensors[N_SENSORS];
static int       muxCurrent = -1;  // channel latched in the mux, -1 = unknown

// Cached, so a burst of register accesses costs one mux write.
static bool muxSelect(uint8_t channel) {
  if (muxCurrent == (int)channel) return true;
  Wire.beginTransmission(MUX_ADDR);
  Wire.write((uint8_t)(1u << channel));
  if (Wire.endTransmission() != 0) {
    muxCurrent = -1;
    return false;
  }
  muxCurrent = channel;
  return true;
}

// The driver asks for len + dummy bytes and strips them itself.
static BMM350_INTF_RET_TYPE magRead(uint8_t reg, uint8_t *data, uint32_t len, void *intfPtr) {
  const MagSensor *s = static_cast<const MagSensor *>(intfPtr);
  if (!muxSelect(s->channel)) return -1;
  Wire.beginTransmission(s->addr);
  Wire.write(reg);
  if (Wire.endTransmission() != 0) return -1;
  if ((size_t)Wire.requestFrom(s->addr, (uint8_t)len) != (size_t)len) return -1;
  for (uint32_t i = 0; i < len; i++) data[i] = Wire.read();
  return 0;
}

static BMM350_INTF_RET_TYPE magWrite(uint8_t reg, const uint8_t *data, uint32_t len, void *intfPtr) {
  const MagSensor *s = static_cast<const MagSensor *>(intfPtr);
  if (!muxSelect(s->channel)) return -1;
  Wire.beginTransmission(s->addr);
  Wire.write(reg);
  for (uint32_t i = 0; i < len; i++) Wire.write(data[i]);
  return Wire.endTransmission() == 0 ? 0 : -1;
}

static void magDelayUs(uint32_t period, void *) {
  if (period >= 1000) {
    delay(period / 1000);
    delayMicroseconds(period % 1000);
  } else {
    delayMicroseconds(period);
  }
}

// bmm350Init() reads this chip's OTP trim into s.dev, so it runs once per sensor.
static bool initSensor(MagSensor &s) {
  s.addr = MAG_ADDR;
  memset(&s.dev, 0, sizeof(s.dev));
  s.dev.intfPtr = &s;
  s.dev.read    = magRead;
  s.dev.write   = magWrite;
  s.dev.delayUs = magDelayUs;

  if (!muxSelect(s.channel)) return false;
  Wire.beginTransmission(MAG_ADDR);
  if (Wire.endTransmission() != 0) return false;  // nothing ACKs on this channel
  if (bmm350Init(&s.dev) != BMM350_OK) return false;
  if (s.dev.chipId != BMM350_CHIP_ID) return false;

  if (bmm350SetPowerMode(eBmm350NormalMode, &s.dev) != BMM350_OK) return false;
  if (bmm350SetOdrPerformance(BMM350_DATA_RATE_25HZ, BMM350_AVERAGING_8, &s.dev) != BMM350_OK) return false;
  if (bmm350_enable_axes(BMM350_X_EN, BMM350_Y_EN, BMM350_Z_EN, &s.dev) != BMM350_OK) return false;

  // ODR and axes changed while already in normal mode, so a conversion can be in
  // flight; discard it or the first row can carry a spike that looks real.
  delay((uint32_t)(1000.0f / ODR_HZ) + 5);
  sBmm350MagTempData_t discard;
  bmm350GetCompensatedMagXYZTempData(&discard, &s.dev);
  return true;
}

// Mux first, then each channel. Healthy: mux acks, one 0x14 per populated channel.
static void scanAll() {
  Wire.beginTransmission(MUX_ADDR);
  bool muxSeen = Wire.endTransmission() == 0;
  Serial.printf("# mux 0x%02X %s\n", MUX_ADDR, muxSeen ? "ack" : "NO ACK");
  if (!muxSeen) return;

  for (uint8_t ch = 0; ch < 8; ch++) {
    muxCurrent = -1;
    if (!muxSelect(ch)) continue;
    Serial.printf("# ch%u:", ch);
    // 0x08..0x77 is the assignable range; the reserved blocks draw stray ACKs.
    for (uint8_t a = 0x08; a <= 0x77; a++) {
      if (a == MUX_ADDR) continue;  // the mux does not answer through itself
      Wire.beginTransmission(a);
      if (Wire.endTransmission() == 0) Serial.printf(" 0x%02X", a);
    }
    Serial.println();
  }
  muxCurrent = -1;
}

// Sent at boot, and on 'h' so a host can sync mid-stream without a reset.
static void printHeader() {
  Serial.print("t_ms");
  for (size_t i = 0; i < N_SENSORS; i++) {
    const char *n = sensors[i].name;
    Serial.printf(",%s_x_uT,%s_y_uT,%s_z_uT,%s_norm_uT,%s_temp_C", n, n, n, n, n);
  }
  Serial.println();
}

void setup() {
  Serial.begin(115200);
  Wire.begin(PIN_SDA, PIN_SCL, I2C_HZ);

  scanAll();

  for (size_t i = 0; i < N_SENSORS; i++) {
    sensors[i].channel = SENSORS[i].channel;
    sensors[i].name    = SENSORS[i].name;
    sensors[i].ok      = initSensor(sensors[i]);
    Serial.printf("# %-5s ch%u %s\n", sensors[i].name, sensors[i].channel,
                  sensors[i].ok ? "ok" : "FAILED");
  }

  Serial.printf("# BMM350 x%u, ODR %.4f Hz\n", (unsigned)N_SENSORS, ODR_HZ);

  printHeader();
}

void loop() {
  static uint32_t next    = 0;
  static uint32_t nextTry = 0;

  while (Serial.available()) {
    if (Serial.read() == 'h') printHeader();
  }

  if ((int32_t)(millis() - next) < 0) return;
  next = millis() + PERIOD_MS;

  // Re-init at RETRY_MS, not per sample: bmm350Init() stalls the loop for ms.
  bool mayRetry = (int32_t)(millis() - nextTry) >= 0;
  if (mayRetry) nextTry = millis() + RETRY_MS;

  Serial.print(millis());
  for (size_t i = 0; i < N_SENSORS; i++) {
    MagSensor &s = sensors[i];

    if (!s.ok) {
      if (mayRetry) s.ok = initSensor(s);
      if (!s.ok) {
        Serial.print(",nan,nan,nan,nan,nan");  // keep the column count fixed
        continue;
      }
    }

    sBmm350MagTempData_t d;
    memset(&d, 0, sizeof(d));
    if (bmm350GetCompensatedMagXYZTempData(&d, &s.dev) != BMM350_OK) {
      s.ok = false;
      Serial.print(",nan,nan,nan,nan,nan");
      continue;
    }

    float norm = sqrtf(d.x * d.x + d.y * d.y + d.z * d.z);
    Serial.printf(",%.2f,%.2f,%.2f,%.2f,%.1f", d.x, d.y, d.z, norm, d.temperature);
  }
  Serial.println();
}
