--------------------------------------------------------------------------------
-- PROJECT: SIMPLE UART FOR FPGA
--------------------------------------------------------------------------------
-- MODULE:  UART TOP MODULE
-- AUTHORS: JAKUB CABAL <JAKUBCABAL@GMAIL.COM>
-- LICENSE: THE MIT LICENSE (MIT)
-- WEBSITE: HTTPS://GITHUB.COM/JAKUBCABAL/UART_FOR_FPGA
--------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

-- UART FOR FPGA REQUIRES: 1 START BIT, 8 DATA BITS, 1 STOP BIT!!!
-- OTHER PARAMETERS CAN BE SET USING GENERICS.

ENTITY UART IS
	GENERIC (
		CLK_FREQ : INTEGER := 100000000;   -- SET SYSTEM CLOCK FREQUENCY IN HZ
		BAUD_RATE : INTEGER := 2000000; -- BAUD RATE VALUE
		PARITY_BIT : STRING  := "NONE"  -- LEGAL VALUES: "NONE", "EVEN", "ODD", "MARK", "SPACE"
	);
	PORT (
		CLK : IN  STD_LOGIC; -- SYSTEM CLOCK
		RST : IN  STD_LOGIC; -- HIGH ACTIVE SYNCHRONOUS RESET
		-- UART INTERFACE
		UART_TXD : OUT STD_LOGIC;
		UART_RXD : IN  STD_LOGIC;
		-- USER DATA INPUT INTERFACE
		DATA_IN : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
		DATA_SEND : IN  STD_LOGIC; -- WHEN DATA_SEND = 1, DATA ON DATA_IN WILL BE TRANSMIT, DATA_SEND CAN SET TO 1 ONLY WHEN BUSY = 0
		BUSY : OUT STD_LOGIC; -- WHEN BUSY = 1 TRANSIEVER IS BUSY, YOU MUST NOT SET DATA_SEND TO 1
		-- USER DATA OUTPUT INTERFACE
		DATA_OUT : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		DATA_VLD : OUT STD_LOGIC; -- WHEN DATA_VLD = 1, DATA ON DATA_OUT ARE VALID
		FRAME_ERROR : OUT STD_LOGIC  -- WHEN FRAME_ERROR = 1, STOP BIT WAS INVALID, CURRENT AND NEXT DATA MAY BE INVALID
	);
END UART;

ARCHITECTURE FULL OF UART IS

	CONSTANT DIVIDER_VALUE : INTEGER := CLK_FREQ/(16*BAUD_RATE);

	SIGNAL UART_TICKS : INTEGER RANGE 0 TO DIVIDER_VALUE-1;
	SIGNAL UART_CLK_EN : STD_LOGIC;
	SIGNAL UART_RXD_SHREG : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL UART_RXD_DEBOUNCED : STD_LOGIC;

BEGIN

	-- -------------------------------------------------------------------------
	-- UART OVERSAMPLING CLOCK DIVIDER
	-- -------------------------------------------------------------------------

	UART_OVERSAMPLING_CLK_DIVIDER : PROCESS (CLK)
	BEGIN
		IF (RISING_EDGE(CLK)) THEN
			IF (RST = '1') THEN
				UART_TICKS <= 0;
				UART_CLK_EN <= '0';
			ELSIF (UART_TICKS = DIVIDER_VALUE-1) THEN
				UART_TICKS <= 0;
				UART_CLK_EN <= '1';
			ELSE
				UART_TICKS <= UART_TICKS + 1;
				UART_CLK_EN <= '0';
			END IF;
		END IF;
	END PROCESS;

	-- -------------------------------------------------------------------------
	-- UART RXD DEBAUNCER
	-- -------------------------------------------------------------------------

	UART_RXD_DEBOUNCER : PROCESS (CLK)
	BEGIN
		IF (RISING_EDGE(CLK)) THEN
			IF (RST = '1') THEN
				UART_RXD_SHREG <= (OTHERS => '1');
				UART_RXD_DEBOUNCED <= '1';
			ELSE
				UART_RXD_SHREG <= UART_RXD & UART_RXD_SHREG(3 DOWNTO 1);
				UART_RXD_DEBOUNCED <= UART_RXD_SHREG(0) OR
									  UART_RXD_SHREG(1) OR
									  UART_RXD_SHREG(2) OR
									  UART_RXD_SHREG(3);
			END IF;
		END IF;
	END PROCESS;

	-- -------------------------------------------------------------------------
	-- UART TRANSMITTER
	-- -------------------------------------------------------------------------

	UART_TX_I: ENTITY WORK.UART_TX
	GENERIC MAP (
		PARITY_BIT => PARITY_BIT
	)
	PORT MAP (
		CLK => CLK,
		RST => RST,
		-- UART INTERFACE
		UART_CLK_EN => UART_CLK_EN,
		UART_TXD => UART_TXD,
		-- USER DATA INPUT INTERFACE
		DATA_IN => DATA_IN,
		DATA_SEND => DATA_SEND,
		BUSY => BUSY
	);

	-- -------------------------------------------------------------------------
	-- UART RECEIVER
	-- -------------------------------------------------------------------------

	UART_RX_I: ENTITY WORK.UART_RX
	GENERIC MAP (
		PARITY_BIT => PARITY_BIT
	)
	PORT MAP (
		CLK => CLK,
		RST => RST,
		-- UART INTERFACE
		UART_CLK_EN => UART_CLK_EN,
		UART_RXD => UART_RXD_DEBOUNCED,
		-- USER DATA OUTPUT INTERFACE
		DATA_OUT => DATA_OUT,
		DATA_VLD => DATA_VLD,
		FRAME_ERROR => FRAME_ERROR
	);

END FULL;
