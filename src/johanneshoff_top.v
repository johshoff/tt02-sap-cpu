`default_nettype none

module johanneshoff_top(
  input [7:0] io_in,
  output [7:0] io_out
);

  wire clk = io_in[0];
  wire reset = io_in[1];

  wire halted;

	machine m(
		clk,
		0, // en_read_external
		0, // external_value
		io_out,
		output wire halted);

endmodule

