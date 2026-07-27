`timescale 1ns/1ps

module static_branch_predictor #(
    
    parameter bit PREDICT_TAKEN = 1'b1
) (
    input  logic clk,
    input  logic rst_n,

    // Branch resolution interface
    input  logic branch_valid,    
    input  logic actual_taken,    

    // Prediction outputs
    output logic predicted_taken, 
    output logic mispredict       
);


    assign predicted_taken = PREDICT_TAKEN;


    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mispredict <= 1'b0;
        end else if (branch_valid) begin
            mispredict <= (predicted_taken != actual_taken);
        end else begin
            mispredict <= 1'b0;
        end
    end

endmodule

