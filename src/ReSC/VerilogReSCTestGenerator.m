%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Copyright (C) 2016 N. Eamon Gaffney
%%
%% This program is free software; you can resdistribute and/or modify it under
%% the terms of the MIT license, a copy of which should have been included with
%% this program at https://github.com/arminalaghi/scsynth
%%
%% References:
%% Qian, W., Li, X., Riedel, M. D., Bazargan, K., & Lilja, D. J. (2011). An
%% Architecture for Fault-Tolerant Computation with Stochastic Logic. IEEE
%% Transactions on Computers IEEE Trans. Comput., 60(1), 93-105.
%% doi:10.1109/tc.2010.202
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function VerilogReSCTestGenerator (coeff, N, m_input, m_coeff, wrapModule,...
                                   namePrefix)

  %Generates a Verilog module that wraps an ReSC unit with conversions
  %from binary to stochastic on the inputs and from stochastic to binary
  %on the outputs.
  
  %Parameters:
  % coeff     : a list of coefficients of the Bernstein polynomial; each
  %             coefficient should fall within the unit interval
  % N         : the length of the stochastic bitstreams, must be a power of 2
  % m_input   : the length in bits of the input, at most log2(N)
  % m_coeff   : the length in bits of the coefficients, at most log2(N)
  % wrapModule: name of the ReSC wrapper module to test
  % namePrefix: a distinguishing prefix to be appended to the Verilog module's
  %             name
  
  m = log2(N);
  degree = length(coeff) - 1;
  
  fileName = sprintf('%s.v', namePrefix);
  header = ['/*\n * This file was generated by the scsynth tool, and is ava',...
            'ilable for use under\n * the MIT license. More information can ',...
            'be found at\n * https://github.com/arminalaghi/scsynth/\n */\n'];
  
  fp = fopen(fileName, 'w');

  fprintf(fp, header);
	fprintf(fp, 'module %s(); //a testbench for an ReSC module\n', namePrefix);
	fprintf(fp, '\treg [%d:0] x_bin; //binary value of input\n', m_input - 1);
  fprintf(fp, '\treg start;\n');
	fprintf(fp, '\twire done;\n');
	fprintf(fp, '\twire [%d:0] z_bin; //binary value of output\n', m - 1);
  fprintf(fp, '\treg [%d:0] expected_z; //expected output\n\n', m - 1);

	fprintf(fp, '\treg clk;\n');
	fprintf(fp, '\treg reset;\n\n');

	fprintf(fp, '\t%s ReSC (\n', wrapModule);
	fprintf(fp, '\t\t.x_bin (x_bin),\n');
	fprintf(fp, '\t\t.start (start),\n');
	fprintf(fp, '\t\t.done (done),\n');
	fprintf(fp, '\t\t.z_bin (z_bin),\n');
	fprintf(fp, '\t\t.clk (clk),\n');
	fprintf(fp, '\t\t.reset (reset)\n');
	fprintf(fp, '\t);\n\n');

	fprintf(fp, '\talways begin\n');
	fprintf(fp, '\t\t#1 clk <= ~clk;\n');
	fprintf(fp, '\tend\n\n');

	fprintf(fp, '\tinitial begin\n');
  fprintf(fp, '\t\tclk = 0;\n');
	fprintf(fp, '\t\treset = 1;\n');
	fprintf(fp, '\t\t#5 reset = 0;\n');
	fprintf(fp, '\t\tstart = 1;\n\n');
    
  for i=0:10
    if (i==0)
      fprintf(fp, '\t\t#10 ');
    else
      fprintf(fp, '\t\t#%d ', N * 2 + 6);
    end
    x = rand();
    y = sum(coeff' .* arrayfun(@nchoosek, degree, 0:degree) .*...
            x .^ (0:degree) .* (1 - x) .^ (degree - (0:degree)));
    x_quantized = round(x * 2 ^ m_input);
    % Fix values which assume exactly 2^m_input
    x_quantized(x_quantized==2^m_input)= (2^m_input)-1;
    y_quantized = round(y * N);
    % Fix values which assume exactly N
    y_quantized(y_quantized==N)= N-1;
    
    fprintf(fp, 'x_bin = %d''d%d;\n', m_input, x_quantized);
    fprintf(fp, '\t\texpected_z = %d''d%d;\n', m, y_quantized);
    fprintf(fp, '\t\tstart = 0;\n\n');
  end
  
	fprintf(fp, '\t\t#%d $stop;\n', 10 * N + 100);
	fprintf(fp, '\tend\n\n');

	fprintf(fp, '\talways @(posedge done) begin\n');
  fprintf(fp, '\t\t$display("x: %%b, z: %%b, expected_z: %%b", ');
  fprintf(fp, 'x_bin, z_bin, expected_z);\n');
	fprintf(fp, '\t\tstart = 1;\n');
	fprintf(fp, '\tend\n');
  fprintf(fp, 'endmodule\n');
  
  fclose(fp);
end
