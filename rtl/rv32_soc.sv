module rv32_soc #(
    parameter int IMEM_WORDS = 256,
    parameter int DMEM_WORDS = 256,
    parameter int CACHE_LINES = 8
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        run,
    input  logic        program_write,
    input  logic [31:0] program_address,
    input  logic [31:0] program_data,
    input  logic        data_preload_write,
    input  logic [31:0] data_preload_address,
    input  logic [31:0] data_preload_value,
    input  logic [31:0] debug_data_address,
    output logic [31:0] debug_data_value,
    input  logic [4:0]  debug_register_address,
    output logic [31:0] debug_register_value,
    output logic [31:0] debug_pc,
    output logic [31:0] debug_cycles,
    output logic [31:0] debug_retired,
    output logic [31:0] debug_stalls,
    output logic [31:0] debug_flushes,
    output logic [31:0] debug_cache_misses,
    output logic        debug_fault,
    output logic [4:0]  trace_valid,
    output logic [31:0] trace_if_pc,
    output logic [31:0] trace_id_pc,
    output logic [31:0] trace_ex_pc,
    output logic [31:0] trace_mem_pc,
    output logic [31:0] trace_wb_pc,
    output logic        trace_load_stall,
    output logic        trace_memory_stall,
    output logic        trace_redirect
);
    localparam logic [31:0] NOP = 32'h0000_0013; // ADDI x0, x0, 0
    localparam int IMEM_INDEX_BITS = $clog2(IMEM_WORDS);
    localparam int DMEM_INDEX_BITS = $clog2(DMEM_WORDS);
    logic [31:0] instruction_memory [0:IMEM_WORDS-1];
    logic [31:0] data_memory [0:DMEM_WORDS-1];
    logic [31:0] instruction_address, instruction_data;
    logic data_read, data_write, data_ready, cache_miss;
    logic [31:0] data_address, data_write_value, data_read_value, backing_read_value;

    initial begin
        for (int i = 0; i < IMEM_WORDS; i++) instruction_memory[i] = NOP;
        for (int i = 0; i < DMEM_WORDS; i++) data_memory[i] = 32'b0;
    end

    assign instruction_data = (instruction_address[1:0] == 2'b00 &&
                               int'(instruction_address[31:2]) < IMEM_WORDS) ?
                              instruction_memory[instruction_address[2 +: IMEM_INDEX_BITS]] : NOP;
    assign backing_read_value = (data_address[1:0] == 2'b00 &&
                                 int'(data_address[31:2]) < DMEM_WORDS) ?
                                data_memory[data_address[2 +: DMEM_INDEX_BITS]] : 32'b0;
    assign debug_data_value = (debug_data_address[1:0] == 2'b00 &&
                               int'(debug_data_address[31:2]) < DMEM_WORDS) ?
                              data_memory[debug_data_address[2 +: DMEM_INDEX_BITS]] : 32'b0;

    always_ff @(posedge clk) begin
        if (!run && program_write && program_address[1:0] == 2'b00 &&
            int'(program_address[31:2]) < IMEM_WORDS)
            instruction_memory[program_address[2 +: IMEM_INDEX_BITS]] <= program_data;
        if (!run && data_preload_write && data_preload_address[1:0] == 2'b00 &&
            int'(data_preload_address[31:2]) < DMEM_WORDS)
            data_memory[data_preload_address[2 +: DMEM_INDEX_BITS]] <= data_preload_value;
        else if (data_write && data_address[1:0] == 2'b00 &&
                 int'(data_address[31:2]) < DMEM_WORDS)
            data_memory[data_address[2 +: DMEM_INDEX_BITS]] <= data_write_value;
    end

    rv32_dcache #(.LINES(CACHE_LINES)) cache (
        .clk(clk), .reset(reset), .cpu_read(data_read), .cpu_write(data_write),
        .cpu_address(data_address), .cpu_write_data(data_write_value),
        .cpu_read_data(data_read_value), .cpu_ready(data_ready),
        .miss(cache_miss), .backing_read_data(backing_read_value)
    );

    rv32_core core (
        .clk(clk), .reset(reset), .run(run),
        .instruction_address(instruction_address), .instruction_data(instruction_data),
        .data_read(data_read), .data_write(data_write), .data_address(data_address),
        .data_write_value(data_write_value), .data_read_value(data_read_value),
        .data_ready(data_ready), .debug_register_address(debug_register_address),
        .debug_register_value(debug_register_value), .debug_pc(debug_pc),
        .debug_cycles(debug_cycles), .debug_retired(debug_retired),
        .debug_stalls(debug_stalls), .debug_flushes(debug_flushes),
        .debug_fault(debug_fault), .trace_valid(trace_valid),
        .trace_if_pc(trace_if_pc), .trace_id_pc(trace_id_pc),
        .trace_ex_pc(trace_ex_pc), .trace_mem_pc(trace_mem_pc),
        .trace_wb_pc(trace_wb_pc), .trace_load_stall(trace_load_stall),
        .trace_memory_stall(trace_memory_stall), .trace_redirect(trace_redirect)
    );

    always_ff @(posedge clk) begin
        if (reset) debug_cache_misses <= 32'b0;
        else if (cache_miss) debug_cache_misses <= debug_cache_misses + 32'd1;
    end
endmodule
