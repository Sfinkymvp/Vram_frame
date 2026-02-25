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
        xor ax, ax   
        mov es, ax                              ; Рассчитываем сегмент 9 прерывания
        mov bx, 4d * 9d                         ; Рассчитываем смещение 9 прерывания

        mov ax, es:[bx]        
        mov [Old09IntOffset], ax                ; Кладем в переменную старое смещение 9 прерывания
        mov ax, es:[bx + 2]   
        mov [Old09IntSegment], ax               ; Кладем в переменную старый сегмент 9 прерывания

        cli
        mov word ptr es:[bx], offset NewInt     ; Загружаем смещение нового 9 прерывания
        mov ax, cs
        mov es:[bx + 2], ax                     ; Загружаем сегмент нового 9 прерывания
        sti

        mov ax, 3100h
        mov dx, offset EndOfProgram
        shr dx, 4
        inc dx

        int 21h

;        mov ax, 0ABCDh
;        call NewInt

        ret
Main endp


NewInt proc
    push ax
    in al, 60h
    cmp al, 38h                                 ; Alt
    jne @@skipPrinting

    push ax bx cx dx si di bp sp ds es
    mov bp, sp

    mov ax, cs 
    mov ds, ax 

    mov ax, [bp + 14]
    mov si, offset NumberBuffer
    call Itoa

    mov ax, 0B800h
    mov es, ax
    mov di, (80d * 14d + 40d) * 2d
    mov si, offset AxBuffer
    call PrintString

    mov ax, 0ABCDh
    mov si, offset NumberBuffer
    call PrintString

    pop es ds sp bp di si dx cx bx ax

@@skipPrinting:
    pop ax
    jmp dword ptr cs:[Old09IntOffset]
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
    jmp @@loop
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
    jae @@hexChars
    add bl, '0'
    jmp @@end

@@hexChars:
    add bl, 'A' - 10d

@@end:
    mov [si], bl
    inc si
    loop @@loop

    pop si bx
    ret
Itoa endp


Old09IntOffset      dw ?
Old09IntSegment     dw ?
AxBuffer            db 'AX = $'
NumberBuffer        db 4 DUP(?), '$'

EndOfProgram:

end Start