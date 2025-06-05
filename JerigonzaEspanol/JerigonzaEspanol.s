.data
@ ──────────────────────────────────────────────
@ === DATOS ESTÁTICOS Y MENSAJES DEL USUARIO ===
@ Mensajes de usuario, buffers para entrada/salida, y cadenas para archivos
@ ──────────────────────────────────────────────
prompt_input:           .asciz "Ingrese el texto (máximo 80 caracteres):\n"
prompt_input2:          .asciz "Ingrese 1 para consola, 2 para archivo: "
prompt_output:          .asciz "\nTexto convertido:\n"
prompt_lang:            .asciz "¿Fuente en español (s) o gerigonza (g)?: "
newline:                .asciz "\n"
stats_msg:              .asciz "\nEstadísticas:\n==================\n     "
letras_msg:             .asciz "\nTotal de letras ingresadas: "
palabras_msg:           .asciz "\nTotal de palabras ingresadas: "
conv_msg:               .asciz "\nPalabras convertidas: "
mod_msg:                .asciz "\nLetras modificadas: "
porc_msg:               .asciz "\nPorcentaje de modificación: "
porc_sym:               .asciz "%\n==================\n"
prompt_file:            .asciz "Ingrese el nombre del archivo: "
output_file:            .asciz "convertido.txt"
translation_filename:   .asciz "Traduccion.txt"
buffer:                 .space 4096
output:                 .space 4096
num_buffer:             .space 12    @ Buffer para convertir números a texto
len_error_msg:          .asciz "\nError: El texto no puede exceder los 80 caracteres.\n"
error_msg:              .asciz "Error al abrir archivo\n"

.section .bss
    .lcomm filename, 256

.text
.global _start

@ ──────────────────────────────────────────────
@ === PUNTO DE ENTRADA PRINCIPAL ===
@ Inicializa idioma y modo de entrada, luego ejecuta el flujo adecuado
@ ──────────────────────────────────────────────
_start:
    bl leer_modo_lenguaje

    @ Solicita modo de entrada (consola o archivo)
    mov r0, #1
    ldr r1, =prompt_input2
    mov r2, #41
    mov r7, #4
    swi 0

    @ Lee selección del usuario (consola o archivo)
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

@ ──────────────────────────────────────────────
@ Solicita idioma de traducción (español o gerigonza)
@ Guarda selección en r9 (0: español→gerigonza, 1: gerigonza→español)
@ ──────────────────────────────────────────────
leer_modo_lenguaje:
    mov r0, #1
    ldr r1, =prompt_lang
    mov r2, #45
    mov r7, #4
    swi 0

    mov r0, #0
    ldr r1, =buffer
    mov r2, #2
    mov r7, #3
    swi 0

    ldrb r0, [r1]
    cmp r0, #'s'
    moveq r9, #0      @ español a gerigonza
    cmp r0, #'g'
    moveq r9, #1      @ gerigonza a español
    bx lr

@ ──────────────────────────────────────────────
@ Modo consola: Lee texto, procesa, imprime y guarda traducción
@ ──────────────────────────────────────────────
modo_consola:
    bl leer_entrada

    @ Cuenta letras y palabras ANTES de la conversión
    ldr r0, =buffer
    bl contar_letras
    mov r5, r0              @ r5 = total de letras
    mov r6, r1              @ r6 = total de palabras

    @ Prepara buffers y ejecuta conversión
    ldr r0, =buffer
    ldr r10, =output
    bl convertir
    mov r4, r0              @ r4 = letras modificadas
    mov r7, r11             @ r7 = palabras cambiadas

    bl imprimir_salida

    @ Escribe traducción en "Traduccion.txt"
    bl calcular_longitud_output
    mov r2, r0
    ldr r0, =translation_filename
    ldr r1, =output
    mov r3, #0644
    bl escribir_archivo

    bl imprimir_estadisticas
    b salir

@ ──────────────────────────────────────────────
@ Lee texto desde consola y valida longitud (máx 80 caracteres)
@ ──────────────────────────────────────────────
leer_entrada:
    mov r0, #1
    ldr r1, =prompt_input
    mov r2, #43
    mov r7, #4
    swi 0

    mov r0, #0
    ldr r1, =buffer
    mov r2, #80
    mov r7, #3
    swi 0

    mov r4, r0          @ Guarda número de bytes leídos

    cmp r4, #80
    bne length_ok

    ldr r1, =buffer
    add r1, r1, #79
    ldrb r3, [r1]
    cmp r3, #'\n'
    beq length_ok

    b input_too_long_strict

