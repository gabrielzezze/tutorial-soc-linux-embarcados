# Usando Código C em Rust

- **Alunes:** Gabriel Zezze
- **Curso:** Engenharia da Computação
- **Semestre:** 10
- **Contato:** gabriel@zezze.dev
- **Ano:** 2022

## Legenda

- **Máquina _host_**:
  Computador do desenvolvedor o qual será usado para desenvolver e compilar os programas.


- **Máquina _target_**:
  Placa DE10-Standard com linux.

## Começando

Para seguir esse tutorial é necessário:

- **Hardware:** 

    1. DE10-Standard rodando linux.

- **Softwares (apenas para a máquina _host_):**

    1. [Tutorial de infra fornecido pelo Prof. Rafael Corsi (Compilador para Linux ARM & Bibliotecas para compilar programas para a DE10-Standard)](https://insper.github.io/Embarcados-Avancados/Tutorial-HPS-BuildSystem/)

    2. [_Cargo_ (gerenciador de pacotes para Rust)](https://www.rust-lang.org/tools/install)

- **Documentos:** 

    1. [Usando recursos em C no Rust](https://docs.opentitan.org/doc/ug/rust_for_c/)
    2. [Tutoriais de como manipular os periféricos da placa](https://github.com/Insper/DE10-Standard-v.1.3.0-SystemCD/tree/master/Demonstration)
    3. [Tutorial do Rust sobre _unsafe code_](https://doc.rust-lang.org/book/ch19-01-unsafe-rust.html#using-extern-functions-to-call-external-code)
    4. [Compilação cruzada usando _Cargo_](https://stackoverflow.com/questions/39705213/cross-compiling-rust-from-windows-to-arm-linux)

## Motivação

Os tutoriais disponiveis no GitHub para manipulação dos periféricos da placa oferecem exemplos completos de como interagir com a placa porém usando codigo C que pode ser complexo de debugar e muito provavél do desenvolvedor enfrentar problemas relcionados a manipulação de memória.
Visando reaproveitar os exemplos fornecidos enquanto desenvolvemos programas completos em uma linguagem mais "completa", este tutorial irá demonstrar como usar funções desenvolvidas em C dentro de um programa desenvolvido em [Rust](https://www.rust-lang.org/), uma linguagem de programação conhecida por sua proteção de memoria, gerenciador de pacotes (_Cargo_), sem necessidade de um _runtime_ e tipagem estricta e bem definida.

---

## Compilando o código em C

Antes de entrarmos no código em Rust do projeto precisamos desenvolver as funções em C as quais iremos utilizar, defini-las em um arquivo de cabeçalho _.h_.

Neste tutorial vamos fornecer ao código C funções para manipular e ler o LED, escrever no LCD e funções para inicializar e encerrar as variavéis necessarias para alterar os periféricos da placa.

Nosso _main.h_ defini as 4 funções que foram citadas acima do seguinte jeito:

`src/board-controller/main.h`
```c
void set_led(int active);

int write_on_lcd(char* content, int len);

int read_led();

int _init_virtual_base();

void _close_virtual_base();
```

O arquivo _main.c_ implementa as funções usando os exemplos fornecidos no documentos item _b_:

!!! warning 
    Note que em nosso _main.c_ há varios módulos incluidos. Alguns destes são fornecidos pela instalação da infra no tutorial do Professor Rafael Corsi (Softwares item _a_) e serão referenciados no momento da compilação.
    Outros precisam ser copiados e compilados juntos no momento da compilação do _main.c_.
    Esta separação ficará clara quando criarmos o _Makefile_ para compilar.

`src/board-controller/main.c`
```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include "hwlib.h"
#include "socal/socal.h"
#include "socal/hps.h"
#include "socal/alt_gpio.h"
#include "terasic_os_includes.h"
#include "LCD_Lib.h"
#include "lcd_graphic.h"
#include "font.h"
#include "main.h"

#define HW_REGS_BASE ( ALT_STM_OFST )
#define HW_REGS_SPAN ( 0x04000000 )
#define HW_REGS_MASK ( HW_REGS_SPAN - 1 )

#define USER_IO_DIR     (0x01000000)
#define BIT_LED         (0x01000000)
#define BUTTON_MASK     (0x02000000)

void *virtual_base;
int fd;
LCD_CANVAS LcdCanvas;


int read_led() {
	uint32_t  scan_input;
    int is_active = 0;
    scan_input = alt_read_word( ( virtual_base + ( ( uint32_t )(  ALT_GPIO1_EXT_PORTA_ADDR ) & ( uint32_t )( HW_REGS_MASK ) ) ) );	
	if(~scan_input&BUTTON_MASK) {
        is_active = 1;
    }
	return is_active;
}

void set_led(int active) {
    if(active > 0) {
        alt_setbits_word( ( virtual_base + ( ( uint32_t )( ALT_GPIO1_SWPORTA_DR_ADDR ) & ( uint32_t )( HW_REGS_MASK ) ) ), BIT_LED );
    }
    else  {
        alt_clrbits_word( ( virtual_base + ( ( uint32_t )( ALT_GPIO1_SWPORTA_DR_ADDR ) & ( uint32_t )( HW_REGS_MASK ) ) ), BIT_LED );
    }
}

int write_on_lcd(char* content, int len) {
    LcdCanvas.Width = LCD_WIDTH;
    LcdCanvas.Height = LCD_HEIGHT;
    LcdCanvas.BitPerPixel = 1;
    LcdCanvas.FrameSize = LcdCanvas.Width * LcdCanvas.Height / 8;
    LcdCanvas.pFrame = (void *)malloc(LcdCanvas.FrameSize);
		
	if (LcdCanvas.pFrame == NULL) {
		printf("failed to allocate lcd frame buffer\r\n");
	}
    else { 			
		LCDHW_Init(virtual_base);
		LCDHW_BackLight(true); // turn on LCD backlight
		
        LCD_Init();
    
        // clear screen
        DRAW_Clear(&LcdCanvas, LCD_WHITE);

        // demo grphic api    
        DRAW_Rect(&LcdCanvas, 0,0, LcdCanvas.Width-1, LcdCanvas.Height-1, LCD_BLACK); // retangle
        
		content[len] = '\0';

        DRAW_PrintString(&LcdCanvas, 20, 5, content, LCD_BLACK, &font_16x16);
        DRAW_Refresh(&LcdCanvas);
        free(LcdCanvas.pFrame);
	}    

    return 0;
}


int _init_virtual_base() {
	// map the address space for the LED registers into user space so we can interact with them.
	// we'll actually map in the entire CSR span of the HPS since we want to access various registers within that span
	if( ( fd = open( "/dev/mem", ( O_RDWR | O_SYNC ) ) ) == -1 ) {
		printf( "ERROR: could not open \"/dev/mem\"...\n" );
		return -1;
	}

	virtual_base = mmap( NULL, HW_REGS_SPAN, ( PROT_READ | PROT_WRITE ), MAP_SHARED, fd, HW_REGS_BASE );
	if( virtual_base == MAP_FAILED ) {
		printf( "ERROR: mmap() failed...\n" );
		close( fd );
		return -1;
	}
    alt_setbits_word( ( virtual_base + ( ( uint32_t )( ALT_GPIO1_SWPORTA_DDR_ADDR ) & ( uint32_t )( HW_REGS_MASK ) ) ), USER_IO_DIR );
    return 0;
}

void _close_virtual_base() {
    // clean up our memory mapping and exit
	if( munmap( virtual_base, HW_REGS_SPAN ) != 0 ) {
		printf( "ERROR: munmap() failed...\n" );
		close( fd );
	}

	close( fd );
}

```

Agora precisamos criar um _Makefile_ para compilarmos nosso programa C em uma biblioteca estática para isso primeiro precisamos compilar os arquivos _.c_ em arquivos _.o_ (código C compilado porém não executavél) e após isso podemos arquivar todos os arquivos _.o_ gerados e uma biblioteca estática _.a_.

!!! info
    Bibliotecas estáticas nada mais são que todos os arquivos em C do seu programa compilados (_.o_) agrupados em um arquivo que pode ser usado em qualquer programa C exatamente como uma biblioteca baixada pelo _pip_ ou _npm_. [Mais informações](https://medium.com/@StueyGK/what-is-c-static-library-fb895b911db1)

!!! warning
    Vale lembrar que bibliotecas estáticas devem possuir o prefixo _lib_ para serem reconhecidas por programas C e programas em Rust

Como vamos compilar para executar na placa temos que usar o GCC apropriado fornecido pela instalação no tutorial de configuração de infra do Professor Rafael Corsi e também fazer referencia as bibliotecs do sistema da placa também fornecido pelo tutorial de configuração da infra.

Segue o _Makefile_ deste tutorial:

```make
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

```

O comando em questão é o comando `build-lib` o qual depende dos arquivos da biblioteca estática em C os quais são compilados usando o GCC apropriado (`arm-linux-gnueabihf-gcc`)  e faz referência aos arquivos do sistema da placa.

!!! warning
    Caso tenha alterado algum caminho durante o tutorial de infra não esqueça de alterar seu _.bashrc_ e _Makefile_ com os caminhos apropriados.

Após gerar os objetos compilados _.o_ usamos o comando `ar rcs ./libboardcontroller.a (...arquivos .o)` (comando `build-lib` do _Makefile_) para gerarmos a biblioteca estática `libboardcontroller.a` a qual possui nossa funções desenvolvidas com todas as dependências.

---

## Desenvolvendo código em Rust usando a biblioteca estática

Agora vamos iniciar nosso projeto em Rust e desenvolver um programa simples em Rust o qual manipula o LED e escreve no LCD da placa.

Primeiro vamos iniciar o _Cargo_ na pasta do projeto usando o seguinte comando

```bash
$ cargo init
```

Assim podemos editar nosso arquivo `src/main.rs` (criar o arquivo caso não existir) para definir as funções disponíveis em nossa biblioteca e utiliza-las.

Para definir as funções disponíveis em nossa biblioteca vamos usar o seguinte bloco de código em Rust:

`src/main.rs`
```rust
#[link(name = "boardcontroller")]
extern "C" {
    fn set_led(v: i32) -> ();

    fn read_led() -> i32;

    fn write_on_lcd(s: *const libc::c_char, len: i32) -> i32;
    
    fn _init_virtual_base() -> i32;
    
    fn _close_virtual_base() -> ();
}
```

Este bloco de codigo usa o atributo `#[link]` para linkar a biblioteca estática que geramos (o Rust procura o nome da biblioteca sem o prefixo _"lib"_) e logo abaixo dizemos ao compilador Rust que as funções definidas dentro do bloco `extern "C"` são funções criadas em C que usam o método de chamada de código C e assim dentro deste bloco definimos as funções igual fizemos no _main.h_ porém usando os tipos convertidos para Rust (Por exemplo `int` em C é igual a `i32` em Rust).

!!! info
    É possivel notar que para definirmos o ponteiro de `char` em C usamos o tipo `libc::c_char` derivado do crate `libc`, isto se dá pois o tipo `char` em Rust não é igual ao tipo `char` em C assim precisamos usar os tipos fornecidos pela `libc`.

Por fim agora estamos prontos para desenvolver a função `main` do código Rust o qual faz uso das funções definidas.

`src/main.rs`
```rust 
use std::{thread, time::Duration};
use std::ffi::CString;

#[link(name = "boardcontroller")]
extern "C" {
    fn set_led(v: i32) -> ();

    fn read_led() -> i32;

    fn write_on_lcd(s: *const libc::c_char, len: i32) -> i32;
    
    fn _init_virtual_base() -> i32;
    
    fn _close_virtual_base() -> ();
}

fn main() {
    println!("Bem Vindo ao tutorial de C em Rust!");

    unsafe {
        println!("Init virtual base... V2");
        _init_virtual_base();

        println!("Actual LED Value: {}", read_led());
        thread::sleep(Duration::from_millis(2000));

        println!("Acendendo Led...");
        set_led(1);
        thread::sleep(Duration::from_millis(2000));

        println!("Apagando Led...");
        set_led(0);
        thread::sleep(Duration::from_millis(2000));

        println!("Escrevendo no LCD...");
        let lcd_string = CString::new("Hello World !").expect("Erro ao criar CString");
        write_on_lcd(lcd_string.as_ptr(), lcd_string.as_bytes().len() as i32);
        thread::sleep(Duration::from_millis(2000));


        println!("Closing virtual base...");
        _close_virtual_base();
    }
}
```
















<br></br>
<br></br>
<br></br>
<br></br>
<br></br>
<br></br>
<br></br>
<br></br>
<br></br>
<br></br>
<br></br>
<br></br>
<br></br>


!!! info
Essas duas partes são obrigatórias no tutorial:

    - Nome de vocês
    - Começando
    - Motivação

## Recursos Markdown

Vocês podem usar tudo que já sabem de markdown mais alguns recursos:

!!! note
Bloco de destaque de texto, pode ser:

    - note, example, warning, info, tip, danger

!!! example "Faça assim"
É possível editar o título desses blocos

    !!! warning
        Isso também é possível de ser feito, mas
        use com parcimonia.

??? info
Também da para esconder o texto, usar para coisas
muito grandes, ou exemplos de códigos.

    ```txt
    ...











    oi!
    ```

- **Esse é um texto em destaque**
- ==Pode fazer isso também==

Usar emojis da lista:

:two_hearts: - https://github.com/caiyongji/emoji-list

```c
// da para colocar códigos
 void main (void) {}
```

É legal usar abas para coisas desse tipo:

=== "C"

    ``` c
    #include <stdio.h>

    int main(void) {
      printf("Hello world!\n");
      return 0;
    }
    ```

=== "C++"

    ``` c++
    #include <iostream>

    int main(void) {
      std::cout << "Hello world!" << std::endl;
      return 0;
    }
    ```

Inserir vídeo:

- Abra o youtube :arrow_right: clique com botão direito no vídeo :arrow_right: copia código de incorporação:

<iframe width="630" height="450" src="https://www.youtube.com/embed/UIGsSLCoIhM" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>

!!! tip
Eu ajusto o tamanho do vídeo `width`/`height` para não ficar gigante na página

Imagens você insere como em plain markdown, mas tem a vantagem de poder mudar as dimensões com o marcador `{width=...}`

![](icon-elementos.png)

![](icon-elementos.png){width=200}
