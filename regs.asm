.model tiny
.code
org 100h

locals @@

; =============================================================================
; CONSTANTS
; =============================================================================

INTERRUPT_09_OFFSET         equ 36d
STRING_BUFFER_SIZE          equ 128d
VIDEO_MEMORY_START          equ 0B800h
SEGMENT_PREFIX_START        equ 80h

SCREEN_SIZE_X               equ 80d
SCREEN_SIZE_Y               equ 25d
START_X                     equ 40d
START_Y                     equ 12d

ROW_OFFSET                  equ 2d
LINE_OFFSET                 equ SCREEN_SIZE_X * ROW_OFFSET
PICTURE_OFFSET              equ (SCREEN_SIZE_X * START_Y + START_X) * ROW_OFFSET
SCREEN_BUFFER_SIZE          equ SCREEN_SIZE_X * SCREEN_SIZE_Y * ROW_OFFSET

ALT_PRESS                   equ 38h
ALT_RELEASE                 equ ALT_PRESS + 80h

REGISTER_COUNT              equ 7d
REG_ENTRY_SIZE              equ 4d
LABEL_LENGTH                equ 3d

HORIZONTAL_FRAME_SIDE       equ 0CDh
VERTICAL_FRAME_SIDE         equ 0BAh

UPPER_LEFT_FRAME_CORNER     equ 0C9h
UPPER_RIGHT_FRAME_CORNER    equ 0BBh
LOWER_LEFT_FRAME_CORNER     equ 0C8h
LOWER_RIGHT_FRAME_CORNER    equ 0BCh

SYMBOL_ATTRIBUTE            equ 00000111b
FRAME_ATTRIBUTE             equ 00001111b



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
        mov bx, INTERRUPT_09_OFFSET             ; Рассчитываем смещение 9 прерывания

        mov ax, es:[bx]        
        mov [Old09IntOffset], ax                ; Кладем в переменную старое смещение 9 прерывания
        mov ax, es:[bx + 2]   
        mov [Old09IntSegment], ax               ; Кладем в переменную старый сегмент 9 прерывания

        cli
        mov word ptr es:[bx], offset New09IntFunction     ; Загружаем смещение нового 9 прерывания
        mov ax, cs
        mov es:[bx + 2], ax                     ; Загружаем сегмент нового 9 прерывания
        sti

        mov ax, 3100h
        mov dx, offset EndOfProgram
        shr dx, 4
        inc dx

        int 21h

        ret
Main endp


New09IntFunction proc
    push ax
    in al, 60h
    cmp al, ALT_PRESS                                 ; Scan-код нажатой клавиши Alt
    je @@handle_press

    cmp al, ALT_RELEASE                           ; Scan-код отпущенной клавиши Alt
    je @@handle_release

    jmp @@std_exit

@@handle_press:
    cmp [IsVisible], 1d
    je @@hotkey_exit

    pop ax
    push ax
    call SaveScreen                                        ; Сохранение старого окна
    call PrintRegs
    mov [IsVisible], 1d
    jmp @@hotkey_exit 

@@handle_release:
    cmp [IsVisible], 0d
    je @@hotkey_exit

    call RestoreScreen                                       ; Возврат старого окна
    mov [IsVisible], 0d
    jmp @@hotkey_exit

@@hotkey_exit:
    in al, 61h
    mov ah, al 
    or al, 80h
    out 61h, al
    xchg ah, al
    out 61h, al

    mov al, 20h
    out 20h, al

    pop ax
    iret

@@std_exit:
    pop ax

    jmp dword ptr cs:[Old09IntOffset]
New09IntFunction endp


PrintRegs proc
    push ax bx cx dx si di bp ds es
    mov bp, sp

    mov ax, cs
    mov ds, ax

    mov ax, VIDEO_MEMORY_START
    mov es, ax

    mov bx, offset RegTable
    mov di, PICTURE_OFFSET
    mov cx, REGISTER_COUNT
    jmp @@entry