@ ──────────────────────────────────────────────
@ Modo archivo: Lee archivo, procesa, imprime y guarda traducción
@ ──────────────────────────────────────────────
modo_archivo:
    @ Solicita nombre de archivo
    mov r0, #1
    ldr r1, =prompt_file
    mov r2, #31
    mov r7, #4
    swi 0

    mov r0, #0
    ldr r1, =filename
    mov r2, #255
    mov r7, #3
    swi #0

    cmp r0, #1
    blt .Lmodo_archivo_filename_error

    push {r0}
    sub r0, r0, #1
    ldr r1, =filename
    mov r2, #0
    strb r2, [r1, r0]
    pop {r0}

    @ Abre archivo de entrada
    ldr r0, =filename
    mov r1, #0
    mov r7, #5
    swi #0

    cmp r0, #0
    blt .Lmodo_archivo_open_error
    mov r5, r0

    @ Lee contenido del archivo
    mov r0, r5
    ldr r1, =buffer
    mov r2, #4095
    mov r7, #3
    swi #0

    cmp r0, #0
    blt .Lmodo_archivo_read_error
    mov r4, r0

    @ Null-termina el buffer
    ldr r1, =buffer
    add r1, r1, r4
    mov r2, #0
    strb r2, [r1]

    @ Cierra archivo de entrada
    mov r0, r5
    mov r7, #6
    swi 0

    @ Cuenta letras y palabras antes de convertir
    ldr r0, =buffer
    bl contar_letras
    mov r5, r0
    mov r6, r1

    @ Prepara buffers y ejecuta conversión
    ldr r0, =buffer
    ldr r10, =output
    bl convertir
    mov r4, r0
    mov r7, r11

    bl calcular_longitud_output
    mov r4, r0          @ Guarda longitud traducción

    @ Escribe traducción en "convertido.txt"
    ldr r0, =output_file
    ldr r1, =output
    mov r2, r4
    mov r3, #0644
    bl escribir_archivo
    cmp r0, #-1
    beq .Lmodo_archivo_write_error

    @ Escribe traducción en "Traduccion.txt"
    ldr r0, =translation_filename
    ldr r1, =output
    mov r2, r4
    mov r3, #0644
    bl escribir_archivo
    cmp r0, #-1
    beq .Lmodo_archivo_write_error2

    bl imprimir_estadisticas
    b salir

.Lmodo_archivo_filename_error:
    ldr r1, =error_msg
    mov r2, #23
    b .Lprint_generic_file_error_and_exit

.Lmodo_archivo_open_error:
    ldr r1, =error_msg
    mov r2, #23
    b .Lprint_generic_file_error_and_exit

.Lmodo_archivo_read_error:
    mov r0, r5
    mov r7, #6
    swi 0
    ldr r1, =error_msg
    mov r2, #23
    b .Lprint_generic_file_error_and_exit

.Lmodo_archivo_write_error:
    b salir

.Lmodo_archivo_write_error2:
    bl imprimir_estadisticas
    b salir

.Lprint_generic_file_error_and_exit:
    mov r0, #1
    mov r7, #4
    swi 0
    b salir

@ ──────────────────────────────────────────────
@ Null-termina el string leído desde consola
@ ──────────────────────────────────────────────
length_ok:
    ldr r1, =buffer
    add r1, r1, r4
    mov r2, #0
    strb r2, [r1]
    bx lr

input_too_long: @ No se usa en la práctica con read limitado a 80 bytes
    b print_error_and_exit

input_too_long_strict: @ Caso: 80 chars sin salto de línea
print_error_and_exit:
    mov r0, #1
    ldr r1, =len_error_msg
    mov r2, #52
    mov r7, #4
    swi 0
    b salir

@ ──────────────────────────────────────────────
@ Cuenta letras (r5) y palabras (r6) en buffer de entrada
@ Devuelve: r0=letras, r1=palabras
@ ──────────────────────────────────────────────
contar_letras:
    push {r4-r9, lr}
    mov r5, #0          @ r5: Contador de letras
    mov r6, #0          @ r6: Contador de palabras
    mov r9, #0          @ r9: Estado actual: 0 = fuera de palabra, 1 = dentro de palabra

.Lcontar_loop:
    ldrb r2, [r0], #1
    cmp r2, #0
    beq .Lfin_conteo_final

    cmp r2, #' '; beq .Lcontar_es_separador
    cmp r2, #'
'; beq .Lcontar_es_separador
    cmp r2, #'	'; beq .Lcontar_es_separador

    cmp r2, #0xC3
    bne .Lcontar_single_byte_char_for_count

    ldrb r3, [r0]
    cmp r3, #0xA1; beq .Lcontar_utf8_char_found_for_count
    cmp r3, #0xA9; beq .Lcontar_utf8_char_found_for_count
    cmp r3, #0xAD; beq .Lcontar_utf8_char_found_for_count
    cmp r3, #0xB3; beq .Lcontar_utf8_char_found_for_count
    cmp r3, #0xBA; beq .Lcontar_utf8_char_found_for_count
    cmp r3, #0xBC; beq .Lcontar_utf8_char_found_for_count
    cmp r3, #0xB1; beq .Lcontar_utf8_char_found_for_count
    b .Lcontar_single_byte_char_logic_for_count

