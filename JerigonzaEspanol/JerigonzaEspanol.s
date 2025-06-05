.data
prompt_input:   .asciz "Ingrese el texto (máximo 80 caracteres):\n"
prompt_input2: .asciz "Ingrese 1 para consola, 2 para archivo: "
prompt_output:  .asciz "\nTexto convertido:\n"
prompt_lang:    .asciz "¿Fuente en español (s) o gerigonza (g)?: "
newline:        .asciz "\n"
stats_msg:      .asciz "\nEstadísticas:\n==================\n     "
letras_msg:     .asciz "\nTotal de letras ingresadas: "
palabras_msg:   .asciz "\nTotal de palabras ingresadas: "
conv_msg:       .asciz "\nPalabras convertidas: "
mod_msg:        .asciz "\nLetras modificadas: "
porc_msg:       .asciz "\nPorcentaje de modificación: "
porc_sym:       .asciz "%\n==================\n"
prompt_file:    .asciz "Ingrese el nombre del archivo: "
output_file:    .asciz "convertido.txt"
translation_filename: .asciz "Traduccion.txt"
buffer:         .space 4096
output:         .space 4096
num_buffer:     .space 12    @ Buffer para convertir números a texto
len_error_msg:  .asciz "\nError: El texto no puede exceder los 80 caracteres.\n"
error_msg:      .asciz "Error al abrir archivo\n"

.section .bss
    .lcomm filename, 256

.text
.global _start

_start:
    bl leer_modo_lenguaje

    @ Solicitar modo de entrada
    mov r0, #1
    ldr r1, =prompt_input2
    mov r2, #41
    mov r7, #4
    swi 0

    @ Leer selección
    mov r0, #0
    ldr r1, =buffer
    mov r2, #2
    mov r7, #3
    swi 0

    ldrb r0, [r1]
    cmp r0, #'1'
    beq modo_consola
    cmp r0, #'2'
    beq modo_archivo

    b salir

leer_modo_lenguaje:
    mov r0, #1
    ldr r1, =prompt_lang
    mov r2, #45          @ Ajustamos la longitud del mensaje
    mov r7, #4
    swi 0

    mov r0, #0
    ldr r1, =buffer
    mov r2, #2
    mov r7, #3
    swi 0

    ldrb r0, [r1]
    cmp r0, #'s'
    moveq r9, #0      @ MODIFIED: español a gerigonza (set r9)
    cmp r0, #'g'
    moveq r9, #1      @ MODIFIED: gerigonza a español (set r9)
    bx lr

modo_consola:
    @ ... existing code to print prompts and read input ...
    bl leer_entrada
    @ ... existing code: check for input_too_long, etc. ...

    @ Contar letras y palabras ANTES de la conversión
    ldr r0, =buffer
    bl contar_letras
    mov r5, r0 @ r5 = total_letters (from r0 of contar_letras)
    mov r6, r1 @ r6 = total_words (from r1 of contar_letras)

    @ Preparar para convertir
    ldr r0, =buffer         @ Puntero al buffer de entrada para convertir
    ldr r10, =output        @ Puntero al buffer de salida para convertir en r10
    @ r9 ya tiene la opción de lenguaje (0 para Español a Jerigonza, 1 para Jerigonza a Español)
    bl convertir
    @ Después de convertir:
    @ r0 (retornado por convertir) tiene el número de letras modificadas (contenido original de r8)
    @ r11 (modificado dentro de convertir) tiene el número de "palabras cambiadas" o transformaciones.
    mov r4, r0              @ r4 = letras modificadas (era r8 en convertir)
    mov r7, r11             @ r7 = palabras cambiadas (era r11 en convertir)

    bl imprimir_salida     @ Imprime a consola
    @ Escribir traducción a "Traduccion.txt"
    bl calcular_longitud_output @ Length of output string will be in r0
    mov r2, r0              @ r2 = content_length
    ldr r0, =translation_filename @ r0 = filename_addr
    ldr r1, =output         @ r1 = content_addr
    mov r3, #0644           @ r3 = permissions
    bl escribir_archivo     @ Escribir a archivo
    @ Optionally, check r0 from escribir_archivo for error

    bl imprimir_estadisticas @ Imprime a consola
    b salir