@@loop:
    mov si, bx
    call PrintString

    mov si, [bx + LABEL_LENGTH]
    and si, 00FFh
    mov ax, [bp + si]
    mov si, offset NumberBuffer

    add di, 2d * ROW_OFFSET
    call Itoa
    call PrintString
    sub di, 2d * ROW_OFFSET

    add di, LINE_OFFSET
    add bx, REG_ENTRY_SIZE
@@entry:
    loop @@loop

    pop es ds bp di si dx cx bx ax
    ret
PrintRegs endp


; es - сегмент
; di - смещение
; si - адрес начала буфера
PrintString proc
    push si di
    mov ah, 00001111b
    cld

@@loop:
    lodsb 
    cmp al, '$'
    je @@exit

    stosw    
    jmp @@loop
@@exit:
    pop di si
    ret
PrintString endp


; ax - hex число
; si - адрес начала буфера
Itoa proc
    push ax bx cx si

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

    mov bl, '$'
    mov [si], bl
    pop si cx bx ax 
    ret
Itoa endp


SaveScreen proc
    push si di ds es

    mov ax, VIDEO_MEMORY_START
    mov ds, ax
    xor si, si

    mov ax, cs
    mov es, ax
    mov di, offset ScreenBuffer

    mov cx, SCREEN_BUFFER_SIZE
    cld
    rep movsb

    pop es ds di si
    ret
SaveScreen endp


RestoreScreen proc
    push si di ds es

    mov ax, cs
    mov ds, ax
    mov si, offset ScreenBuffer

    mov ax, VIDEO_MEMORY_START
    mov es, ax
    xor di, di

    mov cx, SCREEN_BUFFER_SIZE
    cld 
    rep movsb

    pop es ds di si
    ret
RestoreScreen endp


; -----------------------------------------------------------------------------
; PROC: ClearScreen
; -----------------------------------------------------------------------------
; Описание: 
;       Очищает терминал цветом из bh
; Входные параметры:
;       Нет
; Выходные данные:
;       Нет
; Портящиеся регистры:
;       ax, cx, dx
; -----------------------------------------------------------------------------
ClearScreen proc
        push bp
        mov bp, sp
        push bx

        mov ax, 0600h                           ; 06 - Номер функции и 00 - очистить все окно
        mov bh, SYMBOL_ATTRIBUTE                ; Атрибут заполнения
        mov cx, 0000h                           ; Верхний левый угол (Line:0, Row:0)
        mov dx, 184Fh                           ; Нижний правый угол (Line:24, Row:79)
        int 10h

        pop bx
        pop bp
        ret
ClearScreen endp


; -----------------------------------------------------------------------------
; PROC: ParseArguments
; -----------------------------------------------------------------------------
; Описание: 
;       Обрабатывает строку аргументов из командной строки. Изменяет содержимое рамки через массив FrameChars
; Входные параметры:
;       Нет
; Выходные данные:
;       Нет (Изменяет содержимое массива FrameChars)
; Портящиеся регистры:
;       ax, cx
; -----------------------------------------------------------------------------
ParseArguments proc
        push bp                                 ; Сохраняем старый bp
        mov bp, sp                              ; Создаем кадр стека
        push si di

        mov si, SEGMENT_PREFIX_START            ; Загружаем адрес длины строки аргументов
        mov cl, [si]                            ; Читаем длину
        cmp cl, 1                               ; Если длина 0 или 1 байт, то полезных данных (со 2 байта) нет
        jbe @@exit                              ; Выходим

        mov si, SEGMENT_PREFIX_START + 2d       ; Стартуем со 2 символа
        lea di, FrameChars                      ; Указатель на наш массив
        mov cx, FRAME_CHARS_COUNT               ; Читаем максимум 6 символов

@@loop:
        mov al, [si]                            ; Читаем символ из аргументов
        cmp al, 0Dh                             ; Сравниваем символ с кодом возврата каретки
        je @@exit                               ; Если строка кончилась раньше времени - выход

        cmp al, 20h                             ; Проверяем на пробел
        je @@skip_write                         ; Если пробел - пропускаем запись (оставляем старое значение)

        mov [di], al                            ; Если не пробел - пишем в массив
