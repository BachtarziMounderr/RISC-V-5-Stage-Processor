module rv32_regfile (
    input  logic        clk,
    input  logic        reset,
    input  logic [4:0]  read_addr1,
    input  logic [4:0]  read_addr2,
    output logic [31:0] read_data1,
    output logic [31:0] read_data2,
    input  logic        write_enable,
    input  logic [4:0]  write_addr,
    input  logic [31:0] write_data,
    input  logic [4:0]  debug_addr,
    output logic [31:0] debug_data
);
    logic [31:0] registers [0:31];

    assign read_data1 = (read_addr1 == 5'd0) ? 32'b0 : registers[read_addr1];
    assign read_data2 = (read_addr2 == 5'd0) ? 32'b0 : registers[read_addr2];
    assign debug_data = (debug_addr == 5'd0) ? 32'b0 : registers[debug_addr];

    always_ff @(posedge clk) begin
        if (reset) begin
            for (int i = 0; i < 32; i++) registers[i] <= 32'b0;
        end else if (write_enable && write_addr != 5'd0) begin
            registers[write_addr] <= write_data;
        end
    end
endmodule
