module rv32_decode (
    input  logic [31:0] instruction,
    output logic [31:0] immediate,
    output logic [3:0]  alu_operation,
    output logic [2:0]  branch_kind,
    output logic [1:0]  jump_kind,
    output logic [1:0]  writeback_select,
    output logic        operand_a_pc,
    output logic        operand_b_imm,
    output logic        register_write,
    output logic        memory_read,
    output logic        memory_write,
    output logic        uses_rs1,
    output logic        uses_rs2,
    output logic        illegal
);
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    assign opcode = instruction[6:0];
    assign funct3 = instruction[14:12];
    assign funct7 = instruction[31:25];

    always_comb begin
        immediate = 32'b0;
        alu_operation = 4'd0;
        branch_kind = 3'd0;
        jump_kind = 2'd0;
        writeback_select = 2'd0;
        operand_a_pc = 1'b0;
        operand_b_imm = 1'b0;
        register_write = 1'b0;
        memory_read = 1'b0;
        memory_write = 1'b0;
        uses_rs1 = 1'b0;
        uses_rs2 = 1'b0;
        illegal = 1'b0;
        unique case (opcode)
            7'b0110011: begin // register-register arithmetic
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
                register_write = 1'b1;
                unique case ({funct7, funct3})
                    {7'b0000000, 3'b000}: alu_operation = 4'd0; // ADD
                    {7'b0100000, 3'b000}: alu_operation = 4'd1; // SUB
                    {7'b0000000, 3'b111}: alu_operation = 4'd2; // AND
                    {7'b0000000, 3'b110}: alu_operation = 4'd3; // OR
                    {7'b0000000, 3'b100}: alu_operation = 4'd4; // XOR
                    {7'b0000000, 3'b010}: alu_operation = 4'd5; // SLT
                    {7'b0000000, 3'b011}: alu_operation = 4'd6; // SLTU
                    {7'b0000000, 3'b001}: alu_operation = 4'd7; // SLL
                    {7'b0000000, 3'b101}: alu_operation = 4'd8; // SRL
                    {7'b0100000, 3'b101}: alu_operation = 4'd9; // SRA
                    default: illegal = 1'b1;
                endcase
            end
            7'b0010011: begin // register-immediate arithmetic
                uses_rs1 = 1'b1;
                register_write = 1'b1;
                operand_b_imm = 1'b1;
                immediate = {{20{instruction[31]}}, instruction[31:20]};
                unique case (funct3)
                    3'b000: alu_operation = 4'd0; // ADDI
                    3'b111: alu_operation = 4'd2; // ANDI
                    3'b110: alu_operation = 4'd3; // ORI
                    3'b100: alu_operation = 4'd4; // XORI
                    3'b010: alu_operation = 4'd5; // SLTI
                    3'b011: alu_operation = 4'd6; // SLTIU
                    3'b001: begin
                        alu_operation = 4'd7;
                        if (funct7 != 7'b0000000) illegal = 1'b1;
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000) alu_operation = 4'd8; // SRLI
                        else if (funct7 == 7'b0100000) alu_operation = 4'd9; // SRAI
                        else illegal = 1'b1;
                    end
                    default: illegal = 1'b1;
                endcase
            end
            7'b0000011: begin // LW
                uses_rs1 = 1'b1;
                register_write = 1'b1;
                memory_read = 1'b1;
                operand_b_imm = 1'b1;
                writeback_select = 2'd1;
                immediate = {{20{instruction[31]}}, instruction[31:20]};
                if (funct3 != 3'b010) illegal = 1'b1;
            end
            7'b0100011: begin // SW
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
                memory_write = 1'b1;
                operand_b_imm = 1'b1;
                immediate = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
                if (funct3 != 3'b010) illegal = 1'b1;
            end
            7'b1100011: begin // conditional branches
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
                immediate = {{19{instruction[31]}}, instruction[31], instruction[7],
                             instruction[30:25], instruction[11:8], 1'b0};
                unique case (funct3)
                    3'b000: branch_kind = 3'd1; // BEQ
                    3'b001: branch_kind = 3'd2; // BNE
                    3'b100: branch_kind = 3'd3; // BLT
                    3'b101: branch_kind = 3'd4; // BGE
                    3'b110: branch_kind = 3'd5; // BLTU
                    3'b111: branch_kind = 3'd6; // BGEU
                    default: illegal = 1'b1;
                endcase
            end
            7'b1101111: begin // JAL
                register_write = 1'b1;
                jump_kind = 2'd1;
                writeback_select = 2'd2;
                immediate = {{11{instruction[31]}}, instruction[31], instruction[19:12],
                             instruction[20], instruction[30:21], 1'b0};
            end
            7'b1100111: begin // JALR
                uses_rs1 = 1'b1;
                register_write = 1'b1;
                jump_kind = 2'd2;
                writeback_select = 2'd2;
                immediate = {{20{instruction[31]}}, instruction[31:20]};
                if (funct3 != 3'b000) illegal = 1'b1;
            end
            7'b0110111: begin // LUI
                register_write = 1'b1;
                operand_b_imm = 1'b1;
                immediate = {instruction[31:12], 12'b0};
            end
            7'b0010111: begin // AUIPC
                register_write = 1'b1;
                operand_a_pc = 1'b1;
                operand_b_imm = 1'b1;
                immediate = {instruction[31:12], 12'b0};
            end
            default: illegal = 1'b1;
        endcase
        if (illegal) begin
            register_write = 1'b0;
            memory_read = 1'b0;
            memory_write = 1'b0;
            branch_kind = 3'd0;
            jump_kind = 2'd0;
        end
    end
endmodule