.Lcontar_utf8_char_found_for_count:
    add r0, r0, #1      @ Consumir segundo byte UTF-8
    b .Lcontar_single_byte_char_logic_for_count

.Lcontar_single_byte_char_for_count:
.Lcontar_single_byte_char_logic_for_count:
    add r5, r5, #1
    cmp r9, #0
    beq .Lcontar_inicio_palabra_for_count
    b .Lcontar_loop

.Lcontar_es_separador:
    mov r9, #0
    b .Lcontar_loop

.Lcontar_inicio_palabra_for_count:
    mov r9, #1
    add r6, r6, #1
    b .Lcontar_loop

.Lfin_conteo_final:
    mov r0, r5
    mov r1, r6
    pop {r4-r9, lr}
    bx lr

@ ──────────────────────────────────────────────
@ Traduce el texto en buffer de entrada a gerigonza o español
@ Entradas: r0=buffer entrada, r10=buffer salida, r9=modo
@ Devuelve: r0=letras modificadas, r11=palabras transformadas
@ ──────────────────────────────────────────────
convertir:
    push {r4, r5, lr}
    mov r1, r10
    mov r8, #0          @ Letras modificadas
    mov r11, #0         @ Palabras convertidas

procesar:
    ldrb r2, [r0], #1
    cmp r2, #0
    beq fin_conversion

    cmp r9, #0
    beq esp_a_geri      @ Español a Gerigonza

    @ --- Gerigonza a Español ---
    cmp r2, #0xC3
    bne .L_gs_handle_single_byte_char

    ldrb r3, [r0]
    cmp r3, #0xB1 
    beq .L_gs_write_utf8_pair_and_advance

    cmp r3, #0xA1; beq .L_gs_check_p_after_utf8_vowel
    cmp r3, #0xA9; beq .L_gs_check_p_after_utf8_vowel
    cmp r3, #0xAD; beq .L_gs_check_p_after_utf8_vowel
    cmp r3, #0xB3; beq .L_gs_check_p_after_utf8_vowel
    cmp r3, #0xBA; beq .L_gs_check_p_after_utf8_vowel
    cmp r3, #0xBC; beq .L_gs_check_p_after_utf8_vowel

    strb r2, [r1], #1
    b procesar

