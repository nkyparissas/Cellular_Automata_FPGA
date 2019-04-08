----------------------------------------------------------------------------------
-- TECHNICAL UNIVERSITY OF CRETE
-- NICK KYPARISSAS
-- MODULE: Multiplexer choosing between the data arriving to the 
-- memory controller in order to be written.
-- PROJECT NAME: A Framework for the Real-Time Execution of Cellular 
-- Automata on Reconfigurable Logic
-- Diploma Thesis Project 2019
----------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

entity DDR_WRITE_MUX is
	Port (
		APP_WDF_DATA_INIT : IN STD_LOGIC_VECTOR(127 DOWNTO 0);
		APP_WDF_END_INIT : IN STD_LOGIC;
		APP_WDF_WREN_INIT : IN STD_LOGIC;
		APP_WDF_DATA_WRITE : IN STD_LOGIC_VECTOR(127 DOWNTO 0);
		APP_WDF_END_WRITE : IN STD_LOGIC;
		APP_WDF_WREN_WRITE : IN STD_LOGIC;
		SEL : IN STD_LOGIC;
		APP_WDF_DATA : OUT STD_LOGIC_VECTOR(127 DOWNTO 0);
		APP_WDF_END : OUT STD_LOGIC;
		APP_WDF_WREN : OUT STD_LOGIC
	);
end DDR_WRITE_MUX;

architecture Behavioral of DDR_WRITE_MUX is

BEGIN

APP_WDF_DATA <= APP_WDF_DATA_INIT WHEN SEL = '0' ELSE
				APP_WDF_DATA_WRITE;
				
APP_WDF_END <= APP_WDF_END_INIT WHEN SEL = '0' ELSE
				APP_WDF_END_WRITE;
			
APP_WDF_WREN <= APP_WDF_WREN_INIT WHEN SEL = '0' ELSE
				APP_WDF_WREN_WRITE;

END BEHAVIORAL;