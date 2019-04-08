--------------------------------------------------------------------------------
-- PROJECT: SIMPLE UART FOR FPGA
--------------------------------------------------------------------------------
-- MODULE:  UART RECEIVER
-- AUTHORS: JAKUB CABAL <JAKUBCABAL@GMAIL.COM>
-- LICENSE: THE MIT LICENSE (MIT)
-- WEBSITE: HTTPS://GITHUB.COM/JAKUBCABAL/UART_FOR_FPGA
--------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY UART_RX IS
	GENERIC (
		PARITY_BIT  : STRING := "NONE" -- LEGAL VALUES: "NONE", "EVEN", "ODD", "MARK", "SPACE"
	);
	PORT (
		CLK : IN  STD_LOGIC; -- SYSTEM CLOCK
		RST : IN  STD_LOGIC; -- HIGH ACTIVE SYNCHRONOUS RESET
		-- UART INTERFACE
		UART_CLK_EN : IN  STD_LOGIC; -- OVERSAMPLING (16X) UART CLOCK ENABLE
		UART_RXD : IN  STD_LOGIC;
		-- USER DATA OUTPUT INTERFACE
		DATA_OUT : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		DATA_VLD : OUT STD_LOGIC; -- WHEN DATA_VLD = 1, DATA ON DATA_OUT ARE VALID
		FRAME_ERROR : OUT STD_LOGIC  -- WHEN FRAME_ERROR = 1, STOP BIT WAS INVALID, CURRENT AND NEXT DATA MAY BE INVALID
	);
END UART_RX;

ARCHITECTURE FULL OF UART_RX IS

	SIGNAL RX_CLK_EN : STD_LOGIC;
	SIGNAL RX_TICKS : UNSIGNED(3 DOWNTO 0);
	SIGNAL RX_CLK_DIVIDER_EN : STD_LOGIC;
	SIGNAL RX_DATA : STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL RX_BIT_COUNT : UNSIGNED(2 DOWNTO 0);
	SIGNAL RX_BIT_COUNT_EN : STD_LOGIC;
	SIGNAL RX_DATA_SHREG_EN : STD_LOGIC;
	SIGNAL RX_PARITY_BIT : STD_LOGIC;
	SIGNAL RX_PARITY_ERROR : STD_LOGIC;
	SIGNAL RX_PARITY_CHECK_EN : STD_LOGIC;
	SIGNAL RX_OUTPUT_REG_EN : STD_LOGIC;

	TYPE STATE IS (IDLE, STARTBIT, DATABITS, PARITYBIT, STOPBIT);
	SIGNAL RX_PSTATE : STATE;
	SIGNAL RX_NSTATE : STATE;