leer_entrada:
    mov r0, #1
    ldr r1, =prompt_input
    mov r2, #43         @ Length of prompt_input 
    mov r7, #4          @ Syscall write
    swi 0

    mov r0, #0          @ File descriptor stdin
    ldr r1, =buffer     @ Buffer address
    mov r2, #80         @ Read AT MOST 80 bytes (buffer size)
    mov r7, #3          @ Syscall read
    swi 0               @ r0 now contains number of bytes read (max 80)

    @ r0 holds the number of bytes read. Max value of r0 is 80.
    @ If r0 is 80, we need to check if the 80th character IS NOT a newline.
    @ If r0 < 80, it's fine (user typed less than 80 chars, possibly with a newline).

    mov r4, r0          @ Save number of bytes read in r4

    cmp r4, #80         @ Did we read exactly 80 bytes?
    bne length_ok       @ If not 80 bytes, length is considered okay (it's less)

    @ If we read exactly 80 bytes, check if the last one is a newline
    ldr r1, =buffer
    add r1, r1, #79     @ Point to buffer[79] (the 80th character)
    ldrb r3, [r1]       @ Load the 80th character
    cmp r3, #'\n'       @ Is it a newline?
    beq length_ok       @ If 80th char is newline (79 chars + NL), it's OK
    
    @ If we read 80 bytes AND the last char is NOT a newline, then input was > 80
    b input_too_long_strict

modo_archivo:
    @ Pedir nombre del archivo (input file)
    mov r0, #1
    ldr r1, =prompt_file
    mov r2, #31         @ Length of "Ingrese el nombre del archivo: "
    mov r7, #4          @ syscall write
    swi 0

    mov r0, #0          @ stdin
    ldr r1, =filename   @ .bss section for filename
    mov r2, #255        @ Max 255 chars for filename (leave 1 for null)
    mov r7, #3          @ sys_read
    swi #0              @ r0 = bytes read for filename

    @ Procesar nombre del archivo
    cmp r0, #1          @ Check if at least 1 char was read (e.g. not just Enter)
    blt .Lmodo_archivo_filename_error @ If r0 <= 0 (error or empty)

    @ r0 has bytes read including newline. To null terminate at char before newline:
    @ e.g., if "file.txt\n" is read, r0 = 9.
    @ We want filename[8] = null. So filename + (r0-1)
    push {r0}           @ Save original r0 (bytes read including NL)
    sub r0, r0, #1      @ Index for null terminator (length - 1)
    ldr r1, =filename
    mov r2, #0          @ Null
    strb r2, [r1, r0]   @ Null-terminate: filename[bytes_read-1] = 0
    pop {r0}            @ Restore original r0 (not strictly needed now, but good practice)

    @ Abrir input archivo
    ldr r0, =filename   @ Filename string address
    mov r1, #0          @ Flags: O_RDONLY
    mov r7, #5          @ syscall sys_open
    swi #0              @ r0 = input file descriptor (fd_in) or error < 0

    cmp r0, #0          @ Check if fd_in is negative (error)
    blt .Lmodo_archivo_open_error
    mov r5, r0          @ Save fd_in in r5

    @ Leer contenido del input archivo
    mov r0, r5          @ fd_in from r5
    ldr r1, =buffer
    mov r2, #4095       @ Max bytes to read into buffer (leave 1 for null)
    mov r7, #3          @ syscall sys_read
    swi #0              @ r0 = bytes read from input file, or error < 0

    cmp r0, #0          @ Check if bytes read is negative (error)
    blt .Lmodo_archivo_read_error @ r0 has error code if < 0
    mov r4, r0          @ Save actual bytes read into r4 (for null termination of buffer)

    @ Null-terminate el buffer principal
    ldr r1, =buffer
    add r1, r1, r4      @ r1 apunta a buffer + bytes_leídos (using r4)
    mov r2, #0          @ Null
    strb r2, [r1]       @ Guardar null

    @ Cerrar input archivo
    mov r0, r5          @ fd_in from r5
    mov r7, #6          @ syscall sys_close
    swi 0
    @ Ignoring close error for input file for now

    @ Ahora procesar el contenido en 'buffer'
    @ Contar letras y palabras ANTES de la conversión
    ldr r0, =buffer
    bl contar_letras
    mov r5, r0 @ r5 = total_letters
    mov r6, r1 @ r6 = total_words

    @ Preparar para convertir
    ldr r0, =buffer         @ Puntero al buffer de entrada para convertir
    ldr r10, =output        @ Puntero al buffer de salida para convertir en r10
    @ r9 ya tiene la opción de lenguaje (0 para Español a Jerigonza, 1 para Jerigonza a Español)
    bl convertir
    @ Después de convertir:
    @ r0 (retornado por convertir) tiene el número de letras modificadas
    @ r11 (modificado dentro de convertir) tiene el número de "palabras cambiadas"
    mov r4, r0              @ r4 = letras modificadas
    mov r7, r11             @ r7 = palabras cambiadas
    
    @ Calcular longitud del texto traducido en 'output' una sola vez
    bl calcular_longitud_output @ Length of output string will be in r0
    mov r4, r0              @ Guardar la longitud del texto traducido en r4
                            @ (r0, r1, r2, r3 serán usados para escribir_archivo)

    @ 1. Escribir traducción a "convertido.txt" (o el nombre en output_file)
    ldr r0, =output_file    @ r0 = filename_addr ("convertido.txt")
    ldr r1, =output         @ r1 = content_addr
    mov r2, r4              @ r2 = content_length (from saved r4)
    mov r3, #0644           @ r3 = permissions
    bl escribir_archivo     @ Escribir a archivo (returns status in r0)
    
    cmp r0, #-1             @ Check return from escribir_archivo
    beq .Lmodo_archivo_write_error @ If -1, then writing "convertido.txt" failed

    @ 2. Escribir LA MISMA traducción a "Traduccion.txt"
    ldr r0, =translation_filename @ r0 = filename_addr ("Traduccion.txt")
    ldr r1, =output             @ r1 = content_addr (mismo output buffer)
    mov r2, r4                  @ r2 = content_length (misma longitud guardada en r4)
    mov r3, #0644               @ r3 = permissions
    bl escribir_archivo         @ Escribir a "Traduccion.txt"

    cmp r0, #-1                 @ Check return from escribir_archivo para "Traduccion.txt"
    beq .Lmodo_archivo_write_error2 @ Si -1, la escritura de "Traduccion.txt" falló
                                    @ Podríamos tener un manejo de error diferente o el mismo.

    bl imprimir_estadisticas @ Imprime a consola
    b salir

.Lmodo_archivo_filename_error:
    ldr r1, =error_msg  @ Using your generic error_msg for now
    mov r2, #23         @ Length of "Error al abrir archivo\n"
    b .Lprint_generic_file_error_and_exit

.Lmodo_archivo_open_error:
    ldr r1, =error_msg
    mov r2, #23        
    b .Lprint_generic_file_error_and_exit

.Lmodo_archivo_read_error:
    @ Antes de salir, intentar cerrar el archivo de entrada si se abrió
    mov r0, r5          @ fd_in (was saved in r5)
    mov r7, #6          @ syscall sys_close
    swi 0               @ Cerrar input file (ignore error on this close)
    ldr r1, =error_msg
    mov r2, #23        
    b .Lprint_generic_file_error_and_exit

.Lmodo_archivo_write_error: @ Error al escribir "convertido.txt"
    @ escribir_archivo pudo haber impreso un mensaje o no.
    @ Aquí podríamos imprimir un mensaje específico si quisiéramos.
    @ "Error al escribir convertido.txt"
    b salir @ Salir si el primer guardado falla.

.Lmodo_archivo_write_error2: @ Error al escribir "Traduccion.txt"
    @ "Error al escribir Traduccion.txt"
    @ Incluso si este falla, el primero ("convertido.txt") pudo haber tenido éxito.
    @ Continuamos a imprimir estadísticas y salir.
    bl imprimir_estadisticas @ Aún así imprimir estadísticas si la segunda escritura falla.
    b salir

.Lprint_generic_file_error_and_exit:
    mov r0, #1          @ stdout
    @ r1 (error message address) and r2 (length) should be set by the calling label
    mov r7, #4          @ syscall write
    swi 0
    b salir

length_ok:
    @ Null-terminate the string
    ldr r1, =buffer     @ Get buffer base address again
    add r1, r1, r4      @ r1 now points to buffer + bytes_read (r4 has original r0)
                        @ If r0 was 80 and last char was \n, we null terminate after \n.
                        @ If r0 was < 80, null terminate after last char.
    mov r2, #0          @ Value to store (null terminator)
    strb r2, [r1]       @ Store null terminator
    bx lr

input_too_long: @ General case if first swi r0 > 80 (not possible with current read r2=80)
    @ This label is kept for the previous logic but might not be hit now.
    b print_error_and_exit

input_too_long_strict: @ Specifically for 80 chars read and no newline
print_error_and_exit:
    mov r0, #1
    ldr r1, =len_error_msg
    mov r2, #52         @ Length of error message
    mov r7, #4          @ Syscall write
    swi 0
    b salir             @ Branch to exit the program

contar_letras:
    push {r4-r9, lr}
    mov r5, #0          @ r5: Contador de letras
    mov r6, #0          @ r6: Contador de palabras
    mov r9, #0          @ r9: Estado actual: 0 = fuera de palabra, 1 = dentro de palabra

.Lcontar_loop:
    ldrb r2, [r0], #1   @ Cargar byte (r2) del buffer (r0), e incrementar r0
    cmp r2, #0          @ Fin de string?
    beq .Lfin_conteo_final

    cmp r2, #' '; beq .Lcontar_es_separador
    cmp r2, #'
'; beq .Lcontar_es_separador
    cmp r2, #'	'; beq .Lcontar_es_separador

    cmp r2, #0xC3
    bne .Lcontar_single_byte_char_for_count

    ldrb r3, [r0] @ Peek next byte
    cmp r3, #0xA1; beq .Lcontar_utf8_char_found_for_count @ á
    cmp r3, #0xA9; beq .Lcontar_utf8_char_found_for_count @ é
    cmp r3, #0xAD; beq .Lcontar_utf8_char_found_for_count @ í
    cmp r3, #0xB3; beq .Lcontar_utf8_char_found_for_count @ ó
    cmp r3, #0xBA; beq .Lcontar_utf8_char_found_for_count @ ú
    cmp r3, #0xBC; beq .Lcontar_utf8_char_found_for_count @ ü
    cmp r3, #0xB1; beq .Lcontar_utf8_char_found_for_count @ ñ
    b .Lcontar_single_byte_char_logic_for_count @ 0xC3 but not known pair

.Lcontar_utf8_char_found_for_count:
    add r0, r0, #1      @ Consume the second byte of UTF-8 sequence
    b .Lcontar_single_byte_char_logic_for_count @ Process as one conceptual char

.Lcontar_single_byte_char_for_count:
    @ r2 has the single byte, or the 0xC3 if its pair wasn't recognized
.Lcontar_single_byte_char_logic_for_count:
    add r5, r5, #1      @ Incrementar contador de letras (r5)
    cmp r9, #0          @ Estábamos previamente fuera de una palabra (r9 == 0)?
    beq .Lcontar_inicio_palabra_for_count
    b .Lcontar_loop     @ No, ya estábamos dentro de una palabra (r9 == 1), continuar.

.Lcontar_es_separador:
    mov r9, #0          @ Marcar que estamos fuera de una palabra (estado = 0)
    b .Lcontar_loop

.Lcontar_inicio_palabra_for_count:
    mov r9, #1          @ Marcar que ahora estamos dentro de una palabra (estado = 1)
    add r6, r6, #1      @ Incrementar contador de palabras (r6)
    b .Lcontar_loop

.Lfin_conteo_final:
    mov r0, r5          @ Retornar total de letras en r0
    mov r1, r6          @ Retornar total de palabras en r1
    pop {r4-r9, lr}
    bx lr

convertir:
    push {r4, r5, lr} @ Save r4, r5 (used for G->S temps) and link register
    mov r1, r10 @ r10 contains output buffer address, move to r1 for output
    mov r8, #0  @ Initialize counter for modified letters (r8)
    mov r11, #0 @ Initialize counter for transformations/modified_words_proxy (r11)

procesar:
    ldrb r2, [r0], #1   @ Load byte from input (r0) into r2, AND ADVANCE r0.
                        @ r0 now points to the byte AFTER the one in r2.
    cmp r2, #0          @ Check for null terminator
    beq fin_conversion

    cmp r9, #0          @ r9 = 0 for S->G, r9 = 1 for G->S
    beq esp_a_geri      @ Branch if Spanish to Gerigonza (S->G)

    @ --- Gerigonza a Español section (G->S) (if r9 != 0) ---
    @ r2 contains the current byte from input. r0 ALREADY points to the next byte.

    cmp r2, #0xC3 @ Is current byte r2 the start of a 2-byte UTF-8 sequence we care about?
    bne .L_gs_handle_single_byte_char @ Not 0xC3, so must be single-byte ASCII.

    @ r2 is 0xC3. Load the next byte (V1_byte2) from input stream (currently pointed to by r0).
    ldrb r3, [r0] @ r3 = V1_byte2 (e.g. 0xA1 for á). Does NOT advance r0 here.

    @ Check if (0xC3,r3) is UTF-8 'ñ' (consonant).
    cmp r3, #0xB1 
    beq .L_gs_write_utf8_pair_and_advance @ ñ: write 0xC3,r3 and advance r0 over r3.

    @ Check if (0xC3,r3) is one of our target UTF-8 accented VOWELS.
    cmp r3, #0xA1; beq .L_gs_check_p_after_utf8_vowel @ á (0xC3 0xA1)
    cmp r3, #0xA9; beq .L_gs_check_p_after_utf8_vowel @ é (0xC3 0xA9)
    cmp r3, #0xAD; beq .L_gs_check_p_after_utf8_vowel @ í (0xC3 0xAD)
    cmp r3, #0xB3; beq .L_gs_check_p_after_utf8_vowel @ ó (0xC3 0xB3)
    cmp r3, #0xBA; beq .L_gs_check_p_after_utf8_vowel @ ú (0xC3 0xBA)
    cmp r3, #0xBC; beq .L_gs_check_p_after_utf8_vowel @ ü (0xC3 0xBC)

    @ If r2=0xC3 but r3 didn't form a known UTF-8 char we handle as special,
    @ treat 0xC3 as a standalone char. Write it. r3 (pointed to by r0) will be processed in next loop.
    strb r2, [r1], #1   @ Write 0xC3 (original r2).
    b procesar

.L_gs_check_p_after_utf8_vowel: @ r2=0xC3, r3=V1_byte2. r0 points at V1_byte2.
    @ We need to check for 'p' at [r0, #1] (byte after V1_byte2).
    ldrb r4, [r0, #1]   @ r4 = potential 'p'. (r4 is callee-saved by push at start)
    cmp r4, #'p'
    bne .L_gs_write_utf8_pair_and_advance @ Not Vp.. pattern, so just write V1 (0xC3,r3).

    @ Pattern so far: V1_byte1(r2) V1_byte2(r3) 'p'(r4).
    @ Check for V2 (should match V1). V2_byte1 is at [r0, #2], V2_byte2 is at [r0, #3].
    ldrb r5, [r0, #2]   @ r5 = V2_byte1. (r5 is callee-saved by push at start)
    cmp r5, r2          @ Compare V2_byte1 with V1_byte1 (0xC3).
    bne .L_gs_write_utf8_pair_and_advance @ V2_byte1 mismatch. Write V1.

    ldrb r5, [r0, #3]   @ r5 = V2_byte2.
    cmp r5, r3          @ Compare V2_byte2 with V1_byte2 (e.g. 0xA1).
    bne .L_gs_write_utf8_pair_and_advance @ V2_byte2 mismatch. Write V1.
    
    @ Full UTF-8 "Vowel-p-Vowel" pattern found! (e.g., 0xC3 0xA1 'p' 0xC3 0xA1)
    @ Action: Write V1 (0xC3,r3), and advance r0 past the whole pattern.
    strb r2, [r1], #1   @ Write V1_byte1 (0xC3).
    strb r3, [r1], #1   @ Write V1_byte2 (e.g. 0xA1).
    add r0, r0, #1      @ Advance r0 past V1_byte2 (it was pointing at it).
    add r0, r0, #1      @ Advance r0 past 'p'.
    add r0, r0, #1      @ Advance r0 past V2_byte1.
    add r0, r0, #1      @ Advance r0 past V2_byte2.
    add r8, r8, #3      @ 3 bytes removed ('p' + a UTF-8 pair like 0xC3 0xA1).
    add r11, r11, #1    @ Transformation count.
    b procesar

.L_gs_write_utf8_pair_and_advance: @ Not a full G->S pattern for this UTF-8 vowel, or it was ñ.
                                 @ Write the UTF-8 pair (0xC3,r3) and advance r0 past r3.
    strb r2, [r1], #1   @ Write 0xC3 (original r2).
    strb r3, [r1], #1   @ Write the second byte (r3).
    add r0, r0, #1      @ Advance r0 past r3 (it was pointing at r3).
    b procesar

.L_gs_handle_single_byte_char: @ r2 is a single byte char (e.g. ASCII, not 0xC3).
    mov r4, r2          @ Use r4 for V1 (current char r2). (r4 is callee-saved)
    cmp r4, #'a'; beq .L_gs_check_p_after_single_vowel
    cmp r4, #'e'; beq .L_gs_check_p_after_single_vowel
    cmp r4, #'i'; beq .L_gs_check_p_after_single_vowel
    cmp r4, #'o'; beq .L_gs_check_p_after_single_vowel
    cmp r4, #'u'; beq .L_gs_check_p_after_single_vowel
    b .L_gs_write_single_r2_and_procesar @ Not an ASCII vowel, just write r2.

.L_gs_check_p_after_single_vowel: @ r4 is ASCII vowel V1. r2 also holds it. r0 points after r2.
    ldrb r3, [r0]       @ r3 = char after V1 (should be 'p'). (r3 is volatile scratch).
    cmp r3, #'p'; bne .L_gs_write_single_r2_and_procesar @ Not Vp.., write V1(r2).

    ldrb r5, [r0, #1]   @ r5 = char after 'p' (should be V2, matching V1/r4). (r5 is callee-saved)
    cmp r5, r4          @ Compare V2(r5) with V1(r4).
    bne .L_gs_write_single_r2_and_procesar @ Not VpV, write V1(r2).

    @ ASCII "Vowel-p-Vowel" pattern found!
    strb r4, [r1], #1   @ Write V1(r4).
    add r0, r0, #2      @ Advance r0 past 'p' and V2.
    add r8, r8, #2      @ 2 bytes removed ('p' and vowel).
    add r11, r11, #1    @ Transformation count.
    b procesar

.L_gs_write_single_r2_and_procesar: @ Fallback for single byte: just write original byte in r2.
    strb r2, [r1], #1
    b procesar
    @ --- End of Gerigonza a Español section ---

esp_a_geri: @ Spanish to Gerigonza (S->G) (if r9 = 0)
    @ r2 already holds the current byte from input (e.g., 'h' or 0xC3).
    @ r0 ALREADY points to the next byte in the input stream.

    cmp r2, #0xC3   @ Is the current byte 0xC3 (start of our 2-byte UTF-8 chars)?
    bne .L_s2g_process_single_byte @ If not, process as a single byte character.

    @ r2 is 0xC3. Peek at the next byte from the input stream (currently pointed to by r0).
    ldrb r3, [r0] @ r3 = potential second byte of UTF-8 sequence. DOES NOT ADVANCE r0.

    @ Handle UTF-8 'ñ' (0xC3 0xB1) - treat as consonant.
    cmp r3, #0xB1 
    beq .L_s2g_write_utf8_pair_and_advance_consonant

    @ Check for UTF-8 accented VOWELS that need Gerigonza application.
    cmp r3, #0xA1; beq .L_s2g_apply_gerigonza_to_utf8_vowel_pair @ á
    cmp r3, #0xA9; beq .L_s2g_apply_gerigonza_to_utf8_vowel_pair @ é
    cmp r3, #0xAD; beq .L_s2g_apply_gerigonza_to_utf8_vowel_pair @ í
    cmp r3, #0xB3; beq .L_s2g_apply_gerigonza_to_utf8_vowel_pair @ ó
    cmp r3, #0xBA; beq .L_s2g_apply_gerigonza_to_utf8_vowel_pair @ ú
    cmp r3, #0xBC; beq .L_s2g_apply_gerigonza_to_utf8_vowel_pair @ ü

    @ If r2=0xC3 but r3 didn't form a known vowel or ñ that we handle specially,
    @ treat 0xC3 as a standalone character (consonant). Write it.
    @ The next byte (original r3, pointed to by r0) will be processed in the next loop iteration.
    strb r2, [r1], #1   @ Write 0xC3.
    b procesar

.L_s2g_write_utf8_pair_and_advance_consonant: @ For ñ (0xC3 0xB1).
    strb r2, [r1], #1   @ Write 0xC3 (which is in r2).
    strb r3, [r1], #1   @ Write the second byte (which is in r3, e.g., 0xB1 for ñ).
    add r0, r0, #1      @ Consume the second byte (r3) from input stream (r0 was pointing at it).
    b procesar

.L_s2g_apply_gerigonza_to_utf8_vowel_pair: @ r2=0xC3, r3=second byte of UTF-8 vowel.
    strb r2, [r1], #1   @ Write 0xC3.
    strb r3, [r1], #1   @ Write second byte of vowel (e.g. 0xA1 for á).
    mov r4, #'p'        @ Use r4 for 'p' (convertir saves r4 & r5).
    strb r4, [r1], #1   @ Write 'p'.
    strb r2, [r1], #1   @ Write 0xC3 again.
    strb r3, [r1], #1   @ Write second byte of vowel again.
    add r0, r0, #1      @ Consume the second byte (r3) from input stream (r0 was pointing at it).
    add r8, r8, #2      @ Conceptually, 2 "letters" added (p + vowel repetition).
    add r11, r11, #1    @ Transformation count.
    b procesar

.L_s2g_process_single_byte: @ r2 is a single byte character (not 0xC3).
    strb r2, [r1], #1   @ Write the character r2 first.

    @ Check if it's an ASCII vowel.
    cmp r2, #'a'; beq .L_s2g_apply_gerigonza_to_single_ascii_vowel
    cmp r2, #'e'; beq .L_s2g_apply_gerigonza_to_single_ascii_vowel
    cmp r2, #'i'; beq .L_s2g_apply_gerigonza_to_single_ascii_vowel
    cmp r2, #'o'; beq .L_s2g_apply_gerigonza_to_single_ascii_vowel
    cmp r2, #'u'; beq .L_s2g_apply_gerigonza_to_single_ascii_vowel
    
    @ If not an ASCII vowel, it's a consonant or other symbol. It has already been written.
    b procesar

.L_s2g_apply_gerigonza_to_single_ascii_vowel: @ r2 is an ASCII vowel, already written once.
    mov r3, #'p'        @ Use r3 for 'p' (r3 is volatile scratch).
    strb r3, [r1], #1   @ Add 'p'.
    strb r2, [r1], #1   @ Add the vowel (r2) itself back.
    add r8, r8, #2      @ 2 letters added.
    add r11, r11, #1    @ Transformation count.
    b procesar

fin_conversion:
    mov r3, #0          @ Null terminator for the output string.
    strb r3, [r1]       @ Store null terminator in output.
    mov r0, r8          @ Return total modified letters in r0.
    pop {r4, r5, pc}   @ Restore r4, r5 and return (pop lr from stack into pc).

calcular_longitud_output: @ Calculates length of null-terminated string in 'output' buffer
    push {r1-r3, lr}    @ r0 will hold the pointer, then length
    ldr r0, =output     @ Pointer to the start of the output buffer
    mov r1, #0          @ Length counter
.Lcalc_len_loop:
    ldrb r2, [r0], #1   @ Load byte from output buffer, advance pointer
    cmp r2, #0          @ Check for null terminator
    beq .Lcalc_len_done
    add r1, r1, #1      @ Increment length
    b .Lcalc_len_loop
.Lcalc_len_done:
    mov r0, r1          @ Return length in r0
    pop {r1-r3, lr}
    bx lr

escribir_archivo: 
    @ Args: r0=filename_addr, r1=content_addr, r2=content_length, r3=permissions
    push {r4-r7, lr}

    mov r4, r0          @ Save filename_addr from r0 into r4
    mov r5, r1          @ Save content_addr from r1 into r5
    mov r6, r2          @ Save content_length from r2 into r6
    @ r3 (permissions) can be used directly or saved if r3 is needed

    @ Syscall #8 (sys_creat)
    mov r0, r4          @ 1st arg for creat: filename address
    mov r1, r3          @ 2nd arg for creat: permissions
    mov r7, #8          @ syscall sys_creat
    swi 0               @ r0 = output file descriptor or error

    cmp r0, #-1
    beq .L_escribir_error @ Branch if creat failed

    mov r3, r0          @ Save output file descriptor in r3 (was permissions)

    @ Write the content
    mov r0, r3          @ 1st arg for write: File descriptor
    mov r1, r5          @ 2nd arg for write: content_addr (from saved r1)
    mov r2, r6          @ 3rd arg for write: content_length (from saved r2)
    mov r7, #4          @ syscall sys_write
    swi 0
    @ Optionally, check r0 for bytes written or error (<0)
    cmp r0, #0
    blt .L_escribir_close_anyway @ If write error, still try to close

.L_escribir_close_anyway:
    @ Close output file
    mov r0, r3          @ File descriptor (from saved r0 after creat)
    mov r7, #6          @ syscall sys_close
    swi 0
    @ Optionally, check for close errors

    mov r0, #0          @ Return 0 for success
    pop {r4-r7, lr}
    bx lr

.L_escribir_error:
    @ Minimal error indication: return -1
    @ A real error message to console could be printed here or by caller.
    mov r0, #-1         @ Return -1 for error
    pop {r4-r7, lr}
    bx lr

imprimir_salida:
    mov r0, #1
    ldr r1, =prompt_output
    mov r2, #19
    mov r7, #4
    swi 0

    mov r0, #1
    ldr r1, =output
    mov r2, #0

calcular_longitud:
    ldrb r3, [r1, r2]
    cmp r3, #0
    beq imprimir_texto
    add r2, r2, #1
    b calcular_longitud

imprimir_texto:
    mov r0, #1
    ldr r1, =output
    mov r7, #4
    swi 0
    bx lr

imprimir_estadisticas:
    push {r4-r7, lr}

    @ Mensaje inicial de estadísticas
    mov r0, #1
    ldr r1, =stats_msg
    mov r2, #34
    mov r7, #4
    swi 0

    @ Total de letras
    mov r0, #1
    ldr r1, =letras_msg
    mov r2, #28
    mov r7, #4
    swi 0
    mov r0, r5
    bl numero_a_ascii

    @ Total de palabras
    mov r0, #1
    ldr r1, =palabras_msg
    mov r2, #30             @ Nueva longitud para "Total de palabras ingresadas: "
    mov r7, #4
    swi 0
    mov r0, r6          @ Total de palabras
    bl numero_a_ascii

    @ Palabras convertidas
    mov r0, #1
    ldr r1, =conv_msg
    mov r2, #22
    mov r7, #4
    swi 0
    mov r0, r11
    bl numero_a_ascii

    @ Letras modificadas
    mov r0, #1
    ldr r1, =mod_msg
    mov r2, #20
    mov r7, #4
    swi 0
    mov r0, r4
    bl numero_a_ascii

    @ Porcentaje
    mov r0, #1
    ldr r1, =porc_msg
    mov r2, #29
    mov r7, #4
    swi 0

    mov r0, #100
    mul r0, r4, r0
    udiv r0, r0, r5
    bl numero_a_ascii

    @ Símbolo de porcentaje y final
    mov r0, #1
    ldr r1, =porc_sym
    mov r2, #20
    mov r7, #4
    swi 0

    pop {r4-r7, lr}
    bx lr

numero_a_ascii:
    push {r4-r7, lr}
    
    ldr r1, =num_buffer
    add r1, r1, #11
    mov r2, #0
    strb r2, [r1]
    mov r2, #10
    mov r4, r1

convert_loop:
    sub r1, r1, #1
    udiv r3, r0, r2
    mul r5, r3, r2
    sub r5, r0, r5
    add r5, r5, #'0'
    strb r5, [r1]
    mov r0, r3
    cmp r0, #0
    bne convert_loop

    mov r0, #1
    mov r2, r4
    sub r2, r2, r1
    mov r7, #4
    swi 0

    pop {r4-r7, lr}
    bx lr

salir:
    mov r7, #1
    swi 0
