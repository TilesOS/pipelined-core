ENTRY(_start)
SECTIONS {
  . = 0x80000000;
  .text : { *(.text*) }
  . = 0x80002000;
  .data : { *(.data*) }
  . = 0x80004000;
  .bss : { *(.bss*) }
}
