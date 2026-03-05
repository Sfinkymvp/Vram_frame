.model tiny
.code
org 100h

locals @@

; =============================================================================
; CONSTANTS
; =============================================================================

; Смещение 09h прерывания в сегменте 0000
INTERRUPT_09_OFFSET         equ 36d
; Сегмент видеопамяти
VIDEO_MEMORY_START          equ 0B800h
; Смещение начала аргументов командной строки в code segment
SEGMENT_PREFIX_START        equ 80h

; Горизонтальный размер окна
SCREEN_SIZE_X               equ 80d
; Вертикальный размер окна
SCREEN_SIZE_Y               equ 25d
; Горизонтальное смещение текста (Без учета рамки)(Левая граница)
START_X                     equ 40d
; Вертикальное смещение текста (Без учета рамки)(Верхняя граница)
START_Y                     equ 5d

; В видеопамяти на 1 знакоместо приходится байт символа + байт аттрибута символа 
; Соответственно на знакоместо приходится 2 байта 
ROW_OFFSET                  equ 2d
; Смещение между двумя соседними по вертикали знакоместами
LINE_OFFSET                 equ SCREEN_SIZE_X * ROW_OFFSET
; Смещение начала текста (Без учета рамки)(Левый верхний угол)
PICTURE_OFFSET              equ (SCREEN_SIZE_X * START_Y + START_X) * ROW_OFFSET
; Размер окна 
SCREEN_BUFFER_SIZE          equ SCREEN_SIZE_X * SCREEN_SIZE_Y * ROW_OFFSET

; Scan-код нажатой клавиши Alt
ALT_PRESS                   equ 38h
; Scan-код отпущенной клавиши Alt
ALT_RELEASE                 equ ALT_PRESS + 80h

; Установленный флаг
FLAG_TRUE                   equ 1d
; Неустановленный флаг
FLAG_FALSE                  equ 0d

; Размер записи в таблице
REG_ENTRY_SIZE              equ 4d
; Размер строки с именем регистра
LABEL_STRING_LEN            equ 3d
; Размер строки с знаком равенства
EQUALS_SIGN_STRING_LEN      equ 4d
; Высота текста
TEXT_HEIGTH                 equ 14d
; Ширина текста 
TEXT_WIDTH                  equ (LABEL_STRING_LEN - 1d) + (EQUALS_SIGN_STRING_LEN - 1d) + 4d

; Используемый атрибут символа текста
SYMBOL_ATTRIBUTE            equ 00011111b
; Используемый атрибут символа рамки
FRAME_ATTRIBUTE             equ 00010111b


; =============================================================================
; ENTRY POINT
; =============================================================================
Start:
        call Main

        mov ax, 4C00h                                   
        int 21h                                 ; Завершение работы программы


; -----------------------------------------------------------------------------
; PROC: Main
; -----------------------------------------------------------------------------
; Описание:
;       Заменяет стандартную функцию 09h прерывания модифицированной.
; Входные параметры:
;       Нет
; Выходные параметры:
;       Нет
; Портящиеся регистры:
;       ax, bx, es
; -----------------------------------------------------------------------------
Main proc
        call ParseArguments

        xor ax, ax   
        mov es, ax                              ; Рассчитываем сегмент 09h прерывания
        mov bx, INTERRUPT_09_OFFSET             ; Рассчитываем смещение 09h прерывания

        mov ax, es:[bx]        
        mov [Old09IntOffset], ax                ; Кладем в переменную старое смещение 09h прерывания
        mov ax, es:[bx + 2]   
        mov [Old09IntSegment], ax               ; Кладем в переменную старый сегмент 09h прерывания

        cli
        mov word ptr es:[bx], offset New09IntFunction     ; Загружаем смещение нового 09h прерывания
        mov ax, cs
        mov es:[bx + 2], ax                     ; Загружаем сегмент нового 09h прерывания
        sti

        mov ax, 3100h
        mov dx, offset EndOfProgram
        shr dx, 4                               ; Находим размер в параграфах (16 байт) кода программы
        inc dx                                  ; Резервный параграф (против проблемы округления)

        int 21h                                 ; Резидентное завершение программы

        ret