@@skip_write:
        inc si                                  ; Следующий символ в командной строке
        inc di                                  ; Следующая ячейка в нашем массиве
        loop @@loop                             ; Повторяем цикл

@@exit:
        pop di si
        pop bp                                  ; Восстанавливаем старый bp
        ret                                     ; Возвращаемся и очищаем стек
ParseArguments endp


; -----------------------------------------------------------------------------
; PROC: ReadString (Pascal)
; -----------------------------------------------------------------------------
; Описание: 
;       С помощью буферизированного ввода помещает пользовательский ввод в буфер
; Входные параметры:
;       [bp + 4] (Ptr) - Указатель на буфер строки
; Выходные данные:
;       Нет (Помещает пользовательский ввод в буфер)
; Портящиеся регистры:
;       ax, dx
; -----------------------------------------------------------------------------
ReadString proc
        push bp                                 ; Сохраняем старый bp
        mov bp, sp                              ; Создаем кадр стека

        mov dx, [bp + 4]                        ; Загружаем адрес буфера
        mov ah, 0Ah
        int 21h                                 ; Системный вызов буферизированного ввода 

        pop bp                                  ; Восстанавливаем старый bp
        ret 2                                   ; Возвращаемся и очищаем стек
ReadString endp


; -----------------------------------------------------------------------------
; PROC: DrawPicture (Cdecl)
; -----------------------------------------------------------------------------
; Описание: 
;       Организует вывод рамки и текста в видеопамять, управляя координатами и атрибутами
; Входные параметры:
;       [bp + 8] (Word) - Атрибут рамки
;       [bp + 6] (Word) - Атрибут текста
;       [bp + 4] (Ptr)  - Указатель на буфер строки
; Выходные данные:
;       Нет (Рисует сразу в видеопамять)
; Портящиеся регистры:
;       ax
; -----------------------------------------------------------------------------
DrawPicture proc
        push bp                                 ; Сохраняем старый bp
        mov bp, sp                              ; Создаем кадр стека
        push bx 

        mov bx, [bp + 4]                        ; Сохраняем указатель на буфер

        push bx                                 ; Передаем указатель на буфер в функцию
        push [bp + 6]                           ; Передаем аттрибут символа в функцию
        call PrintText

        xor ax, ax
        mov al, [bx + 1]                        ; Записываем длину записанной в буфер строки

        push [bp + 8]                           ; Передаем аттрибут символа рамки
        push ax
        call PrintFrame

        pop bx
        pop bp                                  ; Восстанавливаем старый bp
        ret                                     ; Возвращаемся и очищаем стек
DrawPicture endp


; -----------------------------------------------------------------------------
; PROC: PrintText (Pascal)
; -----------------------------------------------------------------------------
; Описание: 
;       Выводит текст из буфера в видеопамять
; Входные параметры:
;       [bp + 6] (Ptr)  - Указатель на буфер строки
;       [bp + 4] (Word) - Атрибут текста
; Выходные данные:
;       Нет (Рисует сразу в видеопамять)
; Портящиеся регистры:
;       ax, cx, dx
; -----------------------------------------------------------------------------
PrintText proc
        push bp                                 ; Сохраняем старый bp
        mov bp, sp                              ; Создаем кадр стека
        push bx si di es
        
        mov ax, VIDEO_MEMORY_START              ; Устанавливаем начало сегмента видеопамяти
        mov es, ax	                        ; Загружаем указатель на начало области видеопамяти
        mov di, PICTURE_OFFSET                  ; Загружаем смещение для вывода текста

        mov bx, [bp + 6]                        ; Загружаем указатель на начало буфера
        mov dx, [bp + 4]                        ; Загружаем аттрибут символа

        xor cx, cx                              ; Обнуляем cx
        lea si, [bx + 2]                        ; Загружаем адрес начала строки 
        mov cl, [bx + 1]                        ; Загружаем количество символов в строке

        jcxz @@exit                             ; Если cx > 0, то заходим в цикл
