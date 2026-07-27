`timescale 1ns/1ps

module tb;

    localparam int PC_WIDTH   = 32;
    localparam int TABLE_SIZE = 16; // small table to encourage aliasing in tests
    localparam int INDEX_WIDTH = $clog2(TABLE_SIZE);

    // -----------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------
    logic clk;
    logic rst_n;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // -----------------------------------------------------------------
    // DUT signals
    // -----------------------------------------------------------------
    logic                predict_valid;
    logic [PC_WIDTH-1:0] predict_pc;
    logic                predicted_taken;

    logic                update_valid;
    logic [PC_WIDTH-1:0] update_pc;
    logic                actual_taken;
    logic                mispredict;

    one_bit_branch_predictor #(
        .PC_WIDTH  (PC_WIDTH),
        .TABLE_SIZE(TABLE_SIZE)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .predict_valid  (predict_valid),
        .predict_pc     (predict_pc),
        .predicted_taken(predicted_taken),
        .update_valid   (update_valid),
        .update_pc      (update_pc),
        .actual_taken   (actual_taken),
        .mispredict     (mispredict)
    );

    // -----------------------------------------------------------------
    // Golden reference model
    // -----------------------------------------------------------------
    logic ref_bht [TABLE_SIZE-1:0];
    int unsigned error_count = 0;
    int unsigned check_count = 0;

    task automatic reset_ref();
        int i;
        for (i = 0; i < TABLE_SIZE; i++) ref_bht[i] = 1'b0;
    endtask

    // Perform a prediction check for a given PC
    task automatic do_predict(input logic [PC_WIDTH-1:0] pc);
        logic [INDEX_WIDTH-1:0] idx;
        logic exp_pred;
        begin
            idx = pc[INDEX_WIDTH-1:0];
            exp_pred = ref_bht[idx];
            @(negedge clk);
            predict_valid = 1'b1;
            predict_pc    = pc;
            #1; // allow combinational settle
            check_count++;
            if (predicted_taken !== exp_pred) begin
                $display("[%0t] FAIL: predict pc=%0h idx=%0d exp=%0b got=%0b",
                          $time, pc, idx, exp_pred, predicted_taken);
                error_count++;
            end
            predict_valid = 1'b0;
        end
    endtask

    // Perform an update (branch resolution) and check mispredict + BHT update
    task automatic do_update(input logic [PC_WIDTH-1:0] pc, input logic taken);
        logic [INDEX_WIDTH-1:0] idx;
        logic exp_mispredict;
        begin
            idx = pc[INDEX_WIDTH-1:0];
            exp_mispredict = (ref_bht[idx] != taken);

            @(negedge clk);
            update_valid = 1'b1;
            update_pc    = pc;
            actual_taken = taken;
            #1;
            check_count++;
            if (mispredict !== exp_mispredict) begin
                $display("[%0t] FAIL: mispredict pc=%0h idx=%0d exp=%0b got=%0b",
                          $time, pc, idx, exp_mispredict, mispredict);
                error_count++;
            end

            @(negedge clk); // let the synchronous update land
            update_valid = 1'b0;
            ref_bht[idx] = taken;

            // Verify BHT actually updated by checking a subsequent prediction
            do_predict(pc);
        end
    endtask

    // -----------------------------------------------------------------
    // Waveform dumping
    // -----------------------------------------------------------------
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb);
    end

    // -----------------------------------------------------------------
    // Main stimulus
    // -----------------------------------------------------------------
    initial begin
        int unsigned i;
        logic [PC_WIDTH-1:0] rand_pc;
        logic                rand_taken;

        predict_valid = 1'b0;
        update_valid  = 1'b0;
        predict_pc    = '0;
        update_pc     = '0;
        actual_taken  = 1'b0;
        rst_n         = 1'b0;
        reset_ref();

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        // ---------------- Directed tests ----------------
        $display("---- Directed: initial prediction after reset is NOT TAKEN ----");
        do_predict(32'h0000_0004);

        $display("---- Directed: update PC=4 taken, re-predict ----");
        do_update(32'h0000_0004, 1'b1);

        $display("---- Directed: update PC=4 not-taken, re-predict ----");
        do_update(32'h0000_0004, 1'b0);

        $display("---- Directed: aliasing PCs mapping to the same index ----");
        // PCs differing by TABLE_SIZE alias to the same entry
        do_update(32'h0000_0008, 1'b1);
        do_predict(32'h0000_0008 + TABLE_SIZE); // aliasing PC should read same bit

        // ---------------- Corner cases ----------------
        $display("---- Corner: PC = 0 ----");
        do_update(32'h0000_0000, 1'b1);

        $display("---- Corner: max PC value ----");
        do_update({PC_WIDTH{1'b1}}, 1'b0);

        $display("---- Corner: reset clears BHT ----");
        do_update(32'h0000_0010, 1'b1);
        rst_n = 1'b0;
        reset_ref();
        @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
        do_predict(32'h0000_0010);

        // ---------------- Randomized sequence ----------------
        $display("---- Randomized Test: %0d predict/update pairs ----", 300);
        for (i = 0; i < 300; i++) begin
            rand_pc    = $urandom();
            rand_taken = $urandom_range(0, 1);
            do_predict(rand_pc);
            do_update(rand_pc, rand_taken);
        end

        // ---------------- Final report ----------------
        repeat (2) @(negedge clk);
        if (error_count == 0)
            $display("\nTEST PASSED: %0d checks, 0 errors", check_count);
        else
            $display("\nTEST FAILED: %0d checks, %0d errors", check_count, error_count);

        $finish;
    end

endmodule

