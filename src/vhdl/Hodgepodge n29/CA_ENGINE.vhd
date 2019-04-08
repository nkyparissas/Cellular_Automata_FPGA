----------------------------------------------------------------------------------
-- TECHNICAL UNIVERSITY OF CRETE
-- NICK KYPARISSAS
-- MODULE: CA Engine implementing the "Hodgepodge Machine" rule
-- for n = 29.
-- PROJECT NAME: A Framework for the Real-Time Execution of Cellular Automata on Reconfigurable Logic
-- Diploma Thesis Project 2019
----------------------------------------------------------------------------------

-- YOU CANT USE THIS AS IS FOR OTHER RULES: EVERY TIME THE NEIGHBORHOOD SIZE CHANGES, 
-- THE ADDERS BINARY TREE MIGHT REQUIRE CHANGES AS WELL. 

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY CA_ENGINE IS
	GENERIC (
		G : INTEGER := 105;--100; -- 36
		K : INTEGER := 5;--3; -- 3/8 = 135/360
		CELL_SIZE : INTEGER := 8; -- HOW MANY BITS PER CELL, 8 BITS = UP TO 256 STATES
		NEIGHBORHOOD_SIZE : INTEGER := 29); 
		-- DEFAULT GENERIC VALUES FOR THE "HODGEPODGE MACHINE" CA RULE
		-- THIS MODULE'S GENERIC VARIABLES INHERIT THEIR VALUES FROM THE TOP LEVEL
	PORT  ( 
		CLK : IN STD_LOGIC;
		RST : IN STD_LOGIC;
		
		READ_EN : IN STD_LOGIC;
		DATA_IN : IN STD_LOGIC_VECTOR((NEIGHBORHOOD_SIZE*CELL_SIZE)-1 DOWNTO 0);
		
		DATA_OUT : OUT STD_LOGIC_VECTOR(CELL_SIZE-1 DOWNTO 0);
		DATA_OUT_VALID : OUT STD_LOGIC
		
	);
END CA_ENGINE;

