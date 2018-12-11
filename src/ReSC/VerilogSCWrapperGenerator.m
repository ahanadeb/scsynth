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
%%
%% A. Alaghi and J. P. Hayes, "Exploiting correlation in stochastic circuit
%% design," 2013 IEEE 31st International Conference on Computer Design (ICCD),
%% Asheville, NC, 2013, pp. 39-46.
%% doi: 10.1109/ICCD.2013.6657023\
%%
%% Gupta, P. K. and Kumaresan, R. 1988. Binary multiplication with PN sequences.
%% IEEE Trans. Acoustics Speech Signal Process. 36, 603–606.
%%
%% B. D. Brown and H. C. Card, "Stochastic neural computation. I. Computational
%% elements," in IEEE Transactions on Computers, vol. 50, no. 9, pp. 891-905,
%% Sep 2001. doi: 10.1109/12.954505
%%
%% A. Alaghi and J. P. Hayes, "STRAUSS: Spectral Transform Use in Stochastic
%% Circuit Synthesis," in IEEE Transactions on Computer-Aided Design of
%% Integrated Circuits and Systems, vol. 34, no. 11, pp. 1770-1783, Nov. 2015.
%% doi: 10.1109/TCAD.2015.2432138
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function VerilogSCWrapperGenerator (coeff, N, m_input, m_coeff,... 
                                    constRandModule, inputRandModule,...
                                    SCModule, moduleName,...
                                    ConstantRNG='SharedLFSR',...
                                    InputRNG='LFSR',...
                                    ConstantSNG='Comparator',...
                                    InputSNG='Comparator')

  %Generates a Verilog module that wraps an ReSC or STRAUSS unit with
  %conversions from binary to stochastic on the inputs and from stochastic to
  %binary on the outputs.
  
  %Parameters:
  % coeff          : a list of coefficients of the Bernstein polynomial; each
  %                  coefficient should fall within the unit interval
  % N              : the length of the stochastic bitstreams, must be a power of 2
  % m_input        : the length in bits of the input, at most log2(N)
  % m_coeff        : the length in bits of the coefficients, at most log2(N)
  % constRandModule: name of the randomizing Verilog module to be used for
  %                  stochastic number generation for weights
  % inputRandModule: name of the randomizing Verilog module to be used for
  %                  stochastic number generation for inputs
  % SCModule       : name of the ReSC or STRAUSS module to wrap
  % moduleName     : the name of the verilog module
  
  %Optional Parameters:
  % ConstantRNG: Choose the method for generating the random numbers used in
  %              stochastic generation of the constants. Options:
  %                'SharedLFSR' (default) - Use one LFSR for all weights
  %                'LFSR' - Use a unique LFSR for each weight
  %                'Counter' - Count from 0 to 2^m in order
  %                'ReverseCounter' - Count from 0 to 2^m, but reverse the
  %                                    order of the bits
  % InputRNG: Choose the method for generating the random numbers used in
  %           stochastic generation of the input values. Options:
  %             'LFSR' - Use a unique LFSR for each input
  %             'SingleLFSR' - Use one longer LFSR, giving a unique n-bit
  %                            segment tp each copy of the inputs
  % ConstantSNG: Choose the method for generating stochastic versions of the
  %              the constants. Options:
  %                'Comparator' - Compare the values to random numbers (default)
  %                'Majority' - A series of cascading majority gates
  %                'WBG' - Circuit defined in Gupta and Kumaresan (1988)
  %                'Mux' - A series of cascading multiplexers
  %                'HardWire' - A hardwired series of and and or gates with
  %                             space-saving optimizations.
  % InputSNG: Choose the method for generating stochastic versions of the
  %           inputs. Options are the same as for ConstantSNG with the exception
  %           of 'HardWire'.
  
  m = log2(N);
  decimal_coeffs = round(coeff * 2^m_coeff) / (2^m_coeff) * N;
  degree = length(coeff) - 1;
  
	fileName = sprintf('%s.v', moduleName);
  header = ['/*\n * This file was generated by the scsynth tool, and is ava'...
            'ilable for use under\n * the MIT license. More information can '...
            'be found at\n * https://github.com/arminalaghi/scsynth/\n */\n'];
  
  fp = fopen(fileName, 'w');
  
  %declare module
  fprintf(fp, header);
  fprintf(fp, 'module %s( //handles stochastic/binary conversion for ReSC\n',...
          moduleName);
	fprintf(fp, '\tinput [%d:0] x_bin, //binary value of input\n', m_input - 1);
  fprintf(fp, '\tinput start, //signal to start counting\n');
  fprintf(fp, '\toutput reg done, //signal that a number has been computed \n');
  fprintf(fp, '\toutput reg [%d:0] z_bin, //binary value of output\n\n', m - 1);
  
	fprintf(fp, '\tinput clk,\n');
	fprintf(fp, '\tinput reset\n');
  fprintf(fp, ');\n\n');

  if (m_input < m)
    fprintf(fp, '\twire [%d:0] x_bin_shifted;\n', m - 1);
    fprintf(fp, '\tassign x_bin_shifted = x_bin << %d;\n\n', m - m_input);
  end
  
  %define the constant coefficients
  if !strcmp(ConstantSNG, 'HardWire')
    fprintf(fp, '\t//the weights of the Bernstein polynomial\n');
    for i=0:degree
      fprintf(fp, '\treg [%d:0] w%d_bin = %d\''d%d;\n', m - 1, i, m,...
              decimal_coeffs(i+1));
    end
  end
  
  %declare internal wires
	fprintf(fp, '\n\twire [%d:0] x_stoch;\n', degree - 1);
	fprintf(fp, '\twire [%d:0] w_stoch;\n', degree);
	fprintf(fp, '\twire z_stoch;\n');
	fprintf(fp, '\twire init;\n');
	fprintf(fp, '\twire running;\n\n');

  %binary to stochastic conversion for the x values
  fprintf(fp, '\t//RNGs for binary->stochastic conversion\n');
  switch(InputRNG)
    case 'LFSR'
      for i=0:degree - 1
        fprintf(fp, '\twire [%d:0] randx%d;\n', m - 1, i);
        fprintf(fp, '\t%s rand_gen_x_%d (\n', inputRandModule, i);
		    fprintf(fp, '\t\t.seed (%d''d%d),\n', m, round(N*i/(degree*2+1)));
        fprintf(fp, '\t\t.data (randx%d),\n', i);
		    fprintf(fp, '\t\t.enable (running),\n');
        fprintf(fp, '\t\t.restart (init),\n');
	  	  fprintf(fp, '\t\t.clk (clk),\n');
	    	fprintf(fp, '\t\t.reset (reset)\n');
	    	fprintf(fp, '\t);\n\n');
      end
    case 'SingleLFSR'
      fprintf(fp, '\twire [%d:0] randx;\n', m * degree - 1);
      fprintf(fp, '\t%s rand_gen_x (\n', inputRandModule);
		  fprintf(fp, '\t\t.seed (%d''d%d),\n', m * degree, 1);
      fprintf(fp, '\t\t.data (randx),\n', i);
		  fprintf(fp, '\t\t.enable (running),\n');
      fprintf(fp, '\t\t.restart (init),\n');
	    fprintf(fp, '\t\t.clk (clk),\n');
	  	fprintf(fp, '\t\t.reset (reset)\n');0
	    fprintf(fp, '\t);\n');
      for i=0:degree-1
        fprintf(fp, '\twire[%d:0] randx%d;\n', m - 1, i);
        fprintf(fp, '\tassign randx%d = randx[%d:%d];\n\n', i, (i+1)*m-1, i*m);
      end
  end
  
  if (m_input < m)
    x_bin = 'x_bin_shifted';
  else
    x_bin = 'x_bin';
  end
  
  for i=0:degree-1
    switch(InputSNG)
      case 'Comparator'
          fprintf(fp, '\tassign x_stoch[%d] = randx%d < %s;\n\n',  i, i, x_bin);
      case 'Majority'
        fprintf(fp, '\twire majority%d_0;\n', i);
        fprintf(fp, '\tassign majority%d_0 = randx%d[0] & %s[0];\n', i, i,
                x_bin);
        for j=1:m-2
          fprintf(fp, '\twire majority%d_%d;\n', i, j);
          fprintf(fp, ['\tassign majority%d_%d = (randx%d[%d] & %s[%d]) | ',...
                       '(randx%d[%d] & majority%d_%d) | (%s[%d] & majority%d'...
                       '_%d);\n'], i, j, i, j, x_bin, j, i, j, i, j-1, x_bin,...
                  j, i, j-1);
        end
        fprintf(fp, ['\tassign x_stoch[%d] = (randx%d[%d] & %s[%d]) | ',...
                     '(randx%d[%d] & majority%d_%d) | (%s[%d] & majority%d_%'...
                     'd);\n\n'], i, i, m-1, x_bin, m-1, i, m-1, i, m-2,...
                x_bin, m-1, i, m-2);
      case 'WBG'
        and = sprintf('randx%d[%d]', i, m-1);
        for j=fliplr(1:m-1)
          fprintf(fp, '\twire wbg%d_%d;\n', i, j);
          fprintf(fp, '\tassign wbg%d_%d = %s & %s[%d];\n', i, j, and, x_bin, j);
          and = sprintf('randx%d[%d] & ~%s', i, j-1, and);
        end
        fprintf(fp, '\tassign x_stoch[%d] = %s & %s[0]', i, and, x_bin);
        for j=1:m-1
          fprintf(fp, ' | wbg%d_%d', i, j);
        end
        fprintf(fp, ';\n\n');
      case 'Mux'
        fprintf(fp, '\twire mux%d_0;\n', i);
        fprintf(fp, '\tassign mux%d_0 = randx%d[0] & %s[0];\n', i, i, x_bin);
        for j=1:m-2
          fprintf(fp, '\twire mux%d_%d;\n', i, j);
          fprintf(fp, '\tassign mux%d_%d = randx%d[%d] ? %s[%d] : mux%d_%d;\n',...
                  i, j, i, j, x_bin, j, i, j-1);
        end
        fprintf(fp, '\tassign x_stoch[%d] = randx%d[%d]? %s[%d]:mux%d_%d;\n\n',...
                i, i, m-1, x_bin, m-1, i, m-2);
    end
  end
  
  %binary to stochastic conversion for the coefficients
  switch(ConstantRNG)
    case 'SharedLFSR'
      fprintf(fp, '\twire [%d:0] randw;\n', m - 1);
      fprintf(fp, '\t%s rand_gen_w (\n', constRandModule);
	    fprintf(fp, '\t\t.seed (%d''d%d),\n', m, round(N * 2 / 3));
	    fprintf(fp, '\t\t.data (randw),\n');
	    fprintf(fp, '\t\t.enable (running),\n');
	    fprintf(fp, '\t\t.restart (init),\n');
	    fprintf(fp, '\t\t.clk (clk),\n');
	    fprintf(fp, '\t\t.reset (reset)\n');
	    fprintf(fp, '\t);\n\n');
      for i=0:degree
        fprintf(fp, '\twire [%d:0] randw%d;\n', m - 1, i);
        fprintf(fp, '\tassign randw%d = randw;\n\n', i);
      end
    case 'LFSR'
      for i=0:degree
        fprintf(fp, '\twire [%d:0] randw%d;\n', m - 1, i);
        fprintf(fp, '\t%s rand_gen_w_%d (\n', constRandModule, i);
	  	  fprintf(fp, '\t\t.seed (%d''d%d),\n', m,...
                round(N*(i+degree)/(degree*2+1)));
        fprintf(fp, '\t\t.data (randw%d),\n', i);
	  	  fprintf(fp, '\t\t.enable (running),\n');
	  	  fprintf(fp, '\t\t.restart (init),\n');
	  	  fprintf(fp, '\t\t.clk (clk),\n');
	  	  fprintf(fp, '\t\t.reset (reset)\n');
	  	  fprintf(fp, '\t);\n\n');
      end
    case {'Counter', 'ReverseCounter'}
      fprintf(fp, '\twire [%d:0] randw;\n', m - 1);
      fprintf(fp, '\t%s rand_gen_w (\n', constRandModule);
	    fprintf(fp, '\t\t.out (randw),\n');
	    fprintf(fp, '\t\t.enable (running),\n');
	    fprintf(fp, '\t\t.restart (init),\n');
	    fprintf(fp, '\t\t.clk (clk),\n');
	    fprintf(fp, '\t\t.reset (reset)\n');
	    fprintf(fp, '\t);\n\n');
      for i=0:degree
        fprintf(fp, '\twire [%d:0] randw%d;\n', m - 1, i);
        fprintf(fp, '\tassign randw%d = randw;\n\n', i);
      end
  end
  
  for i=0:degree
    if coeff(i+1) == 1
      fprintf(fp, '\tassign w_stoch[%d] = 1;\n\n', i);
    elseif coeff(i+1) == 0
      fprintf(fp, '\tassign w_stoch[%d] = 0;\n\n', i);
    else
      switch(ConstantSNG)
        case 'Comparator'
            fprintf(fp, '\tassign w_stoch[%d] = randw%d < w%d_bin;\n\n', i,...
                    i, i);
        case 'Majority'
          fprintf(fp, '\twire majorityw%d_0;\n', i);
          fprintf(fp, '\tassign majorityw%d_0 = randw%d[0] & w%d_bin[0];\n',...
                  i, i, i);
          for j=1:m-2
            fprintf(fp, '\twire majorityw%d_%d;\n', i, j);
            fprintf(fp, ['\tassign majorityw%d_%d = (randw%d[%d] & w%d_bin[',...
                         '%d]) | (randw%d[%d] & majorityw%d_%d) | (w%d_bin[%'...
                         'd] & majorityw%d_%d);\n'], i, j, i, j, i, j, i, j,...
                    i, j-1, i, j, i, j-1);
          end
          fprintf(fp, ['\tassign w_stoch[%d] = (randw%d[%d] & w%d_bin[%d]) ',...
                       '| (randw%d[%d] & majorityw%d_%d) | (w%d_bin[%d] & ma'...
                       'jorityw%d_%d);\n\n'], i, i, m-1, i, m-1, i, m-1, i,...
                  m-2, i, m-1, i, m-2);
        case 'WBG'
          and = sprintf('randw%d[%d]', i, m-1);
          for j=fliplr(1:m-1)
            fprintf(fp, '\twire wbgw%d_%d;\n', i, j);
            fprintf(fp, '\tassign wbgw%d_%d = %s & w%d_bin[%d];\n', i, j,...
                    and, i, j);
            and = sprintf('randw%d[%d] & ~%s', i, j-1, and);
          end
          fprintf(fp, '\tassign w_stoch[%d] = %s & w%d_bin[0]', i, and, i);
          for j=1:m-1
            fprintf(fp, ' | wbgw%d_%d', i, j);
          end
          fprintf(fp, ';\n\n');
        case 'Mux'
          fprintf(fp, '\twire muxw%d_0;\n', i);
          fprintf(fp, '\tassign muxw%d_0 = randw%d[0] & w%d_bin[0];\n', i, i,...
                  i);
          for j=1:m-2
            fprintf(fp, '\twire muxw%d_%d;\n', i, j);
            fprintf(fp, ['\tassign muxw%d_%d = randw%d[%d] ? w%d_bin[%d] : ',...
                         'muxw%d_%d;\n'], i, j, i, j, i, j, i, j-1);
          end
          fprintf(fp, ['\tassign w_stoch[%d] = randw%d[%d]? w%d_bin[%d]:mux',...
                       'w%d_%d;\n\n'], i, i, m-1, i, m-1, i, m-2);
      end
    end
  end
  
  %initialize the core ReSC module
	fprintf(fp, '\t%s ReSC (\n', SCModule);
	fprintf(fp, '\t\t.x (x_stoch),\n');
  if strcmp(ConstantSNG, 'HardWire')
    if strcmp(ConstantRNG, 'LFSR')
      for i=0:degree
        fprintf(fp, '\t\t.randw%d (randw%d),\n', i, i);
      end
    else
      fprintf(fp, '\t\t.randw (randw0),\n');
    end
  else
	  fprintf(fp, '\t\t.w (w_stoch),\n');
  end
	fprintf(fp, '\t\t.z (z_stoch)\n');
	fprintf(fp, '\t);\n\n');

  %create finite state machine for handling  stochastic to binary conversion
  %and handshaking with the client
	fprintf(fp, '\treg [%d:0] count; //count clock cycles\n', m - 1');
	fprintf(fp, '\twire [%d:0] neg_one;\n', m - 1);
	fprintf(fp, '\tassign neg_one = -1;\n\n');

  fprintf(fp, '\t//Finite state machine. States:\n');
  fprintf(fp, '\t//0: finished, in need of resetting\n');
  fprintf(fp, '\t//1: initialized, start counting when start signal falls\n');
  fprintf(fp, '\t//2: running\n');
	fprintf(fp, '\treg [1:0] cs; //current FSM state\n');
	fprintf(fp, '\treg [1:0] ns; //next FSM state\n');
	fprintf(fp, '\tassign init = cs == 1;\n');
	fprintf(fp, '\tassign running = cs == 2;\n\n');

	fprintf(fp, '\talways @(posedge clk or posedge reset) begin\n');
	fprintf(fp, '\t\tif (reset) cs <= 0;\n');
	fprintf(fp, '\t\telse begin\n');
  fprintf(fp, '\t\t\tcs <= ns;\n');
	fprintf(fp, '\t\t\tif (running) begin\n');
	fprintf(fp, '\t\t\t\tif (count == neg_one) done <= 1;\n');
	fprintf(fp, '\t\t\t\tcount <= count + 1;\n');
	fprintf(fp, '\t\t\t\tz_bin <= z_bin + z_stoch;\n');
	fprintf(fp, '\t\t\tend\n');
	fprintf(fp, '\t\tend\n');
	fprintf(fp, '\tend\n\n');

	fprintf(fp, '\talways @(*) begin\n');
	fprintf(fp, '\t\tcase (cs)\n');
	fprintf(fp, '\t\t\t0: if (start) ns = 1; else ns = 0;\n');
	fprintf(fp, '\t\t\t1: if (start) ns = 1; else ns = 2;\n');
	fprintf(fp, '\t\t\t2: if (done) ns = 0; else ns = 2;\n');
	fprintf(fp, '\t\t\tdefault ns = 0;\n');
	fprintf(fp, '\t\tendcase\n');
	fprintf(fp, '\tend\n\n');

	fprintf(fp, '\talways @(posedge init) begin\n');
	fprintf(fp, '\t\tcount <= 0;\n');
	fprintf(fp, '\t\tz_bin <= 0;\n');
	fprintf(fp, '\t\tdone <= 0;\n');
	fprintf(fp, '\tend\n');
  fprintf(fp, 'endmodule\n');
  fclose(fp);
end
