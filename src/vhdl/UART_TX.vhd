--------------------------------------------------------------------------------
-- PROJECT: SIMPLE UART FOR FPGA
--------------------------------------------------------------------------------
-- MODULE:  UART TRANSMITTER
-- AUTHORS: JAKUB CABAL <JAKUBCABAL@GMAIL.COM>
-- LICENSE: THE MIT LICENSE (MIT)
-- WEBSITE: HTTPS://GITHUB.COM/JAKUBCABAL/UART_FOR_FPGA
--------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY UART_TX IS
	GENERIC (
		PARITY_BIT : STRING := "NONE" -- LEGAL VALUES: "NONE", "EVEN", "ODD", "MARK", "SPACE"
	);
	PORT (
		CLK : IN  STD_LOGIC; -- SYSTEM CLOCK
		RST : IN  STD_LOGIC; -- HIGH ACTIVE SYNCHRONOUS RESET
		-- UART INTERFACE
		UART_CLK_EN : IN  STD_LOGIC; -- OVERSAMPLING (16X) UART CLOCK ENABLE
		UART_TXD : OUT STD_LOGIC;
		-- USER DATA INPUT INTERFACE
		DATA_IN : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
		DATA_SEND : IN  STD_LOGIC; -- WHEN DATA_SEND = 1, DATA ON DATA_IN WILL BE TRANSMIT, DATA_SEND CAN SET TO 1 ONLY WHEN BUSY = 0
		BUSY : OUT STD_LOGIC  -- WHEN BUSY = 1 TRANSIEVER IS BUSY, YOU MUST NOT SET DATA_SEND TO 1
	);
END UART_TX;

ARCHITECTURE FULL OF UART_TX IS

	SIGNAL TX_CLK_EN : STD_LOGIC;
	SIGNAL TX_CLK_DIVIDER_EN : STD_LOGIC;
	SIGNAL TX_TICKS : UNSIGNED(3 DOWNTO 0);
	SIGNAL TX_DATA : STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL TX_BIT_COUNT : UNSIGNED(2 DOWNTO 0);
	SIGNAL TX_BIT_COUNT_EN : STD_LOGIC;
	SIGNAL TX_BUSY : STD_LOGIC;
	SIGNAL TX_PARITY_BIT : STD_LOGIC;
	SIGNAL TX_DATA_OUT_SEL : STD_LOGIC_VECTOR(1 DOWNTO 0);

	TYPE STATE IS (IDLE, TXSYNC, STARTBIT, DATABITS, PARITYBIT, STOPBIT);
	SIGNAL TX_PSTATE : STATE;
	SIGNAL TX_NSTATE : STATE;

