----------------------------------------------------------------------------------
-- TECHNICAL UNIVERSITY OF CRETE
-- NICK KYPARISSAS
-- MODULE: A FIFO accepting 4-bit values, sending out 128-bit values. Made out of 
-- Xilinx's FIFO modules. 
-- PROJECT NAME: A Framework for the Real-Time Execution of Cellular Automata on Reconfigurable Logic
-- Diploma Thesis Project 2019
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity FIFO_4_128 is
	Port ( 
		-- WRITE PORT
		din : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		wr_en : IN STD_LOGIC;
		-- READ PORT
		rd_en : IN STD_LOGIC;
		dout : OUT STD_LOGIC_VECTOR(127 DOWNTO 0);
		empty : OUT STD_LOGIC;
		------------
		rst : IN STD_LOGIC;
		wr_clk : IN STD_LOGIC;
		rd_clk : IN STD_LOGIC
	);
end FIFO_4_128;

architecture Behavioral of FIFO_4_128 is

	SIGNAL fifo_to_fifo_data : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0'); 
	SIGNAL fifo_1_empty, fifo_1_rd_en, fifo_1_valid_data, fifo_2_full : STD_LOGIC;
	
	COMPONENT FIFO_32_128 
	PORT (
		rst : IN STD_LOGIC;
		wr_clk : IN STD_LOGIC;
		rd_clk : IN STD_LOGIC;
		din : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
		wr_en : IN STD_LOGIC;
		rd_en : IN STD_LOGIC;
		dout : OUT STD_LOGIC_VECTOR(127 DOWNTO 0);
		full : OUT STD_LOGIC;
		empty : OUT STD_LOGIC
	);
	END COMPONENT;
	
	COMPONENT FIFO_4_32 
		PORT (
		clk : IN STD_LOGIC;
		rst : IN STD_LOGIC;
		din : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		wr_en : IN STD_LOGIC;
		rd_en : IN STD_LOGIC;
		dout : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
		full : OUT STD_LOGIC;
		empty : OUT STD_LOGIC;
		valid : OUT STD_LOGIC
		);
	END COMPONENT;

begin

	FIFO_1_4_32: FIFO_4_32 
		PORT MAP (
		clk => wr_clk,
		rst => rst,
		din => din,
		wr_en => wr_en,
		rd_en => fifo_1_rd_en,
		dout => fifo_to_fifo_data,
		--full : OUT STD_LOGIC;
		empty => fifo_1_empty,
		valid => fifo_1_valid_data
		);
	
	FIFO_2_32_128: FIFO_32_128 
	Port MAP(
		rst => rst,
		wr_clk => wr_clk,
		rd_clk => rd_clk,
		din => fifo_to_fifo_data,
		wr_en => fifo_1_valid_data,
		rd_en => rd_en,
		dout => dout,
		full => fifo_2_full,
		empty => empty   
		 );

	fifo_1_rd_en <= '1' WHEN fifo_1_empty = '0' AND fifo_2_full = '0' ELSE '0';
	
end Behavioral;
