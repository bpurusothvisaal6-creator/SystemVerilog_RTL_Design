module i2c_master #(
    parameter int CLK_FREQ_HZ = 50_000_000, // system clock frequency
    parameter int I2C_CLK_HZ  = 100_000,    // target SCL frequency
    parameter int ADDR_WIDTH  = 7           // 7-bit addressing
) (
    input  logic                  clk,
    input  logic                  rst_n,

    // Command interface
    input  logic                  start_txn,       // pulse: begin a transaction
    input  logic [ADDR_WIDTH-1:0] slave_addr,      // 7-bit target address
    input  logic                  rw,               // 0 = write, 1 = read
    input  logic [7:0]            wr_data,          // byte to write
    input  logic                  repeated_start,   // 1 = hold bus for a chained
                                                      //     transaction instead of
                                                      //     issuing STOP
    output logic [7:0]            rd_data,          // byte read from slave
    output logic                  rd_valid,         // 1-cycle pulse, rd_data valid
    output logic                  busy,             // transaction (or held bus) active
    output logic                  done,             // 1-cycle pulse, transaction done
    output logic                  ack_error,        // slave NACK'd address or data

    inout  wire                   scl,              // open-drain serial clock
    inout  wire                   sda               // open-drain serial data
);

    //-------------------------------------------------------------------
    // Open-drain drivers
    //-------------------------------------------------------------------
    logic scl_oe, sda_oe; // 1 = drive line low, 0 = release (external pull-up)
    assign scl = scl_oe ? 1'b0 : 1'bz;
    assign sda = sda_oe ? 1'b0 : 1'bz;

    //-------------------------------------------------------------------
    // Bit-clock divider: one tick per SCL half-period while active
    //-------------------------------------------------------------------
    localparam int HALF_PERIOD_CNT = (CLK_FREQ_HZ/(I2C_CLK_HZ*2) < 1) ?
                                       1 : CLK_FREQ_HZ/(I2C_CLK_HZ*2);

    typedef enum logic [3:0] {
        IDLE,
        START,
        ADDR_LOW,  ADDR_HIGH,
        ADDR_ACK_LOW, ADDR_ACK_HIGH,
        DATA_LOW,  DATA_HIGH,
        DATA_ACK_LOW, DATA_ACK_HIGH,
        RSTART_PREP1, RSTART_PREP2, RSTART_GEN,
        STOP_LOW,  STOP_HIGH,
        BUS_HELD
    } state_t;
    state_t state;

    logic [$clog2(HALF_PERIOD_CNT+1)-1:0] div_cnt;
    logic                                 tick;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= '0;
            tick    <= 1'b0;
        end else if (state == IDLE || state == BUS_HELD) begin
            div_cnt <= '0;
            tick    <= 1'b0;
        end else if (div_cnt == HALF_PERIOD_CNT-1) begin
            div_cnt <= '0;
            tick    <= 1'b1;
        end else begin
            div_cnt <= div_cnt + 1'b1;
            tick    <= 1'b0;
        end
    end

    //-------------------------------------------------------------------
    // Transaction registers
    //-------------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] slave_addr_reg;
    logic                  rw_reg;
    logic [7:0]             wr_data_reg;
    logic                  repeated_start_reg;
    logic [7:0]             shift_reg;
    logic [2:0]             bit_idx;
    logic                  txn_error; // captured NACK, forces STOP regardless of RS

    //-------------------------------------------------------------------
    // Main FSM
    //-------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= IDLE;
            scl_oe             <= 1'b0;
            sda_oe             <= 1'b0;
            slave_addr_reg     <= '0;
            rw_reg             <= 1'b0;
            wr_data_reg        <= '0;
            repeated_start_reg <= 1'b0;
            shift_reg          <= '0;
            bit_idx            <= '0;
            rd_data            <= '0;
            rd_valid           <= 1'b0;
            busy               <= 1'b0;
            done               <= 1'b0;
            ack_error          <= 1'b0;
            txn_error          <= 1'b0;
        end else begin
            rd_valid <= 1'b0; // default: single-cycle pulses
            done     <= 1'b0;

            unique case (state)
                //-----------------------------------------------------
                IDLE: begin
                    scl_oe <= 1'b0;
                    sda_oe <= 1'b0;
                    if (start_txn) begin
                        slave_addr_reg     <= slave_addr;
                        rw_reg             <= rw;
                        wr_data_reg        <= wr_data;
                        repeated_start_reg <= repeated_start;
                        shift_reg          <= {slave_addr, rw};
                        bit_idx            <= '0;
                        busy               <= 1'b1;
                        ack_error          <= 1'b0;
                        txn_error          <= 1'b0;
                        sda_oe             <= 1'b1; // START: pull SDA low (SCL still high)
                        state              <= START;
                    end
                end

                //-----------------------------------------------------
                START: begin
                    if (tick) begin
                        scl_oe   <= 1'b1;         // pull SCL low, begin clocking
                        sda_oe   <= ~shift_reg[7]; // set first address/RW bit
                        state    <= ADDR_LOW;
                    end
                end

                //-----------------------------------------------------
                ADDR_LOW: begin
                    if (tick) begin
                        scl_oe <= 1'b0; // release SCL -> goes high
                        state  <= ADDR_HIGH;
                    end
                end

                ADDR_HIGH: begin
                    if (tick) begin
                        scl_oe <= 1'b1; // pull SCL low again
                        if (bit_idx == 3'd7) begin
                            bit_idx <= '0;
                            sda_oe  <= 1'b0; // release SDA for slave ACK
                            state   <= ADDR_ACK_LOW;
                        end else begin
                            bit_idx   <= bit_idx + 1'b1;
                            sda_oe    <= ~shift_reg[6];
                            shift_reg <= {shift_reg[6:0], 1'b0};
                            state     <= ADDR_LOW;
                        end
                    end
                end

                //-----------------------------------------------------
                ADDR_ACK_LOW: begin
                    if (tick) begin
                        scl_oe <= 1'b0; // release SCL -> goes high
                        state  <= ADDR_ACK_HIGH;
                    end
                end

                ADDR_ACK_HIGH: begin
                    if (tick) begin
                        scl_oe <= 1'b1; // pull SCL low
                        if (sda == 1'b0) begin
                            // Address ACKed by slave
                            if (rw_reg == 1'b0) begin
                                shift_reg <= wr_data_reg;
                                sda_oe    <= ~wr_data_reg[7];
                            end else begin
                                sda_oe    <= 1'b0; // release, slave will drive data
                            end
                            bit_idx <= '0;
                            state   <= DATA_LOW;
                        end else begin
                            // Address NACKed - abort transaction
                            ack_error <= 1'b1;
                            txn_error <= 1'b1;
                            sda_oe    <= 1'b1; // prepare STOP (drive SDA low first)
                            state     <= STOP_LOW;
                        end
                    end
                end

                //-----------------------------------------------------
                DATA_LOW: begin
                    if (tick) begin
                        scl_oe <= 1'b0;
                        state  <= DATA_HIGH;
                    end
                end

                DATA_HIGH: begin
                    if (tick) begin
                        scl_oe <= 1'b1;
                        if (rw_reg == 1'b1) begin
                            shift_reg <= {shift_reg[6:0], sda};
                        end else begin
                            shift_reg <= {shift_reg[6:0], 1'b0};
                        end

                        if (bit_idx == 3'd7) begin
                            bit_idx <= '0;
                            if (rw_reg == 1'b1) begin
                                rd_data  <= {shift_reg[6:0], sda};
                                rd_valid <= 1'b1;
                                sda_oe   <= 1'b0; // master NACKs (single-byte read)
                            end else begin
                                sda_oe <= 1'b0;   // release, wait for slave ACK
                            end
                            state <= DATA_ACK_LOW;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                            if (rw_reg == 1'b0) begin
                                sda_oe <= ~shift_reg[6];
                            end
                            state <= DATA_LOW;
                        end
                    end
                end

                //-----------------------------------------------------
                DATA_ACK_LOW: begin
                    if (tick) begin
                        scl_oe <= 1'b0;
                        state  <= DATA_ACK_HIGH;
                    end
                end

                DATA_ACK_HIGH: begin
                    if (tick) begin
                        scl_oe <= 1'b1;
                        if (rw_reg == 1'b0 && sda == 1'b1) begin
                            // Write data byte was NACKed by slave
                            ack_error <= 1'b1;
                            txn_error <= 1'b1;
                        end

                        if (txn_error || (rw_reg == 1'b0 && sda == 1'b1) || !repeated_start_reg) begin
                            sda_oe <= 1'b1; // prepare STOP condition
                            state  <= STOP_LOW;
                        end else begin
                            state <= BUS_HELD; // wait for next start_txn (repeated START)
                        end
                    end
                end

                //-----------------------------------------------------
                BUS_HELD: begin
                    // SCL held low, bus owned; wait for a new transaction
                    // request before generating a repeated START.
                    if (start_txn) begin
                        slave_addr_reg <= slave_addr;
                        rw_reg         <= rw;
                        wr_data_reg    <= wr_data;
                        repeated_start_reg <= repeated_start;
                        sda_oe         <= 1'b0; // release SDA while SCL is low
                        state          <= RSTART_PREP1;
                    end
                end

                RSTART_PREP1: begin
                    if (tick) begin
                        scl_oe <= 1'b0; // release SCL -> goes high (both lines high)
                        state  <= RSTART_PREP2;
                    end
                end

                RSTART_PREP2: begin
                    if (tick) begin
                        sda_oe <= 1'b1; // pull SDA low while SCL high -> repeated START
                        state  <= RSTART_GEN;
                    end
                end

                RSTART_GEN: begin
                    if (tick) begin
                        scl_oe    <= 1'b1; // pull SCL low, begin clocking new address
                        shift_reg <= {slave_addr, rw};
                        sda_oe    <= ~slave_addr[6];
                        bit_idx   <= '0;
                        state     <= ADDR_LOW;
                    end
                end

                //-----------------------------------------------------
                STOP_LOW: begin
                    if (tick) begin
                        scl_oe <= 1'b0; // release SCL -> goes high, SDA still low
                        state  <= STOP_HIGH;
                    end
                end

                STOP_HIGH: begin
                    if (tick) begin
                        sda_oe    <= 1'b0; // release SDA -> goes high (STOP condition)
                        busy      <= 1'b0;
                        done      <= 1'b1;
                        state     <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

