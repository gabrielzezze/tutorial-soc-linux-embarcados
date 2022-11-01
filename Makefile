#
TARGET = ./src/board-controller/board_controller
ALT_DEVICE_FAMILY ?= soc_cv_av
SOCEDS_ROOT ?= $(SOCEDS_DEST_ROOT)
HWLIBS_ROOT = $(SOCEDS_ROOT)/ip/altera/hps/altera_hps/hwlib
CROSS_COMPILE = arm-linux-gnueabihf-
CFLAGS = -fPIC -g -Wall  -D$(ALT_DEVICE_FAMILY) -I$(HWLIBS_ROOT)/include/$(ALT_DEVICE_FAMILY)   -I$(HWLIBS_ROOT)/include/
LDFLAGS =  -g -Wall 
CC = $(CROSS_COMPILE)gcc
ARCH= arm

deploy: build
	scp -o "StrictHostKeyChecking no" ./target/arm-unknown-linux-gnueabihf/debug/c-in-rust-tutorial root@169.254.0.13:/home/root/


build: build-lib
	cargo build --target arm-unknown-linux-gnueabihf


build-lib: ./src/board-controller/main.o ./src/board-controller/terasic_lib.o ./src/board-controller/LCD_Lib.o ./src/board-controller/LCD_Driver.o ./src/board-controller/LCD_Hw.o ./src/board-controller/lcd_graphic.o ./src/board-controller/font.o 
	ar rcs ./libboardcontroller.a ./src/board-controller/main.o ./src/board-controller/terasic_lib.o ./src/board-controller/LCD_Lib.o ./src/board-controller/LCD_Driver.o ./src/board-controller/LCD_Hw.o ./src/board-controller/lcd_graphic.o ./src/board-controller/font.o 


%.o : %.c
	$(CC) $(CFLAGS) -c $< -o $@

.PHONY: clean
clean:
	rm -rf $(TARGET) ./src/board-controller/*.a ./src/board-controller/*.o *~ ./main.o ./libboardcontroller.a ./target/