Main endp


; -----------------------------------------------------------------------------
; PROC: New09IntFunction
; -----------------------------------------------------------------------------
; Описание:
;       Замена для стандартной функции 09h прерывания. Изменяет поведение 
;       только клавиши alt. При ее нажатии выводит рамку с значениями 
;       регистров, а при отпускании возвращает прежнее содержимое экрана.
;       Препятствует работе любых программ, требующих нажатия клавиши alt. 
; Входные параметры:
;       Нет
; Выходные параметры:
;       Нет
; Портящиеся регистры:
;       Нет 
; -----------------------------------------------------------------------------
New09IntFunction proc
    push ax
    in al, 60h                                  ; Читаем 60h порт
    cmp al, ALT_PRESS                      
    je @@handle_press                           ; Прыгаем при нажатой клавише Alt

    cmp al, ALT_RELEASE                          
    je @@handle_release                         ; Прыгаем при отпущенной клавише Alt

    jmp @@std_exit                              ; Прыгаем, если работаем не с клавишей Alt

@@handle_press:
    cmp cs:[IsVisible], FLAG_TRUE
    je @@hotkey_exit                            ; Если регистры выведены - пропустить повторный вывод

    pop ax
    push ax
    call SaveScreen                             ; Сохраняем старое окно
    call PrintRegs                              ; Выводим регистры
    push FRAME_ATTRIBUTE
    push TEXT_HEIGTH
    push TEXT_WIDTH
    call PrintFrame                             ; Выводим рамку

    mov cs:[IsVisible], FLAG_TRUE      
    jmp @@hotkey_exit 

@@handle_release:
    cmp cs:[IsVisible], FLAG_FALSE
    je @@hotkey_exit                            ; Если регистры не выведены - пропускаем возврат содержимого окна

    call RestoreScreen                          ; Возврат содержимого окна
    mov cs:[IsVisible], FLAG_FALSE
    jmp @@hotkey_exit

@@hotkey_exit:
    in al, 61h                                  ; Читаем порт управления динамиком и клавиатурой
    mov ah, al                                  ; Сохраняем значение al, чтобы позже вернуть его
    or al, 80h                                  ; Устанавливаем в 1 самый старший бит, чтобы подтвердить
;                                                 прием scan-кода
    out 61h, al                                 ; Отправляем измененное значение обратно в порт
    xchg ah, al                                 ; Возвращаем в al исходное состояние порта
    out 61h, al                                 ; Отправляем в порт исходное значение 

    mov al, 20h                                 ; Загружаем код команды EOI (End Of Interrupt)
    out 20h, al                                 ; Отправляем команду в контроллер прерываний (порт 20h)

    pop ax
    iret
@@std_exit:
    pop ax

    jmp dword ptr cs:[Old09IntOffset]
New09IntFunction endp


; -----------------------------------------------------------------------------
; PROC: PrintRegs
; -----------------------------------------------------------------------------
; Описание:
;       Выводит в видеопамять содержимое регистров в рамке
; Входные параметры:
;       Нет
; Выходные параметры:
;       Нет
; Портящиеся регистры:
;       Нет 
; -----------------------------------------------------------------------------
; Визуализация стека после последнего push
;|  FL   |  CS   |  IP   |  AX   |  RET  |  BP   |  SP   |  SS   |  ES   |  DS   |  BP   |  DI   |  SI   |  DX   |  CX   |  BX   |  AX   |
;  34 33   32 31   30 29   28 27   26 25   24 23   22 21   20 19   18 17   16 15   14 13 | 12 11   10 09   08 07   06 05   04 03   02 01 | 00
; -----------------------------------------------------------------------------          < BP HERE                                       < SP HERE
PrintRegs proc
    push bp
    mov bp, sp

    push ax
    mov ax, bp
    add ax, 12d                                 ; ax теперь имеет адрес оригинального SP (как перед прерыванием)

    xchg ax, [bp - 2]                           ; ax принимает оригинальное значение, а SP занимает место [BP - 2]

    push ss es ds
    push [bp]                                   ; Пушим оригинальное значение BP
    push di si dx cx bx ax

    mov bp, sp
    mov ax, cs
    mov ds, ax

    mov ax, VIDEO_MEMORY_START
    mov es, ax

    mov bx, offset RegTable
    mov di, PICTURE_OFFSET
    mov cx, TEXT_HEIGTH

