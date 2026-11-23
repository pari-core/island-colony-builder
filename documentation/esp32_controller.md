# Island Colony ESP32 controller

The controller is an ESP32 on a USB cable. It sends button presses to the game and
the game sends back LED and buzzer commands. Firmware:
`firmware/island_controller/island_controller.ino`. Game side:
`scripts/controller_link.gd` (uses the GdSerial plugin in `addons/gdserial`).

## Wiring

Every button goes from its pin to GND (the ESP32's internal pull-up is used, so
no resistors are needed). Each LED goes pin → 220 Ω resistor → LED → GND.

| Part | GPIO | Game action | Keyboard twin |
|---|---|---|---|
| Up button | 32 | Move up / pan | Up arrow |
| Down button | 33 | Move down / pan | Down arrow |
| Left button | 25 | Move left / pan | Left arrow |
| Right button | 26 | Move right / pan | Right arrow |
| Build button | 27 | Start / stop building | B |
| Action button | 14 | Confirm, accept, open | Space |
| Select button | 12 | Next building | Tab |
| Menu button | 13 | Pause menu | M |
| Encoder push | 4 | Back / cancel / decline | Backspace |
| Encoder CLK | 17 | Turn: zoom, scroll a list | - and = |
| Encoder DT | 16 | (direction of the turn) | |
| Green LED | 19 | Colony is fine (blinks: won) | |
| Yellow LED | 21 | Event on (blinks: waiting for your answer) | |
| Red LED | 22 | Danger: starving or storage full (blinks: lost) | |
| Blue LED | 23 | Placing a building | |
| Buzzer (active, +) | 18 | Beeps: built / new event / game over | |

A joystick box can replace the four direction buttons: wire the joystick's four
switch outputs (or a 4-way digital joystick) to GPIO 32, 33, 25, 26.

## Messages (115200 baud, one line each)

ESP32 → game: `HELLO ISLAND 1` (every 2 s until answered), `BTN <NAME> 1|0`,
`ENC 1|-1`.

Game → ESP32: `HI`, `LEDS gyrb` (each digit 0 off, 1 on, 2 blink),
`BEEP 1|2|3`, `BYE`.

## Uploading

Arduino IDE → board "ESP32 Dev Module" → open the sketch → Upload. Close the
Serial Monitor before starting the game (only one program can use the port).
The game finds the board by itself and shows "Controller connected".
