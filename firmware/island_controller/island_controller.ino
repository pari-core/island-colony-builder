// Island Colony: ESP32 controller firmware (joystick + rotary encoder layout)
//
// Wiring: documentation/controller (the "wiring (with rotary encoder)" diagram).
//   Joystick KY-023   VRx D34, VRy D35, SW D32 (= SELECT), +5V -> 3V3, GND
//   Buttons           BUILD D14, ACTION D26, MENU D25 (other leg to GND)
//   Rotary encoder    CLK D4, DT D16 (RX2), SW D17 (TX2) (= BACK), + -> 3V3, GND
//   RGB LED (4 legs)  red leg -> 220 ohm -> D27, green leg -> 220 ohm -> D33,
//                     blue leg -> 220 ohm -> D13, longest leg -> GND
//                     (common anode LED: longest leg -> 3V3, set COMMON_ANODE true)
//   Active buzzer     + D19, - GND
//   2.8" TFT ILI9341  CS D5, RESET D22, DC D21, SDI(MOSI) D23, SCK D18, VCC/LED 3V3
//
// What it sends to the game (115200 baud, one line each):
//   "HELLO ISLAND 1"   every 2 s until the game answers "HI"
//   "BTN UP 1" / "BTN UP 0"   pressed / released. Names: UP DOWN LEFT RIGHT
//                      (the joystick), SELECT, ACTION, BUILD, MENU, BACK
//   "ENC 1" / "ENC -1" the encoder turned one click right / left
//
// What it understands from the game:
//   "HI"           the game found us
//   "LEDS gyrb"    colony state, one digit each (0 off, 1 on, 2 blink). The RGB
//                  LED shows one colour at a time, the most important first:
//                    danger or lost (r) -> RED (fast blink when lost)
//                    event on (y)       -> BLUE (blinks while it waits for you)
//                    thriving (g)       -> GREEN (slow blink when won)
//                  Before the game answers: slow green pulse.
//   "HAPPY n"      happiness 0-100, drawn on the TFT as a bar and a number
//   "BEEP 1|2|3"   short, two short, long
//   "BYE"          the game closed
//
// Libraries (Arduino IDE > Library Manager): "Adafruit ILI9341" and
// "Adafruit GFX Library". Board: "ESP32 Dev Module".

#include <SPI.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ILI9341.h>

// ---------- Pins (GPIO numbers) ----------
const int JOY_X_PIN = 34;
const int JOY_Y_PIN = 35;

// Push buttons. All wired to GND, so pressed = LOW.
const int BUTTON_COUNT = 5;
const int BUTTON_PINS[BUTTON_COUNT] = {32, 26, 14, 25, 17};   // SELECT, ACTION, BUILD, MENU, BACK
const char* BUTTON_NAMES[BUTTON_COUNT] = {"SELECT", "ACTION", "BUILD", "MENU", "BACK"};

const int ENCODER_CLK_PIN = 4;
const int ENCODER_DT_PIN = 16;

const int LED_RED_PIN = 27;
const int LED_GREEN_PIN = 33;
const int LED_BLUE_PIN = 13;
const bool RGB_LED = false;        // false: a plain 2-leg LED on D27 (it blinks; it cannot pick a colour).
const bool COMMON_ANODE = false;   // true if the LED's longest leg goes to 3V3 instead of GND.
const int BUZZER_PIN = 19;

const int TFT_CS = 5;
const int TFT_DC = 21;
const int TFT_RST = 22;
const int TFT_SCK = 18;
const int TFT_MOSI = 23;

// ---------- Joystick tuning ----------
// If a direction comes out backwards, flip the matching line to true.
const bool FLIP_X = true;
const bool FLIP_Y = true;
const bool SWAP_XY = true;   // The real joystick sits sideways in the box (Wokwi: set false).
const int JOY_DEADZONE = 900;   // How far from the centre (0-4095 scale) counts as pushed.

