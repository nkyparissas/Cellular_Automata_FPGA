----------------------------------------------------------------------------------
-- TECHNICAL UNIVERSITY OF CRETE
-- NICK KYPARISSAS
-- MODULE: Multiplexer choosing between the commands arriving at the memory controller.
-- PROJECT NAME: A Framework for the Real-Time Execution of Cellular Automata on Reconfigurable Logic
-- Diploma Thesis Project 2019
----------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

entity DDR_CMD_MUX is
	Port (
		APP_ADDR_INIT : IN STD_LOGIC_VECTOR(26 DOWNTO 0);
		APP_CMD_INIT : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
		APP_EN_INIT : IN STD_LOGIC;
		APP_ADDR_WRITE : IN STD_LOGIC_VECTOR(26 DOWNTO 0);
		APP_CMD_WRITE : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
		APP_EN_WRITE : IN STD_LOGIC;
		APP_ADDR_GRAPHICS : IN STD_LOGIC_VECTOR(26 DOWNTO 0);
		APP_CMD_GRAPHICS : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
		APP_EN_GRAPHICS : IN STD_LOGIC;
		SEL : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
		APP_ADDR : OUT STD_LOGIC_VECTOR(26 DOWNTO 0);
		APP_CMD : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
		APP_EN : OUT STD_LOGIC
	);
end DDR_CMD_MUX;

architecture Behavioral of DDR_CMD_MUX is

BEGIN

APP_ADDR <= APP_ADDR_INIT WHEN SEL = "00" ELSE
			APP_ADDR_GRAPHICS WHEN SEL = "01" ELSE
			APP_ADDR_WRITE WHEN SEL = "10" ELSE
			(OTHERS => '0');

APP_CMD <= 	APP_CMD_INIT WHEN SEL = "00" ELSE
			APP_CMD_GRAPHICS WHEN SEL = "01" ELSE
			APP_CMD_WRITE WHEN SEL = "10" ELSE
			"001"; -- READ COMMAND

APP_EN <= 	APP_EN_INIT WHEN SEL = "00" ELSE
			APP_EN_GRAPHICS WHEN SEL = "01" ELSE
			APP_EN_WRITE WHEN SEL = "10" ELSE
			'0';

END BEHAVIORAL;