@@loop:
    mov si, bx
    call PrintString                            ; Печатаем название регистра, находящееся в начале строки таблицы

    mov si, offset EqualsSign
    add di, (LABEL_STRING_LEN - 1d) * ROW_OFFSET
    call PrintString                            ; Печатаем знак равенства

    mov si, [bx + LABEL_STRING_LEN]             ; Загружаем смещение исходного значения регистра 
;                                                 относительно bp из таблицы
    and si, 00FFh                               ; Обнуляем старший байт, который не относится к смещению 
    mov ax, [bp + si]                           ; Загружаем исходное значение регистра
    mov si, offset NumberBuffer                 
    add di, (EQUALS_SIGN_STRING_LEN - 1d) * ROW_OFFSET
    call Itoa
    call PrintString                            ; Печатаем значение регистра 

    sub di, (LABEL_STRING_LEN + EQUALS_SIGN_STRING_LEN - 2d) * ROW_OFFSET

    add di, LINE_OFFSET                         ; Смещаемся на строку ниже в видеопамяти
    add bx, REG_ENTRY_SIZE                      ; Смещаемся на следующую строку в таблице с регистрами

    loop @@loop

    pop ax bx cx dx si di bp ds es ss
    add sp, 2
    pop bp
    ret
PrintRegs endp


; -----------------------------------------------------------------------------
; PROC: PrintString
; -----------------------------------------------------------------------------
; Описание:
;       Выводит в видеопамять по указанному адресу содержимое в буфере до терминанта ($)
; Входные параметры:
;       si - Указатель на буфер
;       di - Смещение внутри указанного сегмента
;       es - Указанный сегмент
; Выходные параметры:
;       Нет
; Портящиеся регистры:
;       Нет 
; -----------------------------------------------------------------------------
PrintString proc
    push si di
    mov ah, SYMBOL_ATTRIBUTE                    ; Загружаем атрибут символов
    cld

@@loop:
    lodsb                                       ; AL = DS:[SI], SI += 1
    cmp al, '$'
    je @@exit

    stosw                                       ; ES:[DI] = AX, DI += 2
    jmp @@loop

@@exit:
    pop di si
    ret
PrintString endp


; -----------------------------------------------------------------------------
; PROC: Itoa
; -----------------------------------------------------------------------------
; Описание:
;       Записывает 16-ричное представление числа в виде строки в буфер  
; Входные параметры:
;       ax - Целое число
;       bx - Указатель на буфер
; Выходные параметры:
;       Нет (Записывает в массив строковое представление числа в формате hex)
; Портящиеся регистры:
;       Нет 
; -----------------------------------------------------------------------------
Itoa proc
    push ax bx cx si

    mov cx, 4d                                  ; Количество четверок байт в целом числе

@@loop:
    rol ax, 4                                   ; Циклический сдвиг влево
    mov bl, al
    and bl, 0Fh                                 ; Оставляем только младшие 4 байта

    ; cmp bl, 16d                                 
    ; jae @@end                                  
    cmp bl, 10d
    jae @@hexChars                              ; Прыжок для обработки hex-символов ABCDEF
    add bl, '0'                                 ; перевод числа в ascii-символ
    jmp @@end

@@hexChars:
    add bl, 'A' - 10d                           ; Перевод hex-символа в ascii-символ

@@end:
    mov [si], bl
    inc si
    loop @@loop

    mov bl, '$'
    mov [si], bl                                ; Добавление терминанта
    pop si cx bx ax 
    ret
Itoa endp


