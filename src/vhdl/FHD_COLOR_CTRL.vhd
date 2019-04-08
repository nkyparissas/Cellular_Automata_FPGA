----------------------------------------------------------------------------------
-- TECHNICAL UNIVERSITY OF CRETE
-- NICK KYPARISSAS
-- MODULE: Color palettes supported by our system's graphics.
-- PROJECT NAME: A Framework for the Real-Time Execution of Cellular Automata on Reconfigurable Logic
-- Diploma Thesis Project 2019
----------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY FHD_COLOR_CTRL IS
	GENERIC (
		COLOR_BITS : INTEGER := 4; 
		PALETTE : STRING  := "GRADIENT" 
		-- VALID VALUES: "WINDOWS" AND "GRADIENT" 
		-- applicable only to 4-bit cell rules
	); 
	PORT ( 
		RST		 : IN STD_LOGIC;
		CLK		 : IN STD_LOGIC; -- @ 148.5 MHZ
		HCOUNT	  : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
		VCOUNT	 : IN STD_LOGIC_VECTOR(10 DOWNTO 0);
		MEM_DATA	: IN STD_LOGIC_VECTOR(127 DOWNTO 0);
		MEM_EN		: OUT STD_LOGIC;
		RED		 : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
		GREEN	 : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
		BLUE		: OUT STD_LOGIC_VECTOR(3 DOWNTO 0)
	);
END FHD_COLOR_CTRL;

ARCHITECTURE BEHAVIORAL OF FHD_COLOR_CTRL IS
	
	SIGNAL COUNTER_FOR_4B : UNSIGNED(4 DOWNTO 0) := (OTHERS => '0'); 
	SIGNAL COUNTER_FOR_8B : UNSIGNED(3 DOWNTO 0) := (OTHERS => '0'); 
	SIGNAL COLOR   : STD_LOGIC_VECTOR(COLOR_BITS-1 DOWNTO 0) := (OTHERS => '0');
	
