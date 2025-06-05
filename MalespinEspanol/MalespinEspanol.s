.section .data
prompt_input: .asciz "Ingrese 1 para consola, 2 para archivo: "
prompt_file: .asciz "Ingrese el nombre del archivo: "
prompt_lang: .asciz "¿Fuente en español (s) o malespín (m)? "
output_file: .asciz "convertido.txt"
error_msg: .asciz "Error al abrir archivo\n"
error_longitud_msg: .asciz "Error: Palabra demasiado larga (máx 80 caracteres)\n"
error_tamano: .asciz "Error: El archivo excede el tamaño máximo de 2KB\n"
output_msg: .asciz "\nTexto convertido: "
stats_msg:      .asciz "\nEstadísticas:\n==================\n     "
letras_msg:     .asciz "\nTotal de letras ingresadas: "
palabras_msg:   .asciz "\nTotal de palabras ingresadas: "
conv_msg:       .asciz "\nPalabras convertidas: "
mod_msg:        .asciz "\nLetras modificadas: "
porc_msg:       .asciz "\nPorcentaje de modificación: "
porc_sym:       .asciz "%\n==================\n"
num_buffer:     .space 12

.align 2
translation_table:
.fill 256, 1, 0

.section .bss
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

_start:
    bl init_table

    @ Solicitar modo de entrada
    mov r0, #1
    ldr r1, =prompt_input
    mov r2, #41
    mov r7, #4
    swi 0

    @ Leer selección
    mov r0, #0
    ldr r1, =buffer
    mov r2, #2
    mov r7, #3
    swi 0

    @ Manda al modo elegido
    ldrb r0, [r1]
    cmp r0, #'1'
    beq leer_consola
    cmp r0, #'2'
    beq leer_archivo
    b salir

@ Lee el mensaje enviado en modo consola
leer_consola:
    mov r0, #0
    ldr r1, =buffer
    mov r2, #4096
    mov r7, #3
    swi 0

    mov r4, r0          @ Guardar longitud del texto
    mov r12, #1         @ Marcar modo consola

    bl contar_letras
    bl convertir
    bl imprimir_salida

@ Lee el texto del archivo de texto
leer_archivo:
    @ Pedir nombre del archivo
    mov r0, #1
    ldr r1, =prompt_file
    mov r2, #31
    mov r7, #4
    swi 0

    @ Leer nombre del archivo
    mov r0, #0
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
    mov r3, r0
    ldr r1, =buffer
    mov r2, #2048
    mov r7, #3
    swi #0

    mov r4, r0          @ Guardar longitud del texto leído

    cmp r4, #2048       @ Revisa el tamaño del archivo
    blt procesar_archivo      @ Si tiene menos de 2048 caracteres (2 KiB), continúa

    @ Si no, muestra error de tamaño
    mov r0, #1
    ldr r1, =error_tamano
    mov r2, #51
    mov r7, #4
    swi 0
    
    @ Cerrar archivo y salir
    mov r0, r3
    mov r7, #6
    swi 0
    b salir

@ Marca modo archivo y procesa el texto
procesar_archivo:
    mov r12, #2         @ Marcar modo archivo
    
    bl contar_letras
    bl convertir
    bl imprimir_estadisticas

    @ Cerrar archivo
    mov r0, r3          
    mov r7, #6
    swi 0

@ Va por cada caracter y lo opera
bucle:
    ldrb r2, [r0], #1
    cmp r2, #0          @ Fin de texto
    beq fin_procesamiento

    @ Nueva palabra
    cmp r9, #0
    bne en_palabra
    add r6, r6, #1
    mov r9, #1
    mov r10, #0

@ Traduce el caracter o lo mantiene
en_palabra:
    @ Traducir caracter
    ldr r3, =translation_table
    ldrb r3, [r3, r2]
    cmp r3, #0
    moveq r3, r2        @ Si no hay traducción, mantener original
    strb r3, [r1], #1

    @ Contar cambios
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
    @ Verificar modo de salida
    cmp r12, #2
    beq escribir_archivo
    b mostrar_consola

@ Inicializa contadores
contar_letras:
    push {r4, lr}
    ldr r0, =buffer
    mov r5, #0          @ Contador de letras
    mov r6, #0          @ Contador de palabras
    mov r9, #0          @ Estado de palabra (1 es palabra convertida, 0 no lo es)
    mov r4, #0          @ Contador de letras en palabra actual

@ Bucle de caracteres
contar_loop:
    ldrb r2, [r0], #1
    cmp r2, #0
    beq fin_conteo

    @ Si es un espacio, pasa al siguiente
    cmp r2, #' '
    beq es_separador
    cmp r2, #'\n'
    beq es_separador
    cmp r2, #'\t'
    beq es_separador
    
    add r4, r4, #1      @ Aumenta el contador de letras por palabra

    cmp r4, #80         @ Compara la longitud de la palabra
    ble longitud_ok     @ Si es menor a 80, el programa continúa

    @ Si la palabra es demasiado larga, lanza error
    mov r0, #1
    ldr r1, =error_longitud_msg
    mov r2, #52
    mov r7, #4
    swi 0
    b salir

@ Si la palabra es menor a 80 caracteres,
@ Añade un caracter al contador y añade una nueva palabra
longitud_ok:
    add r5, r5, #1
    cmp r9, #0
    beq nueva_palabra
    b contar_loop

nueva_palabra:
    add r6, r6, #1      @ Incrementar contador de palabras
    mov r9, #1          @ Marcar palabra
    b contar_loop

es_separador:
    mov r4, #0          @ resetear contador de letras por palabra
    b contar_loop

fin_conteo:
    pop {r4, lr}
    bx lr

@ Obtiene el buffer e inicializa los contadores
@ de letras y palabras modificadas
convertir:
    ldr r0, =buffer
    ldr r1, =output
    mov r8, #0          @ letras convertidas
    mov r11, #1         @ palabras modificadas

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

@ Muestra el texto convertido en la consola
mostrar_consola:
    @ Mostrar mensaje de salida
    mov r0, #1
    ldr r1, =output_msg
    mov r2, #19
    mov r7, #4
    swi 0

    @ Mostrar texto convertido
    mov r0, #1
    ldr r1, =output
    mov r2, r4
    mov r7, #4
    swi 0

@ Escribe en un nuevo archivo de texto el texto traducido
escribir_archivo:
    mov r7, #8
    ldr r0, =output_file
    mov r1, #0777
    swi 0

    cmp r0, #-1
    beq error_archivo

    mov r3, r0          @ Guardar descriptor
    ldr r1, =output
    mov r2, r4
    mov r7, #4
    swi 0

    bl imprimir_estadisticas
    b salir

@ Mensaje previo al texto convertido
imprimir_salida:
    mov r0, #1
    ldr r1, =output_msg
    mov r2, #19
    mov r7, #4
    swi 0

    mov r0, #1
    ldr r1, =output
    mov r2, #0

error_archivo:
    mov r0, #1
    ldr r1, =error_msg
    mov r2, #23
    mov r7, #4
    swi 0
    b salir

@ La tabla de traducción
init_table:
    @ Inicializar tabla
    ldr r0, =translation_table
    mov r1, #0
1:  
    strb r1, [r0, r1]
    add r1, #1
    cmp r1, #256
    blt 1b

    @ Mapeos malespín
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
    
    @ Caracteres de ASCII extendido
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
    mov r2, #22
    mov r7, #4
    swi 0

    pop {r4-r7, lr}
    bx lr

@ Convierte números a su caracter ASCII
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
