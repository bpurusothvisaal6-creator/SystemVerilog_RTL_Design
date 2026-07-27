`timescale 1ns/1ps
// =============================================================================
// Module      : one_bit_branch_predictor
// Description : One-bit dynamic branch predictor with a parameterizable
//               Branch History Table (BHT) indexed by the lower bits of the
//               program counter. Each entry stores a single bit representing
//               the last observed direction of the branch mapped to that
//               entry. Prediction generation and update logic are kept
//               functionally separate.
// =============================================================================
module one_bit_branch_predictor #(
    parameter int PC_WIDTH   = 32,   // Width of the program counter
    parameter int TABLE_SIZE = 256   // Number of entries in the BHT (power of 2)
) (
    input  logic clk,
    input  logic rst_n,

    // ---------------- Prediction interface ----------------
    input  logic                   predict_valid, // Request a prediction this cycle
    input  logic [PC_WIDTH-1:0]    predict_pc,    // PC of branch being predicted
    output logic                   predicted_taken,

    // ---------------- Update (branch resolution) interface ----------------
    input  logic                   update_valid,  // Pulses when a branch resolves
    input  logic [PC_WIDTH-1:0]    update_pc,     // PC of the resolved branch
    input  logic                   actual_taken,  // Actual resolved direction
    output logic                   mispredict     // Combinational mispredict flag
);

    localparam int INDEX_WIDTH = $clog2(TABLE_SIZE);

    // Branch History Table: one prediction bit per entry
    logic [TABLE_SIZE-1:0] bht;

    // Index extraction from lower PC bits
    logic [INDEX_WIDTH-1:0] predict_index;
    logic [INDEX_WIDTH-1:0] update_index;

    assign predict_index = predict_pc[INDEX_WIDTH-1:0];
    assign update_index  = update_pc[INDEX_WIDTH-1:0];

    // ---------------------------------------------------------------------
    // Prediction generation logic (read-only, combinational)
    // ---------------------------------------------------------------------
    always_comb begin
        predicted_taken = predict_valid ? bht[predict_index] : 1'b0;
    end

    // ---------------------------------------------------------------------
    // Misprediction detection: compares the stored bit (pre-update value)
    // against the resolved outcome for the branch being updated.
    // ---------------------------------------------------------------------
    always_comb begin
        mispredict = update_valid && (bht[update_index] != actual_taken);
    end

    // ---------------------------------------------------------------------
    // Update logic: synchronous reset, one-bit overwrite per resolution
    // ---------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bht <= '0;
        end else if (update_valid) begin
            bht[update_index] <= actual_taken;
        end
    end

endmodule

