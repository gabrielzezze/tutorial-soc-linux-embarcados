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


- **Repositório:**
    1. O [seguinte repositório](https://github.com/gabrielzezze/tutorial-soc-linux-embarcados) contém um projeto exemplo com todos os arquivos desenvolvidos e necessários para completar este tutorial e serve como uma base para futuras iterações.

## Motivação

Os tutoriais disponiveis no GitHub para manipulação dos periféricos da placa oferecem exemplos completos de como interagir com a placa porém usando código C que pode ser complexo de debugar e muito provável do desenvolvedor enfrentar problemas relacionados a manipulação de memória.
Visando reaproveitar os exemplos fornecidos enquanto desenvolvemos programas complexos em uma linguagem mais "completa", este tutorial irá demonstrar como usar funções desenvolvidas em C dentro de um programa desenvolvido em [Rust](https://www.rust-lang.org/), uma linguagem de programação conhecida por sua proteção de memória, gerenciador de pacotes (_Cargo_), sem necessidade de um _runtime_ e tipagem estricta.

---

## Compilando o código em C

Antes de entrarmos no código em Rust do projeto precisamos desenvolver as funções em C as quais iremos utilizar.

Primeiro iremos defini-las em um arquivo de cabeçalho _main.h_.

Neste tutorial vamos fornecer ao programa em Rust funções escritas em C as quais manipulam o LED da placa, escreve no LCD e funções para inicializar e encerrar as variavéis necessárias para alterar os periféricos da placa.

Nosso _main.h_ define as 4 funções que foram citadas acima do seguinte jeito:

`src/board-controller/main.h`
```c
void set_led(int active);

int write_on_lcd(char* content, int len);

int read_led();

int _init_virtual_base();

void _close_virtual_base();
```

O arquivo _main.c_ implementa as funções usando os exemplos fornecidos no item _b_ dos documentos:

!!! warning 
    Note que em nosso _main.c_ há varios módulos incluidos. Alguns destes são fornecidos pela instalação da infra no [tutorial do Professor Rafael Corsi (Softwares item _a_) (Compilador para Linux ARM & Bibliotecas para compilar programas para a DE10-Standard)](https://insper.github.io/Embarcados-Avancados/Tutorial-HPS-BuildSystem/) e serão referenciados no momento da compilação.
    Outros precisam ser copiados e compilados juntos no momento da compilação do _main.c_.
    Esta separação ficará clara quando criarmos o _Makefile_ para compilar o código em C.

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

Agora precisamos criar um _Makefile_ para compilarmos nosso código C em uma biblioteca estática. Para isso primeiro precisamos compilar os arquivos _.c_ em arquivos _.o_ (código C compilado porém não executável) e após isso podemos arquivar todos os arquivos _.o_ gerados em uma biblioteca estática _.a_.

!!! info
    Bibliotecas estáticas nada mais são que todos os arquivos em C do seu programa compilados (_.o_) agrupados em um arquivo que pode ser usado em qualquer programa C exatamente como uma biblioteca baixada pelo _pip_ ou _npm_. [Mais informações](https://medium.com/@StueyGK/what-is-c-static-library-fb895b911db1)

!!! warning
    Vale lembrar que bibliotecas estáticas devem possuir o prefixo _lib_ para serem reconhecidas por programas em C ou em Rust.

Como vamos compilar para executar na placa temos que usar o GCC apropriado fornecido pela instalação no [tutorial de configuração de infra do Professor Rafael Corsi (Compilador para Linux ARM & Bibliotecas para compilar programas para a DE10-Standard)](https://insper.github.io/Embarcados-Avancados/Tutorial-HPS-BuildSystem/) e também fazer referência as bibliotecas do sistema da placa também fornecidos pelo tutorial de configuração da infra.

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

O comando em questão é o comando `build-lib`, quando rodamos no terminal o seguinte comando:

```bash
$ make build-lib
```


O _Makefile_ irá conferir as dependencias do comando `build-lib`, que são os arquivos da biblioteca estática em C compilados usando o GCC apropriado (`arm-linux-gnueabihf-gcc`) e fazendo referência aos arquivos do sistema da placa.

!!! warning
    Caso tenha alterado algum caminho durante o [tutorial de infra](Compilador para Linux ARM & Bibliotecas para compilar programas para a DE10-Standard)](https://insper.github.io/Embarcados-Avancados/Tutorial-HPS-BuildSystem/) não esqueça de alterar seu _.bashrc_ e _Makefile_ com os caminhos apropriados.

Após gerar os objetos compilados _.o_ o _Makefile_ irá executar o comando `ar rcs ./libboardcontroller.a (...arquivos .o)` (primeiro comando do `build-lib`) para gerarmos a biblioteca estática `libboardcontroller.a` a qual possui nossa funções desenvolvidas com todas as dependências.

---

## Desenvolvendo código em Rust usando a biblioteca estática

Agora vamos iniciar nosso projeto em Rust e desenvolver um programa simples em Rust o qual manipula o LED e escreve no LCD da placa usando as funções em C desenvolvidas anteriormente.

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

Nosso programa Rust irá executar as seguintes tarefas usando as funções definidas pela biblioteca:

1. Ler o estado atual do LED e imprimir no terminal.

2. Manipular o LED para ficar acesso.

3. Manipular o LED para ficar apagado.

4. Escrever no LCD a mensagem "_Hello World!_"

Agora estamos prontos para compilar nosso programa Rust e executa-lo no hardware _target_.




## Compilando o programa em Rust usando _Cargo_

Antes de executarmos comandos com o _Cargo_ para compilar nosso programa devemos instalar o crate `libc` usado no programa e fazer algumas configurações para indicar ao compilador qual GCC queremos usar para esta compilação.

Vamos começar instalando o crate `libc`, para isso é ncessario apenas executar o seguinte comando na raiz do projeto:

```bash
$ cargo add libc
```

Agora vamos configurar o _target_ `arm-unknown-linux-gnueabihf` para usar o GCC apropriado para compilar programas para a placa, primeiramente vamos editar o arquivo `~/.cargo/config` e adicionar as seguintes linhas:


`~/.cargo/config`
```bash
[target.arm-unknown-linux-gnueabihf]
linker = "arm-linux-gnueabihf-gcc"
```

Esta linha diz ao compilador do _Cargo_ que quando pedirmos para compilar o programa para o _target_ `arm-unknown-linux-gnueabihf` o compilador deve usar o seguinte GCC (`arm-linux-gnueabihf-gcc`).


A ultima configuração que precisamos fazer antes de executar comandos do _cargo_ é editar o arquivo `build.rs` na raiz do projeto (criar o arquivo caso não existir) e adicionar as seguintes linhas:

`./build.rs`
```rust
fn main() {
    println!("cargo:rustc-link-search=*caminho_para_diretorio_que_contem_sua_biblioteca_.a*");
}
```

!!! warning
    Não esqueça de alterar este caminho no arquivo `build.rs` quando for executar na sua máquina.


Estas linhas acima dizem ao compilador do Rust para procurar as bibliotecas linkadas em seu código Rust usando o atributor `#[link]` no diretório de sua preferência.

Finalmente podemos usar o comando `build` do _Makefile_ para compilar o programa Rust em um executavel, este comando executa o comando `build-lib` como dependencia para compilar a biblioteca estática e após isso usa o _Cargo_ para compilar o programa Rust em um executavel para a placa.

`Makefile`
```make
build: build-lib
	cargo build --target arm-unknown-linux-gnueabihf
```

!!! info 
    Note que no comando `cargo build` especificamos um target `arm-unknown-linux-gnueabihf`, esta especificação usa a configuração feita anteriormente para determinar o GCC correto para compilar o programa.



## Executando o programa

Finalmente de posse do executavel podemos acessar a placa e ao executar o programa Rust compilado temos o resultados esperado.

1. O programa le o estado atual do LED e imprimi no terminal.

2. O LED é ligado.

3. O LED apaga.

4. Escreve no LCD a mensagem "_Hello World!_".


<iframe width="630" height="450" src="https://player.vimeo.com/video/769181527?h=a752617bd7&amp;badge=0&amp;autopause=0&amp;player_id=0&amp;app_id=58479" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>


Este tutorial apresenta somente um exemplo simples do que pode ser feito porém com as funções de manipulação dos perfiréricos + os exemplos fornecidos no item _b_ dos documentos + os _crates_ disponíveis para Rust, o céu é o limite.

Sugiro como continuação deste tutorial implementar a [entrega 2](https://insper.github.io/Embarcados-Avancados/Entrega-5/) usando a biblioteca que já foi gerada no tutorial e implementando o servidor web em Rust.

