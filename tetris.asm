; ----------------------------------------------------
; x86 Tetris in 512 bytes - GNU General Public License v3.0
; Welcome. I tried to make this easy to follow even for 
; people new to assembly, so there are a lot of comments
; Enjoy the code
; ----------------------------------------------------

; NOTE: far from complete implemenation but its only boot sector size
; I will try to implement more later

; 16 bit rm bc obviously lol
bits 16
org 0x7C00

; if i were good i would make constants here


; set up stack, data segment, and call main
start:
    ; set video mode 13h
    mov ax, 0013h
    int 10h
    ; IMPORTANT: we will be manipulating the framebuffer directly, so we won't be using BIOS calls to draw anything, but we still need to set the video mode to get the 320x200 256 color mode

    ; ES = A000h (framebuffer)
    mov ax, 0A000h  
    mov es, ax

    ; DS = CS
    push cs
    pop ds   

    mov si, board

; use PIT to get a random number for the piece selection
; pit means programmable interval timer, a hardware timer that can be used for various purposes, including generating random numbers. 
new_piece:
    ; random piece from PIT
    in al, 40h   ; 40h is the channel 0 for pit
    and al, 7    
    cmp al, 7
    jne ok
    dec al
; set bx to the piece data, dl/dh to the initial position, and cl to the color
ok: ; were good to go with the piece number in al
    mov bx, [pieces+ax*2] ; each piece is 2 bytes (a word), so we multiply by 2 to get the correct offset

    mov dl, 3      ; X
    xor dh, dh     ; Y
    mov cl, al
    inc cl         ; color (we want 1-7, not 0-6)
; ---------------------------------------------------

drop_loop:
    ; draw the piece
    push bx
    push dx

    mov di, dx         ; di = yx
    mov ax, dx
    xor ah, ah
    mov al, dh         ; y

    ; y*320 = y*256 + y*64
    mov bx, ax
    shl ax, 8
    shl bx, 6
    add ax, bx

    mov bl, dl         ; x
    add ax, bx
    mov di, ax

    mov bp, 4          ; 4 rows

; draw loop ----------------------------------------
row_loop:              
    push bp
    mov bp, 4          ; 4 cols
col_loop:
    shl bx,1
    jnc skip_pixel
    mov [es:di], cl   ; es:di = color index, so we set it to the piece color if there is a pixel in the piece bitmap
skip_pixel: ; if there is no pixel, we just skip drawing and move on to the next one
    inc di
    dec bp
    jnz col_loop

    ; keep in mind res is 320x200 so pixels are pretty big
    add di, 320-4   ; offset by 4 pixels to get to the next row (320 pixels per row, minus the 4 we just drew)
    pop bp
    dec bp
    jnz row_loop

    pop dx      ; get rigister values back for next loop
    pop bx

    ; simple delay loop
    mov cx, 20000 ; 20000 is literally random 
; ---------------------------------------------------
delay:
    loop delay
    ; erase the piece by drawing it again in color 0
    push cx
    xor cl, cl
    jmp short drop_loop_draw_erase

; draw and erase (basically same logic)
drop_loop_draw_erase:
    ; same draw logic reused
    push bx
    push dx

    mov di, dx
    mov ax, dx
    xor ah, ah
    mov al, dh

    mov bx, ax
    shl ax, 8   ; shift y * 256
    shl bx, 6   ; shift y * 64
    add ax, bx  ; add them together to get y*320
    mov bl, dl  ; move x into bl
    add ax, bx
    mov di, ax

    mov bp, 4
; erase row
er_row:
    push bp
    mov bp, 4
er_col:
    shl bx,1
    jnc er_skip
    mov [es:di], cl
er_skip:                ; same as before, but instead of drawing the piece color, we draw color 0 to erase it
    inc di
    dec bp
    jnz er_col
    add di, 320-4
    pop bp
    dec bp
    jnz er_row

    pop dx
    pop bx
    pop cx

    ; move the piece down by 1 every loop
    ; test move down
    mov al, dh
    inc al              ; test Y = dh+1
    call collide
    jc lock_piece       ; if carry set = collision, lock piece in place and spawn new one
    inc dh              ; commit move
    jmp drop_loop       ; repeat for next frame
; -------------------------------------------------
; inputs:
;BX = piece bitmap
; DL = x (low 4 bits of position, since pieces are max 4 wide)
; DH = y (high 4 bits of position, since pieces are max 4 tall)
; AL = test y
; returns:
;   CF = 1 if collision
collide:
    push bx            ; save bx (piece data) and dx (position) since we'll be modifying them
    push dx             
    push si            ; save si since we'll be using it to access the board data

    mov si, board     ; point to board data
    mov dh, al        ; use test Y
    mov cx, 4         ; 4 rows

.next_row:
    push cx           ; save row count for next iteration

    mov ax, bx        ; get piece row data
    and ax, 0F000h    ; top 4 bits
    jz .skip_row      ; empty row, goto skip

    shr ax, 12        ; now 0–15
    mov cl, dl
    shl ax, cl        ; shift into position

    cmp dh, 20        ; if y is off the bottom of the board, its a collision
    jae .collision    ; jump if above or equal (unsigned compare, since dh is unsigned)

    mov di, dh         ; di = y
    shl di, 1          ; word index
    mov dx, [si+di]    ; get board row data

    test dx, ax        ; if any bits overlap, its a collision
    jnz .collision     ; jump if not zero (i.e. if there is a collision)

.skip_row:             ; no collision for this row, check next
    shl bx, 4         ; next piece row
    inc dh            ; move down one row
    pop cx            ; restore row count for next iteration
    loop .next_row    ; if we get here, there were no collisions, so clear carry and return

    clc 
    jmp .done

.collision:
    stc              ; set carry flag to indicate collision
    pop cx           ; restore registers before returning

.done:              ; restore registers and return
    pop si
    pop dx
    pop bx
    ret
; ---------------------------------------------------

lock_piece:                ; make the piece stay solid
    push bx                 ; save bx (piece data) and dx (position) since we'll be modifying them
    push dx
    push si

    mov si, board       ; point to board data
    mov cx, 4           ; 4 rows in a piece

.lock_row:              ; loop for each row of the piece
    push cx

    mov ax, bx       ; get piece row data
    and ax, 0F000h  ; top 4 bits
    jz .next_lock   ; empty row, skip

    shr ax, 12      ; now 0–15
    mov cl, dl     ; get x position
    shl ax, cl    ; ax now has the piece row bits in the correct position for the board

    mov di, dh    ; di = y position
    shl di, 1    ; word index (y*2)
    or [si+di], ax   ; lock the piece into the board by ORing the bits
                     ; oring them works because the piece bits are 0 where there is no piece, so it won't affect the existing board data except to set the bits where the piece is

.next_lock:
    shl bx, 4
    inc dh
    pop cx
    loop .lock_row

    pop si      ; restore registers before returning
    pop dx
    pop bx
    jmp new_piece
; -------------------------------------------------


; DATA

; using dw (word) to store piece data, since db (byte) would be too small for 4x4 pieces
; its also more efficent rather than using multiple bytes and bit manipulation to get the piece data
pieces:
    dw 0F00h,6600h,0720h,0360h,0630h,0470h,0270h  ; each peice
board:
    times 20 dw 0                                  ; board as 20 words (40 bytes)

; boot signature and padding to 512 bytes
times 510-($-$$) db 0

dw 0AA55h