// ---------- Timing (milliseconds) ----------
const unsigned long DEBOUNCE_MS = 30;
const unsigned long REPEAT_DELAY_MS = 400;   // Hold a direction this long before repeating...
const unsigned long REPEAT_EVERY_MS = 130;   // ...then repeat this often.
const unsigned long ENCODER_GUARD_MS = 2;
const unsigned long HELLO_EVERY_MS = 2000;
const unsigned long SLOW_BLINK_MS = 400;
const unsigned long FAST_BLINK_MS = 120;

// ---------- State ----------
Adafruit_ILI9341 tft = Adafruit_ILI9341(TFT_CS, TFT_DC, TFT_RST);

int stableState[BUTTON_COUNT];
int lastReading[BUTTON_COUNT];
unsigned long lastChange[BUTTON_COUNT];

// Joystick directions: 0 UP, 1 DOWN, 2 LEFT, 3 RIGHT.
const char* DIR_NAMES[4] = {"UP", "DOWN", "LEFT", "RIGHT"};
bool dirHeld[4] = {false, false, false, false};
unsigned long dirPressedAt[4];
unsigned long dirLastRepeat[4];
int joyCentreX = 2048;
int joyCentreY = 2048;

int lastClk;
unsigned long lastEncoderTime = 0;

int ledMode[4] = {0, 0, 0, 0};   // green, yellow, red, blue: 0 off, 1 on, 2 blink
bool gameAnswered = false;
unsigned long lastHello = 0;
String incoming = "";

int happiness = -1;      // -1 = not known yet.
int shownHappiness = -2; // What the screen shows now.
bool shownLinked = false;

// The buzzer plays a short list of on/off steps without stopping the loop.
unsigned long beepSteps[6];
int beepCount = 0;
int beepIndex = 0;
unsigned long beepStepStart = 0;

void setup() {
  Serial.begin(115200);

  for (int i = 0; i < BUTTON_COUNT; i++) {
    pinMode(BUTTON_PINS[i], INPUT_PULLUP);
    stableState[i] = digitalRead(BUTTON_PINS[i]);
    lastReading[i] = stableState[i];
    lastChange[i] = 0;
  }
  pinMode(ENCODER_CLK_PIN, INPUT_PULLUP);
  pinMode(ENCODER_DT_PIN, INPUT_PULLUP);
  lastClk = digitalRead(ENCODER_CLK_PIN);

  // The joystick's resting point differs a little per stick: measure it now
  // (do not touch the stick while the board starts).
  long sumX = 0, sumY = 0;
  for (int i = 0; i < 16; i++) {
    sumX += analogRead(JOY_X_PIN);
    sumY += analogRead(JOY_Y_PIN);
    delay(2);
  }
  joyCentreX = sumX / 16;
  joyCentreY = sumY / 16;

  // Start SPI without a MISO pin: the default MISO (GPIO19) is our buzzer.
  SPI.begin(TFT_SCK, -1, TFT_MOSI, TFT_CS);
  tft.begin();
  tft.setRotation(3);   // Landscape, 320 x 240, turned the right way up for the box (1 = upside down).

  pinMode(LED_RED_PIN, OUTPUT);
  if (RGB_LED) {
    pinMode(LED_GREEN_PIN, OUTPUT);
    pinMode(LED_BLUE_PIN, OUTPUT);
  }
  digitalWrite(LED_RED_PIN, LOW);
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);

  drawScreen();
  startBeep(1);
}

void loop() {
  unsigned long now = millis();
  sayHello(now);
  readButtons(now);
  readJoystick(now);
  readEncoder(now);
  readGame();
  showLed(now);
  playBeep(now);
  if (happiness != shownHappiness || gameAnswered != shownLinked) {
    drawScreen();
  }
}

// Until the game answers, announce ourselves every 2 seconds.
void sayHello(unsigned long now) {
  if (!gameAnswered && now - lastHello >= HELLO_EVERY_MS) {
    lastHello = now;
    Serial.println("HELLO ISLAND 1");
  }
}

void readButtons(unsigned long now) {
  for (int i = 0; i < BUTTON_COUNT; i++) {
    int reading = digitalRead(BUTTON_PINS[i]);
    if (reading != lastReading[i]) {
      lastReading[i] = reading;
      lastChange[i] = now;
    }
    if (now - lastChange[i] >= DEBOUNCE_MS && reading != stableState[i]) {
      stableState[i] = reading;
      sendButton(BUTTON_NAMES[i], reading == LOW);
    }
  }
}

