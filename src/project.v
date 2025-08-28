/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // Control signals from ui_in - FIXED: Correct bit width declarations
    wire [1:0] precision_sel = ui_in[7:6];  // 00=8bit, 01=16bit, 10=32bit
    wire [2:0] alu_op = ui_in[5:3];         // ALU operation select
    wire data_load = ui_in[2];              // Load data signal
    wire [1:0] result_sel = ui_in[1:0];     // FIXED: Declared as [1:0] instead of single bit
    
    // Internal registers for multi-precision operands
    reg [31:0] operand_a;
    reg [31:0] operand_b;
    reg [31:0] alu_result;
    
    // Data input counter for loading multi-byte operands
    reg [3:0] load_counter;
    reg [1:0] load_state; // 0=idle, 1=loading_a, 2=loading_b, 3=compute
    
    // ALU operations
    parameter ALU_ADD  = 3'b000;
    parameter ALU_SUB  = 3'b001;
    parameter ALU_AND  = 3'b010;
    parameter ALU_OR   = 3'b011;
    parameter ALU_XOR  = 3'b100;
    parameter ALU_SHL  = 3'b101;
    parameter ALU_SHR  = 3'b110;
    parameter ALU_CMP  = 3'b111;
    
    // Precision parameters
    parameter PREC_8BIT  = 2'b00;
    parameter PREC_16BIT = 2'b01;
    parameter PREC_32BIT = 2'b10;
    
    // Status flags
    reg carry_flag, zero_flag, negative_flag, overflow_flag;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            operand_a <= 32'h0;
            operand_b <= 32'h0;
            alu_result <= 32'h0;
            load_counter <= 4'h0;
            load_state <= 2'b00;
            carry_flag <= 1'b0;
            zero_flag <= 1'b0;
            negative_flag <= 1'b0;
            overflow_flag <= 1'b0;
        end else begin
            case (load_state)
                2'b00: begin // IDLE
                    if (data_load) begin
                        load_state <= 2'b01;
                        load_counter <= 4'h0;
                    end
                end
                
                2'b01: begin // LOADING OPERAND A
                    case (precision_sel)
                        PREC_8BIT: begin
                            operand_a[7:0] <= uio_in;
                            load_state <= 2'b10;
                        end
                        PREC_16BIT: begin
                            if (load_counter == 0) begin
                                operand_a[7:0] <= uio_in;
                                load_counter <= load_counter + 1;
                            end else begin
                                operand_a[15:8] <= uio_in;
                                load_state <= 2'b10;
                                load_counter <= 4'h0;
                            end
                        end
                        PREC_32BIT: begin
                            case (load_counter)
                                0: operand_a[7:0]   <= uio_in;
                                1: operand_a[15:8]  <= uio_in;
                                2: operand_a[23:16] <= uio_in;
                                3: begin
                                    operand_a[31:24] <= uio_in;
                                    load_state <= 2'b10;
                                    load_counter <= 4'h0;
                                end
                            endcase
                            if (load_counter < 3)
                                load_counter <= load_counter + 1;
                        end
                        default: load_state <= 2'b00;
                    endcase
                end
                
                2'b10: begin // LOADING OPERAND B
                    case (precision_sel)
                        PREC_8BIT: begin
                            operand_b[7:0] <= uio_in;
                            load_state <= 2'b11;
                        end
                        PREC_16BIT: begin
                            if (load_counter == 0) begin
                                operand_b[7:0] <= uio_in;
                                load_counter <= load_counter + 1;
                            end else begin
                                operand_b[15:8] <= uio_in;
                                load_state <= 2'b11;
                                load_counter <= 4'h0;
                            end
                        end
                        PREC_32BIT: begin
                            case (load_counter)
                                0: operand_b[7:0]   <= uio_in;
                                1: operand_b[15:8]  <= uio_in;
                                2: operand_b[23:16] <= uio_in;
                                3: begin
                                    operand_b[31:24] <= uio_in;
                                    load_state <= 2'b11;
                                    load_counter <= 4'h0;
                                end
                            endcase
                            if (load_counter < 3)
                                load_counter <= load_counter + 1;
                        end
                        default: load_state <= 2'b00;
                    endcase
                end
                
                2'b11: begin // COMPUTE
                    case (precision_sel)
                        PREC_8BIT: begin
                            case (alu_op)
                                ALU_ADD: {carry_flag, alu_result[7:0]} <= operand_a[7:0] + operand_b[7:0];
                                ALU_SUB: {carry_flag, alu_result[7:0]} <= operand_a[7:0] - operand_b[7:0];
                                ALU_AND: alu_result[7:0] <= operand_a[7:0] & operand_b[7:0];
                                ALU_OR:  alu_result[7:0] <= operand_a[7:0] | operand_b[7:0];
                                ALU_XOR: alu_result[7:0] <= operand_a[7:0] ^ operand_b[7:0];
                                ALU_SHL: alu_result[7:0] <= operand_a[7:0] << operand_b[2:0];
                                ALU_SHR: alu_result[7:0] <= operand_a[7:0] >> operand_b[2:0];
                                ALU_CMP: alu_result[7:0] <= (operand_a[7:0] == operand_b[7:0]) ? 8'h00 : 8'hFF;
                            endcase
                            zero_flag <= (alu_result[7:0] == 8'h00);
                            negative_flag <= alu_result[7];
                        end
                        
                        PREC_16BIT: begin
                            case (alu_op)
                                ALU_ADD: {carry_flag, alu_result[15:0]} <= operand_a[15:0] + operand_b[15:0];
                                ALU_SUB: {carry_flag, alu_result[15:0]} <= operand_a[15:0] - operand_b[15:0];
                                ALU_AND: alu_result[15:0] <= operand_a[15:0] & operand_b[15:0];
                                ALU_OR:  alu_result[15:0] <= operand_a[15:0] | operand_b[15:0];
                                ALU_XOR: alu_result[15:0] <= operand_a[15:0] ^ operand_b[15:0];
                                ALU_SHL: alu_result[15:0] <= operand_a[15:0] << operand_b[3:0];
                                ALU_SHR: alu_result[15:0] <= operand_a[15:0] >> operand_b[3:0];
                                ALU_CMP: alu_result[15:0] <= (operand_a[15:0] == operand_b[15:0]) ? 16'h0000 : 16'hFFFF;
                            endcase
                            zero_flag <= (alu_result[15:0] == 16'h0000);
                            negative_flag <= alu_result[15];
                        end
                        
                        PREC_32BIT: begin
                            case (alu_op)
                                ALU_ADD: {carry_flag, alu_result} <= operand_a + operand_b;
                                ALU_SUB: {carry_flag, alu_result} <= operand_a - operand_b;
                                ALU_AND: alu_result <= operand_a & operand_b;
                                ALU_OR:  alu_result <= operand_a | operand_b;
                                ALU_XOR: alu_result <= operand_a ^ operand_b;
                                ALU_SHL: alu_result <= operand_a << operand_b[4:0];
                                ALU_SHR: alu_result <= operand_a >> operand_b[4:0];
                                ALU_CMP: alu_result <= (operand_a == operand_b) ? 32'h00000000 : 32'hFFFFFFFF;
                            endcase
                            zero_flag <= (alu_result == 32'h00000000);
                            negative_flag <= alu_result[31];
                        end
                    endcase
                    
                    if (!data_load)
                        load_state <= 2'b00;
                end
            endcase
        end
    end
    
    // Output multiplexer
    reg [7:0] output_data;
    always @(*) begin
        case (precision_sel)
            PREC_8BIT: begin
                output_data = alu_result[7:0];
            end
            
            PREC_16BIT: begin
                case (result_sel[0])  // FIXED: Now accessing bit 0 of 2-bit signal
                    1'b0: output_data = alu_result[7:0];   // Lower byte
                    1'b1: output_data = alu_result[15:8];  // Upper byte
                endcase
            end
            
            PREC_32BIT: begin
                case (result_sel)     // FIXED: Now using full 2-bit result_sel
                    2'b00: output_data = alu_result[7:0];   // Byte 0
                    2'b01: output_data = alu_result[15:8];  // Byte 1
                    2'b10: output_data = alu_result[23:16]; // Byte 2
                    2'b11: output_data = alu_result[31:24]; // Byte 3
                endcase
            end
            
            default: output_data = 8'h00;
        endcase
    end
    
    // Output assignments
    assign uo_out = output_data;
    assign uio_out = {4'h0, overflow_flag, negative_flag, zero_flag, carry_flag};
    assign uio_oe = 8'hF0; // Upper 4 bits as output for flags, lower 4 bits as input
    
    // List all unused inputs to prevent warnings
    wire _unused = &{ena, 1'b0};

endmodule
