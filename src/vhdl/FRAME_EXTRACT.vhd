----------------------------------------------------------------------------------
-- TECHNICAL UNIVERSITY OF CRETE
-- NICK KYPARISSAS
-- MODULE: UART TX sending out a frame of the autoamton's grid.  
-- PROJECT NAME: A Framework for the Real-Time Execution of Cellular Automata on Reconfigurable Logic
-- Diploma Thesis Project 2019
----------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY FRAME_EXTRACT IS
	GENERIC (
		CELL_SIZE	: INTEGER := 8;
		BURST_SIZE : INTEGER := 128;
		GRID_Y : INTEGER := 1080;
		NEIGHBORHOOD_SIZE : INTEGER := 29;
		GRID_TYPE : STRING  := "TOROIDAL"; 
		-- VALID VALUES: "RECTANGULAR", "CYLINDRICAL" AND "TOROIDAL"
		NUMBER_OF_BURSTS_PER_LINE : INTEGER := 120 -- GRID_X * CELL_SIZE / BURST_SIZE;
		); 
	PORT (
		UI_CLK : IN STD_LOGIC; -- SYSTEM CLOCK
		CLK : IN STD_LOGIC;
		--
		APP_WDF_WREN : IN STD_LOGIC;
		WRITE_BACK_COLUMN : IN INTEGER RANGE 0 TO NUMBER_OF_BURSTS_PER_LINE-1;
		WRITE_BACK_ROW : IN INTEGER RANGE 0 TO GRID_Y-1;
		--
		SIM_ENDED : IN STD_LOGIC;
		END_OF_TRANSMISSION : OUT STD_LOGIC := '0';
		DATA_IN : IN STD_LOGIC_VECTOR(BURST_SIZE-1 DOWNTO 0);
		UART_TX_DATA_SEND : OUT STD_LOGIC := '0';
		UART_TX_DATA : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		UART_TX_BUSY : IN STD_LOGIC
		); 
END FRAME_EXTRACT;

ARCHITECTURE BEHAVIORAL OF FRAME_EXTRACT IS
	
	-- TOROIDAL GRID: GRID_X x GRID_Y cells
	-- RECT OR CYLINDR GRID: GRID_X x (GRID_Y-(NEIGHBORHOOD_SIZE-1)) cells
	function init return INTEGER is
	begin
		IF (GRID_TYPE = "TOROIDAL") THEN
			return 0;
		ELSE
			return (NEIGHBORHOOD_SIZE-1)/2;
		END IF;
	end function init;

	SIGNAL UART_TX_DATA_SEND_SIG, END_OF_TRANSMISSION_SIG : STD_LOGIC := '0';
	SIGNAL BURST_SENT : STD_LOGIC := '0';
	
	TYPE SIG_ARRAY IS ARRAY (31 DOWNTO 0) OF STD_LOGIC;
	SIGNAL BURST_LOADED : SIG_ARRAY := (OTHERS => '0');
	
	SIGNAL BURST_TO_BE_SENT : STD_LOGIC_VECTOR(BURST_SIZE-1 DOWNTO 0);
	
	TYPE BURST_ROW_TYPE IS ARRAY (NUMBER_OF_BURSTS_PER_LINE-1 DOWNTO 0) OF STD_LOGIC_VECTOR(BURST_SIZE-1 DOWNTO 0);
	SIGNAL BURSTS_TO_BE_SENT : BURST_ROW_TYPE;  
	
	SIGNAL I : INTEGER RANGE 0 TO 31 := 0;
	
	SIGNAL CURRENT_ROW_TO_BE_SENT : INTEGER RANGE 0 TO GRID_Y-1 := init; 
	SIGNAL BURST_COUNTER : INTEGER RANGE 0 TO NUMBER_OF_BURSTS_PER_LINE-1 := 0;
	SIGNAL DELAY_COUNTER: INTEGER RANGE 0 TO 10000000 := 0; 
	-- LARGER THAN THE NUMBER OF BURSTS: NUMBER_OF_BURSTS_PER_LINE SO THAT IT STORES THE FIRST BURST THAT LANDS, NO MATTER WHICH ONE IT WAS.
	
	TYPE STATE IS (SMALL_DELAY, FILL_THE_BUFFER, SEND_NEXT_BURST, SYNCH_1, SYNCH_2, WAIT_FOR_BURST_TRANSMISSION, CHECK_IF_LAST_BURST_IN_BUFFER, CHECK_IF_LAST_ROW);
	SIGNAL FSM_STATE : STATE := SMALL_DELAY;
	
	constant CURRENT_ROW_TO_BE_SENT_INIT : INTEGER := init;
	
BEGIN

