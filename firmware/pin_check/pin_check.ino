// Pin check: prints what every controller pin reads, twice a second, and
// blinks the board's own blue LED (GPIO2), the white LED (D27) and the buzzer
// (D19) together, so you can see if the board is running and the wiring works.
//
// Reading the output:
//   Buttons (BUILD, joystick SW, encoder SW/CLK/DT): 1 = not pressed, 0 = pressed.
//   Joystick X / Y: about 1800-2100 at rest, near 0 or 4095 when pushed.
//   A pin that is not connected to anything reads random-looking values.

const int DIGITAL_PINS[] = {26, 32, 17, 4, 16};
const char* DIGITAL_NAMES[] = {"BUILD(26)", "JOY_SW(32)", "ENC_SW(17)", "ENC_CLK(4)", "ENC_DT(16)"};
const int ON_BOARD_LED = 2;
const int WHITE_LED = 27;
const int BUZZER = 19;

void setup() {
  Serial.begin(115200);
  for (int i = 0; i < 5; i++) pinMode(DIGITAL_PINS[i], INPUT_PULLUP);
  pinMode(ON_BOARD_LED, OUTPUT);
  pinMode(WHITE_LED, OUTPUT);
  pinMode(BUZZER, OUTPUT);
}

void loop() {
  static bool on = false;
  on = !on;
  digitalWrite(ON_BOARD_LED, on);
  digitalWrite(WHITE_LED, on);
  digitalWrite(BUZZER, on);   // A click/beep every second.

  Serial.print("PINS ");
  for (int i = 0; i < 5; i++) {
    Serial.print(DIGITAL_NAMES[i]);
    Serial.print("=");
    Serial.print(digitalRead(DIGITAL_PINS[i]));
    Serial.print(" ");
  }
  Serial.print("JOY_X(34)=");
  Serial.print(analogRead(34));
  Serial.print(" JOY_Y(35)=");
  Serial.println(analogRead(35));
  delay(500);
}
