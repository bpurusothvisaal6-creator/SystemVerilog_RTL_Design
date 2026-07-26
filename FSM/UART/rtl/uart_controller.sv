module uart_controller #(
    parameter int CLK_FREQ_HZ = 50_000_000,   // system clock frequency (Hz)
    parameter int BAUD_RATE   = 115_200,      // desired UART baud rate
    parameter int DATA_BITS   = 8             // number of data bits per frame
) (
    input  logic                 clk,
    input  logic                 rst_n,

    //---------------- Transmit interface ----------------
    input  logic                 tx_start,     // pulse to start a transmission
    input  logic [DATA_BITS-1:0] tx_data,      // byte to transmit
    output logic                 tx_busy,      // transmitter is active
    output logic                 tx_done,      // 1-cycle pulse when frame sent
    output logic                 tx,           // serial TX line

    //---------------- Receive interface ----------------
    input  logic                 rx,           // serial RX line
    output logic [DATA_BITS-1:0] rx_data,      // received byte
    output logic                 rx_valid,     // 1-cycle pulse, byte valid
    output logic                 rx_frame_err  // stop bit was not '1'
);

    //-------------------------------------------------------------------
    // Baud rate tick generators
    //   tx_baud_tick : ticks once per bit period    (1x baud rate)
    //   rx_os_tick   : ticks 16 times per bit period (16x oversample)
    //-------------------------------------------------------------------
    localparam int TX_DIV_MAX = CLK_FREQ_HZ / BAUD_RATE;
    localparam int RX_DIV_MAX = CLK_FREQ_HZ / (BAUD_RATE * 16);

    logic [$clog2(TX_DIV_MAX+1)-1:0] tx_baud_cnt;
    logic                            tx_baud_tick;

    logic [$clog2(RX_DIV_MAX+1)-1:0] rx_os_cnt;
    logic                            rx_os_tick;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_baud_cnt  <= '0;
            tx_baud_tick <= 1'b0;
        end else if (tx_baud_cnt == TX_DIV_MAX-1) begin
            tx_baud_cnt  <= '0;
            tx_baud_tick <= 1'b1;
        end else begin
            tx_baud_cnt  <= tx_baud_cnt + 1'b1;
            tx_baud_tick <= 1'b0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_os_cnt  <= '0;
            rx_os_tick <= 1'b0;
        end else if (rx_os_cnt == RX_DIV_MAX-1) begin
            rx_os_cnt  <= '0;
            rx_os_tick <= 1'b1;
        end else begin
            rx_os_cnt  <= rx_os_cnt + 1'b1;
            rx_os_tick <= 1'b0;
        end
    end

    //=====================================================================
    // TRANSMIT FSM
    //=====================================================================
    typedef enum logic [1:0] {TX_IDLE, TX_START, TX_DATA, TX_STOP} tx_state_t;
    tx_state_t tx_state;

    logic [DATA_BITS-1:0]         tx_shift;
    logic [$clog2(DATA_BITS)-1:0] tx_bit_cnt;
    logic                         tx_reg;

    assign tx = tx_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state   <= TX_IDLE;
            tx_reg     <= 1'b1;   // idle line is high (mark)
            tx_shift   <= '0;
            tx_bit_cnt <= '0;
            tx_busy    <= 1'b0;
            tx_done    <= 1'b0;
        end else begin
            tx_done <= 1'b0; // default: single-cycle pulse

            unique case (tx_state)
                TX_IDLE: begin
                    tx_reg <= 1'b1;
                    if (tx_start) begin
                        tx_shift   <= tx_data;
                        tx_bit_cnt <= '0;
                        tx_busy    <= 1'b1;
                        tx_state   <= TX_START;
                    end
                end

                TX_START: begin
                    if (tx_baud_tick) begin
                        tx_reg   <= 1'b0;      // start bit = 0
                        tx_state <= TX_DATA;
                    end
                end

                TX_DATA: begin
                    if (tx_baud_tick) begin
                        tx_reg   <= tx_shift[0];               // LSB first
                        tx_shift <= {1'b0, tx_shift[DATA_BITS-1:1]};
                        if (tx_bit_cnt == DATA_BITS-1) begin
                            tx_state <= TX_STOP;
                        end else begin
                            tx_bit_cnt <= tx_bit_cnt + 1'b1;
                        end
                    end
                end

                TX_STOP: begin
                    if (tx_baud_tick) begin
                        tx_reg   <= 1'b1;      // stop bit = 1
                        tx_busy  <= 1'b0;
                        tx_done  <= 1'b1;
                        tx_state <= TX_IDLE;
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    //=====================================================================
    // RECEIVE FSM (16x oversampling, mid-bit sampling)
    //=====================================================================
    typedef enum logic [1:0] {RX_IDLE, RX_START, RX_DATA, RX_STOP} rx_state_t;
    rx_state_t rx_state;

    logic [DATA_BITS-1:0]         rx_shift;
    logic [$clog2(DATA_BITS)-1:0] rx_bit_cnt;
    logic [3:0]                   rx_os_sample_cnt; // 0..15 within current bit
    logic                         rx_sync0, rx_sync1; // 2-FF metastability sync

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync0 <= 1'b1;
            rx_sync1 <= 1'b1;
        end else begin
            rx_sync0 <= rx;
            rx_sync1 <= rx_sync0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state         <= RX_IDLE;
            rx_shift         <= '0;
            rx_bit_cnt       <= '0;
            rx_os_sample_cnt <= '0;
            rx_data          <= '0;
            rx_valid         <= 1'b0;
            rx_frame_err     <= 1'b0;
        end else begin
            rx_valid <= 1'b0; // default: single-cycle pulse

            unique case (rx_state)
                RX_IDLE: begin
                    rx_os_sample_cnt <= '0;
                    if (rx_sync1 == 1'b0) begin       // falling edge candidate
                        rx_state <= RX_START;
                    end
                end

                RX_START: begin
                    if (rx_os_tick) begin
                        if (rx_os_sample_cnt == 4'd7) begin // mid of start bit
                            if (rx_sync1 == 1'b0) begin     // qualify start bit
                                rx_os_sample_cnt <= '0;
                                rx_bit_cnt       <= '0;
                                rx_state         <= RX_DATA;
                            end else begin
                                rx_state <= RX_IDLE;         // glitch, abort
                            end
                        end else begin
                            rx_os_sample_cnt <= rx_os_sample_cnt + 1'b1;
                        end
                    end
                end

                RX_DATA: begin
                    if (rx_os_tick) begin
                        if (rx_os_sample_cnt == 4'd15) begin // mid of data bit
                            rx_os_sample_cnt <= '0;
                            rx_shift <= {rx_sync1, rx_shift[DATA_BITS-1:1]};
                            if (rx_bit_cnt == DATA_BITS-1) begin
                                rx_state <= RX_STOP;
                            end else begin
                                rx_bit_cnt <= rx_bit_cnt + 1'b1;
                            end
                        end else begin
                            rx_os_sample_cnt <= rx_os_sample_cnt + 1'b1;
                        end
                    end
                end

                RX_STOP: begin
                    if (rx_os_tick) begin
                        if (rx_os_sample_cnt == 4'd15) begin // mid of stop bit
                            rx_os_sample_cnt <= '0;
                            rx_data      <= rx_shift;
                            rx_valid     <= rx_sync1;   // valid only if stop=1
                            rx_frame_err <= ~rx_sync1;
                            rx_state     <= RX_IDLE;
                        end else begin
                            rx_os_sample_cnt <= rx_os_sample_cnt + 1'b1;
                        end
                    end
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