; -----------------------------------------------------------------------------
; PROC: RestoreScreen
; -----------------------------------------------------------------------------
; Описание:
;       Копирует содержимое экрана в буфер ScreenBuffer
; Входные параметры:
;       Нет
; Выходные параметры:
;       Нет
; Портящиеся регистры:
;       Нет 
; -----------------------------------------------------------------------------
SaveScreen proc
    push ax cx si di ds es

    mov ax, VIDEO_MEMORY_START
    mov ds, ax
    xor si, si

    mov ax, cs
    mov es, ax
    mov di, offset ScreenBuffer

    mov cx, SCREEN_BUFFER_SIZE
    cld
    rep movsb                                   ; ES:[DI] = DS:[SI], DI++, SI++

    pop es ds di si cx ax
    ret
SaveScreen endp


; -----------------------------------------------------------------------------
; PROC: RestoreScreen
; -----------------------------------------------------------------------------
; Описание:
;       Замещает содержимое экрана содержимым буфера ScreenBuffer      
; Входные параметры:
;       Нет
; Выходные параметры:
;       Нет
; Портящиеся регистры:
;       Нет 
; -----------------------------------------------------------------------------
RestoreScreen proc
    push ax cx si di ds es

    mov ax, cs
    mov ds, ax
    mov si, offset ScreenBuffer

    mov ax, VIDEO_MEMORY_START
    mov es, ax
    xor di, di

    mov cx, SCREEN_BUFFER_SIZE
    cld 
    rep movsb                                   ; ES:[DI] = DS:[SI], DI++, SI++

    pop es ds di si cx ax
    ret
RestoreScreen endp


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
        push bp                                
        mov bp, sp                             
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
        pop bp                                 
        ret                                  
ParseArguments endp


; -----------------------------------------------------------------------------
; PROC: PrintFrame (Pascal)
; -----------------------------------------------------------------------------
; Описание: 
;       Организует вывод частей рамки в видеопамять
; Входные параметры:
;       [bp + 6] (Word) - Атрибут рамки
;       [bp + 6] (Word) - Высота текста
;       [bp + 4] (Word) - Длина текста
; Выходные данные:
;       Нет (Рисует сразу в видеопамять)
; Портящиеся регистры:
;       Нет
; -----------------------------------------------------------------------------
PrintFrame proc
        push bp                                
        mov bp, sp                           
        push ax cx dx si di ds

        push cs
        pop ds

        mov dx, [bp + 8]                        ; Загружаем атрибут символа рамки
        mov si, [bp + 6]                        ; Загружаем высоту текста внутри рамки
        mov di, [bp + 4]                        ; Загружаем ширину текста внутри рамки

        push dx
        push si
        push di
        call PrintVerticalFrameSide

        push dx
        push si
        push di
        call PrintHorizontalFrameSide

        push dx
        push si
        push di
        call printFrameCorners

        pop ds di si dx cx ax
        pop bp                               
        ret 6                                  
PrintFrame endp


; -----------------------------------------------------------------------------
; PROC: PrintVerticalFrameSide (Pascal)
; -----------------------------------------------------------------------------
; Описание: 
;       Выводит вертикальные части рамки в видеопамять
; Входные параметры:
;       [bp + 8] (Word) - Атрибут рамки
;       [bp + 6] (Word) - Высота текста
;       [bp + 4] (Word) - Длина текста
; Выходные данные:
;       Нет (Рисует сразу в видеопамять)
; Портящиеся регистры:
;       ax, dx
; -----------------------------------------------------------------------------
PrintVerticalFrameSide proc
        push bp                                 
        mov bp, sp                              
        push bx si di

        mov dx, [bp + 8]                        ; Загружаем атрибут символа рамки
        mov si, [bp + 6]                        ; Загружаем высоту текста внутри рамки
        mov di, [bp + 4]                        ; Загружаем ширину текста внутри рамки

        xor bx, bx
        mov bl, [FrameChars + I_VERT]           ; Загружаем символ вертикальной части рамки
        push bx
        push dx
        push PICTURE_OFFSET - ROW_OFFSET
        push LINE_OFFSET
        push si                       
        call PrintSymbolSequence                ; Печатаем часть слева от текста

        push dx
        mov ax, ROW_OFFSET
        mul di
        add ax, PICTURE_OFFSET                  ; Находим смещение для правой стороны рамки
        pop dx

        xor bx, bx
        mov bl, [FrameChars + I_VERT]           ; Загружаем символ вертикальной части рамки
        push bx
        push dx
        push ax
        push LINE_OFFSET
        push si
        call PrintSymbolSequence                ; Печатаем часть рамки справа от текста

        pop di si bx
        pop bp
        ret 6
