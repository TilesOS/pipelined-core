ENTRY(_start)
SECTIONS {
  . = 0x80040000;
  .text : { *(.text*) }
}
