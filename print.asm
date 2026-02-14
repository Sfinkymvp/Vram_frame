.model tiny
.code
org 100h

start:		
		lea dx, [string]
		mov ah, 0ah
		int 21h

		mov ax, 0b800h
		mov es, ax	
		mov di, video_offset

		lea si, [string + 2]
		xor cx, cx
		mov cl, [string + 1]

		jcxz entry_text_loop
text_loop: 
		mov al, [si]
		mov es:[di], al
		mov byte ptr es:[di+1], text_attribute
		inc si
		add di, 2d
entry_text_loop:
		loop text_loop

		xor cx, cx
		mov cl, [string + 1]
		add cx, 1d

		mov di, video_offset
		sub di, 2
		sub di, line_offset
		mov byte ptr es:[di], 0c9h
		mov byte ptr es:[di + 1], frame_attribute
		
		jmp loop_top_frame_entry	
loop_top_frame:
		add di, 2d
		mov byte ptr es:[di], 0cdh
		mov byte ptr es:[di + 1], frame_attribute
loop_top_frame_entry:
		loop loop_top_frame
		
		add di, 2d
		mov byte ptr es:[di], 0bbh
		mov byte ptr es:[di + 1], frame_attribute

		mov cx, vertical_dimension
		jmp loop_left_frame_entry
loop_left_frame:
		add di, line_offset
		mov byte ptr es:[di], 0bah
		mov byte ptr es:[di + 1], frame_attribute
loop_left_frame_entry:
		loop loop_left_frame

		add di, line_offset
		mov byte ptr es:[di], 0bch
		mov byte ptr es:[di + 1], frame_attribute

		xor cx, cx
		mov cl, [string + 1]
		add cx, 1d
		jmp loop_bottom_frame_entry
loop_bottom_frame:
		sub di, 2d
		mov byte ptr es:[di], 0cdh
		mov byte ptr es:[di + 1], frame_attribute
loop_bottom_frame_entry:
		loop loop_bottom_frame

		sub di, 2d
		mov byte ptr es:[di], 0c8h
		mov byte ptr es:[di + 1], frame_attribute

		mov cx, vertical_dimension
		jmp loop_right_frame_entry
loop_right_frame:
		sub di, line_offset
		mov byte ptr es:[di], 0bah
		mov byte ptr es:[di + 1], frame_attribute
loop_right_frame_entry:
		loop loop_right_frame

		mov ax, 4c00h
		int 21h

text_attribute 	equ 00001111b
frame_symbol    equ 23h 
frame_attribute equ 00000111b
vertical_dimension 	equ 2d
video_offset 	equ (80d * 5d + 40d) * 2d
line_offset	equ 80d * 2d
max_size 	equ 128d

string db max_size, 0d, max_size DUP(0d)

end start