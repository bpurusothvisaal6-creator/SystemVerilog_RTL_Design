`timescale 1ns/1ps

module tb;

    // -----------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------
    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #5 clk = ~clk; // 100MHz clock

    // -----------------------------------------------------------------
    // DUT interfaces - one instance per policy
    // -----------------------------------------------------------------
    logic branch_valid;
    logic actual_taken;

    logic predicted_taken_t;   // Always-taken DUT
    logic mispredict_t;

    logic predicted_taken_nt;  // Always-not-taken DUT
    logic mispredict_nt;

    static_branch_predictor #(.PREDICT_TAKEN(1'b1)) dut_taken (
        .clk            (clk),
        .rst_n          (rst_n),
        .branch_valid   (branch_valid),
        .actual_taken   (actual_taken),
        .predicted_taken(predicted_taken_t),
        .mispredict     (mispredict_t)
    );

    static_branch_predictor #(.PREDICT_TAKEN(1'b0)) dut_not_taken (
        .clk            (clk),
        .rst_n          (rst_n),
        .branch_valid   (branch_valid),
        .actual_taken   (actual_taken),
        .predicted_taken(predicted_taken_nt),
        .mispredict     (mispredict_nt)
    );

    // -----------------------------------------------------------------
    // Scoreboard bookkeeping
    // -----------------------------------------------------------------
    int unsigned error_count = 0;
    int unsigned check_count = 0;

    // Reference model check task: compares DUT outputs one cycle after the
    // branch_valid pulse against the expected static-policy behaviour.
    task automatic check_result(
        input bit         predict_policy, // 1 = always taken, 0 = always not taken
        input logic        exp_actual,
        input logic        got_predicted,
        input logic        got_mispredict,
        input string        tag
    );
        logic exp_predicted;
        logic exp_mispredict;
        begin
            exp_predicted  = predict_policy;
            exp_mispredict = (exp_predicted != exp_actual);
            check_count++;
            if (got_predicted !== exp_predicted) begin
                $display("[%0t] FAIL (%s): predicted_taken mismatch. exp=%0b got=%0b",
                          $time, tag, exp_predicted, got_predicted);
                error_count++;
            end
            if (got_mispredict !== exp_mispredict) begin
                $display("[%0t] FAIL (%s): mispredict mismatch. exp=%0b got=%0b",
                          $time, tag, exp_mispredict, got_mispredict);
                error_count++;
            end
        end
    endtask

    // Drive one branch resolution cycle and check the results.
    task automatic drive_branch(input logic taken);
        begin
            @(negedge clk);
            branch_valid = 1'b1;
            actual_taken = taken;
            @(negedge clk);
            branch_valid = 1'b0;
            // mispredict is registered one cycle after branch_valid pulse
            check_result(1'b1, taken, predicted_taken_t,  mispredict_t,  "ALWAYS_TAKEN");
            check_result(1'b0, taken, predicted_taken_nt, mispredict_nt, "ALWAYS_NOT_TAKEN");
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

        branch_valid = 1'b0;
        actual_taken = 1'b0;
        rst_n        = 1'b0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        // ---------------- Directed tests ----------------
        $display("---- Directed Test: actual = TAKEN ----");
        drive_branch(1'b1);

        $display("---- Directed Test: actual = NOT TAKEN ----");
        drive_branch(1'b0);

        $display("---- Directed Test: back-to-back TAKEN ----");
        drive_branch(1'b1);
        drive_branch(1'b1);

        $display("---- Directed Test: back-to-back NOT TAKEN ----");
        drive_branch(1'b0);
        drive_branch(1'b0);

        // ---------------- Corner cases ----------------
        // Corner case: no branch_valid pulse - outputs must not update
        @(negedge clk);
        branch_valid = 1'b0;
        @(negedge clk);
        check_count++;
        if (mispredict_t !== 1'b0 || mispredict_nt !== 1'b0) begin
            $display("[%0t] FAIL: mispredict asserted with no valid branch", $time);
            error_count++;
        end

        // Corner case: reset mid-operation
        drive_branch(1'b1);
        @(negedge clk);
        rst_n = 1'b0;
        @(negedge clk);
        check_count++;
        if (mispredict_t !== 1'b0 || mispredict_nt !== 1'b0) begin
            $display("[%0t] FAIL: mispredict not cleared by reset", $time);
            error_count++;
        end
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        // ---------------- Randomized sequence ----------------
        $display("---- Randomized Test: %0d branches ----", 200);
        for (i = 0; i < 200; i++) begin
            drive_branch($urandom_range(0, 1));
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

