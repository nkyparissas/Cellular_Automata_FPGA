--------------------------------------------------------------------------------
-- PROJECT: SIMPLE UART FOR FPGA
--------------------------------------------------------------------------------
-- MODULE:  UART PARITY BIT GENERATOR
-- AUTHORS: JAKUB CABAL <JAKUBCABAL@GMAIL.COM>
-- LICENSE: THE MIT LICENSE (MIT)
-- WEBSITE: HTTPS://GITHUB.COM/JAKUBCABAL/UART_FOR_FPGA
--------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY UART_PARITY IS
	GENERIC (
		DATA_WIDTH : INTEGER := 8;
		PARITY_TYPE : STRING  := "NONE" -- LEGAL VALUES: "NONE", "EVEN", "ODD", "MARK", "SPACE"
	);
	PORT (
		DATA_IN : IN  STD_LOGIC_VECTOR(DATA_WIDTH-1 DOWNTO 0);
		PARITY_OUT : OUT STD_LOGIC
	);
END UART_PARITY;

ARCHITECTURE FULL OF UART_PARITY IS

BEGIN

	-- -------------------------------------------------------------------------
	-- PARITY BIT GENERATOR
	-- -------------------------------------------------------------------------

	EVEN_PARITY_G : IF (PARITY_TYPE = "EVEN") GENERATE

		PROCESS (DATA_IN)
			VARIABLE PARITY_TEMP : STD_LOGIC;
		BEGIN
			PARITY_TEMP := '0';
			FOR I IN DATA_IN'RANGE LOOP
				PARITY_TEMP := PARITY_TEMP XOR DATA_IN(I);
			END LOOP;
			PARITY_OUT <= PARITY_TEMP;
		END PROCESS;

	END GENERATE;

	ODD_PARITY_G : IF (PARITY_TYPE = "ODD") GENERATE

		PROCESS (DATA_IN)
			VARIABLE PARITY_TEMP : STD_LOGIC;
		BEGIN
			PARITY_TEMP := '1';
			FOR I IN DATA_IN'RANGE LOOP
				PARITY_TEMP := PARITY_TEMP XOR DATA_IN(I);
			END LOOP;
			PARITY_OUT <= PARITY_TEMP;
		END PROCESS;

	END GENERATE;

	MARK_PARITY_G : IF (PARITY_TYPE = "MARK") GENERATE

		PARITY_OUT <= '1';

	END GENERATE;

	SPACE_PARITY_G : IF (PARITY_TYPE = "SPACE") GENERATE

		PARITY_OUT <= '0';

	END GENERATE;

END FULL;