ARCHITECTURE BEHAVIORAL OF CA_ENGINE IS

	-- PIPELINED NEIGHBORHOOD
	type NEIGHBORHOOD_ARRAY is array (NEIGHBORHOOD_SIZE-1 downto 0, NEIGHBORHOOD_SIZE-1 downto 0) of integer range 0 to 255; -- 256 STATES
	SIGNAL NEIGHBORHOOD_CELL, NEIGHBORHOOD_REPLICA : NEIGHBORHOOD_ARRAY := (OTHERS => (OTHERS => 0));

	-- EACH ARRAY CELL MUST BE LARGE ENOUGH FOR NEIGHBORHOOD_CELL*NEIGHBORHOOD_WEIGHT
	type CATEGORIZED_NEIGHBORHOOD_ARRAY is array (NEIGHBORHOOD_SIZE-1 downto 0, NEIGHBORHOOD_SIZE-1 downto 0) of integer range 0 to 1;
	SIGNAL INFECTED_CELL, ILL_CELL : CATEGORIZED_NEIGHBORHOOD_ARRAY := (OTHERS => (OTHERS => 0));

	-- YOU NEED TO ADJUST THIS SIGNAL ACCORDING TO THE DEPTH OF YOUR RULE'S PIPELINE 
	SIGNAL DATA_VALID_SIGNAL : STD_LOGIC_VECTOR( ((NEIGHBORHOOD_SIZE-1)/2)+12+36 DOWNTO 0) := (OTHERS => '0');

	-- CUSTOM RULE SIGNALS
	-- TREE OF SUMS FOR THE STATES SUM
	type SUM_LAYER_0_TYPE is array ((NEIGHBORHOOD_SIZE-1)/2 downto 0, NEIGHBORHOOD_SIZE-1 downto 0) of integer range 0 to 214455;
	SIGNAL SUM_LAYER_0 : SUM_LAYER_0_TYPE;
	type SUM_LAYER_1_TYPE is array ((NEIGHBORHOOD_SIZE-1)/4 downto 0, NEIGHBORHOOD_SIZE-1 downto 0) of integer range 0 to 214455;
	SIGNAL SUM_LAYER_1 : SUM_LAYER_1_TYPE;
	type SUM_LAYER_2_TYPE is array (3 downto 0, NEIGHBORHOOD_SIZE-1 downto 0) of integer range 0 to 214455;
	SIGNAL SUM_LAYER_2 : SUM_LAYER_2_TYPE;
	type SUM_LAYER_3_TYPE is array (1 downto 0, NEIGHBORHOOD_SIZE-1 downto 0) of integer range 0 to 214455;
	SIGNAL SUM_LAYER_3 : SUM_LAYER_3_TYPE; 
	type SUM_TYPE is array (NEIGHBORHOOD_SIZE-1 downto 0) of integer range 0 to 214455;
	SIGNAL SUM : SUM_TYPE;	
	type COLUMN_SUM_LAYER_0_TYPE is array ((NEIGHBORHOOD_SIZE-1)/2 downto 0) of integer range 0 to 214455;
	SIGNAL COLUMN_SUM_LAYER_0 : COLUMN_SUM_LAYER_0_TYPE;
	type COLUMN_SUM_LAYER_1_TYPE is array ((NEIGHBORHOOD_SIZE-1)/4 downto 0) of integer range 0 to 214455;
	SIGNAL COLUMN_SUM_LAYER_1 : COLUMN_SUM_LAYER_1_TYPE;
	type COLUMN_SUM_LAYER_2_TYPE is array (3 downto 0) of integer range 0 to 214455;
	SIGNAL COLUMN_SUM_LAYER_2 : COLUMN_SUM_LAYER_2_TYPE;
	type COLUMN_SUM_LAYER_3_TYPE is array (1 downto 0) of integer range 0 to 214455;
	SIGNAL COLUMN_SUM_LAYER_3 : COLUMN_SUM_LAYER_3_TYPE; 
	SIGNAL TOTAL_SUM : integer range 0 to 214455; 

	-- TREE OF SUMS FOR THE TOTAL NUMBER OF INFECTED CELLS
	type INFECTED_SUM_LAYER_0_TYPE is array ((NEIGHBORHOOD_SIZE-1)/2 downto 0, NEIGHBORHOOD_SIZE-1 downto 0) of integer range 0 to 1023;
	SIGNAL INFECTED_SUM_LAYER_0 : INFECTED_SUM_LAYER_0_TYPE;
	type INFECTED_SUM_LAYER_1_TYPE is array ((NEIGHBORHOOD_SIZE-1)/4 downto 0, NEIGHBORHOOD_SIZE-1 downto 0) of integer range 0 to 1023;
	SIGNAL INFECTED_SUM_LAYER_1 : INFECTED_SUM_LAYER_1_TYPE;
	type INFECTED_SUM_LAYER_2_TYPE is array (3 downto 0, NEIGHBORHOOD_SIZE-1 downto 0) of integer range 0 to 1023;
	SIGNAL INFECTED_SUM_LAYER_2 : INFECTED_SUM_LAYER_2_TYPE;
	type INFECTED_SUM_LAYER_3_TYPE is array (1 downto 0, NEIGHBORHOOD_SIZE-1 downto 0) of integer range 0 to 1023;
	SIGNAL INFECTED_SUM_LAYER_3 : INFECTED_SUM_LAYER_3_TYPE; 
	type INFECTED_SUM_TYPE is array (NEIGHBORHOOD_SIZE-1 downto 0) of integer range 0 to 1023;
	SIGNAL INFECTED_SUM : INFECTED_SUM_TYPE; 
	type INFECTED_COLUMN_SUM_LAYER_0_TYPE is array ((NEIGHBORHOOD_SIZE-1)/2 downto 0) of integer range 0 to 1023;
	SIGNAL INFECTED_COLUMN_SUM_LAYER_0 : INFECTED_COLUMN_SUM_LAYER_0_TYPE;
	type INFECTED_COLUMN_SUM_LAYER_1_TYPE is array ((NEIGHBORHOOD_SIZE-1)/4 downto 0) of integer range 0 to 1023;
	SIGNAL INFECTED_COLUMN_SUM_LAYER_1 : INFECTED_COLUMN_SUM_LAYER_1_TYPE;
	type INFECTED_COLUMN_SUM_LAYER_2_TYPE is array (3 downto 0) of integer range 0 to 1023;
	SIGNAL INFECTED_COLUMN_SUM_LAYER_2 : INFECTED_COLUMN_SUM_LAYER_2_TYPE;
	type INFECTED_COLUMN_SUM_LAYER_3_TYPE is array (1 downto 0) of integer range 0 to 1023;
	SIGNAL INFECTED_COLUMN_SUM_LAYER_3 : INFECTED_COLUMN_SUM_LAYER_3_TYPE; 

	TYPE CURRENT_CELL_PIPELINE is array (56 downto 0) of integer range 0 to 255;
	SIGNAL CURRENT_CELL : CURRENT_CELL_PIPELINE := (OTHERS => 0);
	
	-- DIVISION
	COMPONENT DIVIDER IS
	PORT (
		aclk : IN STD_LOGIC;
		s_axis_divisor_tvalid : IN STD_LOGIC;
		--s_axis_divisor_tready : OUT STD_LOGIC;
		s_axis_divisor_tdata : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
		s_axis_dividend_tvalid : IN STD_LOGIC;
		--s_axis_dividend_tready : OUT STD_LOGIC;
		s_axis_dividend_tdata : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
		m_axis_dout_tvalid : OUT STD_LOGIC;
		m_axis_dout_tdata : OUT STD_LOGIC_VECTOR(47 DOWNTO 0)
	);
	END COMPONENT;
	
	SIGNAL DIVIDEND_INPUT, DIVIDEND2_INPUT : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');
	SIGNAL DIVISOR_INPUT, DIVISOR2_INPUT : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0'); 
	
	SIGNAL DIVIDEND, DIVIDEND2 : integer range 0 to 214455; -- 18 bits
	SIGNAL DIVISOR, DIVISOR2 : integer range 0 to 1023; -- 10 bits
	
	TYPE DIVISION_RESULTS_PIPELINE is array (1 downto 0) of integer range 0 to 2147483647; --max int;
	SIGNAL NEW_INFECTED_CELL_STATE, INFECTED_CELLS_FACTOR : DIVISION_RESULTS_PIPELINE; -- Maximum number of states plus maximum g
	
	SIGNAL INFECTED_TOTAL_SUM : INTEGER range 0 to 1023; -- enough for 29x29
	
	SIGNAL DUMMY_SIG, DUMMY_SIG2 : STD_LOGIC_VECTOR(47 DOWNTO 0) := (OTHERS => '0');
	
