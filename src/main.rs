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
