`timescale 1ns/1ps
package physical_memory_pkg;
    function automatic logic cacheable(input logic [31:0] addr);
        return addr >= 32'h8000_0000 && addr < 32'h8780_0000;
    endfunction
    function automatic logic ddr(input logic [31:0] addr);
        return addr >= 32'h8000_0000 && addr < 32'h8800_0000;
    endfunction
    function automatic logic accessible(input logic [31:0] addr, input logic write_access);
        return (addr < 32'h0001_0000 && !write_access) || ddr(addr) ||
            (addr >= 32'h0200_0000 && addr < 32'h0201_0000) ||
            (addr >= 32'h0c00_0000 && addr < 32'h1000_0000) ||
            (addr >= 32'h1000_0000 && addr < 32'h1000_1000) ||
            (addr >= 32'h1001_0000 && addr < 32'h1001_1000) ||
            (addr >= 32'h1002_0000 && addr < 32'h1002_1000) ||
            (addr >= 32'h1003_0000 && addr < 32'h1003_1000);
    endfunction
    function automatic logic executable(input logic [31:0] addr);
        return addr < 32'h0001_0000 || ddr(addr);
    endfunction
endpackage
