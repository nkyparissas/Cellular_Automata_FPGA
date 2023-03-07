----------------------------------------------------------------------------------
-- TECHNICAL UNIVERSITY OF CRETE
-- NICK KYPARISSAS
-- MODULE: CA Engine implementing the "Greenberg-Hastings Model" rule
-- PROJECT NAME: A Framework for the Real-Time Execution of Cellular Automata on Reconfigurable Logic
-- Diploma Thesis Project 2019
----------------------------------------------------------------------------------

-- YOU CANT USE THIS AS IS FOR A DIFFERENT RULE: EVERY TIME THE NEIGHBORHOOD 
-- SIZE CHANGES, THE ADDERS BINARY TREE MIGHT REQUIRE CHANGES AS WELL. 

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY CA_ENGINE IS
   GENERIC (
      T : INTEGER := 5; -- Threshold -- Theory says: T < 49 = (1/4)(r^2)
      E : INTEGER := 1; -- Threshold of excitable media. Original: 1, variations: up to N-1.
      N : INTEGER := 16; -- Number of colors (up to 16 for 4-bit, up to 256 for 8-bit).
      CELL_SIZE : INTEGER := 4; -- HOW MANY BITS PER CELL, 8 BITS = UP TO 256 STATES
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
   type NEIGHBORHOOD_ARRAY is array (NEIGHBORHOOD_SIZE-1 downto 0, NEIGHBORHOOD_SIZE-1 downto 0) of integer range 0 to 15; -- 16 STATES
   SIGNAL NEIGHBORHOOD_CELL : NEIGHBORHOOD_ARRAY := (OTHERS => (OTHERS => 0));

   -- EACH ARRAY CELL MUST BE LARGE ENOUGH FOR NEIGHBORHOOD_CELL*NEIGHBORHOOD_WEIGHT
   type CATEGORIZED_NEIGHBORHOOD_ARRAY is array (NEIGHBORHOOD_SIZE-1 downto 0, NEIGHBORHOOD_SIZE-1 downto 0) of integer range 0 to 1;
   SIGNAL INFECTED_CELL : CATEGORIZED_NEIGHBORHOOD_ARRAY := (OTHERS => (OTHERS => 0));

   -- YOU NEED TO ADJUST THIS SIGNAL ACCORDING TO THE DEPTH OF YOUR RULE'S PIPELINE 
   SIGNAL DATA_VALID_SIGNAL : STD_LOGIC_VECTOR( ((NEIGHBORHOOD_SIZE-1)/2)+12+20 DOWNTO 0) := (OTHERS => '0');

   -- CUSTOM RULE SIGNALS

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
   SIGNAL INFECTED_TOTAL_SUM : INTEGER range 0 to 1023;

   TYPE CURRENT_CELL_PIPELINE is array (55 downto 0) of integer range 0 to 255;
   SIGNAL CURRENT_CELL : CURRENT_CELL_PIPELINE := (OTHERS => 0);

BEGIN

   PROCESS 
   BEGIN

      WAIT UNTIL RISING_EDGE(CLK);	
      
      IF RST = '1' THEN
         DATA_VALID_SIGNAL <= (OTHERS => '0');
      END IF;

      -- PIPELINING NEIGHBORHOOD ----------------------------------
      -- Inputting from the end of the neighborhood so that we follow 
      -- the window as it traverses through the grid without any mirroring
      -- in the neighborhood weights. 

      FOR I IN NEIGHBORHOOD_SIZE-1 DOWNTO 0 LOOP
         NEIGHBORHOOD_CELL(I, NEIGHBORHOOD_SIZE-1) <= TO_INTEGER(UNSIGNED(DATA_IN((I*CELL_SIZE)+CELL_SIZE-1 DOWNTO I*CELL_SIZE)));
      END LOOP;

      FOR I IN NEIGHBORHOOD_SIZE-1 DOWNTO 0 LOOP
         FOR J IN NEIGHBORHOOD_SIZE-1 DOWNTO 1 LOOP
            NEIGHBORHOOD_CELL(I, J-1) <= NEIGHBORHOOD_CELL(I, J);
         END LOOP;
      END LOOP;

      -- SETTING UP THE 3 DIFFERENT ADDER TREES
      FOR I IN NEIGHBORHOOD_SIZE-1 DOWNTO 0 LOOP
         FOR J IN NEIGHBORHOOD_SIZE-1 DOWNTO 0 LOOP
            IF NEIGHBORHOOD_CELL(I, J) = 1 THEN --> 0 AND NEIGHBORHOOD_CELL(I, J) <= E THEN 
               INFECTED_CELL(I, J) <= 1;
            ELSE
               INFECTED_CELL(I, J) <= 0;
            END IF;
         END LOOP;
      END LOOP;

      -- EXCLUDING CURRENT CELL
      INFECTED_CELL(14, 14) <= 0;

      -- CIRCULAR NEIGHBORHOOD: 

      -- INFECTED_CELL(0, 0) <= 0;
      -- INFECTED_CELL(0, 1) <= 0;
      -- INFECTED_CELL(0, 2) <= 0;
      -- INFECTED_CELL(0, 3) <= 0;
      -- INFECTED_CELL(0, 4) <= 0;
      -- INFECTED_CELL(0, 5) <= 0;
      -- INFECTED_CELL(0, 6) <= 0;
      -- INFECTED_CELL(0, 7) <= 0;
      -- INFECTED_CELL(0, 8) <= 0;
      -- INFECTED_CELL(0, 20) <= 0;
      -- INFECTED_CELL(0, 21) <= 0;
      -- INFECTED_CELL(0, 22) <= 0;
      -- INFECTED_CELL(0, 23) <= 0;
      -- INFECTED_CELL(0, 24) <= 0;
      -- INFECTED_CELL(0, 25) <= 0;
      -- INFECTED_CELL(0, 26) <= 0;
      -- INFECTED_CELL(0, 27) <= 0;
      -- INFECTED_CELL(0, 28) <= 0;
      -- INFECTED_CELL(1, 0) <= 0;
      -- INFECTED_CELL(1, 1) <= 0;
      -- INFECTED_CELL(1, 2) <= 0;
      -- INFECTED_CELL(1, 3) <= 0;
      -- INFECTED_CELL(1, 4) <= 0;
      -- INFECTED_CELL(1, 5) <= 0;
      -- INFECTED_CELL(1, 6) <= 0;
      -- INFECTED_CELL(1, 22) <= 0;
      -- INFECTED_CELL(1, 23) <= 0;
      -- INFECTED_CELL(1, 24) <= 0;
      -- INFECTED_CELL(1, 25) <= 0;
      -- INFECTED_CELL(1, 26) <= 0;
      -- INFECTED_CELL(1, 27) <= 0;
      -- INFECTED_CELL(1, 28) <= 0;
      -- INFECTED_CELL(2, 0) <= 0;
      -- INFECTED_CELL(2, 1) <= 0;
      -- INFECTED_CELL(2, 2) <= 0;
      -- INFECTED_CELL(2, 3) <= 0;
      -- INFECTED_CELL(2, 4) <= 0;
      -- INFECTED_CELL(2, 5) <= 0;
      -- INFECTED_CELL(2, 23) <= 0;
      -- INFECTED_CELL(2, 24) <= 0;
      -- INFECTED_CELL(2, 25) <= 0;
      -- INFECTED_CELL(2, 26) <= 0;
      -- INFECTED_CELL(2, 27) <= 0;
      -- INFECTED_CELL(2, 28) <= 0;
      -- INFECTED_CELL(3, 0) <= 0;
      -- INFECTED_CELL(3, 1) <= 0;
      -- INFECTED_CELL(3, 2) <= 0;
      -- INFECTED_CELL(3, 3) <= 0;
      -- INFECTED_CELL(3, 25) <= 0;
      -- INFECTED_CELL(3, 26) <= 0;
      -- INFECTED_CELL(3, 27) <= 0;
      -- INFECTED_CELL(3, 28) <= 0;
      -- INFECTED_CELL(4, 0) <= 0;
      -- INFECTED_CELL(4, 1) <= 0;
      -- INFECTED_CELL(4, 2) <= 0;
      -- INFECTED_CELL(4, 26) <= 0;
      -- INFECTED_CELL(4, 27) <= 0;
      -- INFECTED_CELL(4, 28) <= 0;
      -- INFECTED_CELL(5, 0) <= 0;
      -- INFECTED_CELL(5, 1) <= 0;
      -- INFECTED_CELL(5, 2) <= 0;
      -- INFECTED_CELL(5, 26) <= 0;
      -- INFECTED_CELL(5, 27) <= 0;
      -- INFECTED_CELL(5, 28) <= 0;
      -- INFECTED_CELL(6, 0) <= 0;
      -- INFECTED_CELL(6, 1) <= 0;
      -- INFECTED_CELL(6, 27) <= 0;
      -- INFECTED_CELL(6, 28) <= 0;
      -- INFECTED_CELL(7, 0) <= 0;
      -- INFECTED_CELL(7, 28) <= 0;
      -- INFECTED_CELL(8, 0) <= 0;
      -- INFECTED_CELL(8, 28) <= 0;
      -- INFECTED_CELL(20, 0) <= 0;
      -- INFECTED_CELL(20, 28) <= 0;
      -- INFECTED_CELL(21, 0) <= 0;
      -- INFECTED_CELL(21, 28) <= 0;
      -- INFECTED_CELL(22, 0) <= 0;
      -- INFECTED_CELL(22, 1) <= 0;
      -- INFECTED_CELL(22, 27) <= 0;
      -- INFECTED_CELL(22, 28) <= 0;
      -- INFECTED_CELL(23, 0) <= 0;
      -- INFECTED_CELL(23, 1) <= 0;
      -- INFECTED_CELL(23, 2) <= 0;
      -- INFECTED_CELL(23, 26) <= 0;
      -- INFECTED_CELL(23, 27) <= 0;
      -- INFECTED_CELL(23, 28) <= 0;
      -- INFECTED_CELL(24, 0) <= 0;
      -- INFECTED_CELL(24, 1) <= 0;
      -- INFECTED_CELL(24, 2) <= 0;
      -- INFECTED_CELL(24, 26) <= 0;
      -- INFECTED_CELL(24, 27) <= 0;
      -- INFECTED_CELL(24, 28) <= 0;
      -- INFECTED_CELL(25, 0) <= 0;
      -- INFECTED_CELL(25, 1) <= 0;
      -- INFECTED_CELL(25, 2) <= 0;
      -- INFECTED_CELL(25, 3) <= 0;
      -- INFECTED_CELL(25, 25) <= 0;
      -- INFECTED_CELL(25, 26) <= 0;
      -- INFECTED_CELL(25, 27) <= 0;
      -- INFECTED_CELL(25, 28) <= 0;
      -- INFECTED_CELL(26, 0) <= 0;
      -- INFECTED_CELL(26, 1) <= 0;
      -- INFECTED_CELL(26, 2) <= 0;
      -- INFECTED_CELL(26, 3) <= 0;
      -- INFECTED_CELL(26, 4) <= 0;
      -- INFECTED_CELL(26, 5) <= 0;
      -- INFECTED_CELL(26, 23) <= 0;
      -- INFECTED_CELL(26, 24) <= 0;
      -- INFECTED_CELL(26, 25) <= 0;
      -- INFECTED_CELL(26, 26) <= 0;
      -- INFECTED_CELL(26, 27) <= 0;
      -- INFECTED_CELL(26, 28) <= 0;
      -- INFECTED_CELL(27, 0) <= 0;
      -- INFECTED_CELL(27, 1) <= 0;
      -- INFECTED_CELL(27, 2) <= 0;
      -- INFECTED_CELL(27, 3) <= 0;
      -- INFECTED_CELL(27, 4) <= 0;
      -- INFECTED_CELL(27, 5) <= 0;
      -- INFECTED_CELL(27, 6) <= 0;
      -- INFECTED_CELL(27, 22) <= 0;
      -- INFECTED_CELL(27, 23) <= 0;
      -- INFECTED_CELL(27, 24) <= 0;
      -- INFECTED_CELL(27, 25) <= 0;
      -- INFECTED_CELL(27, 26) <= 0;
      -- INFECTED_CELL(27, 27) <= 0;
      -- INFECTED_CELL(27, 28) <= 0;
      -- INFECTED_CELL(28, 0) <= 0;
      -- INFECTED_CELL(28, 1) <= 0;
      -- INFECTED_CELL(28, 2) <= 0;
      -- INFECTED_CELL(28, 3) <= 0;
      -- INFECTED_CELL(28, 4) <= 0;
      -- INFECTED_CELL(28, 5) <= 0;
      -- INFECTED_CELL(28, 6) <= 0;
      -- INFECTED_CELL(28, 7) <= 0;
      -- INFECTED_CELL(28, 8) <= 0;
      -- INFECTED_CELL(28, 20) <= 0;
      -- INFECTED_CELL(28, 21) <= 0;
      -- INFECTED_CELL(28, 22) <= 0;
      -- INFECTED_CELL(28, 23) <= 0;
      -- INFECTED_CELL(28, 24) <= 0;
      -- INFECTED_CELL(28, 25) <= 0;
      -- INFECTED_CELL(28, 26) <= 0;
      -- INFECTED_CELL(28, 27) <= 0;
      -- INFECTED_CELL(28, 28) <= 0;

      -- VON NEUMANN NEIGHBORHOOD:

      --INFECTED_CELL(0, 0) <= 0;
      --INFECTED_CELL(0, 1) <= 0;
      --INFECTED_CELL(0, 2) <= 0;
      --INFECTED_CELL(0, 3) <= 0;
      --INFECTED_CELL(0, 4) <= 0;
      --INFECTED_CELL(0, 5) <= 0;
      --INFECTED_CELL(0, 6) <= 0;
      --INFECTED_CELL(0, 7) <= 0;
      --INFECTED_CELL(0, 8) <= 0;
      --INFECTED_CELL(0, 9) <= 0;
      --INFECTED_CELL(0, 10) <= 0;
      --INFECTED_CELL(0, 11) <= 0;
      --INFECTED_CELL(0, 12) <= 0;
      --INFECTED_CELL(0, 13) <= 0;
      --INFECTED_CELL(0, 15) <= 0;
      --INFECTED_CELL(0, 16) <= 0;
      --INFECTED_CELL(0, 17) <= 0;
      --INFECTED_CELL(0, 18) <= 0;
      --INFECTED_CELL(0, 19) <= 0;
      --INFECTED_CELL(0, 20) <= 0;
      --INFECTED_CELL(0, 21) <= 0;
      --INFECTED_CELL(0, 22) <= 0;
      --INFECTED_CELL(0, 23) <= 0;
      --INFECTED_CELL(0, 24) <= 0;
      --INFECTED_CELL(0, 25) <= 0;
      --INFECTED_CELL(0, 26) <= 0;
      --INFECTED_CELL(0, 27) <= 0;
      --INFECTED_CELL(0, 28) <= 0;
      --INFECTED_CELL(1, 0) <= 0;
      --INFECTED_CELL(1, 1) <= 0;
      --INFECTED_CELL(1, 2) <= 0;
      --INFECTED_CELL(1, 3) <= 0;
      --INFECTED_CELL(1, 4) <= 0;
      --INFECTED_CELL(1, 5) <= 0;
      --INFECTED_CELL(1, 6) <= 0;
      --INFECTED_CELL(1, 7) <= 0;
      --INFECTED_CELL(1, 8) <= 0;
      --INFECTED_CELL(1, 9) <= 0;
      --INFECTED_CELL(1, 10) <= 0;
      --INFECTED_CELL(1, 11) <= 0;
      --INFECTED_CELL(1, 12) <= 0;
      --INFECTED_CELL(1, 16) <= 0;
      --INFECTED_CELL(1, 17) <= 0;
      --INFECTED_CELL(1, 18) <= 0;
      --INFECTED_CELL(1, 19) <= 0;
      --INFECTED_CELL(1, 20) <= 0;
      --INFECTED_CELL(1, 21) <= 0;
      --INFECTED_CELL(1, 22) <= 0;
      --INFECTED_CELL(1, 23) <= 0;
      --INFECTED_CELL(1, 24) <= 0;
      --INFECTED_CELL(1, 25) <= 0;
      --INFECTED_CELL(1, 26) <= 0;
      --INFECTED_CELL(1, 27) <= 0;
      --INFECTED_CELL(1, 28) <= 0;
      --INFECTED_CELL(2, 0) <= 0;
      --INFECTED_CELL(2, 1) <= 0;
      --INFECTED_CELL(2, 2) <= 0;
      --INFECTED_CELL(2, 3) <= 0;
      --INFECTED_CELL(2, 4) <= 0;
      --INFECTED_CELL(2, 5) <= 0;
      --INFECTED_CELL(2, 6) <= 0;
      --INFECTED_CELL(2, 7) <= 0;
      --INFECTED_CELL(2, 8) <= 0;
      --INFECTED_CELL(2, 9) <= 0;
      --INFECTED_CELL(2, 10) <= 0;
      --INFECTED_CELL(2, 11) <= 0;
      --INFECTED_CELL(2, 17) <= 0;
      --INFECTED_CELL(2, 18) <= 0;
      --INFECTED_CELL(2, 19) <= 0;
      --INFECTED_CELL(2, 20) <= 0;
      --INFECTED_CELL(2, 21) <= 0;
      --INFECTED_CELL(2, 22) <= 0;
      --INFECTED_CELL(2, 23) <= 0;
      --INFECTED_CELL(2, 24) <= 0;
      --INFECTED_CELL(2, 25) <= 0;
      --INFECTED_CELL(2, 26) <= 0;
      --INFECTED_CELL(2, 27) <= 0;
      --INFECTED_CELL(2, 28) <= 0;
      --INFECTED_CELL(3, 0) <= 0;
      --INFECTED_CELL(3, 1) <= 0;
      --INFECTED_CELL(3, 2) <= 0;
      --INFECTED_CELL(3, 3) <= 0;
      --INFECTED_CELL(3, 4) <= 0;
      --INFECTED_CELL(3, 5) <= 0;
      --INFECTED_CELL(3, 6) <= 0;
      --INFECTED_CELL(3, 7) <= 0;
      --INFECTED_CELL(3, 8) <= 0;
      --INFECTED_CELL(3, 9) <= 0;
      --INFECTED_CELL(3, 10) <= 0;
      --INFECTED_CELL(3, 18) <= 0;
      --INFECTED_CELL(3, 19) <= 0;
      --INFECTED_CELL(3, 20) <= 0;
      --INFECTED_CELL(3, 21) <= 0;
      --INFECTED_CELL(3, 22) <= 0;
      --INFECTED_CELL(3, 23) <= 0;
      --INFECTED_CELL(3, 24) <= 0;
      --INFECTED_CELL(3, 25) <= 0;
      --INFECTED_CELL(3, 26) <= 0;
      --INFECTED_CELL(3, 27) <= 0;
      --INFECTED_CELL(3, 28) <= 0;
      --INFECTED_CELL(4, 0) <= 0;
      --INFECTED_CELL(4, 1) <= 0;
      --INFECTED_CELL(4, 2) <= 0;
      --INFECTED_CELL(4, 3) <= 0;
      --INFECTED_CELL(4, 4) <= 0;
      --INFECTED_CELL(4, 5) <= 0;
      --INFECTED_CELL(4, 6) <= 0;
      --INFECTED_CELL(4, 7) <= 0;
      --INFECTED_CELL(4, 8) <= 0;
      --INFECTED_CELL(4, 9) <= 0;
      --INFECTED_CELL(4, 19) <= 0;
      --INFECTED_CELL(4, 20) <= 0;
      --INFECTED_CELL(4, 21) <= 0;
      --INFECTED_CELL(4, 22) <= 0;
      --INFECTED_CELL(4, 23) <= 0;
      --INFECTED_CELL(4, 24) <= 0;
      --INFECTED_CELL(4, 25) <= 0;
      --INFECTED_CELL(4, 26) <= 0;
      --INFECTED_CELL(4, 27) <= 0;
      --INFECTED_CELL(4, 28) <= 0;
      --INFECTED_CELL(5, 0) <= 0;
      --INFECTED_CELL(5, 1) <= 0;
      --INFECTED_CELL(5, 2) <= 0;
      --INFECTED_CELL(5, 3) <= 0;
      --INFECTED_CELL(5, 4) <= 0;
      --INFECTED_CELL(5, 5) <= 0;
      --INFECTED_CELL(5, 6) <= 0;
      --INFECTED_CELL(5, 7) <= 0;
      --INFECTED_CELL(5, 8) <= 0;
      --INFECTED_CELL(5, 20) <= 0;
      --INFECTED_CELL(5, 21) <= 0;
      --INFECTED_CELL(5, 22) <= 0;
      --INFECTED_CELL(5, 23) <= 0;
      --INFECTED_CELL(5, 24) <= 0;
      --INFECTED_CELL(5, 25) <= 0;
      --INFECTED_CELL(5, 26) <= 0;
      --INFECTED_CELL(5, 27) <= 0;
      --INFECTED_CELL(5, 28) <= 0;
      --INFECTED_CELL(6, 0) <= 0;
      --INFECTED_CELL(6, 1) <= 0;
      --INFECTED_CELL(6, 2) <= 0;
      --INFECTED_CELL(6, 3) <= 0;
      --INFECTED_CELL(6, 4) <= 0;
      --INFECTED_CELL(6, 5) <= 0;
      --INFECTED_CELL(6, 6) <= 0;
      --INFECTED_CELL(6, 7) <= 0;
      --INFECTED_CELL(6, 21) <= 0;
      --INFECTED_CELL(6, 22) <= 0;
      --INFECTED_CELL(6, 23) <= 0;
      --INFECTED_CELL(6, 24) <= 0;
      --INFECTED_CELL(6, 25) <= 0;
      --INFECTED_CELL(6, 26) <= 0;
      --INFECTED_CELL(6, 27) <= 0;
      --INFECTED_CELL(6, 28) <= 0;
      --INFECTED_CELL(7, 0) <= 0;
      --INFECTED_CELL(7, 1) <= 0;
      --INFECTED_CELL(7, 2) <= 0;
      --INFECTED_CELL(7, 3) <= 0;
      --INFECTED_CELL(7, 4) <= 0;
      --INFECTED_CELL(7, 5) <= 0;
      --INFECTED_CELL(7, 6) <= 0;
      --INFECTED_CELL(7, 22) <= 0;
      --INFECTED_CELL(7, 23) <= 0;
      --INFECTED_CELL(7, 24) <= 0;
      --INFECTED_CELL(7, 25) <= 0;
      --INFECTED_CELL(7, 26) <= 0;
      --INFECTED_CELL(7, 27) <= 0;
      --INFECTED_CELL(7, 28) <= 0;
      --INFECTED_CELL(8, 0) <= 0;
      --INFECTED_CELL(8, 1) <= 0;
      --INFECTED_CELL(8, 2) <= 0;
      --INFECTED_CELL(8, 3) <= 0;
      --INFECTED_CELL(8, 4) <= 0;
      --INFECTED_CELL(8, 5) <= 0;
      --INFECTED_CELL(8, 23) <= 0;
      --INFECTED_CELL(8, 24) <= 0;
      --INFECTED_CELL(8, 25) <= 0;
      --INFECTED_CELL(8, 26) <= 0;
      --INFECTED_CELL(8, 27) <= 0;
      --INFECTED_CELL(8, 28) <= 0;
      --INFECTED_CELL(9, 0) <= 0;
      --INFECTED_CELL(9, 1) <= 0;
      --INFECTED_CELL(9, 2) <= 0;
      --INFECTED_CELL(9, 3) <= 0;
      --INFECTED_CELL(9, 4) <= 0;
      --INFECTED_CELL(9, 24) <= 0;
      --INFECTED_CELL(9, 25) <= 0;
      --INFECTED_CELL(9, 26) <= 0;
      --INFECTED_CELL(9, 27) <= 0;
      --INFECTED_CELL(9, 28) <= 0;
      --INFECTED_CELL(10, 0) <= 0;
      --INFECTED_CELL(10, 1) <= 0;
      --INFECTED_CELL(10, 2) <= 0;
      --INFECTED_CELL(10, 3) <= 0;
      --INFECTED_CELL(10, 25) <= 0;
      --INFECTED_CELL(10, 26) <= 0;
      --INFECTED_CELL(10, 27) <= 0;
      --INFECTED_CELL(10, 28) <= 0;
      --INFECTED_CELL(11, 0) <= 0;
      --INFECTED_CELL(11, 1) <= 0;
      --INFECTED_CELL(11, 2) <= 0;
      --INFECTED_CELL(11, 26) <= 0;
      --INFECTED_CELL(11, 27) <= 0;
      --INFECTED_CELL(11, 28) <= 0;
      --INFECTED_CELL(12, 0) <= 0;
      --INFECTED_CELL(12, 1) <= 0;
      --INFECTED_CELL(12, 27) <= 0;
      --INFECTED_CELL(12, 28) <= 0;
      --INFECTED_CELL(13, 0) <= 0;
      --INFECTED_CELL(13, 28) <= 0;
      --INFECTED_CELL(15, 0) <= 0;
      --INFECTED_CELL(15, 28) <= 0;
      --INFECTED_CELL(16, 0) <= 0;
      --INFECTED_CELL(16, 1) <= 0;
      --INFECTED_CELL(16, 27) <= 0;
      --INFECTED_CELL(16, 28) <= 0;
      --INFECTED_CELL(17, 0) <= 0;
      --INFECTED_CELL(17, 1) <= 0;
      --INFECTED_CELL(17, 2) <= 0;
      --INFECTED_CELL(17, 26) <= 0;
      --INFECTED_CELL(17, 27) <= 0;
      --INFECTED_CELL(17, 28) <= 0;
      --INFECTED_CELL(18, 0) <= 0;
      --INFECTED_CELL(18, 1) <= 0;
      --INFECTED_CELL(18, 2) <= 0;
      --INFECTED_CELL(18, 3) <= 0;
      --INFECTED_CELL(18, 25) <= 0;
      --INFECTED_CELL(18, 26) <= 0;
      --INFECTED_CELL(18, 27) <= 0;
      --INFECTED_CELL(18, 28) <= 0;
      --INFECTED_CELL(19, 0) <= 0;
      --INFECTED_CELL(19, 1) <= 0;
      --INFECTED_CELL(19, 2) <= 0;
      --INFECTED_CELL(19, 3) <= 0;
      --INFECTED_CELL(19, 4) <= 0;
      --INFECTED_CELL(19, 24) <= 0;
      --INFECTED_CELL(19, 25) <= 0;
      --INFECTED_CELL(19, 26) <= 0;
      --INFECTED_CELL(19, 27) <= 0;
      --INFECTED_CELL(19, 28) <= 0;
      --INFECTED_CELL(20, 0) <= 0;
      --INFECTED_CELL(20, 1) <= 0;
      --INFECTED_CELL(20, 2) <= 0;
      --INFECTED_CELL(20, 3) <= 0;
      --INFECTED_CELL(20, 4) <= 0;
      --INFECTED_CELL(20, 5) <= 0;
      --INFECTED_CELL(20, 23) <= 0;
      --INFECTED_CELL(20, 24) <= 0;
      --INFECTED_CELL(20, 25) <= 0;
      --INFECTED_CELL(20, 26) <= 0;
      --INFECTED_CELL(20, 27) <= 0;
      --INFECTED_CELL(20, 28) <= 0;
      --INFECTED_CELL(21, 0) <= 0;
      --INFECTED_CELL(21, 1) <= 0;
      --INFECTED_CELL(21, 2) <= 0;
      --INFECTED_CELL(21, 3) <= 0;
      --INFECTED_CELL(21, 4) <= 0;
      --INFECTED_CELL(21, 5) <= 0;
      --INFECTED_CELL(21, 6) <= 0;
      --INFECTED_CELL(21, 22) <= 0;
      --INFECTED_CELL(21, 23) <= 0;
      --INFECTED_CELL(21, 24) <= 0;
      --INFECTED_CELL(21, 25) <= 0;
      --INFECTED_CELL(21, 26) <= 0;
      --INFECTED_CELL(21, 27) <= 0;
      --INFECTED_CELL(21, 28) <= 0;
      --INFECTED_CELL(22, 0) <= 0;
      --INFECTED_CELL(22, 1) <= 0;
      --INFECTED_CELL(22, 2) <= 0;
      --INFECTED_CELL(22, 3) <= 0;
      --INFECTED_CELL(22, 4) <= 0;
      --INFECTED_CELL(22, 5) <= 0;
      --INFECTED_CELL(22, 6) <= 0;
      --INFECTED_CELL(22, 7) <= 0;
      --INFECTED_CELL(22, 21) <= 0;
      --INFECTED_CELL(22, 22) <= 0;
      --INFECTED_CELL(22, 23) <= 0;
      --INFECTED_CELL(22, 24) <= 0;
      --INFECTED_CELL(22, 25) <= 0;
      --INFECTED_CELL(22, 26) <= 0;
      --INFECTED_CELL(22, 27) <= 0;
      --INFECTED_CELL(22, 28) <= 0;
      --INFECTED_CELL(23, 0) <= 0;
      --INFECTED_CELL(23, 1) <= 0;
      --INFECTED_CELL(23, 2) <= 0;
      --INFECTED_CELL(23, 3) <= 0;
      --INFECTED_CELL(23, 4) <= 0;
      --INFECTED_CELL(23, 5) <= 0;
      --INFECTED_CELL(23, 6) <= 0;
      --INFECTED_CELL(23, 7) <= 0;
      --INFECTED_CELL(23, 8) <= 0;
      --INFECTED_CELL(23, 20) <= 0;
      --INFECTED_CELL(23, 21) <= 0;
      --INFECTED_CELL(23, 22) <= 0;
      --INFECTED_CELL(23, 23) <= 0;
      --INFECTED_CELL(23, 24) <= 0;
      --INFECTED_CELL(23, 25) <= 0;
      --INFECTED_CELL(23, 26) <= 0;
      --INFECTED_CELL(23, 27) <= 0;
      --INFECTED_CELL(23, 28) <= 0;
      --INFECTED_CELL(24, 0) <= 0;
      --INFECTED_CELL(24, 1) <= 0;
      --INFECTED_CELL(24, 2) <= 0;
      --INFECTED_CELL(24, 3) <= 0;
      --INFECTED_CELL(24, 4) <= 0;
      --INFECTED_CELL(24, 5) <= 0;
      --INFECTED_CELL(24, 6) <= 0;
      --INFECTED_CELL(24, 7) <= 0;
      --INFECTED_CELL(24, 8) <= 0;
      --INFECTED_CELL(24, 9) <= 0;
      --INFECTED_CELL(24, 19) <= 0;
      --INFECTED_CELL(24, 20) <= 0;
      --INFECTED_CELL(24, 21) <= 0;
      --INFECTED_CELL(24, 22) <= 0;
      --INFECTED_CELL(24, 23) <= 0;
      --INFECTED_CELL(24, 24) <= 0;
      --INFECTED_CELL(24, 25) <= 0;
      --INFECTED_CELL(24, 26) <= 0;
      --INFECTED_CELL(24, 27) <= 0;
      --INFECTED_CELL(24, 28) <= 0;
      --INFECTED_CELL(25, 0) <= 0;
      --INFECTED_CELL(25, 1) <= 0;
      --INFECTED_CELL(25, 2) <= 0;
      --INFECTED_CELL(25, 3) <= 0;
      --INFECTED_CELL(25, 4) <= 0;
      --INFECTED_CELL(25, 5) <= 0;
      --INFECTED_CELL(25, 6) <= 0;
      --INFECTED_CELL(25, 7) <= 0;
      --INFECTED_CELL(25, 8) <= 0;
      --INFECTED_CELL(25, 9) <= 0;
      --INFECTED_CELL(25, 10) <= 0;
      --INFECTED_CELL(25, 18) <= 0;
      --INFECTED_CELL(25, 19) <= 0;
      --INFECTED_CELL(25, 20) <= 0;
      --INFECTED_CELL(25, 21) <= 0;
      --INFECTED_CELL(25, 22) <= 0;
      --INFECTED_CELL(25, 23) <= 0;
      --INFECTED_CELL(25, 24) <= 0;
      --INFECTED_CELL(25, 25) <= 0;
      --INFECTED_CELL(25, 26) <= 0;
      --INFECTED_CELL(25, 27) <= 0;
      --INFECTED_CELL(25, 28) <= 0;
      --INFECTED_CELL(26, 0) <= 0;
      --INFECTED_CELL(26, 1) <= 0;
      --INFECTED_CELL(26, 2) <= 0;
      --INFECTED_CELL(26, 3) <= 0;
      --INFECTED_CELL(26, 4) <= 0;
      --INFECTED_CELL(26, 5) <= 0;
      --INFECTED_CELL(26, 6) <= 0;
      --INFECTED_CELL(26, 7) <= 0;
      --INFECTED_CELL(26, 8) <= 0;
      --INFECTED_CELL(26, 9) <= 0;
      --INFECTED_CELL(26, 10) <= 0;
      --INFECTED_CELL(26, 11) <= 0;
      --INFECTED_CELL(26, 17) <= 0;
      --INFECTED_CELL(26, 18) <= 0;
      --INFECTED_CELL(26, 19) <= 0;
      --INFECTED_CELL(26, 20) <= 0;
      --INFECTED_CELL(26, 21) <= 0;
      --INFECTED_CELL(26, 22) <= 0;
      --INFECTED_CELL(26, 23) <= 0;
      --INFECTED_CELL(26, 24) <= 0;
      --INFECTED_CELL(26, 25) <= 0;
      --INFECTED_CELL(26, 26) <= 0;
      --INFECTED_CELL(26, 27) <= 0;
      --INFECTED_CELL(26, 28) <= 0;
      --INFECTED_CELL(27, 0) <= 0;
      --INFECTED_CELL(27, 1) <= 0;
      --INFECTED_CELL(27, 2) <= 0;
      --INFECTED_CELL(27, 3) <= 0;
      --INFECTED_CELL(27, 4) <= 0;
      --INFECTED_CELL(27, 5) <= 0;
      --INFECTED_CELL(27, 6) <= 0;
      --INFECTED_CELL(27, 7) <= 0;
      --INFECTED_CELL(27, 8) <= 0;
      --INFECTED_CELL(27, 9) <= 0;
      --INFECTED_CELL(27, 10) <= 0;
      --INFECTED_CELL(27, 11) <= 0;
      --INFECTED_CELL(27, 12) <= 0;
      --INFECTED_CELL(27, 16) <= 0;
      --INFECTED_CELL(27, 17) <= 0;
      --INFECTED_CELL(27, 18) <= 0;
      --INFECTED_CELL(27, 19) <= 0;
      --INFECTED_CELL(27, 20) <= 0;
      --INFECTED_CELL(27, 21) <= 0;
      --INFECTED_CELL(27, 22) <= 0;
      --INFECTED_CELL(27, 23) <= 0;
      --INFECTED_CELL(27, 24) <= 0;
      --INFECTED_CELL(27, 25) <= 0;
      --INFECTED_CELL(27, 26) <= 0;
      --INFECTED_CELL(27, 27) <= 0;
      --INFECTED_CELL(27, 28) <= 0;
      --INFECTED_CELL(28, 0) <= 0;
      --INFECTED_CELL(28, 1) <= 0;
      --INFECTED_CELL(28, 2) <= 0;
      --INFECTED_CELL(28, 3) <= 0;
      --INFECTED_CELL(28, 4) <= 0;
      --INFECTED_CELL(28, 5) <= 0;
      --INFECTED_CELL(28, 6) <= 0;
      --INFECTED_CELL(28, 7) <= 0;
      --INFECTED_CELL(28, 8) <= 0;
      --INFECTED_CELL(28, 9) <= 0;
      --INFECTED_CELL(28, 10) <= 0;
      --INFECTED_CELL(28, 11) <= 0;
      --INFECTED_CELL(28, 12) <= 0;
      --INFECTED_CELL(28, 13) <= 0;
      --INFECTED_CELL(28, 15) <= 0;
      --INFECTED_CELL(28, 16) <= 0;
      --INFECTED_CELL(28, 17) <= 0;
      --INFECTED_CELL(28, 18) <= 0;
      --INFECTED_CELL(28, 19) <= 0;
      --INFECTED_CELL(28, 20) <= 0;
      --INFECTED_CELL(28, 21) <= 0;
      --INFECTED_CELL(28, 22) <= 0;
      --INFECTED_CELL(28, 23) <= 0;
      --INFECTED_CELL(28, 24) <= 0;
      --INFECTED_CELL(28, 25) <= 0;
      --INFECTED_CELL(28, 26) <= 0;
      --INFECTED_CELL(28, 27) <= 0;
      --INFECTED_CELL(28, 28) <= 0;
      
      FOR I IN 30 DOWNTO 1 LOOP 
         CURRENT_CELL(I) <= CURRENT_CELL(I-1);
      END LOOP;
      CURRENT_CELL(0) <= NEIGHBORHOOD_CELL(14, 14);
      ------------------------------------------------------------

      -- BINARY ADDER TREE FOR TOTAL INFECTED CELLS SUM ------------------
      FOR J IN NEIGHBORHOOD_SIZE-1 DOWNTO 0 LOOP
         -- LOOP FOR EACH COLUMN:
         FOR I IN (NEIGHBORHOOD_SIZE-1)/2 DOWNTO 1 LOOP -- 19 = 2*9 + 1, 9 SUM RESULTS
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

      -- STATE TRANSITION RULE -----------------------------------
      IF (CURRENT_CELL(10) > 0) THEN 
         IF CURRENT_CELL(10)+1 >= N-1 THEN
            DATA_OUT <= STD_LOGIC_VECTOR(TO_UNSIGNED(0, 4));
         ELSE
            DATA_OUT <= STD_LOGIC_VECTOR(TO_UNSIGNED(CURRENT_CELL(10)+1, 4));
         END IF;
      ELSIF (INFECTED_TOTAL_SUM >= T) THEN
         IF CURRENT_CELL(10)+1 >= N-1 THEN
            DATA_OUT <= STD_LOGIC_VECTOR(TO_UNSIGNED(0, 4));
         ELSE
            DATA_OUT <= STD_LOGIC_VECTOR(TO_UNSIGNED(CURRENT_CELL(10)+1, 4));
         END IF;
      ELSE  
         DATA_OUT <= STD_LOGIC_VECTOR(TO_UNSIGNED(CURRENT_CELL(10), 4));
      END IF;
      -- END OF STATE TRANSITION RULE ----------------------------
      
      -- DATA_VALID DENOTES THE VALID CELL CALUES TO BE WRITTEN BACK TO EXTERNAL MEM
      FOR I IN ((NEIGHBORHOOD_SIZE-1)/2)+12+0 DOWNTO 1 LOOP
         DATA_VALID_SIGNAL(I) <= DATA_VALID_SIGNAL(I-1);
      END LOOP;
      DATA_VALID_SIGNAL(0) <= READ_EN; 

   END PROCESS;

   DATA_OUT_VALID <= DATA_VALID_SIGNAL(((NEIGHBORHOOD_SIZE-1)/2)+12+0);	
      ------------------------------------------------------------
END BEHAVIORAL;
