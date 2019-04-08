----------------------------------------------------------------------------------
-- TECHNICAL UNIVERSITY OF CRETE
-- NICK KYPARISSAS
-- MODULE: Memory initializer is the mediator between UART RX and Memory
-- PROJECT NAME: A Framework for the Real-Time Execution of Cellular Automata on Reconfigurable Logic
-- Diploma Thesis Project 2019
----------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY MEMORY_INITIALIZER IS
	GENERIC (	
		CELL_SIZE : INTEGER := 4;
		BURST_SIZE : INTEGER := 128;
		NUMBER_OF_BURSTS_PER_LINE : INTEGER := 60;
		GRID_Y : INTEGER := 1080;
		MEMORY_ADDR_WIDTH : INTEGER := 27
	);
	PORT ( 	
		CLK : IN STD_LOGIC; -- 81.25MHZ FROM DDR'S UI_CLK
		RST : IN STD_LOGIC;
		-- CONTROL SIGNALS --
		INIT_COMPLETE : OUT STD_LOGIC;
		-- FIFO HANDLING SIGNALS --
		FIFO_DATA : IN STD_LOGIC_VECTOR(BURST_SIZE-1 DOWNTO 0);
		FIFO_READ_EN : OUT STD_LOGIC;
		FIFO_EMPTY : IN STD_LOGIC;
		--
		COLUMN_BEING_WRITTEN : OUT INTEGER RANGE 0 TO NUMBER_OF_BURSTS_PER_LINE;
		ROW_BEING_WRITTEN : OUT INTEGER RANGE 0 TO GRID_Y-1;
		-- MEMORY SIGNALS --- 
		APP_RDY : IN  STD_LOGIC;
		APP_WDF_RDY : IN  STD_LOGIC;
		APP_EN : OUT STD_LOGIC;
		APP_CMD : OUT STD_LOGIC_VECTOR(2 DOWNTO 0); -- "000" = WRITE COMMAND
		APP_WDF_DATA : OUT STD_LOGIC_VECTOR(BURST_SIZE-1 DOWNTO 0);
		--APP_WDF_MASK : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
		APP_WDF_END : OUT STD_LOGIC;
		APP_WDF_WREN : OUT STD_LOGIC;
		APP_ADDR : OUT STD_LOGIC_VECTOR(MEMORY_ADDR_WIDTH-1 DOWNTO 0)
	);
END MEMORY_INITIALIZER;

