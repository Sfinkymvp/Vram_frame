.286
.model tiny
.code 
org 100h

Start:  
        push 0
        pop es  
        
        mov bx, 4d * 09h 
        cli
        mov es:[bx], offset New09       ; Записываем в младшие два байта смещение отн. сегмента cs
        ; <--------------------------------------????? UB, если вызвать int без cli/sti 
        mov ax, cs
        mov es:[bx+2], ax               ; Записываем значение сегмента cs
        sti  

        mov ax, 3100h                   ; функция 21 прерывания, позволяющая оставить код программы в памяти
        mov dx, offset EOPPP            ; Находим длину кода в байтах
        shr dx, 4
        inc dx  
        int 21h

New09 proc
        push ax bx es

        push 0b800h
        pop es  
        mov bx, (80d * 5 + 20d) * 2d
        mov ah, 4eh

        in al, 60h
        mov es:[bx], ax

        in al, 61h
        or al, 80h
        out 61h, al
        and al, not 80h
        out 61h, al

        mov al, 20h
        out 20h, al

        pop es bx ax
        iret
New09 endp

EOPPP:

end Start