READ_FROM_WRITEBACK: PROCESS
BEGIN
		
	WAIT UNTIL RISING_EDGE(UI_CLK);
	
	IF SIM_ENDED = '1' THEN
	
		CASE FSM_STATE IS 
		WHEN SMALL_DELAY =>
			
			IF DELAY_COUNTER < 10000000 THEN
				DELAY_COUNTER <= DELAY_COUNTER + 1;
			ELSE
				IF WRITE_BACK_ROW /= CURRENT_ROW_TO_BE_SENT AND WRITE_BACK_COLUMN = NUMBER_OF_BURSTS_PER_LINE/2 THEN
				-- SO THAT WE KNOW THAT THE NEXT LINE TO BE RECEIVED WILL BE RECEIVED FROM ITS START 
					FSM_STATE <= FILL_THE_BUFFER;
				END IF;
			END IF;
			
		WHEN FILL_THE_BUFFER =>
		
			IF APP_WDF_WREN = '1' AND WRITE_BACK_ROW = CURRENT_ROW_TO_BE_SENT THEN
				BURSTS_TO_BE_SENT(WRITE_BACK_COLUMN) <= DATA_IN;
				IF WRITE_BACK_COLUMN = NUMBER_OF_BURSTS_PER_LINE-1 THEN
					FSM_STATE <= SEND_NEXT_BURST; 
				END IF;
			END IF;
		-- IF WE ARE MISSING ONE BURST FROM CURRENT_ROW_TO_BE_SENT (REMEMBER THE ADDRESS CHANGES BEFORE THE DATA!!!)
		-- SNIFF THE LAST BURST IN A NEXT FSM STATE BEFORE MOVING ON. 
		WHEN SEND_NEXT_BURST =>
			BURST_TO_BE_SENT <= BURSTS_TO_BE_SENT(BURST_COUNTER);   
			FSM_STATE <= SYNCH_1;
		WHEN SYNCH_1 =>
			FSM_STATE <= SYNCH_2;
		WHEN SYNCH_2 => 
			FSM_STATE <= WAIT_FOR_BURST_TRANSMISSION;
		WHEN WAIT_FOR_BURST_TRANSMISSION =>
			IF BURST_SENT = '1' THEN
				FSM_STATE <= CHECK_IF_LAST_BURST_IN_BUFFER;
				BURST_LOADED(0) <= '0';
			ELSE	
				FSM_STATE <= FSM_STATE;
				BURST_LOADED(0) <= '1';
			END IF;
		WHEN CHECK_IF_LAST_BURST_IN_BUFFER =>
			 IF BURST_SENT = '0' THEN
				 IF BURST_COUNTER = NUMBER_OF_BURSTS_PER_LINE-1 THEN
						BURST_COUNTER <= 0;
						FSM_STATE <= CHECK_IF_LAST_ROW;
				 ELSE 
						BURST_COUNTER <= BURST_COUNTER + 1;
						FSM_STATE <= SEND_NEXT_BURST;
				 END IF;
			 ELSE
				FSM_STATE <= FSM_STATE;
			 END IF;
		
		WHEN CHECK_IF_LAST_ROW =>
			
			IF CURRENT_ROW_TO_BE_SENT = (GRID_Y-1)-CURRENT_ROW_TO_BE_SENT_INIT THEN 
				END_OF_TRANSMISSION_SIG <= '1';
			ELSIF WRITE_BACK_ROW /= (CURRENT_ROW_TO_BE_SENT + 1) AND WRITE_BACK_COLUMN = NUMBER_OF_BURSTS_PER_LINE/2 THEN 
			-- SO THAT WE KNOW THAT THE NEXT LINE TO BE RECEIVED WILL BE RECEIVED FROM ITS START 
				CURRENT_ROW_TO_BE_SENT <= CURRENT_ROW_TO_BE_SENT + 1;
				FSM_STATE <= FILL_THE_BUFFER;
			END IF;
					
		END CASE;
	END IF;
	
END PROCESS;

TRANSMIT: PROCESS
BEGIN
		
	WAIT UNTIL RISING_EDGE(CLK);
		
		FOR J IN 31 DOWNTO 1 LOOP
			BURST_LOADED(J) <= BURST_LOADED(J-1);
		END LOOP;
		
		-- SYNCHRONIZING TRANSMISSION AND READING FROM WRITE-BACK
		IF BURST_LOADED(1) = '1' AND BURST_SENT = '0' THEN
			IF UART_TX_DATA_SEND_SIG = '1' THEN
				UART_TX_DATA_SEND_SIG <= '0';
				IF CELL_SIZE = 4 AND I = 31 THEN
					I <= 0;   
					BURST_SENT <= '1'; 
				ELSIF CELL_SIZE = 8 AND I = 15 THEN
					I <= 0;
					BURST_SENT <= '1'; 
				ELSE
					I <= I + 1;
				END IF;
			ELSE
				IF UART_TX_BUSY = '0' THEN 
					UART_TX_DATA_SEND_SIG <= '1'; 
				END IF;
			END IF;
		ELSE
			-- SYNCHRONIZING TRANSMISSION AND READING FROM WRITE-BACK
			IF BURST_LOADED(1) = '0' AND BURST_LOADED(31) = '0' THEN
				BURST_SENT <= '0';
			END IF;
		END IF;
	
END PROCESS;

UART_TX_DATA_SEND <= UART_TX_DATA_SEND_SIG;
END_OF_TRANSMISSION <= END_OF_TRANSMISSION_SIG;

PROCESS(BURST_TO_BE_SENT, I)
BEGIN
	IF CELL_SIZE = 4 THEN
			UART_TX_DATA <= "0000" & BURST_TO_BE_SENT( ((i+1)*4)-1 DOWNTO i*4 );			
	ELSE
			UART_TX_DATA <= BURST_TO_BE_SENT( ((i+1)*8)-1 DOWNTO i*8 ) ;
	END IF;
END PROCESS;

END BEHAVIORAL;