ARCHITECTURE BEHAVIORAL OF MEMORY_INITIALIZER IS
	
	SIGNAL APP_ADDR_SIGNAL: UNSIGNED(19 DOWNTO 0) := (OTHERS => '0');
	SIGNAL COUNTER : UNSIGNED(1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL FRAME_SIGNAL : STD_LOGIC := '0';
	
	SIGNAL ADDRESS_COLUMN : INTEGER RANGE 0 TO NUMBER_OF_BURSTS_PER_LINE := 0;
	SIGNAL ADDRESS_ROW : INTEGER RANGE 0 TO GRID_Y-1 := 0;
	
	TYPE STATE IS (RESET, IDLE, READING_FROM_FIFO, WRITING, WRITING_2, WRITING_3, SEND_COMMAND, SEND_COMMAND_2, DONE_WRITING, INIT_DONE);
		SIGNAL FSM_STATE : STATE;

BEGIN
	
	-- THE FOLLOWING FSM HANDLES THE DATA BEING SENT TO THE SYSTEM'S DDR MEMORY
	FIFO_TO_DDR: PROCESS 
	BEGIN
		
		WAIT UNTIL CLK'EVENT AND CLK = '1';
		
		IF (RST = '1') THEN  
			FSM_STATE <= RESET;	
		ELSE
			CASE FSM_STATE IS 
				WHEN RESET => 
					INIT_COMPLETE <= '0'; 
					FIFO_READ_EN <= '0';
					COUNTER <= (OTHERS => '1');
					APP_EN <= '0';
					APP_CMD <= (OTHERS => '0');
					APP_ADDR_SIGNAL  <= (OTHERS => '0');
					ADDRESS_COLUMN <= 0;
					ADDRESS_ROW <= 0;
					APP_WDF_DATA <= (OTHERS => '0');
					APP_WDF_END <= '0';
					APP_WDF_WREN <= '0';
					FRAME_SIGNAL <= '0';
					FSM_STATE <= IDLE;
				WHEN IDLE =>
					IF (APP_ADDR_SIGNAL = GRID_Y*8*NUMBER_OF_BURSTS_PER_LINE) THEN 
					-- WE ARE DONE STORING 2 FRAMES IN MEMORY
						INIT_COMPLETE <= '1'; 
						FSM_STATE <= INIT_DONE;
					ELSIF (FIFO_EMPTY = '0') THEN -- READ FROM FIFO
						FIFO_READ_EN <= '1';
						FSM_STATE <= READING_FROM_FIFO;
					ELSE
						FSM_STATE <= IDLE;
					END IF; 
				WHEN READING_FROM_FIFO =>
					FIFO_READ_EN <= '0';
					FSM_STATE <= WRITING;
				WHEN WRITING => 
					-- NOT TO BE CONFUSED WITH 
					-- APP_WDF_DATA( ((31-i+1)*CELL_SIZE)-1 DOWNTO (31 - i)*CELL_SIZE )
					IF CELL_SIZE = 4 THEN
						for i in 0 to 31 loop
							APP_WDF_DATA( ((31-i+1)*4)-1 DOWNTO (31 - i)*4 ) <= FIFO_DATA ( ((i+1)*4)-1 DOWNTO i*4 );
						end loop ; 
					ELSE
						for i in 0 to 15 loop
							APP_WDF_DATA( ((15-i+1)*8)-1 DOWNTO (15 - i)*8 ) <= FIFO_DATA ( ((i+1)*8)-1 DOWNTO i*8 ) ;
						end loop;
					END IF; 
					IF (APP_WDF_RDY = '1') THEN	
						APP_WDF_WREN <= '1';
						APP_WDF_END <= '1';
						FSM_STATE <= WRITING_2;
					ELSE
						FSM_STATE <= WRITING;
					END IF;
				WHEN WRITING_2 =>
					IF (APP_WDF_RDY = '1') THEN
						-- RE-WRITING THE SAME BURST FOR THE OTHER FRAME BUFFER
						-- WRITING THE WHOLE BUFFER IS NOT REALLY NEEDED
						-- WE ONLY NEED TO WRITE THE BOUNDARIES
						FSM_STATE <= WRITING_3;
					ELSE
						FSM_STATE <= WRITING_2;
					END IF;
				WHEN WRITING_3 =>
					IF (APP_WDF_RDY = '1') THEN
						APP_WDF_WREN <= '0';
						APP_WDF_END <= '0';
						APP_EN <= '1';
						FSM_STATE <= SEND_COMMAND;
					ELSE
						FSM_STATE <= WRITING_2;
					END IF;
				WHEN SEND_COMMAND =>
					IF (APP_RDY = '0') THEN
						FSM_STATE <= SEND_COMMAND;
					ELSE
						FRAME_SIGNAL <= '1'; 
						FSM_STATE <= SEND_COMMAND_2;
					END IF;
				WHEN SEND_COMMAND_2 =>
					IF (APP_RDY = '0') THEN
						FSM_STATE <= SEND_COMMAND_2;
					ELSE
						APP_EN <= '0'; 
						FSM_STATE <= DONE_WRITING;
					END IF;
				WHEN DONE_WRITING =>
					APP_ADDR_SIGNAL <= APP_ADDR_SIGNAL + 8; -- INCREASING THE ADDRESS FOR THE NEXT WRITE COMMAND
					
					IF ADDRESS_COLUMN = NUMBER_OF_BURSTS_PER_LINE-1 THEN
						ADDRESS_COLUMN <= 0;
						-- CHANGE LINE
						IF ADDRESS_ROW < GRID_Y THEN 
							ADDRESS_ROW <= ADDRESS_ROW + 1;
						ELSE	
							ADDRESS_ROW <= ADDRESS_ROW;
						END IF;
					ELSE
						ADDRESS_COLUMN <= ADDRESS_COLUMN + 1;
					END IF;
					
					FRAME_SIGNAL <= '0';
					FSM_STATE <= IDLE;
				WHEN INIT_DONE =>
			END CASE;
		END IF;
		
	END PROCESS FIFO_TO_DDR;
	
	APP_ADDR(19 DOWNTO 0) <= STD_LOGIC_VECTOR(APP_ADDR_SIGNAL);
	APP_ADDR(20) <= FRAME_SIGNAL; -- DOUBLE BUFFERING: APP_ADDR(20) CHOOSES WHICH OF THE 2 INSTANCES WE ARE ACCESSING
	APP_ADDR(MEMORY_ADDR_WIDTH-1 DOWNTO 21) <= (OTHERS => '0');
	
	COLUMN_BEING_WRITTEN <= ADDRESS_COLUMN;
	ROW_BEING_WRITTEN <= ADDRESS_ROW;
	
END BEHAVIORAL;