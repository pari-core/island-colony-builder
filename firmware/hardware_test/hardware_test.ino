// Island Colony: ESP32 controller hardware test
//
// This sketch only tests the wiring. It has no game code.
// It follows the pin table in documentation/hardware/esp32_wiring_diagram.png.
//
// At start-up: each LED lights in turn, then the buzzer beeps once.
// After that: open Serial Monitor at 115200 baud, then press and turn the controls.

// ---------- Pin numbers (these are GPIO numbers) ----------

// A list of the 8 buttons plus the encoder's push button.
const int BUTTON_COUNT = 9;
const int BUTTON_PINS[BUTTON_COUNT] = {32, 33, 25, 26, 27, 14, 12, 13, 4};
const char* BUTTON_NAMES[BUTTON_COUNT] = {
  "UP", "DOWN", "LEFT", "RIGHT", "BUILD", "ACTION", "SELECT", "MENU", "ENCODER PUSH"
};

const int ENCODER_CLK_PIN = 17;  // labelled TX2 on the board
const int ENCODER_DT_PIN = 16;   // labelled RX2 on the board

const int LED_COUNT = 4;
const int LED_PINS[LED_COUNT] = {19, 21, 22, 23};
const char* LED_NAMES[LED_COUNT] = {"LED1 green", "LED2 yellow", "LED3 red", "LED4 blue"};

const int BUZZER_PIN = 18;

// ---------- Timing ----------

// A button's metal contacts bounce for a few milliseconds when pressed.
// A new reading only counts once it has stayed the same for this long.
const unsigned long DEBOUNCE_MS = 30;

// Ignores encoder signal changes closer together than this, which are usually noise.
const unsigned long ENCODER_GUARD_MS = 2;

// ---------- Values the sketch remembers between loops ----------

int stableButtonState[BUTTON_COUNT];
int lastButtonReading[BUTTON_COUNT];
unsigned long lastButtonChangeTime[BUTTON_COUNT];

int lastClkState;
unsigned long lastEncoderTime = 0;
long encoderCount = 0;

// ---------- setup() runs once when the board starts ----------

void setup() {
  Serial.begin(115200);
  delay(500);  // gives Serial Monitor a moment to connect

  // INPUT_PULLUP keeps a pin HIGH inside the ESP32 until something connects it to GND.
  // So not pressed = HIGH and pressed = LOW.
  for (int i = 0; i < BUTTON_COUNT; i++) {
    pinMode(BUTTON_PINS[i], INPUT_PULLUP);
    stableButtonState[i] = digitalRead(BUTTON_PINS[i]);
    lastButtonReading[i] = stableButtonState[i];
    lastButtonChangeTime[i] = 0;
  }
  pinMode(ENCODER_CLK_PIN, INPUT_PULLUP);
  pinMode(ENCODER_DT_PIN, INPUT_PULLUP);
  lastClkState = digitalRead(ENCODER_CLK_PIN);

  for (int i = 0; i < LED_COUNT; i++) {
    pinMode(LED_PINS[i], OUTPUT);
    digitalWrite(LED_PINS[i], LOW);
  }
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);

  Serial.println();
  Serial.println("=== Island Colony hardware test ===");
  warnAboutStuckButtons();
  testOutputs();
  Serial.println("Ready: press each button and turn the encoder.");
}

// ---------- loop() runs over and over, forever ----------

void loop() {
  checkButtons();
  checkEncoder();
}

// A button reading LOW at start-up is being held, or is wired to GND on both sides.
void warnAboutStuckButtons() {
  for (int i = 0; i < BUTTON_COUNT; i++) {
    if (stableButtonState[i] == LOW) {
      Serial.print("WARNING: ");
      Serial.print(BUTTON_NAMES[i]);
      Serial.println(" reads as pressed at start-up. Check its wires.");
    }
  }
}

// Turns on each output in turn, so you can check each one by eye or by ear.
void testOutputs() {
  for (int i = 0; i < LED_COUNT; i++) {
    Serial.print("Testing ");
    Serial.println(LED_NAMES[i]);
    digitalWrite(LED_PINS[i], HIGH);
    delay(500);
    digitalWrite(LED_PINS[i], LOW);
  }
  Serial.println("Testing buzzer");
  digitalWrite(BUZZER_PIN, HIGH);
  delay(200);
  digitalWrite(BUZZER_PIN, LOW);
}

void checkButtons() {
  unsigned long now = millis();

  for (int i = 0; i < BUTTON_COUNT; i++) {
    int reading = digitalRead(BUTTON_PINS[i]);

    // The reading changed, so restart this button's debounce timer.
    if (reading != lastButtonReading[i]) {
      lastButtonReading[i] = reading;
      lastButtonChangeTime[i] = now;
    }

    // The reading has stayed the same long enough to trust it.
    if (now - lastButtonChangeTime[i] >= DEBOUNCE_MS && reading != stableButtonState[i]) {
      stableButtonState[i] = reading;
      Serial.print(BUTTON_NAMES[i]);
      Serial.println(reading == LOW ? " pressed" : " released");
    }
  }
}

void checkEncoder() {
  int clkState = digitalRead(ENCODER_CLK_PIN);

  if (clkState != lastClkState) {
    unsigned long now = millis();
    if (now - lastEncoderTime >= ENCODER_GUARD_MS) {
      lastEncoderTime = now;

      // Comparing DT with CLK at the moment CLK falls shows the direction of turn.
      if (clkState == LOW) {
        if (digitalRead(ENCODER_DT_PIN) != clkState) {
          encoderCount++;
          Serial.print("ENCODER clockwise, count = ");
        } else {
          encoderCount--;
          Serial.print("ENCODER anticlockwise, count = ");
        }
        Serial.println(encoderCount);
      }
    }
    lastClkState = clkState;
  }
}
