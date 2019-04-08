----------------------------------------------------------------------------------
-- TECHNICAL UNIVERSITY OF CRETE
-- NICK KYPARISSAS
-- MODULE: Recirculation MUX synchronizer
-- PROJECT NAME: A Framework for the Real-Time Execution of Cellular Automata on Reconfigurable Logic
-- Diploma Thesis Project 2019
----------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY SYNCHRONIZER IS
	GENERIC (
		GRID_Y : INTEGER := 1080;
		NEIGHBORHOOD_SIZE : INTEGER := 7); 
	PORT (
		CLK_RX : IN STD_LOGIC;
		RST : IN STD_LOGIC;
		--
		CONTROL : IN STD_LOGIC := '0';
		DATA_IN_1 : IN INTEGER RANGE 0 TO GRID_Y;
		DATA_OUT_1 : OUT INTEGER RANGE 0 TO GRID_Y := 0;
		DATA_IN_2 : IN INTEGER RANGE 0 TO NEIGHBORHOOD_SIZE;
		DATA_OUT_2 : OUT INTEGER RANGE 0 TO NEIGHBORHOOD_SIZE := 0
	);
END SYNCHRONIZER;

ARCHITECTURE BEHAVIORAL OF SYNCHRONIZER IS
	
	SIGNAL CONTROL_SIGNAL : STD_LOGIC_VECTOR(2 DOWNTO 0) := (OTHERS  => '0');
	
BEGIN
	
	WRITE: PROCESS
	BEGIN
		
		WAIT UNTIL RISING_EDGE(CLK_RX);	
		
		IF RST = '1' THEN
			CONTROL_SIGNAL <= (OTHERS  => '0');
			DATA_OUT_1 <= 0;
			DATA_OUT_2 <= 0;
		ELSE
			CONTROL_SIGNAL(2) <= CONTROL_SIGNAL(1);
			CONTROL_SIGNAL(1) <= CONTROL_SIGNAL(0);
			CONTROL_SIGNAL(0) <= CONTROL;
			
			IF (CONTROL_SIGNAL(1) XOR CONTROL_SIGNAL(2)) = '1' THEN
				DATA_OUT_1 <= DATA_IN_1;
				DATA_OUT_2 <= DATA_IN_2;
			END IF;
					
		END IF;
		
	END PROCESS;
	
END BEHAVIORAL;