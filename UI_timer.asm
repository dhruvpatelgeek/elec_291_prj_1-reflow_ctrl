;Start/Constants
    $MODLP51
        ; Reset vector
        org 0x0000
            ljmp MainProgram

        ; External interrupt 0 vector (not used in this code)
        org 0x0003
            reti

        ; Timer/Counter 0 overflow interrupt vector
        org 0x000B
            ljmp Timer0_ISR

        ; External interrupt 1 vector (not used in this code)
        org 0x0013
            reti

        ; Timer/Counter 1 overflow interrupt vector (not used in this code)
        org 0x001B
            reti

        ; Serial port receive/transmit interrupt vector (not used in this code)
        org 0x0023 
            reti
            
        ; Timer/Counter 2 overflow interrupt vector
        org 0x002B
            ljmp Timer2_ISR

    ;CLK  EQU 22118400
    CLK  EQU 22118400
    ;termometer
    BAUD equ 115200
    BRG_VAL equ (0x100-(CLK/(16*BAUD)))
    ;timer
    TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
    TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
    TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
    TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))


    ; There is a couple of typos in MODLP51 in the definition of the timer 0/1 reload
    ; special function registers (SFRs), so:

    TIMER0_RELOAD_L DATA 0xf2
    TIMER1_RELOAD_L DATA 0xf3
    TIMER0_RELOAD_H DATA 0xf4
    TIMER1_RELOAD_H DATA 0xf5

;Variables (dseg)
    DSEG at 30H

    Result:    ds 4
    x:         ds 4
    y:         ds 4
    bcd:       ds 5
    ;FSM varialbles
    temp_soak: ds 1
    time_soak: ds 1
    temp_refl: ds 1
    time_refl: ds 1
    state:     ds 1
    state_lcd: ds 1
    temp:      ds 1
    sec:       ds 1
    pwm:       ds 1 ; Register that controls the power of the oven 
    ;;owen_temp ds 1

    ;Timer variables
    Count1ms:     ds 2 ; Used to determine when half second has passed
    reflow_temp:  ds 2
    soak_temp:    ds 2
    reflow_temp_var: ds 1
    BCD_counter:  ds 1 ; The BCD counter incrememted in the ISR and displayed in the main loop
    minutes:          ds 1
    hour:         ds 1
    reflow_sec:   ds 1
    reflow_min:   ds 1
    soak_sec:     ds 1
    soak_min:     ds 1
    alarm_min:    ds 1
    alarm_hour:   ds 1
    day:          ds 1
    month:        ds 1
    year:         ds 1
    hour_24:      ds 1


;flags (bseg)
    bseg
    mf:                dbit 1
    half_seconds_flag: dbit 1 ; Set to one in the ISR every time 500 ms had passed
    AMPM_flag:         dbit 1
    alarm_AMPM_flag:   dbit 1
    on_off_flag:       dbit 1 ; 1 is on
    alarm_buzzer_flag: dbit 1
    TR2_flag:          dbit 1
    tt_reflow_flag:    dbit 1
    tt_flag_soak:      dbit 1

;Pins Config (cseg)
    CSEG 

    done_button equ P0.0    
    done 		  equ P0.1
    setup 		  equ P0.2
    setmin		  equ P0.3
    sethour 	  equ P0.4
    setday        equ P0.5

    start         equ P0.7

    LCD_RS        equ P1.1
    LCD_RW        equ P1.2
    LCD_E         equ P1.3
    start2         equ p1.7   ;in slide it was KEY.3 which should be decided later so p1.7 is just a random pin


    ; These �EQU� must match the wiring between the microcontroller and ADC 
    CE_ADC       EQU  P2.0 
    MY_MOSI      EQU  P2.1 
    MY_MISO      EQU  P2.2 
    MY_SCLK      EQU  P2.3
    SETUP_SOAK_Button equ  P2.4
    set_BUTTON           equ  P2.5
    Button_min    equ  P2.6
    HOME_BUTTON   equ  P2.7

    ;LCD 4bits data
    LCD_D4        equ  P3.2
    LCD_D5        equ  P3.3
    LCD_D6        equ  P3.4
    LCD_D7        equ  P3.5

    BOOT_BUTTON   equ  P4.5
    SOUND_OUT     equ  P3.7

