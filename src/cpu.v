// an attempt to recreate Ben Eaters 8-bit computer in Verilog

`default_nettype none

module register(
	inout wire [7:0] bus,
	input wire clk,
	input wire reset,
	input wire en_write,
	output reg [7:0] value

);
	always @(posedge clk)
		if (reset) value <= 0;
		else if (en_write) value <= bus;
endmodule

module registerpc(
	inout wire [7:0] bus,
	input wire clk,
	input wire reset,
	input wire en_write,
	input wire en_increment_pc,
	output reg [7:0] value

);
	always @(posedge clk)
		if (reset) value <= 0;
		else if (en_increment_pc) value <= value + 1;
		else if (en_write) value <= bus;
endmodule

module memory(
	inout wire [7:0] bus,
	input wire clk,
	input wire reset,
	input wire en_write_mem,
	input wire en_write_mem_adr,
	output reg [7:0] last_read
);
	reg [3:0] address_register;
	reg [7:0] data[0:15];

	always @(posedge clk) begin
		if (reset) address_register <= 0; // zeroing address, but not memory
		else if (en_write_mem_adr) address_register <= bus;
		else if (en_write_mem) data[address_register] <= bus;
	end

	always @(*)
		last_read <= data[address_register];

	initial begin
		// add a default program to RAM
		$readmemh("build/fib.hex", data);
	end
endmodule

module micro_instr_counter(
	input wire clk,
	input wire reset,
	output reg [2:0] count
);
	always @(posedge clk)
		if (reset) count <= 0;
		else if (count == 5) count <= 0;
		else count <= count + 1;
endmodule

module add_carry(
	input wire [7:0] a,
	input wire [7:0] b,
	input wire carry_in,
	output wire [7:0] sum,
	output wire carry_out
);
	wire [8:0] internal_sum;

	assign internal_sum = a + b + carry_in;
	assign sum = internal_sum[7:0];
	assign carry_out = internal_sum[8];
endmodule

module machine(
	input wire clk,
	input wire reset,
	input wire en_read_external,
	input wire [7:0] external_value,
	output wire [7:0] out_reg_out,
	output wire halted
);
	wire [7:0] bus;
	wire [7:0] alu;
	wire [15:0] micro_lookup;
	wire [15:0] micro;
	wire [2:0] micro_counter;
	wire en_write_a;
	wire en_read_a;
	wire en_write_b;
	wire en_write_pc;
	wire en_read_pc;
	wire en_increment_pc;
	wire en_write_instr;
	wire en_read_instr;
	wire en_write_mem;
	wire en_read_mem;
	wire en_write_mem_adr;
	wire en_read_alu;
	wire micro_done;
	wire en_subtraction;
	wire en_write_out;

	wire carry_out;
	reg last_zero;
	reg last_carry;

	wire [7:0] out_mem;
	wire [7:0] out_reg_a;
	wire [7:0] out_reg_b; // never read
	wire [7:0] out_reg_pc;
	wire [7:0] out_reg_instr;

	micro_instr_counter mc(clk, reset | micro_done, micro_counter);

	register a    (bus, clk, reset, en_write_a,     out_reg_a);
	register b    (bus, clk, reset, en_write_b,     out_reg_b);
	register out  (bus, clk, reset, en_write_out,   out_reg_out);
	register instr(bus, clk, reset, en_write_instr, out_reg_instr);
	registerpc pc (bus, clk, reset, en_write_pc,    en_increment_pc, out_reg_pc);

	memory m(bus, clk, reset, en_write_mem, en_write_mem_adr, out_mem);

	assign micro_lookup = out_reg_instr[7:4] == 4'h1 ? (
		micro_counter == 2 ? 16'b0000000000010010 :
		16'b0010010000000100
	)
	: out_reg_instr[7:4] == 4'h2 ? (
		micro_counter == 2 ? 16'b0000000000010010 :
		micro_counter == 3 ? 16'b0000000100000100 :
		16'b0010010000000001
	)
	: out_reg_instr[7:4] == 4'h3 ? (
		micro_counter == 2 ? 16'b0000000000010010 :
		micro_counter == 3 ? 16'b0000000100000100 :
		16'b0110010000000001
	)
	: out_reg_instr[7:4] == 4'h4 ? (
		micro_counter == 2 ? 16'b0000000000010010 :
		16'b0010001000001000
	)
	: out_reg_instr[7:4] == 4'h5 ? (
		16'b0010010000010000
	)
	: out_reg_instr[7:4] == 4'h6 ? (
		16'b0010000010010000
	)
	: out_reg_instr[7:4] == 4'h7 ? (
		last_carry ? 16'b0010000010010000 : 16'b0010000000000000
	)
	: out_reg_instr[7:4] == 4'h8 ? (
		last_zero ? 16'b0010000010010000 : 16'b0010000000000000
	)
	: out_reg_instr[7:4] == 4'h9 ? (
		last_carry ? 16'b0010000000000000 : 16'b0010000010010000
	)
	: out_reg_instr[7:4] == 4'ha ? (
		last_zero ? 16'b0010000000000000 : 16'b0010000010010000
	)
	: out_reg_instr[7:4] == 4'he ? (
		16'b1010001000000000
	)
	: out_reg_instr[7:4] == 4'hf ? (
		16'b0001000000000000
	)
	: 16'b0010000000000000;

	assign micro = micro_counter == 0 ? 16'b0000000001000010
	             : micro_counter == 1 ? 16'b0000100000100100
	             : micro_lookup;

	add_carry adc(
		out_reg_a,
		en_subtraction ? ~out_reg_b : out_reg_b,
		en_subtraction,
		alu,
		carry_out);

	assign bus = en_read_external ? external_value
	           : en_read_alu      ? alu
	           : en_read_instr    ? { 4'b0, out_reg_instr[3:0] }
	           : en_read_mem      ? out_mem
	           : en_read_a        ? out_reg_a
	           : en_read_pc       ? out_reg_pc
	           : 0;

	assign
		{
			en_write_out,
			en_subtraction,
			micro_done,
			halted,
			en_increment_pc,
			en_write_a,
			en_read_a,
			en_write_b,
			en_write_pc,
			en_read_pc,
			en_write_instr,
			en_read_instr,
			en_write_mem,
			en_read_mem,
			en_write_mem_adr,
			en_read_alu
		} = micro;

	always @(posedge clk) begin
		if (reset) begin
			last_zero <= 0;
			last_carry <= 0;
		end else if (en_read_alu) begin
			last_zero <= alu == 0;
			last_carry <= carry_out;
		end
	end
endmodule

