`timescale 1ns/1ps

interface jtag_if(input logic clk);
  logic rst_n;
  logic tms;
  logic tdi;
  logic tdo;
  logic [3:0] tap_state;

  logic shift_enable;
  logic [31:0] tdi_word;
  logic [31:0] tdo_word;
  logic [31:0] shift_tdi;
  logic [31:0] shift_tdo;

  logic [31:0] jtag_frequency;
  logic tck;
endinterface