void sendButton(const char* name, bool pressed) {
  Serial.print("BTN ");
  Serial.print(name);
  Serial.println(pressed ? " 1" : " 0");
}

// The joystick acts like four direction buttons. Holding one repeats it.
void readJoystick(unsigned long now) {
  int dx = analogRead(JOY_X_PIN) - joyCentreX;
  int dy = analogRead(JOY_Y_PIN) - joyCentreY;
  if (FLIP_X) dx = -dx;
  if (FLIP_Y) dy = -dy;
  if (SWAP_XY) {   // Joystick mounted sideways: turn the readings a quarter turn.
    int t = dx;
    dx = -dy;
    dy = t;
  }
  bool want[4] = {
    dy < -JOY_DEADZONE,   // UP
    dy > JOY_DEADZONE,    // DOWN
    dx < -JOY_DEADZONE,   // LEFT
    dx > JOY_DEADZONE,    // RIGHT
  };
  for (int d = 0; d < 4; d++) {
    if (want[d] && !dirHeld[d]) {
      dirHeld[d] = true;
      dirPressedAt[d] = now;
      dirLastRepeat[d] = now;
      sendButton(DIR_NAMES[d], true);
    } else if (!want[d] && dirHeld[d]) {
      dirHeld[d] = false;
      sendButton(DIR_NAMES[d], false);
    } else if (dirHeld[d] && now - dirPressedAt[d] >= REPEAT_DELAY_MS && now - dirLastRepeat[d] >= REPEAT_EVERY_MS) {
      dirLastRepeat[d] = now;
      sendButton(DIR_NAMES[d], true);
    }
  }
}

void readEncoder(unsigned long now) {
  int clk = digitalRead(ENCODER_CLK_PIN);
  if (clk != lastClk) {
    if (now - lastEncoderTime >= ENCODER_GUARD_MS && clk == LOW) {
      lastEncoderTime = now;
      // Comparing DT with CLK as CLK falls gives the direction.
      Serial.println(digitalRead(ENCODER_DT_PIN) != clk ? "ENC 1" : "ENC -1");
    }
    lastClk = clk;
  }
}

// Lines from the game.
void readGame() {
  while (Serial.available() > 0) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      if (incoming.length() > 0) {
        handleLine(incoming);
      }
      incoming = "";
    } else if (c == 8 || c == 127) {
      // Backspace typed in a terminal: remove the last letter.
      if (incoming.length() > 0) incoming.remove(incoming.length() - 1);
    } else if (incoming.length() < 40) {
      incoming += c;
    }
  }
}

void handleLine(String line) {
  line.trim();
  line.toUpperCase();
  // Echo every line back, so you can see in the Serial Monitor what arrived.
  // (The game ignores lines starting with GOT.)
  Serial.print("GOT [");
  Serial.print(line);
  Serial.println("]");
  if (line == "HI") {
    gameAnswered = true;
  } else if (line.startsWith("LEDS ") && line.length() >= 9) {
    gameAnswered = true;
    for (int i = 0; i < 4; i++) {
      char d = line.charAt(5 + i);
      ledMode[i] = (d >= '0' && d <= '2') ? d - '0' : 0;
    }
  } else if (line.startsWith("HAPPY ")) {
    happiness = constrain(line.substring(6).toInt(), 0, 100);
  } else if (line.startsWith("BEEP ")) {
    startBeep(line.substring(5).toInt());
  } else if (line == "BYE") {
    gameAnswered = false;   // The game closed: start announcing again.
    happiness = -1;
    for (int i = 0; i < 4; i++) ledMode[i] = 0;
  }
}

// Turns each colour of the RGB LED on or off.
void setColour(bool r, bool g, bool b) {
  digitalWrite(LED_RED_PIN, r != COMMON_ANODE ? HIGH : LOW);
  digitalWrite(LED_GREEN_PIN, g != COMMON_ANODE ? HIGH : LOW);
  digitalWrite(LED_BLUE_PIN, b != COMMON_ANODE ? HIGH : LOW);
}