BEGIN
	
	COLOR_4_BIT_GRADIENT: IF (COLOR_BITS = 4 AND PALETTE = "GRADIENT") GENERATE 
		PROCESS 
			BEGIN
			
			WAIT UNTIL CLK'EVENT AND CLK = '1';
			
			IF (RST = '1') THEN 
				MEM_EN <= '0';
				COUNTER_FOR_4B <= (OTHERS => '0');
				RED <= "0000";
				GREEN <= "0000";
				BLUE <= "0000";
			ELSE
				
				IF (UNSIGNED(HCOUNT) < 1920 AND UNSIGNED(VCOUNT) < 1080) THEN --  IF
					IF (COUNTER_FOR_4B = 30 AND UNSIGNED(HCOUNT) < 1918) THEN
						MEM_EN <= '1';
					ELSE
						MEM_EN <= '0';
					END IF;
					COUNTER_FOR_4B <= COUNTER_FOR_4B + 1;
					RED <= COLOR;
					GREEN <= COLOR;
					BLUE <= COLOR; 
				ELSIF (UNSIGNED(HCOUNT) = 2199 AND UNSIGNED(VCOUNT) < 1079) THEN
						MEM_EN <= '1';
						COUNTER_FOR_4B <= (OTHERS => '0');
						RED <= "0000";
						GREEN <= "0000";
						BLUE <= "0000";
				ELSIF (UNSIGNED(HCOUNT) = 2199 AND UNSIGNED(VCOUNT) = 1125) THEN -- new frame
						MEM_EN <= '1';
						COUNTER_FOR_4B <= (OTHERS => '0');
						RED <= "0000";
						GREEN <= "0000";
						BLUE <= "0000";
				ELSE -- NOT NEEDED - USEFUL WHEN MANUALLY ALIGNING THE SCREEN
						RED <= "0000";
						GREEN <= "0000";
						BLUE <= "0000";
						MEM_EN <= '0';
				END IF;	
			END IF;
		END PROCESS;
		
		COLOR <= MEM_DATA(((TO_INTEGER(COUNTER_FOR_4B)+1)*COLOR_BITS)-1 DOWNTO TO_INTEGER(COUNTER_FOR_4B)*COLOR_BITS);
	END GENERATE;
	
	COLOR_4_BIT_WINDOWS: IF (COLOR_BITS = 4 AND PALETTE = "WINDOWS") GENERATE 
		PROCESS 
			BEGIN
			
			WAIT UNTIL CLK'EVENT AND CLK = '1';
			
			IF (RST = '1') THEN 
				MEM_EN <= '0';
				COUNTER_FOR_4B <= (OTHERS => '0');
				RED <= "0000";
				GREEN <= "0000";
				BLUE <= "0000";
			ELSE
				
				IF (UNSIGNED(HCOUNT) < 1920 AND UNSIGNED(VCOUNT) < 1080) THEN --  IF
					IF (COUNTER_FOR_4B = 30 AND UNSIGNED(HCOUNT) < 1918) THEN
						MEM_EN <= '1';
					ELSE
						MEM_EN <= '0';
					END IF;
					COUNTER_FOR_4B <= COUNTER_FOR_4B + 1;
					-- MICROSOFT WINDOWS DEFAULT 16-COLOR PALETTE
					-- YOU CAN CHANGE THIS TO YOUR LIKIKNG
					IF COLOR = "0000" THEN -- BLACK
						RED <= "0000";
						GREEN <= "0000";
						BLUE <= "0000";
					ELSIF COLOR = "0001" THEN -- MAROON
						RED <= "1011";
						GREEN <= "0000";
						BLUE <= "0000";
					ELSIF COLOR = "0010" THEN -- GREEN
						RED <= "0000";
						GREEN <= "1011";
						BLUE <= "0000";
					ELSIF COLOR = "0011" THEN -- OLIVE
						RED <= "1011";
						GREEN <= "0110";
						BLUE <= "0000";
					ELSIF COLOR = "0100" THEN -- NAVY
						RED <= "0000";
						GREEN <= "0000";
						BLUE <= "1011";
					ELSIF COLOR = "0101" THEN -- PURPLE
						RED <= "1011";
						GREEN <= "0000";
						BLUE <= "1011";
					ELSIF COLOR = "0110" THEN -- TEAL
						RED <= "0000";
						GREEN <= "1011";
						BLUE <= "1011";
					ELSIF COLOR = "0111" THEN -- SILVER
						RED <= "1011";
						GREEN <= "1011";
						BLUE <= "1011";
					ELSIF COLOR = "1000" THEN -- GRAY
						RED <= "0110";
						GREEN <= "0110";
						BLUE <= "0110";
					ELSIF COLOR = "1001" THEN -- RED
						RED <= "1111";
						GREEN <= "0010";
						BLUE <= "0010";
					ELSIF COLOR = "1010" THEN -- LIME
						RED <= "0110";
						GREEN <= "1111";
						BLUE <= "0110";
					ELSIF COLOR = "1011" THEN -- YELLOW
						RED <= "1111";
						GREEN <= "1111";
						BLUE <= "0010";
					ELSIF COLOR = "1100" THEN -- BLUE
						RED <= "0010";
						GREEN <= "0010";
						BLUE <= "1111";
					ELSIF COLOR = "1101" THEN -- FUCHSIA
						RED <= "1111";
						GREEN <= "0110";
						BLUE <= "1111";
					ELSIF COLOR = "1110" THEN -- AQUA
						RED <= "0110";
						GREEN <= "1111";
						BLUE <= "1111";
					ELSIF COLOR = "1111" THEN -- WHITE
						RED <= "1111";
						GREEN <= "1111";
						BLUE <= "1111";
					END IF;
				ELSIF (UNSIGNED(HCOUNT) = 2199 AND UNSIGNED(VCOUNT) < 1079) THEN
						MEM_EN <= '1';
						COUNTER_FOR_4B <= (OTHERS => '0');
						RED <= "0000";
						GREEN <= "0000";
						BLUE <= "0000";
				ELSIF (UNSIGNED(HCOUNT) = 2199 AND UNSIGNED(VCOUNT) = 1125) THEN -- new frame
						MEM_EN <= '1';
						COUNTER_FOR_4B <= (OTHERS => '0');
						RED <= "0000";
						GREEN <= "0000";
						BLUE <= "0000";
				ELSE -- NOT NEEDED - USEFUL WHEN MANUALLY ALIGNING THE SCREEN
						RED <= "0000";
						GREEN <= "0000";
						BLUE <= "0000";
						MEM_EN <= '0';
				END IF;	
			END IF;
		END PROCESS;
		
		COLOR <= MEM_DATA(((TO_INTEGER(COUNTER_FOR_4B)+1)*COLOR_BITS)-1 DOWNTO TO_INTEGER(COUNTER_FOR_4B)*COLOR_BITS);
	END GENERATE;
	
	COLOR_8_BIT: IF (COLOR_BITS = 8) GENERATE
		PROCESS 
			BEGIN
			
			WAIT UNTIL CLK'EVENT AND CLK = '1';
			
			IF (RST = '1') THEN 
				MEM_EN <= '0';
				COUNTER_FOR_8B <= (OTHERS => '0');
				RED <= "0000";
				GREEN <= "0000";
				BLUE <= "0000";
			ELSE
				IF (UNSIGNED(HCOUNT) < 1920 AND UNSIGNED(VCOUNT) < 1080) THEN --  
					IF (COUNTER_FOR_8B = 14 AND UNSIGNED(HCOUNT) < 1910) THEN
						MEM_EN <= '1';
					ELSE
						MEM_EN <= '0';
					END IF;
					COUNTER_FOR_8B <= COUNTER_FOR_8B + 1;
					-- BLACK-RED-WHITE GRADIENT
					IF COLOR(7 DOWNTO 4) = "0000" THEN
						RED <= COLOR(3 DOWNTO 0);
						GREEN <= "0000";
						BLUE <= "0000";
					ELSE
						RED <= "1111";
						GREEN <= COLOR(7 DOWNTO 4);
						BLUE <= COLOR(7 DOWNTO 4);
					END IF;
				ELSIF (UNSIGNED(HCOUNT) = 2199 AND UNSIGNED(VCOUNT) < 1079) THEN
						MEM_EN <= '1';
						COUNTER_FOR_8B <= (OTHERS => '0');
						RED <= "0000";
						GREEN <= "0000";
						BLUE <= "0000";
				ELSIF (UNSIGNED(HCOUNT) = 2199 AND UNSIGNED(VCOUNT) = 1125) THEN -- new frame
						MEM_EN <= '1';
						COUNTER_FOR_8B <= (OTHERS => '0');
						RED <= "0000";
						GREEN <= "0000";
						BLUE <= "0000";
				ELSE -- NOT NEEDED - USEFUL WHEN MANUALLY ALIGNING THE SCREEN
						RED <= "0000";
						GREEN <= "0000";
						BLUE <= "0000";
						MEM_EN <= '0';
				END IF;	
			END IF;
		END PROCESS;
		
		COLOR <= MEM_DATA(((TO_INTEGER(COUNTER_FOR_8B)+1)*COLOR_BITS)-1 DOWNTO TO_INTEGER(COUNTER_FOR_8B)*COLOR_BITS);
	END GENERATE;
	
END BEHAVIORAL;