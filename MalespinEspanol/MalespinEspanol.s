.section .data
@ ──────────────────────────────────────────────
@ === DATOS ESTÁTICOS ===
@ Descripción: Cadenas y recursos para interacción con el usuario
@ Restricciones: No exceder longitudes asignadas
@ ──────────────────────────────────────────────
prompt_input:       .asciz "Ingrese 1 para consola, 2 para archivo: "
prompt_file:        .asciz "Ingrese el nombre del archivo: "
prompt_lang:        .asciz "¿Fuente en español (s) o malespín (m)? "
output_file:        .asciz "convertido.txt"
error_msg:          .asciz "Error al abrir archivo\n"
error_longitud_msg: .asciz "Error: Palabra demasiado larga (máx 80 caracteres)\n"
error_tamano:       .asciz "Error: El archivo excede el tamaño máximo de 2KB\n"
output_msg:         .asciz "\nTexto convertido: "
stats_msg:          .asciz "\nEstadísticas:\n==================\n     "
letras_msg:         .asciz "\nTotal de letras ingresadas: "
palabras_msg:       .asciz "\nTotal de palabras ingresadas: "
conv_msg:           .asciz "\nPalabras convertidas: "
mod_msg:            .asciz "\nLetras modificadas: "
porc_msg:           .asciz "\nPorcentaje de modificación: "
porc_sym:           .asciz "%\n==================\n"
num_buffer:         .space 12

.align 2
translation_table:
    .fill 256, 1, 0

.section .bss
@ ──────────────────────────────────────────────
@ === MEMORIA DINÁMICA (NO INICIALIZADA) ===
@ Descripción: Buffers y contadores necesarios para procesamiento
@ Restricciones:
@   buffer: máx 2048 bytes
@   filecontent/output: suficiente tamaño para procesado
@ ──────────────────────────────────────────────
.lcomm filename, 256
.lcomm filecontent, 4096
.lcomm buffer, 2048
.lcomm output, 4096
.lcomm total_letras, 4
.lcomm total_palabras, 4
.lcomm conv_palabras, 4
.lcomm conv_letras, 4

.section .text
.global _start

@ ──────────────────────────────────────────────
@ === PUNTO DE ENTRADA PRINCIPAL ===
@ Inicializa la tabla y dirige el flujo según el tipo de entrada
@ ──────────────────────────────────────────────
_start:
    bl init_table

    @ Solicita modo de entrada al usuario
    mov r0, #1
    ldr r1, =prompt_input
    mov r2, #41
    mov r7, #4
    swi 0

    @ Lee selección de modo (consola o archivo)
    mov r0, #0
    ldr r1, =buffer
    mov r2, #2
    mov r7, #3
    swi 0

    @ Redirecciona flujo según la selección del usuario
    ldrb r0, [r1]
    cmp r0, #'1'
    beq leer_consola
    cmp r0, #'2'
    beq leer_archivo
    b salir

@ ──────────────────────────────────────────────
@ Lee texto desde consola
@ Entrada: stdin
@ Salida: buffer ← texto ingresado
@ Restricción: máx 4096 bytes
@ ──────────────────────────────────────────────
leer_consola:
    mov r0, #0
    ldr r1, =buffer
    mov r2, #4096
    mov r7, #3
    swi 0

    mov r4, r0          @ Guarda longitud del texto ingresado
    mov r12, #1         @ Marca modo consola

    bl contar_letras
    bl convertir
    bl imprimir_salida

@ ──────────────────────────────────────────────
@ Lee texto desde archivo con nombre solicitado
@ Restricciones:
@   - archivo: máx 2 KiB, debe existir y ser legible
@   - nombre: hasta 256 caracteres
@ ──────────────────────────────────────────────
leer_archivo:
    @ Solicita nombre del archivo
    mov r0, #1
    ldr r1, =prompt_file
    mov r2, #31
    mov r7, #4
    swi 0

    @ Lee nombre de archivo desde entrada estándar
    mov r0, #0
    ldr r1, =filename
    mov r2, #256
    mov r7, #3
    swi #0

    @ Procesa nombre del archivo (quita salto de línea final)
    cmp r0, #0
    ble error_archivo
    sub r0, r0, #1
    ldr r1, =filename
    mov r2, #0
    strb r2, [r1, r0]

    @ Intenta abrir el archivo
    ldr r0, =filename
    mov r1, #0          @ 0_RDONLY
    mov r7, #5          @ sys_open
    swi #0

    cmp r0, #-1
    beq error_archivo

    @ Lee contenido del archivo en buffer
    mov r3, r0
    ldr r1, =buffer
    mov r2, #2048
    mov r7, #3
    swi #0

    mov r4, r0          @ Guarda longitud del texto leído

    cmp r4, #2048
    blt procesar_archivo

    @ Si excede tamaño permitido, muestra error
    mov r0, #1
    ldr r1, =error_tamano
    mov r2, #51
    mov r7, #4
    swi 0

    @ Cierra archivo y termina
    mov r0, r3
    mov r7, #6
    swi 0
    b salir

