// TCA9548A bring-up check. Not part of the streaming firmware.
//   pio run -e muxcheck -t upload && pio device monitor
//
// Are the bus lines idle-high, what address does the mux answer at, and does its
// control register actually switch.
#include <Arduino.h>
#include <Wire.h>

constexpr int      PIN_SDA = 21;
constexpr int      PIN_SCL = 22;
constexpr uint32_t I2C_HZ  = 100000;  // slow on purpose for bring-up

static uint8_t muxAddr = 0;

// Idle I2C sits high through its pull-up. Low before any traffic means a short,
// a missing pull-up, or a device holding the bus.
static void checkIdleLines() {
  pinMode(PIN_SDA, INPUT);
  pinMode(PIN_SCL, INPUT);
  delay(5);
  int sdaHi = 0, sclHi = 0;
  for (int i = 0; i < 16; i++) {
    sdaHi += digitalRead(PIN_SDA);
    sclHi += digitalRead(PIN_SCL);
    delayMicroseconds(200);
  }
  Serial.printf("# idle lines (hi-Z, 16 samples): SDA high %d/16, SCL high %d/16\n", sdaHi, sclHi);
  if (sdaHi == 16 && sclHi == 16) {
    Serial.println("#   both idle high -> pull-ups present and nothing holding the bus");
  } else if (sdaHi == 0 || sclHi == 0) {
    Serial.println("#   LINE STUCK LOW -> short to GND, or a device holding the bus");
  } else {
    Serial.println("#   floating/indeterminate -> no external pull-up on at least one line");
  }
}

static bool ping(uint8_t addr) {
  Wire.beginTransmission(addr);
  return Wire.endTransmission() == 0;
}

// The control register reads back what was last written, so a round trip proves
// the switch logic works, not just that the address ACKs.
static bool writeCtrl(uint8_t addr, uint8_t value) {
  Wire.beginTransmission(addr);
  Wire.write(value);
  return Wire.endTransmission() == 0;
}

static bool readCtrl(uint8_t addr, uint8_t &out) {
  if (Wire.requestFrom(addr, (uint8_t)1) != 1) return false;
  out = Wire.read();
  return true;
}

static void scanBus(const char *label) {
  Serial.printf("# %s:", label);
  int n = 0;
  for (uint8_t a = 0x03; a <= 0x77; a++) {
    if (ping(a)) {
      Serial.printf(" 0x%02X", a);
      n++;
    }
  }
  if (n == 0) Serial.print(" (nothing)");
  Serial.println();
}

static void reportAddress() {
  Serial.println("# --- address ---");
  int found = 0;
  for (uint8_t a = 0x70; a <= 0x77; a++) {
    if (ping(a)) {
      if (muxAddr == 0) muxAddr = a;
      found++;
      Serial.printf("# candidate mux at 0x%02X -> A2=%d A1=%d A0=%d\n",
                    a, (a >> 2) & 1, (a >> 1) & 1, a & 1);
    }
  }
  if (found == 0) {
    Serial.println("# no device in 0x70..0x77 -- mux not responding");
  } else if (found > 1) {
    Serial.println("# MORE THAN ONE address answered: address pins are floating and picking");
    Serial.println("# up noise. Strap A0/A1/A2 to GND before trusting anything below.");
  }
}

static void testControlRegister(uint32_t hz) {
  Wire.setClock(hz);
  Serial.printf("# --- control register round trip @ %lu kHz ---\n", (unsigned long)(hz / 1000));
  const uint8_t patterns[] = {0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0xA5, 0xFF, 0x00};
  int pass = 0, fail = 0;

  for (uint8_t p : patterns) {
    uint8_t got = 0;
    bool wrote = writeCtrl(muxAddr, p);
    bool read  = wrote && readCtrl(muxAddr, got);
    bool ok    = read && got == p;
    Serial.printf("#   write 0x%02X -> read %s%02X  %s\n",
                  p, read ? "0x" : "--", read ? got : 0, ok ? "ok" : "MISMATCH");
    ok ? pass++ : fail++;
  }

  Serial.printf("# control register @ %lu kHz: %d ok, %d bad\n", (unsigned long)(hz / 1000), pass, fail);
  if (fail == 0) {
    Serial.println("#   the mux latches every channel mask -> switching logic is good");
  } else {
    Serial.println("#   readback disagrees with what was written -> check RST (must be high)");
  }
}

// Reads BMM350 reg 0x00 the way the Bosch driver does: two dummy bytes, then the
// value. A real BMM350 returns 0x33; anything else merely ACKed.
static bool probeChipId(uint8_t addr, uint8_t &id) {
  Wire.beginTransmission(addr);
  Wire.write((uint8_t)0x00);
  if (Wire.endTransmission() != 0) return false;
  if (Wire.requestFrom(addr, (uint8_t)3) != 3) return false;
  Wire.read(); Wire.read();
  id = Wire.read();
  return true;
}

static void scanChannels() {
  Serial.println("# --- per-channel scan ---");
  for (uint8_t ch = 0; ch < 8; ch++) {
    if (!writeCtrl(muxAddr, (uint8_t)(1u << ch))) {
      Serial.printf("# ch%u: channel select FAILED\n", ch);
      continue;
    }
    Serial.printf("# ch%u:", ch);
    uint8_t hits[16]; int n = 0;
    for (uint8_t a = 0x01; a <= 0x7F; a++) {
      if (a >= 0x70 && a <= 0x77) continue;  // the mux does not answer through itself
      if (ping(a)) {
        Serial.printf(" 0x%02X%s", a, (a >= 0x78) ? "(reserved)" : "");
        if (n < 16) hits[n] = a;
        n++;
      }
    }
    if (n == 0) Serial.print(" (empty)");
    Serial.println();

    for (int i = 0; i < n && i < 16; i++) {
      uint8_t id = 0;
      bool ok = probeChipId(hits[i], id);
      Serial.printf("#     0x%02X -> reg0x00 %s%02X %s\n", hits[i],
                    ok ? "0x" : "--", ok ? id : 0,
                    (ok && id == 0x33) ? "BMM350" : "not a BMM350 response");
    }
  }
  writeCtrl(muxAddr, 0x00);
}

static void runCheck() {
  Serial.println();
  Serial.println("# ===== TCA9548A check =====");

  checkIdleLines();

  Wire.begin(PIN_SDA, PIN_SCL, I2C_HZ);
  muxAddr = 0;
  scanBus("upstream scan, no channel selected");
  reportAddress();

  if (muxAddr == 0) {
    Serial.println("# nothing to test");
    return;
  }

  Serial.printf("# testing mux at 0x%02X\n", muxAddr);
  testControlRegister(100000);
  testControlRegister(400000);   // the speed src/main.cpp runs at
  Wire.setClock(I2C_HZ);
  scanChannels();
  Serial.println("# ===== done, repeating in 5 s =====");
}

void setup() {
  Serial.begin(115200);
  delay(300);
  runCheck();
}

// Repeats so attaching the monitor after boot still shows a result.
void loop() {
  delay(5000);
  runCheck();
}
