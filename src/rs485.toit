// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import uart
import gpio
import reader

interface Rs485 implements reader.Reader:
  /**
  Constructs an RS-485 transceiver.

  The $rx and $tx pins are used to construct a UART with the given $baud_rate.

  The $read_enable pin must be active low and enables reading.
  The $write_enable pin must be active high and enables writing.

  Note that it is safe to use a simple pin and connect it to the the RE and DE pins of external chips.
    In that case use $(constructor --rts --rx --tx --baud_rate) instead.

  Example chips: Max485, SP3485.
  */
  constructor
      --read_enable/gpio.Pin
      --write_enable/gpio.Pin
      --rx/gpio.Pin
      --tx/gpio.Pin
      --baud_rate/int:
    return Rs485Uart2_
        --read_enable=read_enable
        --write_enable=write_enable
        --rx=rx
        --tx=tx
        --baud_rate=baud_rate

  /**
  Constructs an RS485 transceiver.

  The $rts pin (request to send) must put the transceiver into read-mode when low, and into write mode when high.

  Example chip: THVD8010.
  Example breakout board: Sparkfun BOB-10124
  */
  constructor --rts/gpio.Pin --rx/gpio.Pin --tx/gpio.Pin --baud_rate/int:
    return Rs485Uart1_ --rts=rts --rx=rx --tx=tx --baud_rate=baud_rate


  /**
  Constructs an RS485 transceiver.

  Does not use any pin to switch read/write mode.
  This constructor is primarily used when running the RS-485 protocol over a simple UART line whithout
    using any transceiver chip.
  */
  constructor --rx/gpio.Pin --tx/gpio.Pin --baud_rate/int:
    return Rs485Uart_ --rx=rx --tx=tx --baud_rate=baud_rate

  /**
  The baud rate of this transceiver.
  */
  baud_rate -> int

  /**
  Reads data from the RS485 line.

  This method blocks until data is available.

  If the transceiver is not in input mode, then the read function will not receive any data.
    However, it is possible to start reading an then to change the transceiver to input mode.
  */
  read -> ByteArray?

  /**
  Writes the data to the RS485 line.

  The transceiver must be in write mode.
  Returns the amount of bytes that were written.
  */
  write data from/int=0 to/int=data.size -> int

  /**
  Sets the mode of the transceiver.

  Exactly one of $read or $write must be true.
  */
  set_mode --read/bool=false --write/bool=false

  /**
  Calls the given $block in output mode.

  Sets the mode to write and then runs the block. When the block has finished executing, ensures that
    enough time has passed for the last byte to have been emitted on the RS-485 line. Then switches the
    mode to read.
  */
  do_transmission [block] -> none

  /**
  Closes the transceiver.
  */
  close -> none

/**
A UART-based RS-485 transceiver.

Without any directional pins, this class is either used to simulate RS-485 communication
  over a UART line, or by a transceiver with separate read and write lines (4-wire), like the
  MAX488, or MAX490.
*/
class Rs485Uart_ implements Rs485:
  port_ /uart.Port
  baud_rate/int
  writing_ /bool := false

  constructor --rx/gpio.Pin --tx/gpio.Pin --rts/gpio.Pin?=null --.baud_rate/int:
    port_ = uart.Port --rx=rx --tx=tx --rts=rts --baud_rate=baud_rate --stop_bits=uart.Port.STOP_BITS_1 --parity=uart.Port.PARITY_DISABLED
    set_mode --read

  read -> ByteArray?:
    return port_.read

  write data from/int=0 to/int=data.size -> int:
    if not writing_: throw "INVALID_STATE"
    // TODO(florian): we would prefer to just call `flush` at the end of the $do_transmission, but
    // UARTs currently don't have any way to do that.
    return port_.write data from to --wait

  /**
  # Inheritance:
  Subclasses must call this method using `super`.
  */
  set_mode --read/bool=false --write/bool=false:
    if read == write: throw "INVALID_ARGUMENT"
    writing_ = write

  do_transmission [block] -> none:
    set_mode --write
    try:
      block.call
    finally:
      set_mode --read

  close:
    port_.close

/**
Base class for UART-based RS-485 transceivers that are half-duplex.
*/
class Rs485HalfDuplexUart_ extends Rs485Uart_:
  constructor --rx/gpio.Pin --tx/gpio.Pin --baud_rate/int:
    super --rx=rx --tx=tx --baud_rate=baud_rate

  do_transmission [block] -> none:
    set_mode --write
    try:
      block.call
    finally:
      set_mode --read

  write data from/int=0 to/int=data.size -> int:
    result := super data from to
    return result

/**
Driver for RS-485 transceivers that use only one pin to switch read/write mode.

This driver is also used when the microcontroller connects a single pin to the RE and DE pins of
  the external chip.

For example, Texas Instruments THVD8010 chip uses only one pin.
*/
class Rs485Uart1_ extends Rs485HalfDuplexUart_:
  rts_ /gpio.Pin

  /**
  Constructs a RS485 transceiver that is connected with a UART and two GPIO pins.

  The $rts pin must put the transceiver into read-mode when low, and into write mode when high. */
  constructor --rts/gpio.Pin --rx/gpio.Pin --tx/gpio.Pin --baud_rate/int:
    rts_ = rts
    rts.config --output
    super --rx=rx --tx=tx --baud_rate=baud_rate

  set_mode --read/bool=false --write/bool=false:
    if read == write: throw "INVALID_ARGUMENT"
    rts_.set (read ? 0 : 1)
    super --read=read --write=write

/**
Driver for RS-485 transceivers that use two pins two enable the receiver/transmitter.

For example, the MAX485 chip uses two pins.
*/
class Rs485Uart2_ extends Rs485HalfDuplexUart_:
  read_enable_ /gpio.Pin
  write_enable_ /gpio.Pin

  /**
  Constructs a RS485 transceiver that is connected with a UART and two GPIO pins.

  The $read_enable pin must be active low and enables reading.
  The $write_enable pin must be active high and enables writing.
  */
  constructor --read_enable/gpio.Pin --write_enable/gpio.Pin --rx/gpio.Pin --tx/gpio.Pin --baud_rate/int:
    read_enable_ = read_enable
    write_enable_ = write_enable
    read_enable.config --output
    write_enable.config --output
    super --rx=rx --tx=tx --baud_rate=baud_rate

  set_mode --read/bool=false --write/bool=false:
    if read == write: throw "INVALID_ARGUMENT"
    if read:
      read_enable_.set 0
      write_enable_.set 1
    else:
      read_enable_.set 1
      write_enable_.set 0
    super --read=read --write=write