// The RGB LED shows one colour at a time: the most important thing the game reported.
void showLed(unsigned long now) {
  bool slow = (now / SLOW_BLINK_MS) % 2 == 0;
  bool fast = (now / FAST_BLINK_MS) % 2 == 0;
  if (!RGB_LED) {
    // A 2-leg LED on D27: one light, so the pattern shows the state.
    bool on;
    if (!gameAnswered) on = (now / 1000) % 2 == 0;      // Slow pulse: looking for the game.
    else if (ledMode[2] != 0) on = fast;                 // Fast blink: danger or lost.
    else if (ledMode[1] != 0 || ledMode[0] == 2) on = slow;  // Slow blink: event on, or won.
    else on = ledMode[0] != 0;                           // Steady: thriving.
    digitalWrite(LED_RED_PIN, on ? HIGH : LOW);
    return;
  }
  if (!gameAnswered) {
    setColour(false, (now / 1000) % 2 == 0, false);  // Slow green pulse: looking for the game.
  } else if (ledMode[2] != 0) {
    setColour(ledMode[2] == 2 ? fast : true, false, false);   // RED: danger (blinks if lost).
  } else if (ledMode[1] != 0) {
    setColour(false, false, ledMode[1] == 2 ? slow : true);   // BLUE: an event is on.
  } else if (ledMode[0] != 0) {
    setColour(false, ledMode[0] == 2 ? slow : true, false);   // GREEN: thriving (blinks if won).
  } else {
    setColour(false, false, false);
  }
}

// The TFT: "HAPPINESS", a bar and the number. Redrawn only when it changes.
void drawScreen() {
  shownHappiness = happiness;
  shownLinked = gameAnswered;
  tft.fillScreen(ILI9341_BLACK);
  tft.setTextColor(ILI9341_WHITE);
  tft.setTextSize(3);
  tft.setCursor(20, 20);
  tft.print("HAPPINESS");

  if (!gameAnswered || happiness < 0) {
    tft.setTextSize(2);
    tft.setTextColor(ILI9341_LIGHTGREY);
    tft.setCursor(20, 110);
    tft.print(gameAnswered ? "Connected! Waiting for" : "Waiting for the game...");
    if (gameAnswered) {
      tft.setCursor(20, 135);
      tft.print("the happiness number...");
    }
    return;
  }

  // Bar: outline, then a fill coloured by how happy the colony is.
  const int x = 20, y = 100, w = 200, h = 50;
  uint16_t colour = happiness >= 70 ? ILI9341_GREEN : (happiness >= 35 ? ILI9341_YELLOW : ILI9341_RED);
  tft.drawRect(x, y, w, h, ILI9341_WHITE);
  int fill = (w - 4) * happiness / 100;
  tft.fillRect(x + 2, y + 2, fill, h - 4, colour);

  // The number beside the bar.
  tft.setTextSize(4);
  tft.setTextColor(colour);
  tft.setCursor(x + w + 14, y + 10);
  tft.print(happiness);
}

// 1: short beep. 2: two short beeps. 3: one long beep.
void startBeep(int kind) {
  beepIndex = 0;
  beepStepStart = millis();
  if (kind == 2) {
    beepSteps[0] = 80; beepSteps[1] = 80; beepSteps[2] = 80;
    beepCount = 3;
  } else if (kind == 3) {
    beepSteps[0] = 600;
    beepCount = 1;
  } else {
    beepSteps[0] = 120;
    beepCount = 1;
  }
}

void playBeep(unsigned long now) {
  if (beepIndex >= beepCount) {
    digitalWrite(BUZZER_PIN, LOW);
    return;
  }
  // Even steps sound, odd steps are silences.
  digitalWrite(BUZZER_PIN, beepIndex % 2 == 0 ? HIGH : LOW);
  if (now - beepStepStart >= beepSteps[beepIndex]) {
    beepIndex++;
    beepStepStart = now;
  }
}
