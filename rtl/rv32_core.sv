module rv32_core (
    input  logic        clk,
    input  logic        reset,
    input  logic        run,
    output logic [31:0] instruction_address,
    input  logic [31:0] instruction_data,
    output logic        data_read,
    output logic        data_write,
    output logic [31:0] data_address,
    output logic [31:0] data_write_value,
    input  logic [31:0] data_read_value,
    input  logic        data_ready,
    input  logic [4:0]  debug_register_address,
    output logic [31:0] debug_register_value,
    output logic [31:0] debug_pc,
    output logic [31:0] debug_cycles,
    output logic [31:0] debug_retired,
    output logic [31:0] debug_stalls,
    output logic [31:0] debug_flushes,
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
    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] instruction;
    } ifid_t;

    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] first_value;
        logic [31:0] second_value;
        logic [31:0] immediate;
        logic [4:0]  rs1;
        logic [4:0]  rs2;
        logic [4:0]  rd;
        logic [3:0]  alu_operation;
        logic [2:0]  branch_kind;
        logic [1:0]  jump_kind;
        logic [1:0]  writeback_select;
        logic        operand_a_pc;
        logic        operand_b_imm;
        logic        uses_rs1;
        logic        register_write;
        logic        memory_read;
        logic        memory_write;
    } idex_t;

    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] alu_value;
        logic [31:0] store_value;
        logic [31:0] pc_plus_four;
        logic [4:0]  rd;
        logic [1:0]  writeback_select;
        logic        register_write;
        logic        memory_read;
        logic        memory_write;
    } exmem_t;

    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] value;
        logic [4:0]  rd;
        logic        register_write;
    } memwb_t;

    logic [31:0] pc;
    ifid_t ifid;
    idex_t idex;
    exmem_t exmem;
    memwb_t memwb;

    logic [31:0] decoded_immediate;
    logic [3:0]  decoded_alu_operation;
    logic [2:0]  decoded_branch_kind;
    logic [1:0]  decoded_jump_kind;
    logic [1:0]  decoded_writeback_select;
    logic decoded_operand_a_pc, decoded_operand_b_imm;
    logic decoded_register_write, decoded_memory_read, decoded_memory_write;
    logic decoded_uses_rs1, decoded_uses_rs2, decoded_illegal;
    logic [31:0] register_first, register_second;
    logic [31:0] decoded_first, decoded_second;
    logic [31:0] forwarded_first, forwarded_second;
    logic [31:0] alu_first, alu_second, alu_result;
    logic [31:0] prior_result, memory_result;
    logic [31:0] redirect_target;
    logic branch_taken, redirect, load_use_stall, memory_stall;

    rv32_decode decoder (
        .instruction(ifid.instruction), .immediate(decoded_immediate),
        .alu_operation(decoded_alu_operation), .branch_kind(decoded_branch_kind),
        .jump_kind(decoded_jump_kind), .writeback_select(decoded_writeback_select),
        .operand_a_pc(decoded_operand_a_pc), .operand_b_imm(decoded_operand_b_imm),
        .register_write(decoded_register_write), .memory_read(decoded_memory_read),
        .memory_write(decoded_memory_write), .uses_rs1(decoded_uses_rs1),
        .uses_rs2(decoded_uses_rs2), .illegal(decoded_illegal)
    );

    rv32_regfile register_file (
        .clk(clk), .reset(reset), .read_addr1(ifid.instruction[19:15]),
        .read_addr2(ifid.instruction[24:20]), .read_data1(register_first),
        .read_data2(register_second),
        .write_enable(run && memwb.valid && memwb.register_write),
        .write_addr(memwb.rd), .write_data(memwb.value),
        .debug_addr(debug_register_address), .debug_data(debug_register_value)
    );

    // An instruction in ID may read a register being written in WB on this
    // clock edge. Bypass it here as well as forwarding operands into EX.
    assign decoded_first = (memwb.valid && memwb.register_write && memwb.rd != 5'd0 &&
                            memwb.rd == ifid.instruction[19:15]) ? memwb.value : register_first;
    assign decoded_second = (memwb.valid && memwb.register_write && memwb.rd != 5'd0 &&
                             memwb.rd == ifid.instruction[24:20]) ? memwb.value : register_second;

    assign prior_result = (exmem.writeback_select == 2'd2) ? exmem.pc_plus_four : exmem.alu_value;
    always_comb begin
        forwarded_first = idex.first_value;
        forwarded_second = idex.second_value;
        if (exmem.valid && exmem.register_write && !exmem.memory_read && exmem.rd != 5'd0) begin
            if (exmem.rd == idex.rs1) forwarded_first = prior_result;
            if (exmem.rd == idex.rs2) forwarded_second = prior_result;
        end
        if (memwb.valid && memwb.register_write && memwb.rd != 5'd0) begin
            if (memwb.rd == idex.rs1 &&
                !(exmem.valid && exmem.register_write && !exmem.memory_read && exmem.rd == idex.rs1))
                forwarded_first = memwb.value;
            if (memwb.rd == idex.rs2 &&
                !(exmem.valid && exmem.register_write && !exmem.memory_read && exmem.rd == idex.rs2))
                forwarded_second = memwb.value;
        end
    end

    assign alu_first = idex.operand_a_pc ? idex.pc :
                       (idex.uses_rs1 ? forwarded_first : 32'b0);
    assign alu_second = idex.operand_b_imm ? idex.immediate : forwarded_second;
    rv32_alu alu (.a(alu_first), .b(alu_second),
                  .operation(idex.alu_operation), .result(alu_result));

    always_comb begin
        branch_taken = 1'b0;
        unique case (idex.branch_kind)
            3'd1: branch_taken = forwarded_first == forwarded_second;
            3'd2: branch_taken = forwarded_first != forwarded_second;
            3'd3: branch_taken = $signed(forwarded_first) < $signed(forwarded_second);
            3'd4: branch_taken = $signed(forwarded_first) >= $signed(forwarded_second);
            3'd5: branch_taken = forwarded_first < forwarded_second;
            3'd6: branch_taken = forwarded_first >= forwarded_second;
            default: branch_taken = 1'b0;
        endcase
    end
    assign redirect = idex.valid && ((idex.branch_kind != 3'd0 && branch_taken) ||
                                     idex.jump_kind != 2'd0);
    assign redirect_target = idex.jump_kind == 2'd2 ?
                             ((forwarded_first + idex.immediate) & 32'hffff_fffe) :
                             (idex.pc + idex.immediate);
    assign load_use_stall = ifid.valid && idex.valid && idex.memory_read && idex.rd != 5'd0 &&
                            ((decoded_uses_rs1 && ifid.instruction[19:15] == idex.rd) ||
                             (decoded_uses_rs2 && ifid.instruction[24:20] == idex.rd));
    assign memory_stall = exmem.valid && exmem.memory_read && !data_ready;

    assign instruction_address = pc;
    assign data_read = run && exmem.valid && exmem.memory_read;
    assign data_write = run && exmem.valid && exmem.memory_write;
    assign data_address = exmem.alu_value;
    assign data_write_value = exmem.store_value;
    assign memory_result = exmem.writeback_select == 2'd1 ? data_read_value :
                           exmem.writeback_select == 2'd2 ? exmem.pc_plus_four : exmem.alu_value;
    assign debug_pc = pc;
    assign trace_valid = {memwb.valid, exmem.valid, idex.valid, ifid.valid, run};
    assign trace_if_pc = pc;
    assign trace_id_pc = ifid.pc;
    assign trace_ex_pc = idex.pc;
    assign trace_mem_pc = exmem.pc;
    assign trace_wb_pc = memwb.pc;
    assign trace_load_stall = load_use_stall;
    assign trace_memory_stall = memory_stall;
    assign trace_redirect = redirect;

    always_ff @(posedge clk) begin
        if (reset) begin
            pc <= 32'b0;
            ifid <= '0;
            idex <= '0;
            exmem <= '0;
            memwb <= '0;
            debug_cycles <= 32'b0;
            debug_retired <= 32'b0;
            debug_stalls <= 32'b0;
            debug_flushes <= 32'b0;
            debug_fault <= 1'b0;
        end else if (run) begin
            debug_cycles <= debug_cycles + 32'd1;
            if (memwb.valid) debug_retired <= debug_retired + 32'd1;
            if (memory_stall) begin
                // Cache fills at this edge; older WB completes, younger stages hold.
                // Preserve WB forwarding into the held EX operands before WB
                // disappears, otherwise EX can resume with stale register data.
                idex.first_value <= forwarded_first;
                idex.second_value <= forwarded_second;
                memwb <= '0;
                debug_stalls <= debug_stalls + 32'd1;
            end else begin
                memwb.valid <= exmem.valid;
                memwb.pc <= exmem.pc;
                memwb.value <= memory_result;
                memwb.rd <= exmem.rd;
                memwb.register_write <= exmem.register_write;

                exmem.valid <= idex.valid;
                exmem.pc <= idex.pc;
                exmem.alu_value <= alu_result;
                exmem.store_value <= forwarded_second;
                exmem.pc_plus_four <= idex.pc + 32'd4;
                exmem.rd <= idex.rd;
                exmem.writeback_select <= idex.writeback_select;
                exmem.register_write <= idex.register_write;
                exmem.memory_read <= idex.memory_read;
                exmem.memory_write <= idex.memory_write;

                if (redirect) begin
                    pc <= redirect_target;
                    ifid <= '0;
                    idex <= '0;
                    debug_flushes <= debug_flushes + 32'd1;
                    if (redirect_target[1:0] != 2'b00) debug_fault <= 1'b1;
                end else if (load_use_stall) begin
                    idex <= '0;
                    debug_stalls <= debug_stalls + 32'd1;
                end else begin
                    pc <= pc + 32'd4;
                    ifid.valid <= 1'b1;
                    ifid.pc <= pc;
                    ifid.instruction <= instruction_data;

                    idex.valid <= ifid.valid && !decoded_illegal;
                    idex.pc <= ifid.pc;
                    idex.first_value <= decoded_first;
                    idex.second_value <= decoded_second;
                    idex.immediate <= decoded_immediate;
                    idex.rs1 <= ifid.instruction[19:15];
                    idex.rs2 <= ifid.instruction[24:20];
                    idex.rd <= ifid.instruction[11:7];
                    idex.alu_operation <= decoded_alu_operation;
                    idex.branch_kind <= decoded_branch_kind;
                    idex.jump_kind <= decoded_jump_kind;
                    idex.writeback_select <= decoded_writeback_select;
                    idex.operand_a_pc <= decoded_operand_a_pc;
                    idex.operand_b_imm <= decoded_operand_b_imm;
                    idex.uses_rs1 <= decoded_uses_rs1;
                    idex.register_write <= decoded_register_write;
                    idex.memory_read <= decoded_memory_read;
                    idex.memory_write <= decoded_memory_write;
                    if (ifid.valid && decoded_illegal) debug_fault <= 1'b1;
                    if (idex.valid && (idex.memory_read || idex.memory_write) &&
                        alu_result[1:0] != 2'b00) debug_fault <= 1'b1;
                end
            end
        end
    end
endmodule