PrintVerticalFrameSide endp


; -----------------------------------------------------------------------------
; PROC: PrintHorizontalFrameSide (Pascal)
; -----------------------------------------------------------------------------
; Описание: 
;       Выводит горизонтальные части рамки в видеопамять
; Входные параметры:
;       [bp + 8] (Word) - Атрибут рамки
;       [bp + 6] (Word) - Высота текста
;       [bp + 4] (Word) - Длина текста
; Выходные данные:
;       Нет (Рисует сразу в видеопамять)
; Портящиеся регистры:
;       ax, dx
; -----------------------------------------------------------------------------
PrintHorizontalFrameSide proc
        push bp                               
        mov bp, sp                           
        push si di

        mov dx, [bp + 8]                        ; Загружаем атрибут символа рамки
        mov si, [bp + 6]                        ; Загружаем высоту текста внутри рамки
        mov di, [bp + 4]                        ; Загружаем ширину текста внутри рамки

        xor ax, ax
        mov al, [FrameChars + I_HORIZ]          ; Загружаем символ горизонтальной части рамки
        push ax
        push dx
        push PICTURE_OFFSET - LINE_OFFSET
        push ROW_OFFSET
        push di
        call PrintSymbolSequence                ; Печатаем часть рамки над текстом  

        xor ax, ax
        mov al, [FrameChars + I_HORIZ]          ; Загружаем символ горизонтальной части рамки
        push ax
        push dx

        push dx
        mov ax, LINE_OFFSET
        mul si
        add ax, PICTURE_OFFSET                 
        pop dx 

        push ax                                 ; push PICTURE_OFFSET + LINE_OFFSET * SI 
        push ROW_OFFSET
        push di
        call PrintSymbolSequence                ; Печатаем часть рамки под текстом

        pop di si
        pop bp
        ret 6

PrintHorizontalFrameSide endp


; -----------------------------------------------------------------------------
; PROC: PrintFrameCorners (Pascal)
; -----------------------------------------------------------------------------
; Описание: 
;       Выводит угловые части рамки в видеопамять
; Входные параметры:
;       [bp + 8] (Word) - Атрибут рамки
;       [bp + 6] (Word) - Высота текста
;       [bp + 4] (Word) - Длина текста
; Выходные данные:
;       Нет (Рисует сразу в видеопамять)
; Портящиеся регистры:
;       ax, dx
; -----------------------------------------------------------------------------
PrintFrameCorners proc
        push bp                               
        mov bp, sp                           
        push bx si di

        mov dx, [bp + 8]                        ; Загружаем атрибут символа рамки
        mov si, [bp + 6]                        ; Загружаем высоту текста внутри рамки
        mov di, [bp + 4]                        ; Загружаем ширину текста внутри рамки

        xor ax, ax
        mov al, [FrameChars + I_UP_LEFT]        ; Загружаем символ верхнего левого угла рамки
        push ax
        push dx
        push PICTURE_OFFSET - LINE_OFFSET - ROW_OFFSET
        call PrintSymbol

        xor ax, ax
        mov al, [FrameChars + I_LOW_LEFT]       ; Загружаем символ нижнего левого угла рамки
        push ax
        push dx

        push dx
        mov ax, LINE_OFFSET
        mul si
        add ax, PICTURE_OFFSET - ROW_OFFSET
        pop dx

        push ax                                 ; PUSH PICTURE_OFFSET + LINE_OFFSET * SI - ROW_OFFSET
        call PrintSymbol

        push dx
        mov ax, ROW_OFFSET
        mul di
        add ax, PICTURE_OFFSET - LINE_OFFSET 
        pop dx

        xor bx, bx
        mov bl, [FrameChars + I_UP_RIGHT]       ; Загружаем символ верхнего правого угла рамки
        push bx
        push dx
        push ax
        call PrintSymbol 

        push dx
        mov ax, ROW_OFFSET
        mul di
        mov bx, ax                              ; BX = ROW_OFFSET * DI
        mov ax, LINE_OFFSET
        mul si
        add ax, bx                              
        add ax, PICTURE_OFFSET                  ; AX = PICTURE_OFFSET + ROW_OFFSET * DI + LINE_OFFSET * SI
        pop dx   

        xor bx, bx
        mov bl, [FrameChars + I_LOW_RIGHT]      ; Загружаем символ нижнего правого угла рамки
        push bx
        push dx
        push ax
        call PrintSymbol

        pop di si bx
        pop bp
        ret 6
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
        push bp                               
        mov bp, sp                           
        push si di es

        mov ax, VIDEO_MEMORY_START              
        mov es, ax                              ; Загружаем указатель на начало области видеопамяти

        mov al, [bp + 12]                       ; Загружаем символ рамки
        mov ah, [bp + 10]                       ; Загружаем атрибут символа рамки
        mov di, [bp + 8]                        ; Загружаем начальное смещение в области видеопамяти
        mov si, [bp + 6]                        ; Загружаем шаг увеличения адреса при итерации
        mov cx, [bp + 4]                        ; Загружаем количество итераций цикла 

        jcxz @@exit