;include files 
    $NOLIST
    $include(math32.inc)
    $include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
    $LIST


;ISR

    
    ;---------------------------------;
    ; Routine to initialize the ISR   ;
    ; for timer 0                     ;
    ;---------------------------------;
    Timer0_Init:
        mov a, TMOD
        anl a, #0xf0 ; Clear the bits for timer 0
        orl a, #0x01 ; Configure timer 0 as 16-timer
        mov TMOD, a
        mov TH0, #high(TIMER0_RELOAD)
        mov TL0, #low(TIMER0_RELOAD)
        ; Set autoreload value
        mov TIMER0_RELOAD_H, #high(TIMER0_RELOAD)
        mov TIMER0_RELOAD_L, #low(TIMER0_RELOAD)
        ; Enable the timer and interrupts
        setb ET0  ; Enable timer 0 interrupt
        setb TR0  ; Start timer 0
        ret

    ;---------------------------------;
    ; ISR for timer 0.  Set to execute;
    ; every 1/4096Hz to generate a    ;
    ; 2048 Hz square wave at pin P3.7 ;
    ;---------------------------------;
    Timer0_ISR:
        ;clr TF0  ; According to the data sheet this is done for us already.
        cpl SOUND_OUT ; Connect speaker to P3.7!
        reti

    ;---------------------------------;
    ; Routine to initialize the ISR   ;
    ; for timer 2                     ;
    ;---------------------------------;
    Timer2_Init:
        mov T2CON, #0 ; Stop timer/counter.  Autoreload mode.
        mov TH2, #high(TIMER2_RELOAD)
        mov TL2, #low(TIMER2_RELOAD)
        ; Set the reload value
        mov RCAP2H, #high(TIMER2_RELOAD)
        mov RCAP2L, #low(TIMER2_RELOAD)
        ; Init One millisecond interrupt counter.  It is a 16-bit variable made with two 8-bit parts
        clr a
        mov Count1ms+0, a
        mov Count1ms+1, a
        ; Enable the timer and interrupts
        setb ET2  ; Enable timer 2 interrupt
        setb TR2  ; Enable timer 2
        ret

    ;---------------------------------;
    ; ISR for timer 2                 ;
    ;---------------------------------;
    Timer2_ISR:
        clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR
        cpl P3.6 ; To check the interrupt rate with oscilloscope. It must be precisely a 1 ms pulse.
        
        ; The two registers used in the ISR must be saved in the stack
        push acc
        push psw
        
        ; Increment the 16-bit one mili second counter
        inc Count1ms+0    ; Increment the low 8-bits first
        mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
        jnz Inc_Done
        inc Count1ms+1

    Inc_Done:
        ; Check if half second has passed
        mov a, Count1ms+0
        cjne a, #low(1000), Timer2_ISR_done ; Warning: this instruction changes the carry flag!
        mov a, Count1ms+1
        cjne a, #high(1000), Timer2_ISR_done
        
        ; 500 milliseconds have passed.  Set a flag so the main program knows
        setb half_seconds_flag ; Let the main program know half second had passed
       ; cpl TR0 ; Enable/disable timer/counter 0. This line creates a beep-silence-beep-silence sound.
        ; Reset to zero the milli-seconds counter, it is a 16-bit variable
        clr a
        mov Count1ms+0, a
        mov Count1ms+1, a
        ; Increment the BCD counter
        mov a, BCD_counter
       ; jnb UPDOWN, Timer2_ISR_decrement
        add a, #0x01
        sjmp Timer2_ISR_da
    Timer2_ISR_decrement:
       ; add a, #0x99 ; Adding the 10-complement of -1 is like subtracting 1.
    Timer2_ISR_da:
        da a ; Decimal adjust instruction.  Check datasheet for more details!
        mov BCD_counter, a
        
    Timer2_ISR_done:
        pop psw
        pop acc
        reti