@@loop: 
        mov al, [si]                            
        mov ah, dl
        mov es:[di], ax                         ; Загружаем в видеопамять символ и его аттрибут

        inc si                                  ; Смещаемся к следующему символу строки
        add di, ROW_OFFSET                      ; Смещаемся на 2 байта в видеопамяти
        loop @@loop                             ; Повторяем вывод символа

@@exit: 
        pop es di si bx
        pop bp                                  ; Восстанавливаем старый bp
        ret 4                                   ; Возвращаемся и очищаем стек
PrintText endp


; -----------------------------------------------------------------------------
; PROC: PrintFrame (Pascal)
; -----------------------------------------------------------------------------
; Описание: 
;       Организует вывод частей рамки в видеопамять
; Входные параметры:
;       [bp + 6] (Word) - Атрибут рамки
;       [bp + 4] (Word) - Длина текста
; Выходные данные:
;       Нет (Рисует сразу в видеопамять)
; Портящиеся регистры:
;       Нет
; -----------------------------------------------------------------------------
PrintFrame proc
        push bp                                 ; Сохраняем старый bp
        mov bp, sp                              ; Создаем кадр стека
        push si di

        mov si, [bp + 6]                        ; Загружаем аттрибут символа рамки
        mov di, [bp + 4]                        ; Загружаем ширину текста внутри рамки

        push si
        push di
        call PrintVerticalFrameSide

        push si
        push di
        call PrintHorizontalFrameSide

        push si
        push di
        call printFrameCorners

        pop di si
        pop bp                                  ; Восстанавливаем старый bp
        ret 4                                   ; Возвращаемся и очищаем стек
PrintFrame endp


; -----------------------------------------------------------------------------
; PROC: PrintVerticalFrameSide (Pascal)
; -----------------------------------------------------------------------------
; Описание: 
;       Выводит вертикальные части рамки в видеопамять
; Входные параметры:
;       [bp + 6] (Word) - Атрибут рамки
;       [bp + 4] (Word) - Длина текста
; Выходные данные:
;       Нет (Рисует сразу в видеопамять)
; Портящиеся регистры:
;       ax
; -----------------------------------------------------------------------------
PrintVerticalFrameSide proc
        push bp                                 ; Сохраняем старый bp
        mov bp, sp                              ; Создаем кадр стека
        push bx si di

        mov si, [bp + 6]                        ; Загружаем аттрибут символа рамки
        mov di, [bp + 4]                        ; Загружаем ширину текста внутри рамки

        xor bx, bx
        mov bl, [FrameChars + I_VERT]           ; Загружаем символ вертикальной части рамки
        push bx
        push si
        push PICTURE_OFFSET - ROW_OFFSET
        push LINE_OFFSET
        push 1d                                
        call PrintSymbolSequence                ; Печатаем часть рамки над текстом  

        mov ax, ROW_OFFSET
        mul di
        add ax, PICTURE_OFFSET                  ; Находим смещение для правой стороны рамки

        xor bx, bx
        mov bl, [FrameChars + I_VERT]           ; Загружаем символ вертикальной части рамки
        push bx
        push si
        push ax
        push LINE_OFFSET
        push 1d
        call PrintSymbolSequence                ; Печатаем часть рамки под текстом

        pop di si bx
        pop bp
        ret 4
PrintVerticalFrameSide endp


