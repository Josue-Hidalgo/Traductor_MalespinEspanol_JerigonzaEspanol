#*************************************************
# Executable name : JerigonzaEspanol
# Authors : Grupo #6
# Description : Simple makefile for GAS
#*************************************************

name=JerigonzaEspanol
ASM=as

# Program to use as linker
LINKER=ld

# Link executable
$(name): $(name).o
	$(LINKER) -o $(name) $(name).o

# Assemble source code
$(name).o: $(name).s
	$(ASM) $(ASM_F) -o $(name).o $(name).s
