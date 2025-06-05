# Definición de herramientas del toolchain para ARM de 32 bits (formato ELF para Linux)
AS=arm-linux-gnueabi-as       # Ensamblador
LD=arm-linux-gnueabi-ld       # Enlazador
OBJCOPY=arm-linux-gnueabi-objcopy # Utilidad para convertir formatos (no se usa aquí, pero puede ser útil)

# Archivos fuente, objeto y ejecutable
SRC=MalespinEspanol.s        # Archivo fuente en ensamblador
OBJ=MalespinEspanol.o        # Archivo objeto generado
EXE=MalespinEspanol.elf      # Archivo ejecutable en formato ELF

# Regla por defecto: compila y enlaza el ejecutable
all: $(EXE)

# Regla para compilar el código ensamblador a objeto
$(OBJ): $(SRC)
	$(AS) -o $(OBJ) $(SRC)

# Regla para enlazar el archivo objeto y generar el ejecutable
$(EXE): $(OBJ)
	$(LD) -o $(EXE) $(OBJ)

# Regla para limpiar los archivos generados durante la compilación
clean:
	rm -f *.o *.elf
