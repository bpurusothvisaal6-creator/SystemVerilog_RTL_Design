module spi_master #(
    parameter int CLK_FREQ_HZ = 50_000_000,  // system clock frequency
    parameter int SPI_CLK_HZ  = 1_000_000,   // desired SPI SCLK frequency
    parameter int DATA_WIDTH  = 8            // transfer width in bits
) (
    input  logic                   clk,
    input  logic                   rst_n,

    input  logic                   cpol,      // clock polarity select
    input  logic                   cpha,      // clock phase select

    input  logic                   start,     // pulse to start a transfer
    input  logic [DATA_WIDTH-1:0]  tx_data,   // data to shift out on MOSI
    output logic [DATA_WIDTH-1:0]  rx_data,   // data captured from MISO
    output logic                   busy,      // transfer in progress
    output logic                   done,      // 1-cycle pulse, transfer done

    output logic                   sclk,      // SPI serial clock
    output logic                   mosi,      // master-out slave-in
    input  logic                   miso,      // master-in slave-out
    output logic                   cs_n       // active-low chip select
);

    //-------------------------------------------------------------------
    // SCLK half-period divider value
    //-------------------------------------------------------------------
    localparam int HALF_PERIOD_CNT = (CLK_FREQ_HZ / (SPI_CLK_HZ * 2) < 1) ?
                                       1 : CLK_FREQ_HZ / (SPI_CLK_HZ * 2);
    localparam int EDGE_TOTAL      = DATA_WIDTH * 2; // 2 sclk edges per bit

    typedef enum logic [1:0] {IDLE, CS_SETUP, TRANSFER, CS_HOLD} state_t;
    state_t state;

    logic [$clog2(HALF_PERIOD_CNT+1)-1:0] div_cnt;
    logic                                 sclk_en;   // pulses each half period

    logic [DATA_WIDTH-1:0]        tx_shift;
    logic [DATA_WIDTH-1:0]        rx_shift;
    logic [$clog2(EDGE_TOTAL+1)-1:0] edge_cnt;
    logic                          sclk_reg;
    logic                          mosi_reg;
    logic                          cs_n_reg;

    assign sclk    = sclk_reg;
    assign mosi    = mosi_reg;
    assign cs_n    = cs_n_reg;
    assign rx_data = rx_shift;

    //-------------------------------------------------------------------
    // SCLK divider: generates sclk_en pulse every HALF_PERIOD_CNT cycles
    // while a transfer is in progress.
    //-------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= '0;
            sclk_en <= 1'b0;
        end else if (state == TRANSFER) begin
            if (div_cnt == HALF_PERIOD_CNT-1) begin
                div_cnt <= '0;
                sclk_en <= 1'b1;
            end else begin
                div_cnt <= div_cnt + 1'b1;
                sclk_en <= 1'b0;
            end
        end else begin
            div_cnt <= '0;
            sclk_en <= 1'b0;
        end
    end

    //-------------------------------------------------------------------
    // Main transaction control FSM
    //-------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            sclk_reg <= 1'b0;
            mosi_reg <= 1'b0;
            cs_n_reg <= 1'b1;
            tx_shift <= '0;
            rx_shift <= '0;
            edge_cnt <= '0;
            busy     <= 1'b0;
            done     <= 1'b0;
        end else begin
            done <= 1'b0; // default: single-cycle pulse

            unique case (state)
                //-----------------------------------------------------
                IDLE: begin
                    sclk_reg <= cpol;   // idle clock level = CPOL
                    cs_n_reg <= 1'b1;
                    busy     <= 1'b0;
                    if (start) begin
                        tx_shift <= tx_data;
                        rx_shift <= '0;
                        edge_cnt <= '0;
                        cs_n_reg <= 1'b0;
                        busy     <= 1'b1;
                        state    <= CS_SETUP;
                    end
                end

                //-----------------------------------------------------
                // One cycle of CS setup time; also pre-load MOSI with
                // the MSB when CPHA = 0, since that mode requires data
                // to be valid on the line before the first clock edge.
                //-----------------------------------------------------
                CS_SETUP: begin
                    if (cpha == 1'b0) begin
                        mosi_reg <= tx_shift[DATA_WIDTH-1];
                    end
                    state <= TRANSFER;
                end

                //-----------------------------------------------------
                TRANSFER: begin
                    if (sclk_en) begin
                        sclk_reg <= ~sclk_reg;
                        edge_cnt <= edge_cnt + 1'b1;

                        // "Leading" edge = transition away from the idle
                        // (CPOL) level; "trailing" edge returns to idle.
                        if (sclk_reg == cpol) begin
                            // ---- Leading edge ----
                            if (cpha == 1'b0) begin
                                // Sample MISO on leading edge
                                rx_shift <= {rx_shift[DATA_WIDTH-2:0], miso};
                            end else begin
                                // Shift new MOSI bit out on leading edge
                                mosi_reg <= tx_shift[DATA_WIDTH-1];
                                tx_shift <= {tx_shift[DATA_WIDTH-2:0], 1'b0};
                            end
                        end else begin
                            // ---- Trailing edge ----
                            if (cpha == 1'b0) begin
                                // Shift out next bit (setup for next sample)
                                if (edge_cnt != EDGE_TOTAL-1) begin
                                    mosi_reg <= tx_shift[DATA_WIDTH-2];
                                    tx_shift <= {tx_shift[DATA_WIDTH-2:0], 1'b0};
                                end
                            end else begin
                                // Sample MISO on trailing edge
                                rx_shift <= {rx_shift[DATA_WIDTH-2:0], miso};
                            end
                        end

                        if (edge_cnt == EDGE_TOTAL-1) begin
                            state <= CS_HOLD;
                        end
                    end
                end

                //-----------------------------------------------------
                CS_HOLD: begin
                    sclk_reg <= cpol;
                    cs_n_reg <= 1'b1;
                    busy     <= 1'b0;
                    done     <= 1'b1;
                    state    <= IDLE;
                end

                default: state <= IDLE;
            endcase