Strings:
    ;Hello_World:
        ;DB  'Hello, World!', '\r', '\n', 0
    Newline:
            DB   '\r', '\n', 0
    Space:
            DB   '      ','\r', '\n', 0

                    ;     1234567890123456
    Temp0:            db 'Temp:xxxC       ', 0
    nothing:          db '                ',0
    test2:            db '      Test2     ',0
    hot:			  db '      HOT       ', 0
    Time:             db 'Time xx:xx SET  ', 0
    dots:             db ':',0
    soak_reflw:       db '  SOAK  REFLOW  ', 0
    reflow_setup:     db 'Temp',0
    reflow_setup4:    db '*REFLOW*',0
    reflow_setup2:    db 'Time',0
    reflow_setup3:    db 'HOME',0

    soak_setup0:      db 'Temp',0
    soak_setup1:      db ' *SOAK*',0
    soak_setup2:      db 'Time',0
    soak_setup3:      db 'HOME',0



;CONFIG Putty:
    ; Configure the serial port and baud rate
    InitSerialPort:
        ; Since the reset button bounces, we need to wait a bit before
        ; sending messages, otherwise we risk displaying gibberish!
        mov R1, #222
        mov R0, #166
        djnz R0, $   ; 3 cycles->3*45.21123ns*166=22.51519us
        djnz R1, $-4 ; 22.51519us*222=4.998ms
        ; Now we can proceed with the configuration
        orl	PCON,#0x80
        mov	SCON,#0x52
        mov	BDRCON,#0x00
        mov	BRL,#BRG_VAL
        mov	BDRCON,#0x1E ; BDRCON=BRR|TBCK|RBCK|SPD;
        ret

    ; Send a character using the serial port
    putchar:
        jnb TI, putchar 
        ; TI serial interrupt flag is set and when last bit (stop bit) 
        ; of receiving data byte is received, RI flag get set. IE register
        ; is used to enable/disable interrupt sources.
        clr TI
        mov SBUF, a
        ret

    getchar: 
        jnb RI, getchar 
        clr RI 
        mov a, SBUF 
        ret

    ; Send a constant-zero-terminated string using the serial port
    SendString:
        clr A
        movc A, @A+DPTR
        jz SendStringDone
        lcall putchar
        inc DPTR
        sjmp SendString
    SendStringDone:
        ret

    INIT_SPI:     
        setb MY_MISO    ; Make MISO an input pin  1 master input 0 slave out   ;MISO master in/slave out
        clr MY_SCLK     ; For mode (0,0) SCLK is zero     
        ret 

    DO_SPI_G:     
        push acc     
        mov R1, #0      ; Received byte stored in R1     
        mov R2, #8      ; Loop counter (8-bits)
        
    DO_SPI_G_LOOP:     
        mov a, R0       ; Byte to write is in R0     
        rlc a           ; Carry flag has bit to write 
        mov R0, a     
        mov MY_MOSI, c     
        setb MY_SCLK    ; Transmit     
        mov c, MY_MISO  ; Read received bit     
        mov a, R1       ; Save received bit in R1     
        rlc a     
        mov R1, a     
        clr MY_SCLK     
        djnz R2, DO_SPI_G_LOOP     
        pop acc     
        ret 
    
WaitHalfSec:
        mov R2, #178
        Lr3: mov R1, #250
        Lr2: mov R0, #166
        Lr1: djnz R0, Lr1 ; 3 cycles->3*45.21123ns*166=22.51519us
        djnz R1, Lr2 ; 22.51519us*250=5.629ms
        djnz R2, Lr3 ; 5.629ms*89=0.5s (approximately)
        ret
	