BEGIN

	BUSY <= TX_BUSY;

	-- -------------------------------------------------------------------------
	-- UART TRANSMITTER CLOCK DIVIDER
	-- -------------------------------------------------------------------------

	UART_TX_CLK_DIVIDER : PROCESS (CLK)
	BEGIN
		IF (RISING_EDGE(CLK)) THEN
			IF (TX_CLK_DIVIDER_EN = '1') THEN
				IF (UART_CLK_EN = '1') THEN
					IF (TX_TICKS = "1111") THEN
						TX_TICKS <= (OTHERS => '0');
						TX_CLK_EN <= '0';
					ELSIF (TX_TICKS = "0001") THEN
						TX_TICKS <= TX_TICKS + 1;
						TX_CLK_EN <= '1';
					ELSE
						TX_TICKS <= TX_TICKS + 1;
						TX_CLK_EN <= '0';
					END IF;
				ELSE
					TX_TICKS <= TX_TICKS;
					TX_CLK_EN <= '0';
				END IF;
			ELSE
				TX_TICKS <= (OTHERS => '0');
				TX_CLK_EN <= '0';
			END IF;
		END IF;
	END PROCESS;

	-- -------------------------------------------------------------------------
	-- UART TRANSMITTER INPUT DATA REGISTER
	-- -------------------------------------------------------------------------

	UART_TX_INPUT_DATA_REG : PROCESS (CLK)
	BEGIN
		IF (RISING_EDGE(CLK)) THEN
			IF (RST = '1') THEN
				TX_DATA <= (OTHERS => '0');
			ELSIF (DATA_SEND = '1' AND TX_BUSY = '0') THEN
				TX_DATA <= DATA_IN;
			END IF;
		END IF;
	END PROCESS;

	-- -------------------------------------------------------------------------
	-- UART TRANSMITTER BIT COUNTER
	-- -------------------------------------------------------------------------

	UART_TX_BIT_COUNTER : PROCESS (CLK)
	BEGIN
		IF (RISING_EDGE(CLK)) THEN
			IF (RST = '1') THEN
				TX_BIT_COUNT <= (OTHERS => '0');
			ELSIF (TX_BIT_COUNT_EN = '1' AND TX_CLK_EN = '1') THEN
				IF (TX_BIT_COUNT = "111") THEN
					TX_BIT_COUNT <= (OTHERS => '0');
				ELSE
					TX_BIT_COUNT <= TX_BIT_COUNT + 1;
				END IF;
			END IF;
		END IF;
	END PROCESS;

	-- -------------------------------------------------------------------------
	-- UART TRANSMITTER PARITY GENERATOR
	-- -------------------------------------------------------------------------

	UART_TX_PARITY_G : IF (PARITY_BIT /= "NONE") GENERATE
		UART_TX_PARITY_GEN_I: ENTITY WORK.UART_PARITY
		GENERIC MAP (
			DATA_WIDTH  => 8,
			PARITY_TYPE => PARITY_BIT
		)
		PORT MAP (
			DATA_IN	 => TX_DATA,
			PARITY_OUT  => TX_PARITY_BIT
		);
	END GENERATE;

	UART_TX_NOPARITY_G : IF (PARITY_BIT = "NONE") GENERATE
		TX_PARITY_BIT <= 'Z';
	END GENERATE;

	-- -------------------------------------------------------------------------
	-- UART TRANSMITTER OUTPUT DATA REGISTER
	-- -------------------------------------------------------------------------

	UART_TX_OUTPUT_DATA_REG : PROCESS (CLK)
	BEGIN
		IF (RISING_EDGE(CLK)) THEN
			IF (RST = '1') THEN
				UART_TXD <= '1';
			ELSE
				CASE TX_DATA_OUT_SEL IS
					WHEN "01" => -- START BIT
						UART_TXD <= '0';
					WHEN "10" => -- DATA BITS
						UART_TXD <= TX_DATA(TO_INTEGER(TX_BIT_COUNT));
					WHEN "11" => -- PARITY BIT
						UART_TXD <= TX_PARITY_BIT;
					WHEN OTHERS => -- STOP BIT OR IDLE
						UART_TXD <= '1';
				END CASE;
			END IF;
		END IF;
	END PROCESS;

	-- -------------------------------------------------------------------------
	-- UART TRANSMITTER FSM
	-- -------------------------------------------------------------------------

	-- PRESENT STATE REGISTER
	PROCESS (CLK)
	BEGIN
		IF (RISING_EDGE(CLK)) THEN
			IF (RST = '1') THEN
				TX_PSTATE <= IDLE;
			ELSE
				TX_PSTATE <= TX_NSTATE;
			END IF;
		END IF;
	END PROCESS;

	-- NEXT STATE AND OUTPUTS LOGIC
	PROCESS (TX_PSTATE, DATA_SEND, TX_CLK_EN, TX_BIT_COUNT)
	BEGIN

		CASE TX_PSTATE IS

			WHEN IDLE =>
				TX_BUSY <= '0';
				TX_DATA_OUT_SEL <= "00";
				TX_BIT_COUNT_EN <= '0';
				TX_CLK_DIVIDER_EN <= '0';

				IF (DATA_SEND = '1') THEN
					TX_NSTATE <= TXSYNC;
				ELSE
					TX_NSTATE <= IDLE;
				END IF;

			WHEN TXSYNC =>
				TX_BUSY <= '1';
				TX_DATA_OUT_SEL <= "00";
				TX_BIT_COUNT_EN <= '0';
				TX_CLK_DIVIDER_EN <= '1';

				IF (TX_CLK_EN = '1') THEN
					TX_NSTATE <= STARTBIT;
				ELSE
					TX_NSTATE <= TXSYNC;
				END IF;

			WHEN STARTBIT =>
				TX_BUSY <= '1';
				TX_DATA_OUT_SEL <= "01";
				TX_BIT_COUNT_EN <= '0';
				TX_CLK_DIVIDER_EN <= '1';

				IF (TX_CLK_EN = '1') THEN
					TX_NSTATE <= DATABITS;
				ELSE
					TX_NSTATE <= STARTBIT;
				END IF;

			WHEN DATABITS =>
				TX_BUSY <= '1';
				TX_DATA_OUT_SEL <= "10";
				TX_BIT_COUNT_EN <= '1';
				TX_CLK_DIVIDER_EN <= '1';

				IF ((TX_CLK_EN = '1') AND (TX_BIT_COUNT = "111")) THEN
					IF (PARITY_BIT = "NONE") THEN
						TX_NSTATE <= STOPBIT;
					ELSE
						TX_NSTATE <= PARITYBIT;
					END IF ;
				ELSE
					TX_NSTATE <= DATABITS;
				END IF;

			WHEN PARITYBIT =>
				TX_BUSY <= '1';
				TX_DATA_OUT_SEL <= "11";
				TX_BIT_COUNT_EN <= '0';
				TX_CLK_DIVIDER_EN <= '1';

				IF (TX_CLK_EN = '1') THEN
					TX_NSTATE <= STOPBIT;
				ELSE
					TX_NSTATE <= PARITYBIT;
				END IF;

			WHEN STOPBIT =>
				TX_BUSY <= '0';
				TX_DATA_OUT_SEL <= "00";
				TX_BIT_COUNT_EN <= '0';
				TX_CLK_DIVIDER_EN <= '1';

				IF (DATA_SEND = '1') THEN
					TX_NSTATE <= TXSYNC;
				ELSIF (TX_CLK_EN = '1') THEN
					TX_NSTATE <= IDLE;
				ELSE
					TX_NSTATE <= STOPBIT;
				END IF;

			WHEN OTHERS =>
				TX_BUSY <= '1';
				TX_DATA_OUT_SEL <= "00";
				TX_BIT_COUNT_EN <= '0';
				TX_CLK_DIVIDER_EN <= '0';
				TX_NSTATE <= IDLE;

		END CASE;
	END PROCESS;

END FULL;