BEGIN
	
	PROCESS 
	BEGIN
		
		WAIT UNTIL RISING_EDGE(CLK);	
		
		IF RST = '1' THEN
			DATA_VALID_SIGNAL <= (OTHERS => '0');
		END IF;
		
		-- PIPELINING NEIGHBORHOOD ----------------------------------
		FOR I IN NEIGHBORHOOD_SIZE-1 DOWNTO 1 LOOP
			FOR J IN NEIGHBORHOOD_SIZE-1 DOWNTO 0 LOOP
				NEIGHBORHOOD_CELL(I, J) <= NEIGHBORHOOD_CELL(I-1, J);
			END LOOP;
		END LOOP;
		
		FOR I IN NEIGHBORHOOD_SIZE-1 DOWNTO 0 LOOP
			NEIGHBORHOOD_CELL(0, I) <= TO_INTEGER(UNSIGNED(DATA_IN((I*CELL_SIZE)+CELL_SIZE-1 DOWNTO I*CELL_SIZE)));
		END LOOP;
		
		-- SETTING UP THE 3 DIFFERENT ADDER TREES
		FOR I IN NEIGHBORHOOD_SIZE-1 DOWNTO 0 LOOP
			FOR J IN NEIGHBORHOOD_SIZE-1 DOWNTO 0 LOOP
				NEIGHBORHOOD_REPLICA(I, J) <= NEIGHBORHOOD_CELL(I, J);
				IF NEIGHBORHOOD_CELL(I, J) > 0  THEN 
					INFECTED_CELL(I, J) <= 1;
				ELSE
					INFECTED_CELL(I, J) <= 0;
				END IF;
			END LOOP;
		END LOOP;
		
		-- EXCLUDING CURRENT CELL
		INFECTED_CELL(14, 14) <= 0;
		
		FOR I IN 52 DOWNTO 1 LOOP
			CURRENT_CELL(I) <= CURRENT_CELL(I-1);
		END LOOP;
		CURRENT_CELL(0) <= NEIGHBORHOOD_CELL(14, 14);
		------------------------------------------------------------
		
		-- BINARY ADDER TREE FOR TOTAL STATES SUM ------------------
		FOR J IN NEIGHBORHOOD_SIZE-1 DOWNTO 0 LOOP
			-- LOOP FOR EACH COLUMN:
			FOR I IN (NEIGHBORHOOD_SIZE-1)/2 DOWNTO 1 LOOP
				SUM_LAYER_0(I, J) <= NEIGHBORHOOD_REPLICA(2*I, J) + NEIGHBORHOOD_REPLICA(2*I-1, J);
			END LOOP;			
			SUM_LAYER_0(0, J) <= NEIGHBORHOOD_REPLICA(0, J); 
			
			FOR I IN 7 DOWNTO 1 LOOP 
				SUM_LAYER_1(I, J) <= SUM_LAYER_0(2*I, J) + SUM_LAYER_0(2*I-1, J);
			END LOOP;			
			SUM_LAYER_1(0, J) <= SUM_LAYER_0(0, J);
			
			SUM_LAYER_2(3, J) <= SUM_LAYER_1(6, J) + SUM_LAYER_1(7, J);
			SUM_LAYER_2(2, J) <= SUM_LAYER_1(4, J) + SUM_LAYER_1(5, J);
			SUM_LAYER_2(1, J) <= SUM_LAYER_1(2, J) + SUM_LAYER_1(3, J);
			SUM_LAYER_2(0, J) <= SUM_LAYER_1(0, J) + SUM_LAYER_1(1, J);
			
			SUM_LAYER_3(1, J) <= SUM_LAYER_2(0, J) + SUM_LAYER_2(1, J);
			SUM_LAYER_3(0, J) <= SUM_LAYER_2(2, J) + SUM_LAYER_2(3, J);
			
			SUM(J) <= SUM_LAYER_3(1, J) + SUM_LAYER_3(0, J);
		END LOOP;
		
		-- SUM(J) CONTAINS THE SUM OF COLUMN J
		-- ADDER TREE FOR THE SUM OF EACH COLUMN:
		FOR I IN (NEIGHBORHOOD_SIZE-1)/2 DOWNTO 1 LOOP 
			COLUMN_SUM_LAYER_0(I) <= SUM(2*I) + SUM(2*I-1);
		END LOOP;
		COLUMN_SUM_LAYER_0(0) <= SUM(0); 
		
		FOR I IN 7 DOWNTO 1 LOOP 
			COLUMN_SUM_LAYER_1(I) <= COLUMN_SUM_LAYER_0(2*I) + COLUMN_SUM_LAYER_0(2*I-1);
		END LOOP;
		COLUMN_SUM_LAYER_1(0) <= COLUMN_SUM_LAYER_0(0);
		
		COLUMN_SUM_LAYER_2(3) <= COLUMN_SUM_LAYER_1(6) + COLUMN_SUM_LAYER_1(7);
		COLUMN_SUM_LAYER_2(2) <= COLUMN_SUM_LAYER_1(4) + COLUMN_SUM_LAYER_1(5);
		COLUMN_SUM_LAYER_2(1) <= COLUMN_SUM_LAYER_1(2) + COLUMN_SUM_LAYER_1(3);
		COLUMN_SUM_LAYER_2(0) <= COLUMN_SUM_LAYER_1(0) + COLUMN_SUM_LAYER_1(1);
		
		COLUMN_SUM_LAYER_3(1) <= COLUMN_SUM_LAYER_2(0) + COLUMN_SUM_LAYER_2(1);
		COLUMN_SUM_LAYER_3(0) <= COLUMN_SUM_LAYER_2(2) + COLUMN_SUM_LAYER_2(3);
		
		TOTAL_SUM <= COLUMN_SUM_LAYER_3(1) + COLUMN_SUM_LAYER_3(0);
		------------------------------------------------------------
		
		-- BINARY ADDER TREE FOR TOTAL INFECTED CELLS SUM ------------------
		FOR J IN NEIGHBORHOOD_SIZE-1 DOWNTO 0 LOOP
			-- LOOP FOR EACH COLUMN:
			FOR I IN (NEIGHBORHOOD_SIZE-1)/2 DOWNTO 1 LOOP 
				INFECTED_SUM_LAYER_0(I, J) <= INFECTED_CELL(2*I, J) + INFECTED_CELL(2*I-1, J);
			END LOOP;		
			INFECTED_SUM_LAYER_0(0, J) <= INFECTED_CELL(0, J); 
			
			FOR I IN 7 DOWNTO 1 LOOP 
				INFECTED_SUM_LAYER_1(I, J) <= INFECTED_SUM_LAYER_0(2*I, J) + INFECTED_SUM_LAYER_0(2*I-1, J);
			END LOOP;
			INFECTED_SUM_LAYER_1(0, J) <= INFECTED_SUM_LAYER_0(0, J);
			
			INFECTED_SUM_LAYER_2(3, J) <= INFECTED_SUM_LAYER_1(6, J) + INFECTED_SUM_LAYER_1(7, J);
			INFECTED_SUM_LAYER_2(2, J) <= INFECTED_SUM_LAYER_1(4, J) + INFECTED_SUM_LAYER_1(5, J);
			INFECTED_SUM_LAYER_2(1, J) <= INFECTED_SUM_LAYER_1(2, J) + INFECTED_SUM_LAYER_1(3, J);
			INFECTED_SUM_LAYER_2(0, J) <= INFECTED_SUM_LAYER_1(0, J) + INFECTED_SUM_LAYER_1(1, J);

			INFECTED_SUM_LAYER_3(1, J) <= INFECTED_SUM_LAYER_2(0, J) + INFECTED_SUM_LAYER_2(1, J);
			INFECTED_SUM_LAYER_3(0, J) <= INFECTED_SUM_LAYER_2(2, J) + INFECTED_SUM_LAYER_2(3, J);
			
			INFECTED_SUM(J) <= INFECTED_SUM_LAYER_3(1, J) + INFECTED_SUM_LAYER_3(0, J);
		END LOOP;
		
		-- INFECTED_SUM(J) CONTAINS THE SUM OF COLUMN J
		-- ADDER TREE FOR THE SUM OF EACH COLUMN:
		FOR I IN (NEIGHBORHOOD_SIZE-1)/2 DOWNTO 1 LOOP 
			INFECTED_COLUMN_SUM_LAYER_0(I) <= INFECTED_SUM(2*I) + INFECTED_SUM(2*I-1);
		END LOOP;	
		INFECTED_COLUMN_SUM_LAYER_0(0) <= INFECTED_SUM(0); 
		
		FOR I IN 7 DOWNTO 1 LOOP 
			INFECTED_COLUMN_SUM_LAYER_1(I) <= INFECTED_COLUMN_SUM_LAYER_0(2*I) + INFECTED_COLUMN_SUM_LAYER_0(2*I-1);
		END LOOP;
		INFECTED_COLUMN_SUM_LAYER_1(0) <= INFECTED_COLUMN_SUM_LAYER_0(0);
		
		INFECTED_COLUMN_SUM_LAYER_2(3) <= INFECTED_COLUMN_SUM_LAYER_1(6) + INFECTED_COLUMN_SUM_LAYER_1(7);
		INFECTED_COLUMN_SUM_LAYER_2(2) <= INFECTED_COLUMN_SUM_LAYER_1(4) + INFECTED_COLUMN_SUM_LAYER_1(5);
		INFECTED_COLUMN_SUM_LAYER_2(1) <= INFECTED_COLUMN_SUM_LAYER_1(2) + INFECTED_COLUMN_SUM_LAYER_1(3);
		INFECTED_COLUMN_SUM_LAYER_2(0) <= INFECTED_COLUMN_SUM_LAYER_1(0) + INFECTED_COLUMN_SUM_LAYER_1(1);

		INFECTED_COLUMN_SUM_LAYER_3(1) <= INFECTED_COLUMN_SUM_LAYER_2(0) + INFECTED_COLUMN_SUM_LAYER_2(1);
		INFECTED_COLUMN_SUM_LAYER_3(0) <= INFECTED_COLUMN_SUM_LAYER_2(2) + INFECTED_COLUMN_SUM_LAYER_2(3);
		
		INFECTED_TOTAL_SUM <= INFECTED_COLUMN_SUM_LAYER_3(1) + INFECTED_COLUMN_SUM_LAYER_3(0);
		
		-- DIVISION SIGNALS 
		-- TOTAL SUM / ( INFECTED_TOTAL_SUM + 1) 
		DIVIDEND <= TOTAL_SUM;
		DIVISOR <= INFECTED_TOTAL_SUM + 1;
		
		-- INFECTED INFECTED_TOTAL_SUM / K
		DIVIDEND2 <= INFECTED_TOTAL_SUM;
		DIVISOR2 <= K; 
		
		-- END OF DIVISION SIGNALS --------------
		
		NEW_INFECTED_CELL_STATE(1) <= NEW_INFECTED_CELL_STATE(0)+G;
		INFECTED_CELLS_FACTOR(1) <= INFECTED_CELLS_FACTOR(0);
		
		-- STATE TRANSITION RULE -----------------------------------
		IF CURRENT_CELL(46) = 0 then
			IF INFECTED_CELLS_FACTOR(1) > 255 THEN
				DATA_OUT <= (OTHERS => '1'); -- 255
			ELSE
				DATA_OUT <= STD_LOGIC_VECTOR(TO_UNSIGNED(INFECTED_CELLS_FACTOR(1), 8));
			END IF;
		ELSIF CURRENT_CELL(46) = 255 THEN 
			DATA_OUT <= (OTHERS => '0');
		ELSE
			IF NEW_INFECTED_CELL_STATE(1) > 255 THEN -- + G 
				DATA_OUT <= (OTHERS => '1'); -- 255
			ELSE 
				DATA_OUT <= STD_LOGIC_VECTOR(TO_UNSIGNED(NEW_INFECTED_CELL_STATE(1), 8));
			END IF;
		END IF;
		-- END OF STATE TRANSITION RULE ----------------------------
		
		-- DATA_VALID DENOTES THE VALID CELL VALUES TO BE WRITTEN BACK TO THE EXTERNAL MEM
		FOR I IN ((NEIGHBORHOOD_SIZE-1)/2)+12+36 DOWNTO 1 LOOP
			DATA_VALID_SIGNAL(I) <= DATA_VALID_SIGNAL(I-1);
		END LOOP;
		DATA_VALID_SIGNAL(0) <= READ_EN;		
		
	END PROCESS;
		
	DATA_OUT_VALID <= DATA_VALID_SIGNAL(((NEIGHBORHOOD_SIZE-1)/2)+12+36);		
		------------------------------------------------------------
		
	-- DIVISION ------------------------------
	-- 20 CYCLES IN TOTAL: 19 FOR THE DIVIDER + 1 FOR THE ADDITION (INFECTED_TOTAL_SUM + 1;) 
	DIVIDEND_INPUT <= STD_LOGIC_VECTOR(TO_UNSIGNED(DIVIDEND, 32)); -- 18 BITS
	DIVISOR_INPUT <= STD_LOGIC_VECTOR(TO_UNSIGNED(DIVISOR, 16)); -- 10 BITS
	
	DIVISION: DIVIDER
	PORT MAP(
		aclk => CLK,
		s_axis_divisor_tvalid => '1', 
		s_axis_divisor_tdata => DIVISOR_INPUT,
		s_axis_dividend_tvalid => '1',
		s_axis_dividend_tdata => DIVIDEND_INPUT,
		--m_axis_dout_tvalid : OUT STD_LOGIC;
		m_axis_dout_tdata => DUMMY_SIG
	);
		
	NEW_INFECTED_CELL_STATE(0) <= TO_INTEGER(UNSIGNED(DUMMY_SIG(47 DOWNTO 16)));
	
	-- END OF DIVISION------------------------
	
	-- DIVISION NO 2 -------------------------
	-- 20 CYCLES IN TOTAL: 19 FOR THE DIVIDER + 1 FOR THE ADDITION (INFECTED_TOTAL_SUM + 1;) 
	DIVIDEND2_INPUT <= STD_LOGIC_VECTOR(TO_UNSIGNED(DIVIDEND2, 32)); -- 18 BITS
	DIVISOR2_INPUT <= STD_LOGIC_VECTOR(TO_UNSIGNED(DIVISOR2, 16)); -- 10 BITS
	
	DIVISION2: DIVIDER
	PORT MAP(
		aclk => CLK,
		s_axis_divisor_tvalid => '1', 
		s_axis_divisor_tdata => DIVISOR2_INPUT,
		s_axis_dividend_tvalid => '1',
		s_axis_dividend_tdata => DIVIDEND2_INPUT,
		--m_axis_dout_tvalid : OUT STD_LOGIC;
		m_axis_dout_tdata => DUMMY_SIG2
	);
		
	INFECTED_CELLS_FACTOR(0) <= TO_INTEGER(UNSIGNED(DUMMY_SIG2(47 DOWNTO 16)));
	
	-- END OF DIVISION------------------------
	
END BEHAVIORAL;
	