blink:
        mov SP, #7FH
        mov P3M1, #0   ; Configure P3 in bidirectional mode
    M0:
        cpl P3.7
        Set_Cursor(1, 1)
        Send_Constant_String(#nothing)
        Set_Cursor(2, 1)
        Send_Constant_String(#nothing)
        Set_Cursor(1, 1)
        Send_Constant_String(#hot)
        Set_Cursor(2, 1)
        Send_Constant_String(#hot)

        lcall WaitHalfSec

        ret

convert:
    mov x+0, Result
	mov x+1, Result+1 
	mov x+2, #0
	mov x+3, #0
    ret
    

Display_temp:
    Load_y(410)
    lcall mul32
    Load_y(1023)
    lcall div32
    Load_y(273)
    lcall sub32
    lcall hex2bcd
    lcall InitSerialPort
    Set_Cursor(1, 1)
    Send_Constant_String(#Temp0)
    lcall SendString
    Set_Cursor(1, 5)    
    Send_BCD(bcd+1) ; send fisrt 2 digits to putty
    Display_BCD(bcd+1); send fisrt 2 digits to lcd
    Set_Cursor(1, 7) 
    Send_BCD(bcd) ; send last 2 digits to putty
    Display_BCD(bcd+0) ; send last 2 digits to lcd
    Set_Cursor(1, 5)
    Send_Constant_String(#dots)
    lcall SendString
    mov DPTR, #Newline
    lcall SendString
    ret
config_adc:
        clr CE_ADC 
        mov R0, #00000001B; Start bit:1 
        lcall DO_SPI_G

        mov R0, #10000000B; Single ended, read channel 0 
        lcall DO_SPI_G 
        mov a, R1          ; R1 contains bits 8 and 9 
        anl a, #00000011B  ; We need only the two least significant bits 
        mov Result+1, a    ; Save result high.

        mov R0, #55H; It doesn't matter what we transmit... 
        lcall DO_SPI_G 
        mov Result, R1     ; R1 contains bits 0 to 7.  Save result low. 
        setb CE_ADC 
        lcall convert  
        mov a, bcd ; move temp to accumulator 
        ret
Reset_timer:

    clr TR2                 ; Stop timer 2
    clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Now clear the BCD counter and minutes
	mov BCD_counter, a
	setb TR2                ; Start timer 2

    ret
Display_time:
    Set_Cursor(2, 1)
    Send_Constant_String(#Time)
    clr half_seconds_flag ; We clear this flag in the main loop, but it is set in the ISR for timer 2
	Set_Cursor(2, 9)     ; the place in the LCD where we want the BCD counter value
	Display_BCD(BCD_counter) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(2, 6)     ; the place in the LCD where we want the BCD counter value
	Display_BCD(minutes) ; This macro is also in 'LCD_4bit.inc'

    ret
;Timer couter 
    sec_counter: 
        mov a,BCD_counter
        cjne a, #0x60, Continue1 ; check if the couter reached 60s
        mov a, minutes
        add a, #0x01 ; add one to the minutes
        da a ; Decimal adjust instruction.  Check datasheet for more details!
        mov minutes, a
        lcall Reset_timer
	    Continue1:
        ret
    min_counter:
		mov a,minutes
		cjne a, #0x60, Continue2
		clr TR2                 ; Stop timer 2
		clr a                   
		mov Count1ms+0, a
		mov Count1ms+1, a       ; Now clear the BCD counter
		mov minutes, a              ; Reset minutes
        setb TR2                ; Start timer 2

		Continue2:
        ret
home_page:
    ;--------Timer----------;
    jnb half_seconds_flag, Temp_sensor
    lcall sec_counter
    lcall min_counter
    lcall Display_time
    ;-----------------------;
            
    ;-----TEMP SENSOR-------;
    Temp_sensor:
    jnb half_seconds_flag, Return
    lcall config_adc
    lcall Display_temp
    Return:
    ;-----------------------;
    ret

setup_reflow_page:
    PushButton(set_BUTTON, continue9)
    cpl tt_reflow_flag
    continue9:

    jb tt_reflow_flag, jump1
    ;jnb tt_reflow_flag, jump1
    lcall INC_DEC_Reflow_time
    ljmp display_reflow_page
    jump1:
    lcall INC_DEC_Reflow_temp


    display_reflow_page:
    Set_Cursor(1, 5)
    Display_BCD(reflow_temp+0)
    Set_Cursor(1, 7)
    Display_BCD(reflow_temp+1)
       
    
    Set_Cursor(1, 1)
    Send_Constant_String(#reflow_setup)
    Set_Cursor(1, 9)
    Send_Constant_String(#reflow_setup4)

    Set_Cursor(2, 1)
    Send_Constant_String(#reflow_setup2)
    Set_Cursor(2, 8)
    Send_Constant_String(#dots)
    Set_Cursor(2, 12)
    Send_Constant_String(#reflow_setup3)
    Set_Cursor(2, 9)
    Display_BCD(reflow_sec)
    Set_Cursor(2, 6)
    Display_BCD(reflow_min)

    ret
    INC_DEC_Reflow_time:

        PushButton(SETUP_SOAK_Button,check_decrement) ; setup soak is also used to increment 

        mov a, reflow_sec
        cjne a, #0x59, add_reflow_sec
        mov a, reflow_min
        add a, #0x01
        da a
        mov reflow_min, a
        clr a 
        ljmp Continue5
        add_reflow_sec:
        add a, #0x01
        da a ; Decimal adjust instruction.  Check datasheet for more details!
        Continue5:
        mov reflow_sec, a

        check_decrement:
        PushButton(Button_min, continue8)
        mov a, reflow_sec
        cjne a, #0x00, sub_reflow_sec
        clr a 
        ljmp Continue6
        sub_reflow_sec:
        add a, #0x99 ; add 99 reduces 1
        da a ; Decimal adjust instruction.  Check datasheet for more details!
        Continue6:
        mov reflow_sec, a
        continue8:
        ret
    INC_DEC_Reflow_temp:
        ;PushButton(SETUP_SOAK_Button,check_decrement2) ; setup soak is also used to increment 

            jb SETUP_SOAK_Button, check_decrement2  
                Wait_Milli_Seconds(#50)	
            jb SETUP_SOAK_Button, check_decrement2  
            loop_hold_inc:

            jnb SETUP_SOAK_Button, jump2
            Wait_Milli_Seconds(#100)
            jnb SETUP_SOAK_Button, jump2
            ljmp hold_done
            jump2:
            Set_Cursor(1, 5)
            Display_BCD(reflow_temp+0)
            Set_Cursor(1, 7)
            Display_BCD(reflow_temp+1)
            Wait_Milli_Seconds(#100)	
            mov a, reflow_temp+1
            add a, #0x01
            da a ; Decimal adjust instruction.  Check datasheet for more details!
            mov reflow_temp+1, a
            mov a, reflow_temp+1
            jnz INC_reflow_temp_done2
            mov a, reflow_temp+0
            add a, #0x01
            da a ; Decimal adjust instruction.  Check datasheet for more details!
            mov reflow_temp+0, a
            mov a, reflow_temp+1
            INC_reflow_temp_done2:
            
            ljmp loop_hold_inc
        hold_done:
        


        check_decrement2:
            jb Button_min, DEC_reflow_temp_done2  
                Wait_Milli_Seconds(#50)	
            jb Button_min, DEC_reflow_temp_done2  
            loop_hold_dec:

            jnb Button_min, jump3
            Wait_Milli_Seconds(#100)
            jnb Button_min, jump3
            ljmp DEC_reflow_temp_done2
            jump3:
            Set_Cursor(1, 5)
            Display_BCD(reflow_temp+0)
            Set_Cursor(1, 7)
            Display_BCD(reflow_temp+1)
            Wait_Milli_Seconds(#100)	
            mov a, reflow_temp+1
            add a, #0x99
            da a ; Decimal adjust instruction.  Check datasheet for more details!
            mov reflow_temp+1, a
            mov a, reflow_temp+1
            jnz INC_reflow_temp_done
            mov a, reflow_temp+0
            add a, #0x99
            da a ; Decimal adjust instruction.  Check datasheet for more details!
            mov reflow_temp+0, a
            mov a, reflow_temp+1
            INC_reflow_temp_done:
            
            ljmp loop_hold_dec

        DEC_reflow_temp_done2:
    

    ret
setup_soak_page:
    PushButton(set_BUTTON, continue11)
    cpl tt_flag_soak
    continue11:

    jb tt_flag_soak, jump4
    lcall INC_DEC_soak_time
    ljmp display_soak_page
    jump4:
    lcall INC_DEC_soak_temp


    display_soak_page:
    Set_Cursor(1, 5)
    Display_BCD(soak_temp+0)
    Set_Cursor(1, 7)
    Display_BCD(soak_temp+1)
       
    
    Set_Cursor(1, 1)
    Send_Constant_String(#soak_setup0)
    Set_Cursor(1, 9)
    Send_Constant_String(#soak_setup1)

    Set_Cursor(2, 1)
    Send_Constant_String(#soak_setup2)
    Set_Cursor(2, 8)
    Send_Constant_String(#dots)
    Set_Cursor(2, 12)
    Send_Constant_String(#soak_setup3)
    Set_Cursor(2, 9)
    Display_BCD(soak_sec)
    Set_Cursor(2, 6)
    Display_BCD(soak_min)
ret
    INC_DEC_soak_time:
    
        PushButton(SETUP_SOAK_Button,check_decrement_soak) ; setup soak is also used to increment 

        mov a, soak_sec
        cjne a, #0x59, add_soak_sec
        mov a, soak_min
        add a, #0x01
        da a
        mov soak_min, a
        clr a 
        ljmp Continue12
        add_soak_sec:
        add a, #0x01
        da a ; Decimal adjust instruction.  Check datasheet for more details!
        Continue12:
        mov soak_sec, a

        check_decrement_soak:
        PushButton(Button_min, continue13)
        mov a, soak_sec
        cjne a, #0x00, sub_soak_sec
        clr a 
        ljmp Continue14
        sub_soak_sec:
        add a, #0x99 ; add 99 reduces 1
        da a ; Decimal adjust instruction.  Check datasheet for more details!
        Continue14:
        mov soak_sec, a
        continue13:
        
        ret
    INC_DEC_soak_temp:
        
            jb SETUP_SOAK_Button, check_decrement2_soak  
                Wait_Milli_Seconds(#50)	
            jb SETUP_SOAK_Button, check_decrement2_soak  
            loop_hold_inc_soak:

            jnb SETUP_SOAK_Button, jump6
            Wait_Milli_Seconds(#100)
            jnb SETUP_SOAK_Button, jump6
            ljmp hold_done_soak
            jump6:
            Set_Cursor(1, 5)
            Display_BCD(soak_temp+0)
            Set_Cursor(1, 7)
            Display_BCD(soak_temp+1)
            Wait_Milli_Seconds(#200)	
            mov a, soak_temp+1
            add a, #0x01
            da a ; Decimal adjust instruction.  Check datasheet for more details!
            mov soak_temp+1, a
            mov a, soak_temp+1
            jnz INC_soak_temp_done2
            mov a, soak_temp+0
            add a, #0x01
            da a ; Decimal adjust instruction.  Check datasheet for more details!
            mov soak_temp+0, a
            mov a, soak_temp+1
            INC_soak_temp_done2:
            
            ljmp loop_hold_inc_soak
        hold_done_soak:
        


        check_decrement2_soak:
            jb Button_min, DEC_soak_temp_done2  
                Wait_Milli_Seconds(#50)	
            jb Button_min, DEC_soak_temp_done2  
            loop_hold_dec_soak:

            jnb Button_min, jump7
            Wait_Milli_Seconds(#100)
            jnb Button_min, jump7
            ljmp DEC_soak_temp_done2
            jump7:
            Set_Cursor(1, 5)
            Display_BCD(soak_temp+0)
            Set_Cursor(1, 7)
            Display_BCD(soak_temp+1)
            Wait_Milli_Seconds(#100)	
            mov a, soak_temp+1
            add a, #0x99
            da a ; Decimal adjust instruction.  Check datasheet for more details!
            mov soak_temp+1, a
            mov a, soak_temp+1
            jnz INC_soak_temp_done
            mov a, soak_temp+0
            add a, #0x99
            da a ; Decimal adjust instruction.  Check datasheet for more details!
            mov soak_temp+0, a
            mov a, soak_temp+1
            INC_soak_temp_done:
            
            ljmp loop_hold_dec_soak

        DEC_soak_temp_done2:
        ret
second_page:
    Set_Cursor(1, 1)
    Send_Constant_String(#soak_reflw)
    Set_Cursor(2, 1)
    Send_Constant_String(#nothing)
    ret

FSM_LCD:
        mov a, state_lcd


        ;----------------STATE 0------------------;
         home_state:
            cjne a, #0, soak_reflow_state
            PushButton(set_BUTTON,done_home2) 
            ;setb set_flag  
            mov state_lcd, #1
            ljmp done_home
            done_home2:
            ;clr set_flag
            lcall home_page
            done_home:
            ljmp Forever_done           
        ;------------------------------------------;
        
        ;----------------STATE 1-------------------;
        soak_reflow_state:
            cjne a, #1, setup_soak
            lcall second_page
          ;  Wait_Milli_Seconds(#50)
            lcall sec_counter ; prevent the timer to go over 60
            lcall min_counter
            PushButton(HOME_BUTTON,next_pushb) ; check if home button is pressed 
            mov state_lcd, #0
            next_pushb:
            PushButton(SETUP_SOAK_Button,next_pushb2) ; check if the the button to setup soak is pressed
            mov state_lcd, #2
            next_pushb2:
            PushButton(Button_min,done_soak) ; check if the buttion to setup the reflow was pressed 
            mov state_lcd, #3
            done_soak:
           ljmp Forever_done 
        ;------------------------------------------;

        ;-----------------STATE 2------------------;
        setup_soak: ; its actually set up reflow Im dumb
            cjne a, #2, setup_reflow
            lcall setup_reflow_page
          ;  Wait_Milli_Seconds(#50)
            lcall sec_counter ; prevent the timer to go over 60
            lcall min_counter
            PushButton(HOME_BUTTON,done_setup_soak) ; check if home button is pressed 
            mov state_lcd, #0
            done_setup_soak:
            ljmp Forever_done 
        ;------------------------------------------;

        ;----------------STATE 3-------------------;
        setup_reflow: ; its actually set up soak Im dumb
            cjne a, #3, FDP
            ljmp FDP2
            FDP:
            ljmp home_state
            FDP2:
            lcall setup_soak_page
            lcall sec_counter ; prevent the timer to go over 60
            lcall min_counter
            PushButton(HOME_BUTTON,done_setup_reflow) ; check if home button is pressed 
            mov state_lcd, #0
            done_setup_reflow:
            ljmp Forever_done 
        ;------------------------------------------;
        Forever_done:
ret
;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;
MainProgram:
        mov SP, #7FH ; Set the stack pointer to the begining of idata
        ; Initialization_LCD
        lcall LCD_4BIT
        ; Initialization_Termometer
        lcall INIT_SPI
        ; Initialization_timer
    
        lcall Timer0_Init
        ;lcall Timer1_Init
        lcall Timer2_Init
        setb EA   ; Enable Global interrupts
        setb half_seconds_flag
	    mov BCD_counter, #0x00
        
        mov reflow_sec, #0x00
        mov reflow_min, #0x00
        mov minutes, #0x00
        mov state_lcd, #0
        clr TR2_flag
        mov reflow_temp+0, #0x01
        mov reflow_temp+1, #0x50
        clr tt_reflow_flag
        mov soak_sec, #0x00
        mov soak_min, #0x00

        mov soak_temp+0, #0x01
        mov soak_temp+1, #0x50

        


    Forever: 
     
     lcall FSM_LCD
     ljmp Forever

END