; -----------------------------------------------------------------------------
; PROC: PrintHorizontalFrameSide (Pascal)
; -----------------------------------------------------------------------------
; Описание: 
;       Выводит горизонтальные части рамки в видеопамять
; Входные параметры:
;       [bp + 6] (Word) - Атрибут рамки
;       [bp + 4] (Word) - Длина текста
; Выходные данные:
;       Нет (Рисует сразу в видеопамять)
; Портящиеся регистры:
;       ax
; -----------------------------------------------------------------------------
PrintHorizontalFrameSide proc
        push bp                                 ; Сохраняем старый bp
        mov bp, sp                              ; Создаем кадр стека
        push si di

        mov si, [bp + 6]                        ; Загружаем аттрибут символа рамки
        mov di, [bp + 4]                        ; Загружаем ширину текста внутри рамки

        xor ax, ax
        mov al, [FrameChars + I_HORIZ]          ; Загружаем символ горизонтальной части рамки
        push ax
        push si
        push PICTURE_OFFSET - LINE_OFFSET
        push ROW_OFFSET
        push di
        call PrintSymbolSequence                ; Печатаем часть рамки над текстом  

        xor ax, ax
        mov al, [FrameChars + I_HORIZ]          ; Загружаем символ горизонтальной части рамки
        push ax
        push si
        push PICTURE_OFFSET + LINE_OFFSET
        push ROW_OFFSET
        push di
        call PrintSymbolSequence                ; Печатаем часть рамки под текстом

        pop di si
        pop bp
        ret 4

PrintHorizontalFrameSide endp


; -----------------------------------------------------------------------------
; PROC: PrintFrameCorners (Pascal)
; -----------------------------------------------------------------------------
; Описание: 
;       Выводит угловые части рамки в видеопамять
; Входные параметры:
;       [bp + 6] (Word) - Атрибут рамки
;       [bp + 4] (Word) - Длина текста
; Выходные данные:
;       Нет (Рисует сразу в видеопамять)
; Портящиеся регистры:
;       ax
; -----------------------------------------------------------------------------
PrintFrameCorners proc
        push bp                                 ; Сохраняем старый bp
        mov bp, sp                              ; Создаем кадр стека
        push bx si di

        mov si, [bp + 6]                        ; Загружаем аттрибут символа рамки
        mov di, [bp + 4]                        ; Загружаем ширину текста внутри рамки

        xor ax, ax
        mov al, [FrameChars + I_UP_LEFT]        ; Загружаем символ верхнего левого угла рамки
        push ax
        push si
        push PICTURE_OFFSET - LINE_OFFSET - ROW_OFFSET
        call PrintSymbol

        xor ax, ax
        mov al, [FrameChars + I_LOW_LEFT]       ; Загружаем символ нижнего левого угла рамки
        push ax
        push si
        push PICTURE_OFFSET + LINE_OFFSET - ROW_OFFSET
        call PrintSymbol

        mov ax, ROW_OFFSET
        mul di
        add ax, PICTURE_OFFSET - LINE_OFFSET    ; Находим смещение для правого верхнего угла рамки

        xor bx, bx
        mov bl, [FrameChars + I_UP_RIGHT]       ; Загружаем символ верхнего правого угла рамки
        push bx
        push si
        push ax
        call PrintSymbol 

        mov ax, ROW_OFFSET
        mul di
        add ax, PICTURE_OFFSET + LINE_OFFSET    ; Находим смещение для правого нижнего угла рамки

        xor bx, bx
        mov bl, [FrameChars + I_LOW_RIGHT]      ; Загружаем символ нижнего правого угла рамки
        push bx
        push si
        push ax
        call PrintSymbol

        pop di si bx
        pop bp
        ret 4
PrintFrameCorners endp 