@ Marca modo archivo y procesa el texto
procesar_archivo:
    mov r12, #2         @ Marca modo archivo

    bl contar_letras
    bl convertir
    bl imprimir_estadisticas

    @ Cierra archivo
    mov r0, r3
    mov r7, #6
    swi 0

@ ──────────────────────────────────────────────
@ Recorre cada carácter y lo procesa o traduce
@ ──────────────────────────────────────────────
bucle:
    ldrb r2, [r0], #1
    cmp r2, #0
    beq fin_procesamiento

    @ Detecta inicio de nueva palabra
    cmp r9, #0
    bne en_palabra
    add r6, r6, #1
    mov r9, #1
    mov r10, #0

@ Traduce el carácter o lo mantiene
en_palabra:
    ldr r3, =translation_table
    ldrb r3, [r3, r2]
    cmp r3, #0
    moveq r3, r2
    strb r3, [r1], #1

    @ Contabiliza cambios
    cmp r3, r2
    beq sin_cambio
    add r8, #1
    mov r10, #1

sin_cambio:
    b bucle

espacio:
    strb r2, [r1], #1
    cmp r9, #0
    beq bucle
    mov r9, #0
    cmp r10, #0
    beq bucle
    add r11, #1
    b bucle

fin_procesamiento:
    cmp r12, #2
    beq escribir_archivo
    b mostrar_consola

@ ──────────────────────────────────────────────
@ Cuenta letras y palabras en el buffer de entrada
@ Restricción: cada palabra máx 80 caracteres
@ ──────────────────────────────────────────────
contar_letras:
    push {r4, lr}
    ldr r0, =buffer
    mov r5, #0          @ Contador de letras total
    mov r6, #0          @ Contador de palabras
    mov r9, #0          @ Estado palabra (0: fuera, 1: dentro)
    mov r4, #0          @ Letras en palabra actual

contar_loop:
    ldrb r2, [r0], #1
    cmp r2, #0
    beq fin_conteo

    @ Verifica si es separador
    cmp r2, #' '
    beq es_separador
    cmp r2, #'\n'
    beq es_separador
    cmp r2, #'\t'
    beq es_separador

    add r4, r4, #1      @ Incrementa conteo de letras en palabra

    cmp r4, #80
    ble longitud_ok

    @ Si excede, error y termina
    mov r0, #1
    ldr r1, =error_longitud_msg
    mov r2, #52
    mov r7, #4
    swi 0
    b salir

longitud_ok:
    add r5, r5, #1
    cmp r9, #0
    beq nueva_palabra
    b contar_loop

nueva_palabra:
    add r6, r6, #1
    mov r9, #1
    b contar_loop

es_separador:
    mov r4, #0
    b contar_loop

fin_conteo:
    pop {r4, lr}
    bx lr

@ ──────────────────────────────────────────────
@ Convierte el texto del buffer aplicando tabla de traducción
@ Salida: output ← texto convertido, actualiza contadores de cambios
@ ──────────────────────────────────────────────
convertir:
    ldr r0, =buffer
    ldr r1, =output
    mov r8, #0          @ Letras convertidas
    mov r11, #1         @ Palabras modificadas

procesar:
    ldrb r2, [r0], #1
    cmp r2, #0
    beq fin_conversion

    cmp r2, #'\n'
    beq es_espacio
    cmp r2, #' '
    beq es_espacio
    cmp r2, #'\''
    beq es_espacio
    b en_palabra

es_espacio:
    b procesar

fin_conversion:
    mov r2, #0
    bx lr

@ ──────────────────────────────────────────────
@ Muestra en consola el texto convertido
@ ──────────────────────────────────────────────
mostrar_consola:
    mov r0, #1
    ldr r1, =output_msg
    mov r2, #19
    mov r7, #4
    swi 0

    mov r0, #1
    ldr r1, =output
    mov r2, r4
    mov r7, #4
    swi 0

@ ──────────────────────────────────────────────
@ Escribe el texto convertido en un archivo de salida
@ ──────────────────────────────────────────────
escribir_archivo:
    mov r7, #8
    ldr r0, =output_file
    mov r1, #0777
    swi 0

    cmp r0, #-1
    beq error_archivo

    mov r3, r0
    ldr r1, =output
    mov r2, r4
    mov r7, #4
    swi 0

    bl imprimir_estadisticas
    b salir

