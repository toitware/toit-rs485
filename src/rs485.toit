// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import gpio
import io
import uart
import reader as old-reader

interface Rs485 implements old-reader.Reader:
  /**
  Constructs an RS-485 transceiver.

  The $rx and $tx pins are used to construct a UART with the given $baud-rate.

  The $read-enable pin must be active low and enables reading.
  The $write-enable pin must be active high and enables writing.

  It is recommended to use a single pin and connect to the RE and DE pins of the
    external chip and use $(Rs485.constructor --rts --rx --tx --baud-rate) instead.

  The $parity and $stop-bits parameters are passed to the UART. See $uart.Port.constructor.

  Example chips: Max485, SP3485.
  */
  constructor
      --read-enable/gpio.Pin
      --write-enable/gpio.Pin
      --rx/gpio.Pin
      --tx/gpio.Pin
      --baud-rate/int
      --parity/int=uart.Port.PARITY-DISABLED
      --stop-bits/uart.StopBits=uart.Port.STOP-BITS-1:
    return Rs485Uart2_
        --read-enable=read-enable
        --write-enable=write-enable
        --rx=rx
        --tx=tx
        --baud-rate=baud-rate
        --parity=parity
        --stop-bits=stop-bits

  /**
  Constructs an RS485 transceiver.

  The $rts pin (request to send) must put the transceiver into read-mode when low, and into write mode when high.

  The $parity and $stop-bits parameters are passed to the UART. See $uart.Port.constructor.

  Example chip: THVD8010.
  Example breakout board: Sparkfun BOB-10124
  */
  constructor
      --rts/gpio.Pin
      --rx/gpio.Pin
      --tx/gpio.Pin
      --baud-rate/int
      --parity/int=uart.Port.PARITY-DISABLED
      --stop-bits/uart.StopBits=uart.Port.STOP-BITS-1:
    return Rs485Uart_ --rts=rts --rx=rx --tx=tx --baud-rate=baud-rate --parity=parity --stop-bits=stop-bits


  /**
  Constructs an RS485 transceiver.

  Does not use any pin to switch read/write mode.
  This constructor is primarily used when running the RS-485 protocol over a simple UART line whithout
    using any transceiver chip.

  The $parity and $stop-bits parameters are passed to the UART. See $uart.Port.constructor.
  */
  constructor
      --rx/gpio.Pin
      --tx/gpio.Pin
      --baud-rate/int
      --parity/int=uart.Port.PARITY-DISABLED
      --stop-bits/uart.StopBits=uart.Port.STOP-BITS-1:
    return Rs485Uart_ --rx=rx --tx=tx --baud-rate=baud-rate --parity=parity --stop-bits=stop-bits

  /**
  The baud rate of this transceiver.
  */
  baud-rate -> int

  /**
  Reads data from the RS485 line.

  This method blocks until data is available.

  If the transceiver is not in input mode, then the read function will not receive any data.
    However, it is possible to start reading an then to change the transceiver to input mode.

  Deprecated. Use ($in).read instead.
  */
  read -> ByteArray?

  /**
  Writes the data to the RS485 line.

  The transceiver must be in write mode.
  Returns the amount of bytes that were written.

  Deprecated. Use ($out).write or ($out).try-write instead.
  */
  write data from/int=0 to/int=data.size -> int

  in -> io.Reader
  out -> io.Writer

  /**
  Sets the mode of the transceiver.

  Exactly one of $read or $write must be true.
  */
  set-mode --read/bool=false --write/bool=false

  /**
  Calls the given $block in output mode.

  Sets the mode to write and then runs the block. When the block has finished executing, ensures that
    enough time has passed for the last byte to have been emitted on the RS-485 line. Then switches the
    mode to read.
  */
  do-transmission [block] -> none

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
class Rs485Uart_ extends Object with io.InMixin io.OutMixin implements Rs485:
  port_ /uart.Port
  baud-rate/int
  writing_ /bool := false
  reader_/io.Reader
  writer_/io.Writer

  constructor
      --rx/gpio.Pin
      --tx/gpio.Pin
      --rts/gpio.Pin?=null
      --.baud-rate/int
      --parity/int
      --stop-bits/uart.StopBits:
    port_ = uart.Port --rx=rx --tx=tx --rts=rts
        --baud-rate=baud-rate
        --stop-bits=stop-bits
        --parity=parity
        --mode=uart.Port.MODE-RS485-HALF-DUPLEX
    reader_ = port_.in
    writer_ = port_.out
    set-mode --read

  /**
  Deprecated. Use ($in).read instead.
  */
  read -> ByteArray?:
    return in.read

  read_ -> ByteArray?:
    return reader_.read

  /**
  Deprecated. Use ($out).write or ($out).try-write instead.
  */
  write data from/int=0 to/int=data.size -> int:
    return try-write_ data from to

  try-write_ data/io.Data from/int=0 to/int=data.byte-size -> int:
    if not writing_: throw "INVALID_STATE"
    // TODO(florian): we would prefer to just call `flush` at the end of the $do_transmission, but
    // UARTs currently don't have any way to do that.
    return writer_.write data from to --flush

  /**
  # Inheritance:
  Subclasses must call this method using `super`.
  */
  set-mode --read/bool=false --write/bool=false:
    if read == write: throw "INVALID_ARGUMENT"
    writing_ = write

  do-transmission [block] -> none:
    set-mode --write
    try:
      block.call
    finally:
      set-mode --read

  close:
    port_.close

/**
Base class for UART-based RS-485 transceivers that are half-duplex.
*/
class Rs485HalfDuplexUart_ extends Rs485Uart_:
  constructor
      --rx/gpio.Pin
      --tx/gpio.Pin
      --baud-rate/int
      --parity/int
      --stop-bits/uart.StopBits:
    super --rx=rx --tx=tx --baud-rate=baud-rate --parity=parity --stop-bits=stop-bits

  do-transmission [block] -> none:
    set-mode --write
    try:
      block.call
    finally:
      set-mode --read

  try-write_ data/io.Data from/int=0 to/int=data.byte-size -> int:
    result := super data from to
    return result

/**
Driver for RS-485 transceivers that use two pins two enable the receiver/transmitter.

For example, the MAX485 chip uses two pins.
*/
class Rs485Uart2_ extends Rs485HalfDuplexUart_:
  read-enable_ /gpio.Pin
  write-enable_ /gpio.Pin

  /**
  Constructs a RS485 transceiver that is connected with a UART and two GPIO pins.

  The $read-enable pin must be active low and enables reading.
  The $write-enable pin must be active high and enables writing.
  */
  constructor --read-enable/gpio.Pin
      --write-enable/gpio.Pin
      --rx/gpio.Pin
      --tx/gpio.Pin
      --baud-rate/int
      --parity/int
      --stop-bits/uart.StopBits:
    read-enable_ = read-enable
    write-enable_ = write-enable
    read-enable.configure --output
    write-enable.configure --output
    super --rx=rx --tx=tx --baud-rate=baud-rate --parity=parity --stop-bits=stop-bits

  set-mode --read/bool=false --write/bool=false:
    if read == write: throw "INVALID_ARGUMENT"
    if read:
      read-enable_.set 0
      write-enable_.set 1
    else:
      read-enable_.set 1
      write-enable_.set 0
    super --read=read --write=write