; -----------------------------------------------------------------------------
; PROC: PrintSymbolSequence (Pascal)
; -----------------------------------------------------------------------------
; Описание: 
;       Выводит в видеопамять последовательность символов указанной длины с некоторым шагом
; Входные параметры:
;       [bp + 12] (Word) - Символ
;       [bp + 10] (Word) - Атрибут для символа
;       [bp + 8]  (Ptr)  - Смещение относительно начала области видеопамяти
;       [bp + 6]  (Word) - Шаг итерирования
;       [bp + 4]  (Word) - Количество итераций
; Выходные данные:
;       Нет (Рисует сразу в видеопамять)
; Портящиеся регистры:
;       ax, cx
; -----------------------------------------------------------------------------
PrintSymbolSequence proc
        push bp                                 ; Сохраняем старый bp
        mov bp, sp                              ; Создаем кадр стека
        push si di es

        mov ax, VIDEO_MEMORY_START              
        mov es, ax                              ; Загружаем указатель на начало области видеопамяти

        mov al, [bp + 12]                       ; Загружаем символ рамки
        mov ah, [bp + 10]                       ; Загружаем аттрибут символа рамки
        mov di, [bp + 8]                        ; Загружаем начальное смещение в области видеопамяти
        mov si, [bp + 6]                        ; Загружаем шаг увеличения адреса при итерации
        mov cx, [bp + 4]                        ; Загружаем количество итераций цикла 

        jcxz @@exit
@@loop:
        mov es:[di], ax                         ; Загружаем в видеопамять символ и его аттрибут
        add di, si                              ; Изменяем смещение на заданную величину si
        loop @@loop                             ; Повторяем итерацию
@@exit:

        pop es di si
        pop bp 
        ret 10 
PrintSymbolSequence endp


; -----------------------------------------------------------------------------
; PROC: PrintSymbol (Pascal)
; -----------------------------------------------------------------------------
; Описание: 
;       Выводит в видеопамять последовательность символов указанной длины с некоторым шагом
; Входные параметры:
;       [bp + 8] (Word) - Символ
;       [bp + 6] (Word) - Атрибут для символа
;       [bp + 4] (Ptr)  - Смещение относительно начала области видеопамяти
; Выходные данные:
;       Нет (Рисует сразу в видеопамять)
; Портящиеся регистры:
;       ax
; -----------------------------------------------------------------------------
PrintSymbol proc 
        push bp                                 ; Сохраняем старый bp
        mov bp, sp                              ; Создаем кадр стека
        push di es

        mov ax, VIDEO_MEMORY_START
        mov es, ax                              ; Загружаем указатель на начало области видеопамяти

        mov al, [bp + 8]                        ; Загружаем символ рамки
        mov ah, [bp + 6]                        ; Загружаем аттрибут символа рамки
        mov di, [bp + 4]                        ; Загружаем начальное смещение в области видеопамяти

        mov es:[di], ax                         ; Загружаем в видеопамять символ и его аттрибут

        pop es di
        pop bp 
        ret 6
PrintSymbol endp 


; =============================================================================
; VARIABLES
; =============================================================================

Old09IntOffset      dw ?
Old09IntSegment     dw ?

IsVisible           db ?

RegTable:
    db 'AX$', 16d
    db 'BX$', 14d
    db 'CX$', 12d
    db 'DX$', 10d
    db 'SI$', 8d
    db 'DI$', 6d
    db 'BP$', 4d

NumberBuffer        db 4 DUP(?), '$'
ScreenBuffer        db SCREEN_BUFFER_SIZE DUP(?)

; Символы, использующиеся в рамке (Порядок важен)
; 0: Левый верхний, 1: Горизонталь, 2: Правый верхний
; 3: Вертикаль, 4: Левый нижний, 5: Правый нижний
FrameChars db UPPER_LEFT_FRAME_CORNER,  \  ; index - [0]
              HORIZONTAL_FRAME_SIDE,    \  ; index - [1]
              UPPER_RIGHT_FRAME_CORNER, \  ; index - [2]
              VERTICAL_FRAME_SIDE,      \  ; index - [3]
              LOWER_LEFT_FRAME_CORNER,  \  ; index - [4]
              LOWER_RIGHT_FRAME_CORNER     ; index - [5]

FRAME_CHARS_COUNT       equ $ - FrameChars
I_UP_LEFT               equ 0d 
I_HORIZ                 equ 1d 
I_UP_RIGHT              equ 2d 
I_VERT                  equ 3d 
I_LOW_LEFT              equ 4d
I_LOW_RIGHT             equ 5d


EndOfProgram:

end Start