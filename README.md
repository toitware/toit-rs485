# RS-485

Support for the RS-485 bus.

Also includes drivers for typical UART based RS-485 chips, like
- MAX485
- SP3485
- SN75176

Typically, these chips have two pins to select the direction of the transceiver:
- `~RE`: enables the receiver (active low).
- `DE`: enables the driver (active high).

One can just use one pin of the ESP32 and connect it to both of these pins. In fact, some
breakout boards, like Sparkfun's [BOB-10124](https://www.sparkfun.com/products/10124) already do this
for you.

Some hardware chips, like the THVD8010 chip only expose one `RTS` (request to send) pin, which
  behaves exactly as if it had internally connected those two pins.