@ ──────────────────────────────────────────────
@ Imprime el encabezado y el texto convertido por consola
@ ──────────────────────────────────────────────
imprimir_salida:
    mov r0, #1
    ldr r1, =output_msg
    mov r2, #19
    mov r7, #4
    swi 0

    mov r0, #1
    ldr r1, =output
    mov r2, #0

@ ──────────────────────────────────────────────
@ Muestra mensaje de error al fallar apertura o escritura de archivo
@ ──────────────────────────────────────────────
error_archivo:
    mov r0, #1
    ldr r1, =error_msg
    mov r2, #23
    mov r7, #4
    swi 0
    b salir

@ ──────────────────────────────────────────────
@ Inicializa la tabla de traducción (español <-> malespín)
@ ──────────────────────────────────────────────
init_table:
    ldr r0, =translation_table
    mov r1, #0
1:
    strb r1, [r0, r1]
    add r1, #1
    cmp r1, #256
    blt 1b

    ldr r0, =translation_table

    @ a <-> e
    mov r1, #'a'
    mov r2, #'e'
    strb r2, [r0, r1]
    strb r1, [r0, r2]
    @ A <-> E
    mov r1, #'A'
    mov r2, #'E'
    strb r2, [r0, r1]
    strb r1, [r0, r2]
    @ i <-> o
    mov r1, #'i'
    mov r2, #'o'
    strb r2, [r0, r1]
    strb r1, [r0, r2]
    @ I <-> O
    mov r1, #'I'
    mov r2, #'O'
    strb r2, [r0, r1]
    strb r1, [r0, r2]
    @ b <-> t
    mov r1, #'b'
    mov r2, #'t'
    strb r2, [r0, r1]
    strb r1, [r0, r2]
    @ B <-> T
    mov r1, #'B'
    mov r2, #'T'
    strb r2, [r0, r1]
    strb r1, [r0, r2]
    @ f <-> g
    mov r1, #'f'
    mov r2, #'g'
    strb r2, [r0, r1]
    strb r1, [r0, r2]
    @ F <-> G
    mov r1, #'F'
    mov r2, #'G'
    strb r2, [r0, r1]
    strb r1, [r0, r2]
    @ p <-> m
    mov r1, #'p'
    mov r2, #'m'
    strb r2, [r0, r1]
    strb r1, [r0, r2]
    @ P <-> M
    mov r1, #'P'
    mov r2, #'M'
    strb r2, [r0, r1]
    strb r1, [r0, r2]

    @ Caracteres extendidos ASCII para vocales acentuadas
    @ á (0xA1) <-> é (0xA9)
    mov r1, #0xA1
    mov r2, #0xA9
    strb r2, [r0, r1]
    strb r1, [r0, r2]
    @ Á (0x81) <-> É (0x89)
    mov r1, #0x81
    mov r2, #0x89
    strb r2, [r0, r1]
    strb r1, [r0, r2]
    @ í (0xAD) <-> ó (0xB3)
    mov r1, #0xAD
    mov r2, #0xB3
    strb r2, [r0, r1]
    strb r1, [r0, r2]
    @ Í (0x8D) <-> Ó (0x93)
    mov r1, #0x8D
    mov r2, #0x93
    strb r2, [r0, r1]
    strb r1, [r0, r2]
    @ ä (0xA4) <-> ë (0xAB)
    mov r1, #0xA4
    mov r2, #0xAB
    strb r2, [r0, r1]
    strb r1, [r0, r2]
    @ Ä (0x84) <-> Ë (0x8B)
    mov r1, #0x84
    mov r2, #0x8B
    strb r2, [r0, r1]
    strb r1, [r0, r2]
    @ ï (0xAF) <-> ö (0xB6)
    mov r1, #0xAF
    mov r2, #0xB6
    strb r2, [r0, r1]
    strb r1, [r0, r2]
    @ Ï (0x8F) <-> Ö (0x96)
    mov r1, #0x8F
    mov r2, #0x96
    strb r2, [r0, r1]
    strb r1, [r0, r2]

    bx lr

@ ──────────────────────────────────────────────
@ Imprime las estadísticas de conversión y procesamiento
@ ──────────────────────────────────────────────
imprimir_estadisticas:
    push {r4-r7, lr}

    @ Encabezado
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
    mov r0, r8
    bl numero_a_ascii

    @ Porcentaje de modificación
    mov r0, #1
    ldr r1, =porc_msg
    mov r2, #29
    mov r7, #4
    swi 0

    mov r0, #100
    mul r0, r8, r0
    udiv r0, r0, r5
    bl numero_a_ascii

    @ Símbolo de porcentaje y cierre
    mov r0, #1
    ldr r1, =porc_sym
    mov r2, #22
    mov r7, #4
    swi 0

    pop {r4-r7, lr}
    bx lr

@ ──────────────────────────────────────────────
@ Convierte un número en texto ASCII y lo imprime
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
