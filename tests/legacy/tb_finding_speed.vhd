-- Finding 1: GRAPHICS_FEEDER and WRITE_BACK each keep a speed counter and a
-- buffer-select bit (APP_ADDR(20)) and evaluate them at their own end of
-- frame. Changing SPEED_SETTING between the two events (an "up" button press)
-- leaves both on the same buffer. Correct operation keeps the bits opposite.
library ieee;
use ieee.std_logic_1164.all;

entity tb_finding_speed is end;

architecture sim of tb_finding_speed is
  constant NB : integer := 2;
  constant NROWS : integer := 2;
  signal clk, rst : std_logic := '0';
  signal g_grant, w_grant, rdy, wdf_rdy, fifo_ready : std_logic := '0';
  signal speed : integer range 0 to 60 := 2;
  signal g_addr, w_addr : std_logic_vector(26 downto 0);
  signal g_en, w_en, w_rd, w_wren, w_end : std_logic;
  signal g_cmd, w_cmd : std_logic_vector(2 downto 0);
  signal w_data : std_logic_vector(127 downto 0);
  signal w_spd : integer range 0 to 60;
  signal w_col : integer range 0 to NB;
  signal w_row : integer range 0 to NROWS - 1;
begin
  clk <= not clk after 5 ns;

  i_gfx : entity work.GRAPHICS_FEEDER
    generic map (MEMORY_ADDRESS_WIDTH => 27, GRID_Y => NROWS, NUMBER_OF_BURSTS_PER_LINE => NB, SPEED => 60)
    port map (CLK => clk, RST => rst, MEM_ACCESS_GRANTED => g_grant, SPEED_SETTING => speed,
              APP_RDY => rdy, APP_ADDR => g_addr, APP_EN => g_en, APP_CMD => g_cmd);

  i_wb : entity work.WRITE_BACK
    generic map (CELL_SIZE => 8, MEMORY_ADDRESS_WIDTH => 27, NUMBER_OF_ROWS => NROWS, NEIGHBORHOOD_SIZE => 3,
                 GRID_TYPE => "TOROIDAL", NUMBER_OF_BURSTS_PER_LINE => NB, BURST_SIZE => 128, SPEED => 60)
    port map (CLK => clk, RST => rst, MEM_ACCESS_GRANTED => w_grant, FIFO_DATA => (others => '0'),
              FIFO_READ_EN => w_rd, FIFO_READY => fifo_ready, SPEED_SETTING => speed, WB_SPEED_COUNTER => w_spd,
              COLUMN_BEING_WRITTEN => w_col, ROW_BEING_WRITTEN => w_row, APP_RDY => rdy,
              APP_WDF_RDY => wdf_rdy, APP_EN => w_en, APP_CMD => w_cmd, APP_WDF_DATA => w_data,
              APP_WDF_END => w_end, APP_WDF_WREN => w_wren, APP_ADDR => w_addr);

  process
    variable words : integer := 0;
  begin
    rst <= '1';
    for k in 1 to 3 loop wait until falling_edge(clk); end loop;
    rst <= '0';
    rdy <= '1';
    wait until falling_edge(clk);
    assert g_addr(20) /= w_addr(20) report "buffer selects equal after reset" severity failure;
    -- One displayed frame: per line, grant until its commands are issued, then release.
    for line in 1 to NROWS loop
      g_grant <= '1';
      for k in 1 to 6 loop wait until falling_edge(clk); end loop;
      g_grant <= '0';
      for k in 1 to 4 loop wait until falling_edge(clk); end loop;
    end loop;
    -- "Up" pressed after the graphics end of frame, before the write-back one.
    speed <= 0;
    -- The write-back finishes the frame: NROWS * NB bursts, one FIFO word per
    -- completed command (the legacy counters assume the engine is slower than
    -- the write path; faster words overflow BURSTS_RECEIVED_FROM_FIFO_COUNTER).
    w_grant <= '1';
    wdf_rdy <= '1';
    while words < NROWS * NB loop
      fifo_ready <= '1';
      loop
        wait until rising_edge(clk);
        exit when w_rd = '1' and fifo_ready = '1';
      end loop;
      fifo_ready <= '0';
      words := words + 1;
      loop
        wait until rising_edge(clk);
        exit when w_en = '1' and rdy = '1';
      end loop;
    end loop;
    for k in 1 to 20 loop wait until falling_edge(clk); end loop;
    if g_addr(20) = w_addr(20) then
      report "FINDING1 CONFIRMED: reader and writer both select buffer " & std_logic'image(g_addr(20)) &
             " after SPEED_SETTING changed between the two end-of-frame events";
    else
      report "FINDING1 NOT_REPRODUCED: reader " & std_logic'image(g_addr(20)) & ", writer " &
             std_logic'image(w_addr(20));
    end if;
    std.env.finish;
  end process;
end sim;
