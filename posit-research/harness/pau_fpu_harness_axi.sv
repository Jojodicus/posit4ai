module pau_fpu_harness_axi import ariane_pkg::*; (
    input  logic        clk_i,  // 100 MHz from Zedboard
    input  logic        rst_ni,

    // AXI-Lite Slave Interface
    input  logic [31:0] awaddr_i,
    input  logic [2:0]  awprot_i,
    input  logic        awvalid_i,
    output logic        awready_o,

    input  logic [31:0] wdata_i,
    input  logic [3:0]  wstrb_i,
    input  logic        wvalid_i,
    output logic        wready_o,

    output logic [1:0]  bresp_o,
    output logic        bvalid_o,
    input  logic        bready_i,

    input  logic [31:0] araddr_i,
    input  logic [2:0]  arprot_i,
    input  logic        arvalid_i,
    output logic        arready_o,

    output logic [31:0] rdata_o,
    output logic [1:0]  rresp_o,
    output logic        rvalid_o,
    input  logic        rready_i
);

    // -------------------------
    // Register Address Map
    // -------------------------
    // 0x00: OP_A [31:0]
    // 0x04: OP_A [63:32]
    // 0x08: OP_B [31:0]
    // 0x0C: OP_B [63:32]
    // 0x10: OP_SEL (8 bits), FU_SEL (4 bits), VALID_I (1 bit) - [12:0]
    // 0x14: RESULT [31:0] (Read Only)
    // 0x18: RESULT [63:32] (Read Only)
    // 0x1C: VALID_O (1 bit), READY_O (1 bit) - [1:0] (Read Only)

    logic [63:0] op_a_reg;
    logic [63:0] op_b_reg;
    logic [7:0]  op_sel_reg;
    logic [3:0]  fu_sel_reg;
    logic        valid_i_reg;

    logic [63:0] result_wire;
    logic        valid_o_wire;
    logic        ready_o_wire;

    // -------------------------
    // Register Bus Interface
    // -------------------------
    typedef struct packed {
        logic [31:0] addr;
        logic        write;
        logic [31:0] wdata;
        logic [3:0]  wstrb;
        logic        valid;
    } reg_req_t;

    typedef struct packed {
        logic [31:0] rdata;
        logic        ready;
        logic        error;
    } reg_rsp_t;

    reg_req_t reg_req;
    reg_rsp_t reg_rsp;

    // AXI-Lite to RegBus mapping (Simplified)
    assign awready_o = ~reg_req.valid;
    assign wready_o  = ~reg_req.valid;
    assign arready_o = ~reg_req.valid;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            reg_req.valid <= 1'b0;
            bvalid_o <= 1'b0;
            rvalid_o <= 1'b0;
        end else begin
            // Write Transaction
            if (awvalid_i && wvalid_i && !reg_req.valid && !bvalid_o) begin
                reg_req.addr  <= awaddr_i;
                reg_req.wdata <= wdata_i;
                reg_req.wstrb <= wstrb_i;
                reg_req.write <= 1'b1;
                reg_req.valid <= 1'b1;
            end 
            // Read Transaction
            else if (arvalid_i && !reg_req.valid && !rvalid_o) begin
                reg_req.addr  <= araddr_i;
                reg_req.write <= 1'b0;
                reg_req.valid <= 1'b1;
            end
            
            if (reg_req.valid && reg_rsp.ready) begin
                reg_req.valid <= 1'b0;
                if (reg_req.write) begin
                    bvalid_o <= 1'b1;
                end else begin
                    rdata_o  <= reg_rsp.rdata;
                    rvalid_o <= 1'b1;
                end
            end

            if (bvalid_o && bready_i) bvalid_o <= 1'b0;
            if (rvalid_o && rready_i) rvalid_o <= 1'b0;
        end
    end

    assign bresp_o = 2'b00; // OKAY
    assign rresp_o = 2'b00; // OKAY

    // -------------------------
    // Register Logic
    // -------------------------
    assign reg_rsp.ready = 1'b1;
    assign reg_rsp.error = 1'b0;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            op_a_reg    <= '0;
            op_b_reg    <= '0;
            op_sel_reg  <= '0;
            fu_sel_reg  <= '0;
            valid_i_reg <= 1'b0;
        end else begin
            // Auto-clear valid after one cycle in the harness
            valid_i_reg <= 1'b0;

            if (reg_req.valid && reg_req.write) begin
                case (reg_req.addr[4:0])
                    5'h00: op_a_reg[31:0]  <= reg_req.wdata;
                    5'h04: op_a_reg[63:32] <= reg_req.wdata;
                    5'h08: op_b_reg[31:0]  <= reg_req.wdata;
                    5'h0C: op_b_reg[63:32] <= reg_req.wdata;
                    5'h10: begin
                        op_sel_reg  <= reg_req.wdata[7:0];
                        fu_sel_reg  <= reg_req.wdata[11:8];
                        valid_i_reg <= reg_req.wdata[12];
                    end
                endcase
            end
        end
    end

    always_comb begin
        reg_rsp.rdata = '0;
        case (reg_req.addr[4:0])
            5'h00: reg_rsp.rdata = op_a_reg[31:0];
            5'h04: reg_rsp.rdata = op_a_reg[63:32];
            5'h08: reg_rsp.rdata = op_b_reg[31:0];
            5'h0C: reg_rsp.rdata = op_b_reg[63:32];
            5'h10: reg_rsp.rdata = {19'b0, valid_i_reg, fu_sel_reg, op_sel_reg};
            5'h14: reg_rsp.rdata = result_wire[31:0];
            5'h18: reg_rsp.rdata = result_wire[63:32];
            5'h1C: reg_rsp.rdata = {30'b0, ready_o_wire, valid_o_wire};
        endcase
    end

    // -------------------------
    // Existing Harness Instance
    // -------------------------
    pau_fpu_harness i_harness (
        .clk_i    ( clk_i       ),
        .rst_ni   ( rst_ni      ),
        .op_a_i   ( op_a_reg    ),
        .op_b_i   ( op_b_reg    ),
        .op_sel_i ( op_sel_reg  ),
        .fu_sel_i ( fu_sel_reg  ),
        .valid_i  ( valid_i_reg ),
        .result_o ( result_wire ),
        .valid_o  ( valid_o_wire),
        .ready_o  ( ready_o_wire)
    );

endmodule
