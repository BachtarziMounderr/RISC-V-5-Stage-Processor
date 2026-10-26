module rv32_dcache #(
    parameter int LINES = 8
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        cpu_read,
    input  logic        cpu_write,
    input  logic [31:0] cpu_address,
    input  logic [31:0] cpu_write_data,
    output logic [31:0] cpu_read_data,
    output logic        cpu_ready,
    output logic        miss,
    input  logic [31:0] backing_read_data
);
    localparam int INDEX_BITS = $clog2(LINES);
    localparam int TAG_BITS = 30 - INDEX_BITS;
    logic [31:0] line_data [0:LINES-1];
    logic [TAG_BITS-1:0] line_tag [0:LINES-1];
    logic [LINES-1:0] line_valid;
    logic [INDEX_BITS-1:0] index;
    logic [TAG_BITS-1:0] tag;
    logic hit;

    assign index = cpu_address[2 +: INDEX_BITS];
    assign tag = cpu_address[31:2+INDEX_BITS];
    assign hit = line_valid[index] && line_tag[index] == tag;
    assign miss = cpu_read && cpu_address[1:0] == 2'b00 && !hit;
    assign cpu_ready = !miss;
    assign cpu_read_data = hit ? line_data[index] : 32'b0;

    always_ff @(posedge clk) begin
        if (reset) begin
            line_valid <= '0;
            for (int i = 0; i < LINES; i++) begin
                line_data[i] <= 32'b0;
                line_tag[i] <= '0;
            end
        end else begin
            // A load miss takes one extra cycle. The CPU holds its MEM request
            // while this word is installed from the backing memory.
            if (miss) begin
                line_data[index] <= backing_read_data;
                line_tag[index] <= tag;
                line_valid[index] <= 1'b1;
            end
            // Stores write through to backing memory in rv32_soc. A hit also
            // updates this cached word; a store miss does not allocate a line.
            if (cpu_write && hit) line_data[index] <= cpu_write_data;
        end
    end
endmodule