.L_gs_check_p_after_utf8_vowel:
    ldrb r4, [r0, #1]
    cmp r4, #'p'
    bne .L_gs_write_utf8_pair_and_advance

    ldrb r5, [r0, #2]
    cmp r5, r2
    bne .L_gs_write_utf8_pair_and_advance

    ldrb r5, [r0, #3]
    cmp r5, r3
    bne .L_gs_write_utf8_pair_and_advance
    
    strb r2, [r1], #1
    strb r3, [r1], #1
    add r0, r0, #4
    add r8, r8, #3
    add r11, r11, #1
    b procesar

.L_gs_write_utf8_pair_and_advance:
    strb r2, [r1], #1
    strb r3, [r1], #1
    add r0, r0, #1
    b procesar

.L_gs_handle_single_byte_char:
    mov r4, r2
    cmp r4, #'a'; beq .L_gs_check_p_after_single_vowel
    cmp r4, #'e'; beq .L_gs_check_p_after_single_vowel
    cmp r4, #'i'; beq .L_gs_check_p_after_single_vowel
    cmp r4, #'o'; beq .L_gs_check_p_after_single_vowel
    cmp r4, #'u'; beq .L_gs_check_p_after_single_vowel
    b .L_gs_write_single_r2_and_procesar

.L_gs_check_p_after_single_vowel:
    ldrb r3, [r0]
    cmp r3, #'p'
    bne .L_gs_write_single_r2_and_procesar

    ldrb r5, [r0, #1]
    cmp r5, r4
    bne .L_gs_write_single_r2_and_procesar

    strb r4, [r1], #1
    add r0, r0, #2
    add r8, r8, #2
    add r11, r11, #1
    b procesar

.L_gs_write_single_r2_and_procesar:
    strb r2, [r1], #1
    b procesar

@ ---- Español a Gerigonza ----
esp_a_geri:
    cmp r2, #0xC3
    bne .L_s2g_process_single_byte

    ldrb r3, [r0]
    cmp r3, #0xB1 
    beq .L_s2g_write_utf8_pair_and_advance_consonant

    cmp r3, #0xA1; beq .L_s2g_apply_gerigonza_to_utf8_vowel_pair
    cmp r3, #0xA9; beq .L_s2g_apply_gerigonza_to_utf8_vowel_pair
    cmp r3, #0xAD; beq .L_s2g_apply_gerigonza_to_utf8_vowel_pair
    cmp r3, #0xB3; beq .L_s2g_apply_gerigonza_to_utf8_vowel_pair
    cmp r3, #0xBA; beq .L_s2g_apply_gerigonza_to_utf8_vowel_pair
    cmp r3, #0xBC; beq .L_s2g_apply_gerigonza_to_utf8_vowel_pair

    strb r2, [r1], #1
    b procesar

.L_s2g_write_utf8_pair_and_advance_consonant:
    strb r2, [r1], #1
    strb r3, [r1], #1
    add r0, r0, #1
    b procesar

.L_s2g_apply_gerigonza_to_utf8_vowel_pair:
    strb r2, [r1], #1
    strb r3, [r1], #1
    mov r4, #'p'
    strb r4, [r1], #1
    strb r2, [r1], #1
    strb r3, [r1], #1
    add r0, r0, #1
    add r8, r8, #2
    add r11, r11, #1
    b procesar

.L_s2g_process_single_byte:
    strb r2, [r1], #1

    cmp r2, #'a'; beq .L_s2g_apply_gerigonza_to_single_ascii_vowel
    cmp r2, #'e'; beq .L_s2g_apply_gerigonza_to_single_ascii_vowel
    cmp r2, #'i'; beq .L_s2g_apply_gerigonza_to_single_ascii_vowel
    cmp r2, #'o'; beq .L_s2g_apply_gerigonza_to_single_ascii_vowel
    cmp r2, #'u'; beq .L_s2g_apply_gerigonza_to_single_ascii_vowel
    
    b procesar

.L_s2g_apply_gerigonza_to_single_ascii_vowel:
    mov r3, #'p'
    strb r3, [r1], #1
    strb r2, [r1], #1
    add r8, r8, #2
    add r11, r11, #1
    b procesar

fin_conversion:
    mov r3, #0
    strb r3, [r1]
    mov r0, r8
    pop {r4, r5, pc}

@ ──────────────────────────────────────────────
@ Calcula longitud de la cadena traducida en 'output'
@ Devuelve la longitud en r0
@ ──────────────────────────────────────────────
calcular_longitud_output:
    push {r1-r3, lr}
    ldr r0, =output
    mov r1, #0
.Lcalc_len_loop:
    ldrb r2, [r0], #1
    cmp r2, #0
    beq .Lcalc_len_done
    add r1, r1, #1
    b .Lcalc_len_loop
.Lcalc_len_done:
    mov r0, r1
    pop {r1-r3, lr}
    bx lr

@ ──────────────────────────────────────────────
@ Escribe contenido en archivo. Retorna 0 o -1
@ Entradas: r0=filename_addr, r1=content_addr, r2=content_length, r3=permissions
@ ──────────────────────────────────────────────
escribir_archivo:
    push {r4-r7, lr}

    mov r4, r0
    mov r5, r1
    mov r6, r2

    mov r0, r4
    mov r1, r3
    mov r7, #8          @ syscall sys_creat
    swi 0

    cmp r0, #-1
    beq .L_escribir_error

    mov r3, r0

    mov r0, r3
    mov r1, r5
    mov r2, r6
    mov r7, #4
    swi 0
    cmp r0, #0
    blt .L_escribir_close_anyway

.L_escribir_close_anyway:
    mov r0, r3
    mov r7, #6
    swi 0

    mov r0, #0
    pop {r4-r7, lr}
    bx lr

.L_escribir_error:
    mov r0, #-1
    pop {r4-r7, lr}
    bx lr

@ ──────────────────────────────────────────────
@ Imprime el texto traducido a consola
@ ──────────────────────────────────────────────
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

@ ──────────────────────────────────────────────
@ Imprime estadísticas de procesamiento y conversión
@ ──────────────────────────────────────────────
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
    mov r2, #30
    mov r7, #4
    swi 0
    mov r0, r6
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

    @ Porcentaje de modificación
    mov r0, #1
    ldr r1, =porc_msg
    mov r2, #29
    mov r7, #4
    swi 0

    mov r0, #100
    mul r0, r4, r0
    udiv r0, r0, r5
    bl numero_a_ascii

    @ Símbolo de porcentaje y cierre
    mov r0, #1
    ldr r1, =porc_sym
    mov r2, #20
    mov r7, #4
    swi 0

    pop {r4-r7, lr}
    bx lr

@ ──────────────────────────────────────────────
@ Imprime un número decimal a consola (en ASCII)
@ Entrada: r0 = número a imprimir
@ ──────────────────────────────────────────────
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

@ ──────────────────────────────────────────────
@ Finaliza la ejecución del programa
@ ──────────────────────────────────────────────

salir:
    mov r7, #1
    swi 0