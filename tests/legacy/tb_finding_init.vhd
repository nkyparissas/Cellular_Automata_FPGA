-- Finding 2: MEMORY_INITIALIZER pushes a third write-data beat when
-- APP_WDF_RDY drops while it is in WRITING_3. The burst should be written
-- twice (once per frame buffer), so two accepted beats are expected.
library ieee;
use ieee.std_logic_1164.all;

entity tb_finding_init is end;

architecture sim of tb_finding_init is
  signal clk, rst, done, rd_en, en, wdf_end, wren : std_logic := '0';
  signal empty : std_logic := '0';
  signal rdy, wdf_rdy : std_logic := '1';
  signal fifo_data : std_logic_vector(127 downto 0) := (others => '1');
  signal cmd : std_logic_vector(2 downto 0);
  signal wdata : std_logic_vector(127 downto 0);
  signal addr : std_logic_vector(26 downto 0);
  signal col : integer range 0 to 2;
  signal row : integer range 0 to 1;
begin
  clk <= not clk after 5 ns;
  dut : entity work.MEMORY_INITIALIZER
    generic map (CELL_SIZE => 8, BURST_SIZE => 128, NUMBER_OF_BURSTS_PER_LINE => 2, GRID_Y => 2,
                 MEMORY_ADDR_WIDTH => 27)
    port map (CLK => clk, RST => rst, INIT_COMPLETE => done, FIFO_DATA => fifo_data, FIFO_READ_EN => rd_en,
              FIFO_EMPTY => empty, COLUMN_BEING_WRITTEN => col, ROW_BEING_WRITTEN => row,
              APP_RDY => rdy, APP_WDF_RDY => wdf_rdy, APP_EN => en, APP_CMD => cmd,
              APP_WDF_DATA => wdata, APP_WDF_END => wdf_end, APP_WDF_WREN => wren, APP_ADDR => addr);

  process
    variable beats : integer := 0;
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    -- Run until the first beat of the first burst is accepted.
    loop
      wait until rising_edge(clk);
      if wren = '1' and wdf_rdy = '1' then
        beats := beats + 1;
        exit;
      end if;
    end loop;
    -- The FSM is now in WRITING_3: withhold APP_WDF_RDY for one cycle.
    wdf_rdy <= '0';
    wait until rising_edge(clk);
    wdf_rdy <= '1';
    -- Count accepted beats until the command phase starts.
    loop
      wait until falling_edge(clk);
      exit when en = '1';
      if wren = '1' and wdf_rdy = '1' then
        beats := beats + 1;
      end if;
    end loop;
    if beats > 2 then
      report "FINDING2 CONFIRMED: " & integer'image(beats) & " write-data beats for one burst (2 expected)";
    else
      report "FINDING2 NOT_REPRODUCED: " & integer'image(beats) & " beats";
    end if;
    std.env.finish;
  end process;
end sim;
