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
    moveq r10, #0      @ español a gerigonza
    cmp r0, #'g'
    moveq r10, #1      @ gerigonza a español
    bx lr

modo_consola:
    bl leer_entrada
    bl contar_letras
    bl convertir
    bl imprimir_salida
    bl imprimir_estadisticas
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
    @ Pedir nombre del archivo
    mov r0, #1
    ldr r1, =prompt_file
    mov r2, #31
    mov r7, #4
    swi 0

    mov r0, #0          @ stdin
    ldr r1, =filename
    mov r2, #256
    mov r7, #3          @ sys_read
    swi #0

    @ Procesar nombre del archivo
    cmp r0, #0
    ble error_archivo
    sub r0, r0, #1
    ldr r1, =filename
    mov r2, #0
    strb r2, [r1, r0]

    @ Abrir archivo
    ldr r0, =filename
    mov r1, #0          @ 0_RDONLY
    mov r7, #5          @ sys_open
    swi #0

    cmp r0, #-1
    beq error_archivo

    @ Leer contenido del archivo
    mov r5, r0
    ldr r1, =buffer
    mov r2, #4096
    mov r7, #3          @ sys_read
    swi #0

    mov r4, r0          @ Guardar longitud del texto leído
    mov r12, #2         @ Marcar modo archivo
    
    mov r0, r5
    mov r7, #6
    swi 0
    
    bl contar_letras
    bl convertir
    bl escribir_archivo @ Si es modo archivo, escribir a archivo
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
    push {lr}
    ldr r0, =buffer
    mov r5, #0          @ Contador de letras
    mov r6, #0          @ Contador de palabras
    mov r9, #0          @ Estado de palabra

contar_loop:
    ldrb r2, [r0], #1
    cmp r2, #0
    beq fin_conteo

    cmp r2, #' '
    beq es_separador
    cmp r2, #'\n'
    beq es_separador
    cmp r2, #'\t'
    beq es_separador
    
    add r5, r5, #1
    
    cmp r9, #0
    moveq r9, #1
    beq nueva_palabra
    b contar_loop

es_separador:
    cmp r9, #1
    moveq r9, #0
    b contar_loop

nueva_palabra:
    add r6, r6, #1
    b contar_loop

fin_conteo:
    cmp r9, #1
    addeq r6, r6, #1
    pop {lr}
    bx lr

convertir:
    ldr r0, =buffer
    ldr r1, =output
    mov r8, #0          @ letras convertidas
    mov r11, #0         @ palabras modificadas
    mov r9, #0          @ estado palabra

procesar:
    ldrb r2, [r0], #1
    cmp r2, #0
    beq fin_conversion

    cmp r2, #'\n'
    beq es_espacio
    cmp r2, #' '
    beq es_espacio
    cmp r2, #9
    beq es_espacio
    b no_espacio

es_espacio:
    strb r2, [r1], #1
    cmp r9, #1
    moveq r9, #0
    addeq r11, r11, #1
    b procesar

no_espacio:
    cmp r9, #0
    moveq r9, #1

    cmp r10, #0
    beq esp_a_geri

    mov r4, r2
    cmp r4, #'a'
    beq es_vocal
    cmp r4, #'e'
    beq es_vocal
    cmp r4, #'i'
    beq es_vocal
    cmp r4, #'o'
    beq es_vocal
    cmp r4, #'u'
    beq es_vocal
    b copiar_normal

es_vocal:
    ldrb r3, [r0]
    cmp r3, #'p'
    bne copiar_normal

    ldrb r5, [r0, #1]
    cmp r5, r4
    bne copiar_normal

    strb r4, [r1], #1
    add r0, r0, #2
    add r8, r8, #2
    b procesar

copiar_normal:
    strb r2, [r1], #1
    b procesar

esp_a_geri:
    strb r2, [r1], #1
    cmp r2, #'a'
    beq agregar_pvocal
    cmp r2, #'e'
    beq agregar_pvocal
    cmp r2, #'i'
    beq agregar_pvocal
    cmp r2, #'o'
    beq agregar_pvocal
    cmp r2, #'u'
    beq agregar_pvocal
    b procesar

agregar_pvocal:
    mov r3, #'p'
    strb r3, [r1], #1
    strb r2, [r1], #1
    add r8, r8, #2
    b procesar

fin_conversion:
    cmp r9, #1
    addeq r11, r11, #1
    mov r2, #0
    strb r2, [r1]
    bx lr

escribir_archivo:
    mov r7, #8
    ldr r0, =output_file
    mov r1, #0777
    swi 0

    cmp r0, #-1
    beq error_archivo

    mov r5, r0          @ Guardar descriptor
    ldr r1, =output
    mov r2, r4
    mov r7, #4
    swi 0

    bl imprimir_estadisticas
    b salir

error_archivo:
    mov r0, #1
    ldr r1, =error_msg
    mov r2, #23
    mov r7, #4
    swi 0
    b salir

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
    mov r0, r8
    bl numero_a_ascii

    @ Porcentaje
    mov r0, #1
    ldr r1, =porc_msg
    mov r2, #29
    mov r7, #4
    swi 0

    mov r0, #100
    mul r0, r8, r0
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