BEGIN

	-- -------------------------------------------------------------------------
	-- UART RECEIVER CLOCK DIVIDER
	-- -------------------------------------------------------------------------

	UART_RX_CLK_DIVIDER : PROCESS (CLK)
	BEGIN
		IF (RISING_EDGE(CLK)) THEN
			IF (RX_CLK_DIVIDER_EN = '1') THEN
				IF (UART_CLK_EN = '1') THEN
					IF (RX_TICKS = "1111") THEN
						RX_TICKS <= (OTHERS => '0');
						RX_CLK_EN <= '0';
					ELSIF (RX_TICKS = "0111") THEN
						RX_TICKS <= RX_TICKS + 1;
						RX_CLK_EN <= '1';
					ELSE
						RX_TICKS <= RX_TICKS + 1;
						RX_CLK_EN <= '0';
					END IF;
				ELSE
					RX_TICKS <= RX_TICKS;
					RX_CLK_EN <= '0';
				END IF;
			ELSE
				RX_TICKS <= (OTHERS => '0');
				RX_CLK_EN <= '0';
			END IF;
		END IF;
	END PROCESS;

	-- -------------------------------------------------------------------------
	-- UART RECEIVER BIT COUNTER
	-- -------------------------------------------------------------------------

	UART_RX_BIT_COUNTER : PROCESS (CLK)
	BEGIN
		IF (RISING_EDGE(CLK)) THEN
			IF (RST = '1') THEN
				RX_BIT_COUNT <= (OTHERS => '0');
			ELSIF (RX_BIT_COUNT_EN = '1' AND RX_CLK_EN = '1') THEN
				IF (RX_BIT_COUNT = "111") THEN
					RX_BIT_COUNT <= (OTHERS => '0');
				ELSE
					RX_BIT_COUNT <= RX_BIT_COUNT + 1;
				END IF;
			END IF;
		END IF;
	END PROCESS;

	-- -------------------------------------------------------------------------
	-- UART RECEIVER DATA SHIFT REGISTER
	-- -------------------------------------------------------------------------

	UART_RX_DATA_SHIFT_REG : PROCESS (CLK)
	BEGIN
		IF (RISING_EDGE(CLK)) THEN
			IF (RST = '1') THEN
				RX_DATA <= (OTHERS => '0');
			ELSIF (RX_CLK_EN = '1' AND RX_DATA_SHREG_EN = '1') THEN
				RX_DATA <= UART_RXD & RX_DATA(7 DOWNTO 1);
			END IF;
		END IF;
	END PROCESS;

	DATA_OUT <= RX_DATA;

	-- -------------------------------------------------------------------------
	-- UART RECEIVER PARITY GENERATOR AND CHECK
	-- -------------------------------------------------------------------------

	UART_RX_PARITY_G : IF (PARITY_BIT /= "NONE") GENERATE
		UART_RX_PARITY_GEN_I: ENTITY WORK.UART_PARITY
		GENERIC MAP (
			DATA_WIDTH  => 8,
			PARITY_TYPE => PARITY_BIT
		)
		PORT MAP (
			DATA_IN	 => RX_DATA,
			PARITY_OUT  => RX_PARITY_BIT
		);

		UART_RX_PARITY_CHECK_REG : PROCESS (CLK)
		BEGIN
			IF (RISING_EDGE(CLK)) THEN
				IF (RST = '1') THEN
					RX_PARITY_ERROR <= '0';
				ELSIF (RX_PARITY_CHECK_EN = '1') THEN
					RX_PARITY_ERROR <= RX_PARITY_BIT XOR UART_RXD;
				END IF;
			END IF;
		END PROCESS;
	END GENERATE;

	UART_RX_NOPARITY_G : IF (PARITY_BIT = "NONE") GENERATE
		RX_PARITY_ERROR <= '0';
	END GENERATE;

	-- -------------------------------------------------------------------------
	-- UART RECEIVER OUTPUT REGISTER
	-- -------------------------------------------------------------------------

	UART_RX_OUTPUT_REG : PROCESS (CLK)
	BEGIN
		IF (RISING_EDGE(CLK)) THEN
			IF (RST = '1') THEN
				DATA_VLD <= '0';
				FRAME_ERROR <= '0';
			ELSE
				IF (RX_OUTPUT_REG_EN = '1') THEN
					DATA_VLD <= NOT RX_PARITY_ERROR AND UART_RXD;
					FRAME_ERROR <= NOT UART_RXD;
				ELSE
					DATA_VLD <= '0';
					FRAME_ERROR <= '0';
				END IF;
			END IF;
		END IF;
	END PROCESS;

	-- -------------------------------------------------------------------------
	-- UART RECEIVER FSM
	-- -------------------------------------------------------------------------

	-- PRESENT STATE REGISTER
	PROCESS (CLK)
	BEGIN
		IF (RISING_EDGE(CLK)) THEN
			IF (RST = '1') THEN
				RX_PSTATE <= IDLE;
			ELSE
				RX_PSTATE <= RX_NSTATE;
			END IF;
		END IF;
	END PROCESS;

	-- NEXT STATE AND OUTPUTS LOGIC
	PROCESS (RX_PSTATE, UART_RXD, RX_CLK_EN, RX_BIT_COUNT)
	BEGIN
		CASE RX_PSTATE IS

			WHEN IDLE =>
				RX_OUTPUT_REG_EN <= '0';
				RX_BIT_COUNT_EN <= '0';
				RX_DATA_SHREG_EN <= '0';
				RX_CLK_DIVIDER_EN <= '0';
				RX_PARITY_CHECK_EN <= '0';

				IF (UART_RXD = '0') THEN
					RX_NSTATE <= STARTBIT;
				ELSE
					RX_NSTATE <= IDLE;
				END IF;

			WHEN STARTBIT =>
				RX_OUTPUT_REG_EN <= '0';
				RX_BIT_COUNT_EN <= '0';
				RX_DATA_SHREG_EN <= '0';
				RX_CLK_DIVIDER_EN <= '1';
				RX_PARITY_CHECK_EN <= '0';

				IF (RX_CLK_EN = '1') THEN
					RX_NSTATE <= DATABITS;
				ELSE
					RX_NSTATE <= STARTBIT;
				END IF;

			WHEN DATABITS =>
				RX_OUTPUT_REG_EN <= '0';
				RX_BIT_COUNT_EN <= '1';
				RX_DATA_SHREG_EN <= '1';
				RX_CLK_DIVIDER_EN <= '1';
				RX_PARITY_CHECK_EN <= '0';

				IF ((RX_CLK_EN = '1') AND (RX_BIT_COUNT = "111")) THEN
					IF (PARITY_BIT = "NONE") THEN
						RX_NSTATE <= STOPBIT;
					ELSE
						RX_NSTATE <= PARITYBIT;
					END IF ;
				ELSE
					RX_NSTATE <= DATABITS;
				END IF;

			WHEN PARITYBIT =>
				RX_OUTPUT_REG_EN <= '0';
				RX_BIT_COUNT_EN <= '0';
				RX_DATA_SHREG_EN <= '0';
				RX_CLK_DIVIDER_EN <= '1';
				RX_PARITY_CHECK_EN <= '1';

				IF (RX_CLK_EN = '1') THEN
					RX_NSTATE <= STOPBIT;
				ELSE
					RX_NSTATE <= PARITYBIT;
				END IF;

			WHEN STOPBIT =>
				RX_BIT_COUNT_EN <= '0';
				RX_DATA_SHREG_EN <= '0';
				RX_CLK_DIVIDER_EN <= '1';
				RX_PARITY_CHECK_EN <= '0';

				IF (RX_CLK_EN = '1') THEN
					RX_NSTATE <= IDLE;
					RX_OUTPUT_REG_EN <= '1';
				ELSE
					RX_NSTATE <= STOPBIT;
					RX_OUTPUT_REG_EN <= '0';
				END IF;

			WHEN OTHERS =>
				RX_OUTPUT_REG_EN <= '0';
				RX_BIT_COUNT_EN <= '0';
				RX_DATA_SHREG_EN <= '0';
				RX_CLK_DIVIDER_EN <= '0';
				RX_PARITY_CHECK_EN <= '0';
				RX_NSTATE <= IDLE;

		END CASE;
	END PROCESS;

END FULL;
