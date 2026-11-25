# Island Colony ESP32 controller

The controller is an ESP32 on a USB cable. It sends joystick, button and encoder
input to the game, and the game sends back the LED state, beeps and the colony's
happiness for the TFT screen. Firmware:
`firmware/island_controller/island_controller.ino`. Game side:
`scripts/controller_link.gd` (uses the GdSerial plugin in `addons/gdserial`).

## Wiring

Every button goes from its pin to GND (the ESP32's internal pull-up is used, so
no resistors are needed). The joystick and encoder are powered from 3V3, never
5 V (ESP32 inputs take 3.3 V at most).

| Part | GPIO | Game action | Keyboard twin |
|---|---|---|---|
| Joystick VRx | 34 | Left / right: move, pan | Left / Right arrow |
| Joystick VRy | 35 | Up / down: move, pan | Up / Down arrow |
| Joystick press (SW) | 32 | Select: next building | Tab |
| Action button | 26 | Confirm, accept, open | Space |
| Build button | 14 | Start / stop building | B |
| Menu button | 25 | Pause menu | M |
| Encoder CLK | 4 | Turn: zoom, scroll a list | - and = |
| Encoder DT | 16 (RX2) | (direction of the turn) | |
| Encoder push (SW) | 17 (TX2) | Back / cancel / decline | Backspace |
| White LED (+, via 220 Ω) | 27 | Colony state, see below | |
| Active buzzer (+) | 19 | Beeps: built / new event / game over | |
| TFT CS | 5 | Happiness bar | |
| TFT RESET | 22 | | |
| TFT DC | 21 | | |
| TFT SDI (MOSI) | 23 | | |
| TFT SCK | 18 | | |
| TFT VCC and LED | 3V3 | | |

**The white LED:** slow pulse (1 s) = looking for the game; steady = playing;
slow blink = an event is on, or the game was won; fast blink = danger
(starving or storage full) or the game was lost.

**The TFT** shows "HAPPINESS", a bar (green 70+, yellow 35+, red below) and the
number beside it.

If a joystick direction comes out backwards, set `FLIP_X` or `FLIP_Y` to `true`
at the top of the sketch. Don't touch the joystick while the board starts: it
measures its resting point then.

## Messages (115200 baud, one line each)

ESP32 → game: `HELLO ISLAND 1` (every 2 s until answered), `BTN <NAME> 1|0`
(UP DOWN LEFT RIGHT SELECT ACTION BUILD MENU BACK), `ENC 1|-1`.

Game → ESP32: `HI`, `LEDS gyrb` (each digit 0 off, 1 on, 2 blink), `HAPPY n`
(0-100), `BEEP 1|2|3`, `BYE`.

## Uploading

1. Arduino IDE → Library Manager → install "Adafruit ILI9341" (it also offers
   "Adafruit GFX Library" and "Adafruit BusIO": install those too).
2. Tools → Board → "ESP32 Dev Module", and pick the board's port.
3. Open the sketch and click Upload.
4. Close the Serial Monitor before starting the game (only one program can use
   the port). The game finds the board by itself and shows "Controller connected".
