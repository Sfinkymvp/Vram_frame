.model tiny
.code
org 100h

locals @@

; =============================================================================
; CONSTANTS
; =============================================================================

; =============================================================================
; ENTRY POINT
; =============================================================================
Start:
        call Main

        mov ax, 4C00h
        int 21h


Main proc
;        xor ax, ax   
;        mov es, ax                              ; Рассчитываем сегмент 9 прерывания
;        mov bx, 4d * 9d                         ; Рассчитываем смещение 9 прерывания

;        push es:[bx]                            ; Кладем в стек старое смещение 9 прерывания
;        push es:[bx + 2]                        ; Кладем в стек старый сегмент 9 прерывания

;        cli
;        mov word ptr es:[bx], offset NewInt     ; Загружаем смещение нового 9 прерывания
;        mov ax, cs
;        mov es:[bx + 2],                        ; Загружаем сегмент нового 9 прерывания
;        sti

;        mov ax, 3100h
;        mov dx, offset EndOfProgram
;        shr dx, 4
;        inc dx

        call NewInt

        ret
Main endp


NewInt proc
    mov si, offset NumberBuffer
    call Itoa

    mov ax, 0B800h
    mov es, ax
    mov di, (80d * 14d + 40d) * 2d
    mov si, offset AxBuffer
    call PrintString

    mov si, offset NumberBuffer
    call PrintString

    ret
NewInt endp


; es - сегмент
; di - смещение
; si - адрес начала буфера
PrintString proc
    push si
    mov ah, 00001111b
    cld

@@loop:
    lodsb 
    cmp al, '$'
    je @@exit

    stosw    
    loop @@loop
@@exit:
    pop si
    ret
PrintString endp


; ax - hex число
; si - адрес начала буфера
Itoa proc
    push bx si

    mov cx, 4d

@@loop:
    rol ax, 4
    mov bl, al
    and bl, 0Fh

    cmp bl, 16d
    jae @@end
    cmp bl, 10d
    jae @@hex_chars
    add bl, '0'
    jmp @@end

@@hex_chars:
    add bl, 'A' - 10d

@@end:
    mov [si], bl
    inc si
    loop @@loop

    pop si bx
    ret
Itoa endp


AxBuffer     db 'AX = $'
NumberBuffer db 4 DUP(?), '$'

EndOfProgram:

end Start