@@loop:
        mov es:[di], ax                         ; Загружаем в видеопамять символ и его атрибут
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
        push bp                                
        mov bp, sp                           
        push di es

        mov ax, VIDEO_MEMORY_START
        mov es, ax                              ; Загружаем указатель на начало области видеопамяти

        mov al, [bp + 8]                        ; Загружаем символ рамки
        mov ah, [bp + 6]                        ; Загружаем атрибут символа рамки
        mov di, [bp + 4]                        ; Загружаем начальное смещение в области видеопамяти

        mov es:[di], ax                         ; Загружаем в видеопамять символ и его атрибут

        pop es di
        pop bp 
        ret 6
PrintSymbol endp 


; =============================================================================
; VARIABLES
; =============================================================================

; Переменная, хранящая смещение стандартной функции 09h прерывания
Old09IntOffset      dw ?
; Переменная, хранящаа сегмент стандартной функции 09h прерывания
Old09IntSegment     dw ?

; Флаг, который равен FLAG_TRUE, если регистры выведены на экран и FLAG_FALSE, если не выведены
IsVisible           db 0d

; Таблица с строками-названиями регистров и смещением оригинальных
; значений регистров относительно bp в функции PrintRegs 
RegTable:
    db 'AX$', 0d
    db 'BX$', 2d
    db 'CX$', 4d
    db 'DX$', 6d
    db 'SI$', 8d
    db 'DI$', 10d
    db 'BP$', 12d
    db 'SP$', 20d
    db 'DS$', 14d
    db 'ES$', 16d
    db 'SS$', 18d
    db 'CS$', 30d
    db 'IP$', 28d
    db 'FL$', 32d

EqualsSign          db ' = $'

; Буфер для строкового представления числа
NumberBuffer        db 4 DUP(?), '$'

; Буфер для хранения содержимого окна
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

; Смещение символов рамки в массиве
FRAME_CHARS_COUNT           equ $ - FrameChars
I_UP_LEFT                   equ 0d 
I_HORIZ                     equ 1d 
I_UP_RIGHT                  equ 2d 
I_VERT                      equ 3d 
I_LOW_LEFT                  equ 4d
I_LOW_RIGHT                 equ 5d

; ascii-коды для символов рамки
HORIZONTAL_FRAME_SIDE       equ 0CDh
VERTICAL_FRAME_SIDE         equ 0BAh
UPPER_LEFT_FRAME_CORNER     equ 0C9h
UPPER_RIGHT_FRAME_CORNER    equ 0BBh
LOWER_LEFT_FRAME_CORNER     equ 0C8h
LOWER_RIGHT_FRAME_CORNER    equ 0BCh


EndOfProgram:

end Start