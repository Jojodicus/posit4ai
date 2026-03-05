
module pau_fpu_harness import ariane_pkg::*; (
    input  logic        clk_i,  // 100 MHz from Zedboard
    input  logic        rst_ni,
    // Inputs
    input  logic [63:0] op_a_i,
    input  logic [63:0] op_b_i,
    input  logic [7:0]  op_sel_i, // fu_op
    input  logic [3:0]  fu_sel_i, // fu_t
    input  logic        valid_i,
    // Outputs
    output logic [63:0] result_o,
    output logic        valid_o,
    output logic        ready_o
);

    // Clocking Wizard
    logic clk_research;
    logic locked;
    clk_wiz_0 i_clk_wiz (
        .clk_in1  ( clk_i        ),
        .reset    ( !rst_ni      ),
        .clk_out1 ( clk_research ),
        .locked   ( locked       )
    );

    // Input Registers
    logic [63:0] op_a_q, op_b_q;
    fu_op        operator_q;
    fu_t         fu_q;
    logic        valid_q;

    always_ff @(posedge clk_research or negedge rst_ni) begin
        if (!rst_ni) begin
            op_a_q     <= '0;
            op_b_q     <= '0;
            operator_q <= ADD;
            fu_q       <= NONE;
            valid_q    <= 1'b0;
        end else if (locked) begin
            op_a_q     <= op_a_i;
            op_b_q     <= op_b_i;
            operator_q <= fu_op'(op_sel_i);
            fu_q       <= fu_t'(fu_sel_i);
            valid_q    <= valid_i;
        end
    end

    // Internal Signals
    fu_data_t fu_data;
    assign fu_data.fu        = fu_q;
    assign fu_data.operator  = operator_q;
    assign fu_data.operand_a = op_a_q;
    assign fu_data.operand_b = op_b_q;
    assign fu_data.imm       = '0;
    assign fu_data.trans_id  = '0;

    logic [63:0] pau_result, fpu_result;
    logic        pau_valid, fpu_valid;
    logic        pau_ready, fpu_ready;

    // Instantiate PAU
    pau_top i_pau_top (
        .clk_i          ( clk_research ),
        .rst_ni         ( rst_ni       ),
        .fu_data_i      ( fu_data      ),
        .pau_valid_i    ( valid_q && (fu_q == PAU) ),
        .pau_ready_o    ( pau_ready    ),
        .pau_trans_id_o (              ),
        .pau_valid_o    ( pau_valid    ),
        .result_o       ( pau_result   )
    );

    // Instantiate FPU
    fpu_wrap i_fpu_wrap (
        .clk_i          ( clk_research ),
        .rst_ni         ( rst_ni       ),
        .flush_i        ( 1'b0         ),
        .fpu_valid_i    ( valid_q && (fu_q == FPU) ),
        .fpu_ready_o    ( fpu_ready    ),
        .fu_data_i      ( fu_data      ),
        .fpu_fmt_i      ( 2'b01        ), // Fixed to FP64 for now
        .fpu_rm_i       ( 3'b000       ),
        .fpu_frm_i      ( 3'b000       ),
        .fpu_prec_i     ( 7'b0         ),
        .fpu_trans_id_o (              ),
        .result_o       ( fpu_result   ),
        .fpu_valid_o    ( fpu_valid    ),
        .fpu_exception_o(              )
    );

    // Output Mux and Registers
    logic [63:0] result_d;
    logic        valid_d;

    assign result_d = (fu_q == PAU) ? pau_result : fpu_result;
    assign valid_d  = (fu_q == PAU) ? pau_valid  : fpu_valid;
    assign ready_o  = (fu_q == PAU) ? pau_ready  : fpu_ready;

    always_ff @(posedge clk_research or negedge rst_ni) begin
        if (!rst_ni) begin
            result_o <= '0;
            valid_o  <= 1'b0;
        end else if (locked) begin
            result_o <= result_d;
            valid_o  <= valid_d;
        end
    end

endmodule
