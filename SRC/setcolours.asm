/*############################ 6502 assembly: set one color, then reset ############################
This complete example prints a banner using color 15, changes that color from
lt.gray to red, waits for a key, and restores the built-in palette. Assemble at
$C000 and start it with SYS 49152. Production code should also read and check
the status bytes at $DF1F; successful commands return the ASCII string 00,OK. */

* = $C000 "set palette entry"

.label UCI_CONTROL = $DF1C
.label UCI_COMMAND = $DF1D

.label PUSH_CMD = $01
.label DATA_ACCEPT = $02
.label STATE_MASK = $30
.label STATE_BUSY = $10
.label STATE_LAST = $20

.label UCI_RESPONSE = $DF1E
.label UCI_STATUS   = $DF1F

start:
    lda #$93               // clear screen
    jsr $FFD2              // KERNAL CHROUT
    lda #$0f
    sta $0286              // current text color = color 15
    ldx #$00
show:
    lda banner,x    // message to print - 0=eof
    beq change
    jsr $FFD2
    inx
    bne show
change:
    jsr set_light_gray_red
key:
    jsr $FFE4              // KERNAL GETIN
    beq key
    jsr reset_palette
    rts

set_light_gray_red:
    lda #$04               // Control register
    sta UCI_COMMAND
    lda #$53               // SET_PALETTE_COLOR
    sta UCI_COMMAND
    lda #$0f               // we alter color 15
    sta UCI_COMMAND
    lda #$ff               // set new red value
    sta UCI_COMMAND
    lda #$00               // set new green, and blue values
    sta UCI_COMMAND
    sta UCI_COMMAND
    jsr send_and_accept
    rts

reset_palette:
    lda #$04               // Control target
    sta UCI_COMMAND
    lda #$54               // RESET_PALETTE
    sta UCI_COMMAND
    jsr send_and_accept
    rts

send_and_accept:
    lda #PUSH_CMD
    sta UCI_CONTROL
wait:
    lda UCI_CONTROL
    and #STATE_MASK
    cmp #STATE_BUSY     // are we still BUSY?
    beq wait
    cmp #STATE_LAST     // last of DATA?
    bne protocol_error
    lda #DATA_ACCEPT
    sta UCI_CONTROL
    rts

//############################ 6502 assembly: read all 16 colors ############################
//After STATE_LAST is reached, bit 7 of $DF1C indicates that another response byte is available at $DF1E.

* = $C08C "reset SYS49292"

get_palette:
    lda #$04
    sta UCI_COMMAND
    lda #$51               // GET_PALETTE
    sta UCI_COMMAND
    lda #PUSH_CMD
    sta UCI_CONTROL
wait2:
    lda UCI_CONTROL
    and #STATE_MASK
    cmp #STATE_BUSY
    beq wait2
    cmp #STATE_LAST
    bne protocol_error
    ldx #$00
read:
    lda UCI_CONTROL
    bpl done               // bit 7 clear: response queue empty
    lda UCI_RESPONSE
    sta palette,x
    inx
    bne read
done:
    cpx #$30
    bne protocol_error
    lda #DATA_ACCEPT
    sta UCI_CONTROL
    rts
    
protocol_error: // Application-specific error handling goes here.
    lda #$00
    sta $d020   // black border
    rts

banner:
    .text "COLOR 15: RED - PRESS A KEY"
    .byte 0

palette:

.byte $00,$00,$00
.byte $F7,$F7,$F7
.byte $8D,$2F,$34
.byte $6A,$D4,$CD
.byte $98,$35,$A4
.byte $4C,$B4,$42
.byte $2C,$29,$B1
.byte $EF,$EF,$5D
.byte $98,$4E,$20
.byte $5B,$38,$00
.byte $D1,$67,$6D
.byte $4A,$4A,$4A
.byte $7B,$7B,$7B
.byte $9F,$EF,$93
.byte $6D,$6A,$EF
.byte $B2,$B2,$B2

/* 
############################ Runtime and VPL file behavior? ############################
The four palette commands change runtime video output only. They do not write flash configuration
and do not select, create or overwrite a VPL file. A later palette change from the configuration UI,
applying a VPL file, or rebooting the Ultimate may replace the runtime palette.
A C64 program can load and save VPL files through the existing Ultimate-DOS UCI target ($01 or $02):
To load:
    DOS_CMD_OPEN_FILE ($02) with attribute $01
    DOS_CMD_READ_DATA ($04) then
    DOS_CMD_CLOSE_FILE ($03).
    Parse 16 RGB lines and send them with SET_PALETTE.
To save or overwrite:
    DOS_CMD_OPEN_FILE ($02) with attribute $0E
    one or more DOS_CMD_WRITE_DATA ($05) commands, then
    DOS_CMD_CLOSE_FILE ($03).
A VPL file contains 16 non-empty RGB lines in C64 color-number order. Components are hexadecimal.
Blank lines and text after # are ignored. This is the built-in default palette in VPL form

Command format summary

CTRL_CMD_SET_PALETTE_COLOR (0x53)
Command format: $04 $53 [INDEX] [R] [G] [B]
Description: Replaces one runtime color without rewriting the other 15 colors. INDEX is the C64 color
number and must be in the range 0 through 15. The command must be exactly six bytes long.
Status: 00,OK, or 81,INVALID PARAMS for an invalid index or command length.
Invalid commands do not change the palette.

CTRL_CMD_GET_PALETTE (0x51)
Command format: $04 $51
Description: Returns the currently applied runtime palette. The response is 48 bytes: 16 consecutive
RGB triples in C64 color-number order (0 through 15). Each component is an unsigned 8-bit value.
For example, response bytes 45, 46 and 47 are the red, green and blue components of color 15.
Status: 00,OK. A payload or any command length other than two bytes returns 81,INVALID PARAMS.

CTRL_CMD_RESET_PALETTE (0x54)
Command format: $04 $54
Description: Restores the runtime palette to the firmware’s built-in C64 default colors.
No RGB payload is required.
Status: 00,OK. A payload or any command length other than two bytes returns
81,INVALID PARAMS without changing the palette.

####################

.label UCI_RESPONSE = $DF1E
.label UCI_STATUS   = $DF1F

The user software can now read both data and status from the respective registers $DF1E and $DF1F.
Whether there is data or status available can be seen from the upper two bits of the status register.
These bits will be ‘1’ when there is still more data to be read, and ‘0’ otherwise.
####################
When the protocol is in idle state (see paragraph 2.4.2 for the state encoding), the Ultimate-II is ready
to receive a new command. This is done by writing the command byte by byte into the command data
register at $DF1D. Then, the command is pushed into the Ultimate-II by writing a ‘1’ to the control bit
‘PUSH_CMD’, in the control register. This will cause a state transition to “Command Busy”.
####################
As soon as the software has read all the data (or decides not to do so), the C64 should write a ‘1’ to the
register bit ‘DATA_ACC’, to indicate that all data was accepted. If this was the last data block, this
causes the state machine to go back to the idle state, or else, the state returns to “Command Busy”.
####################
The status register contains the following bits:
Bit 7   Bit 6   Bit 5 Bit 4 Bit 3 Bit 2   Bit 1    Bit 0
DATA_AV STAT_AV   STATE     ERROR ABORT_P DATA_ACC CMD_BUSY
The control register contains the following bits:
Bit 7 Bit 6 Bit 5 Bit 4 Bit 3   Bit 2 Bit 1    Bit 0
      reserved          CLR_ERR ABORT DATA_ACC PUSH_CMD
*/