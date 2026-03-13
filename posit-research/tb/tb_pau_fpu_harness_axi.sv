module tb_pau_fpu_harness_axi import ariane_pkg::*; ();
    logic        clk_i;
    logic        rst_ni;

    logic [31:0] awaddr_i;
    logic [2:0]  awprot_i;
    logic        awvalid_i;
    logic        awready_o;
    logic [31:0] wdata_i;
    logic [3:0]  wstrb_i;
    logic        wvalid_i;
    logic        wready_o;
    logic [1:0]  bresp_o;
    logic        bvalid_o;
    logic        bready_i;
    logic [31:0] araddr_i;
    logic [2:0]  arprot_i;
    logic        arvalid_i;
    logic        arready_o;
    logic [31:0] rdata_o;
    logic [1:0]  rresp_o;
    logic        rvalid_o;
    logic        rready_i;

    pau_fpu_harness_axi dut (.*);

    initial clk_i = 0;
    always #5 clk_i = ~clk_i;

    task static axi_write(input [31:0] addr, input [31:0] data);
        awaddr_i = addr;
        awvalid_i = 1;
        wdata_i = data;
        wstrb_i = 4'hf;
        wvalid_i = 1;
        bready_i = 1;
        @(posedge clk_i);
        while (!awready_o || !wready_o) @(posedge clk_i);
        awvalid_i = 0;
        wvalid_i = 0;
        while (!bvalid_o) @(posedge clk_i);
        @(posedge clk_i);
    endtask

    task static axi_read(input [31:0] addr, output [31:0] data);
        araddr_i = addr;
        arvalid_i = 1;
        rready_i = 1;
        @(posedge clk_i);
        while (!arready_o) @(posedge clk_i);
        arvalid_i = 0;
        while (!rvalid_o) @(posedge clk_i);
        data = rdata_o;
        @(posedge clk_i);
    endtask

    logic [31:0] read_val;

    initial begin
        rst_ni = 0;
        awvalid_i = 0; wvalid_i = 0; arvalid_i = 0; bready_i = 0; rready_i = 0;
        repeat(10) @(posedge clk_i);
        rst_ni = 1;
        repeat(5) @(posedge clk_i);

        $display("AXI Test: Writing Operands...");
        // Write OP_A = 0x7F939D17
        axi_write(32'h00, 32'h7F939D17);
        // Write OP_B = 0x7F6EC2BF
        axi_write(32'h08, 32'h7F6EC2BF);
        // Write CONTROL (PADD=26 (approx based on enum), PAU=10, VALID=1)
        // PADD is 26th in enum (0-indexed) -> 0x1A
        // PAU is 10th in enum -> 0xA
        // Control word: {valid[12], fu[11:8], op[7:0]}
        // 1_1010_1010_1010 -> but wait, let's use the actual values
        axi_write(32'h10, (1 << 12) | (10 << 8) | 8'h1A);

        $display("AXI Test: Waiting for result...");
        do begin
            axi_read(32'h1C, read_val); // Read STATUS
        end while (read_val[0] == 0);

        axi_read(32'h14, read_val); // Read RES_LO
        $display("AXI Result: %h", read_val);

        repeat(20) @(posedge clk_i);
        $finish;
    end
endmodule
