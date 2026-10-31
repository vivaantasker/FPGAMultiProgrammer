package programmer_pkg;

  parameter int CLK_FREQ_HZ          = 100_000_000;
  parameter int AXI_ADDR_WIDTH      = 32;
  parameter int AXI_DATA_WIDTH      = 32;
  parameter int STREAM_DATA_WIDTH   = 32;
  parameter int UART_BAUD           = 115_200;
  parameter int FIFO_DEPTH          = 16;
  parameter int JTAG_MAX_IR_LENGTH  = 32;
  parameter int JTAG_MAX_DR_LENGTH  = 1024;
  parameter int INTERNAL_RAM_SIZE   = 2048;
  parameter int MEMORY_ADDRESS_WIDTH = 24;

  parameter logic [7:0] UART_SOF = 8'hAA;
  parameter logic [7:0] UART_EOF = 8'h55;

  typedef enum logic [2:0] {
    MEM_SPI  = 3'd0,
    MEM_QSPI = 3'd1,
    MEM_OSPI = 3'd2
  } memory_type_t;

  typedef enum logic [2:0] {
    TRIG_MANUAL           = 3'd0,
    TRIG_GPIO             = 3'd1,
    TRIG_TIMER            = 3'd2,
    TRIG_EXTERNAL_TRIGGER = 3'd3,
    TRIG_TARGET_FEEDBACK  = 3'd4,
    TRIG_ERROR_RECOVERY   = 3'd5
  } trigger_type_t;

  typedef enum logic [7:0] {
    CMD_CONFIGURE      = 8'h01,
    CMD_START          = 8'h02,
    CMD_STATUS         = 8'h03,
    CMD_ABORT          = 8'h04,
    CMD_READ_ID        = 8'h05,
    CMD_RESET          = 8'h06,
    CMD_READ_ERROR     = 8'h07,
    CMD_UNKNOWN        = 8'hFF
  } uart_cmd_t;

  typedef enum logic [7:0] {
    RESP_ACK            = 8'h01,
    RESP_NACK           = 8'h02,
    RESP_STATUS         = 8'h03,
    RESP_PROGRAM_STARTED = 8'h04,
    RESP_IDCODE_RECEIVED = 8'h05,
    RESP_PROGRAM_COMPLETE = 8'h06,
    RESP_PROGRAM_ERROR  = 8'h07,
    RESP_TIMEOUT        = 8'h08,
    RESP_UNKNOWN        = 8'hFF
  } uart_resp_t;

  typedef enum logic [3:0] {
    ERR_NONE            = 4'd0,
    ERR_BAD_SOF         = 4'd1,
    ERR_BAD_EOF         = 4'd2,
    ERR_INVALID_LENGTH  = 4'd3,
    ERR_CRC             = 4'd4,
    ERR_UNKNOWN_CMD     = 4'd5,
    ERR_INCOMPLETE      = 4'd6,
    ERR_MEMORY_TIMEOUT  = 4'd7,
    ERR_MEMORY_ERROR    = 4'd8,
    ERR_DMA_ERROR       = 4'd9,
    ERR_JTAG_ERROR      = 4'd10,
    ERR_IDCODE_MISMATCH = 4'd11,
    ERR_ABORTED         = 4'd12,
    ERR_RESET           = 4'd13
  } error_code_t;

  typedef enum logic [3:0] {
    IRQ_UART_RX            = 4'd0,
    IRQ_UART_TX            = 4'd1,
    IRQ_MEMORY_DONE        = 4'd2,
    IRQ_MEMORY_ERROR       = 4'd3,
    IRQ_DMA_DONE           = 4'd4,
    IRQ_DMA_ERROR          = 4'd5,
    IRQ_DMA_UNDERRUN       = 4'd6,
    IRQ_JTAG_DONE          = 4'd7,
    IRQ_JTAG_ERROR         = 4'd8,
    IRQ_JTAG_IDCODE_READY = 4'd9,
    IRQ_JTAG_RESPONSE_READY = 4'd10,
    IRQ_TIMEOUT            = 4'd11
  } irq_bit_t;

  typedef enum logic [3:0] {
    JTAG_CMD_IDCODE = 4'd0,
    JTAG_CMD_IR     = 4'd1,
    JTAG_CMD_DR     = 4'd2,
    JTAG_CMD_RESET  = 4'd3,
    JTAG_CMD_XFER   = 4'd4
  } jtag_cmd_t;

  typedef enum logic [3:0] {
    DMA_IDLE     = 4'd0,
    DMA_RUNNING  = 4'd1,
    DMA_DONE     = 4'd2,
    DMA_ERROR    = 4'd3,
    DMA_ABORTED  = 4'd4,
    DMA_UNDERRUN = 4'd5
  } dma_status_t;

  typedef enum logic [3:0] {
    CTRL_IDLE          = 4'd0,
    CTRL_CONFIGURE     = 4'd1,
    CTRL_MEMORY_CONFIG = 4'd2,
    CTRL_DMA_CONFIG    = 4'd3,
    CTRL_JTAG_CONFIG   = 4'd4,
    CTRL_START_TRANSFER = 4'd5,
    CTRL_WAIT_TRANSFER = 4'd6,
    CTRL_VERIFY        = 4'd7,
    CTRL_REPORT_SUCCESS = 4'd8,
    CTRL_ERROR         = 4'd9,
    CTRL_ABORT         = 4'd10,
    CTRL_RESET_PERIPHERALS = 4'd11
  } controller_state_t;

  typedef enum logic [3:0] {
    TAP_TEST_LOGIC_RESET = 4'd0,
    TAP_RUN_TEST_IDLE = 4'd1,
    TAP_SELECT_DR_SCAN = 4'd2,
    TAP_CAPTURE_DR = 4'd3,
    TAP_SHIFT_DR = 4'd4,
    TAP_EXIT1_DR = 4'd5,
    TAP_PAUSE_DR = 4'd6,
    TAP_EXIT2_DR = 4'd7,
    TAP_UPDATE_DR = 4'd8,
    TAP_SELECT_IR_SCAN = 4'd9,
    TAP_CAPTURE_IR = 4'd10,
    TAP_SHIFT_IR = 4'd11,
    TAP_EXIT1_IR = 4'd12,
    TAP_PAUSE_IR = 4'd13,
    TAP_EXIT2_IR = 4'd14,
    TAP_UPDATE_IR = 4'd15
  } tap_state_t;

  typedef logic [31:0] axi_addr_t;
  typedef logic [31:0] axi_data_t;
  typedef logic [31:0] stream_data_t;

  typedef struct packed {
    logic [2:0] memory_type;
    axi_addr_t memory_address;
    logic [31:0] bitstream_length;
    logic [31:0] expected_idcode;
    logic [31:0] jtag_frequency;
    logic [7:0] jtag_mode;
    logic [2:0] trigger_type;
    logic [15:0] bitstream_id;
    logic [7:0] flags;
  } programmer_config_t;

  typedef struct packed {
    axi_addr_t memory_address;
    logic [31:0] bitstream_length;
    logic [31:0] expected_idcode;
    logic [2:0] memory_type;
    logic [31:0] jtag_frequency;
    logic [7:0] flags;
  } bitstream_descriptor_t;

  typedef struct packed {
    logic start;
    logic abort;
    logic done;
    logic error;
    logic timeout;
  } dma_ctrl_t;

  typedef struct packed {
    logic [15:0] irq_status;
    logic [15:0] irq_enable;
    logic [15:0] irq_clear;
  } irq_regs_t;

  // CRC-16/CCITT-FALSE: poly=0x1021, init=0xFFFF, refin=false, refout=false, xorout=0.
  // Process each byte most-significant bit first. UART frames cover CMD, LEN_MSB,
  // LEN_LSB, and payload; the two transmitted CRC bytes are not themselves folded in.
  function automatic logic [15:0] crc16_update(input logic [15:0] crc_in, input logic [7:0] data);
    logic [15:0] crc;
    crc = crc_in ^ {data, 8'h00};
    for (int i = 0; i < 8; i++) begin
      if (crc[15]) crc = {crc[14:0], 1'b0} ^ 16'h1021;
      else         crc = {crc[14:0], 1'b0};
    end
    return crc;
  endfunction

endpackage
