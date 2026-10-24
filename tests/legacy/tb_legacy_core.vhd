-- Legacy core co-simulation: GRID_LINES_TOROIDAL_BUFFER + CA_ENGINE for one
-- generation of a small toroidal grid. The bottom-halo rows are loaded
-- through the legacy initialisation path (INIT_ROW/INIT_COLUMN), then the
-- frame rows are fed as the legacy memory read path would, one line at a
-- time and slow enough for the drain. Every engine output is written to
-- OUT_FILE, one decimal value per line, in raster order.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_legacy_core is
  generic (
    CELL_SIZE : integer := 8;
    NBH       : integer := 29;
    GRID_X    : integer := 64;
    GRID_Y    : integer := 64;
    IN_FILE   : string  := "bursts.hex";
    OUT_FILE  : string  := "cells.txt";
    COL_FILE  : string  := "");            -- optional dump of the buffer's valid columns
end tb_legacy_core;

architecture sim of tb_legacy_core is
  constant NB    : integer := GRID_X * CELL_SIZE / 128;
  constant R     : integer := (NBH - 1) / 2;
  constant PACE  : integer := 3 * (GRID_X + NBH) + 20;   -- CLK_200 cycles per line

  signal clk200, uiclk : std_logic := '0';
  signal rst           : std_logic := '1';
  signal init_complete : std_logic := '0';
  signal init_row      : integer range 0 to GRID_Y - 1 := 0;
  signal init_col      : integer range 0 to NB - 1 := 0;
  signal wdf_wren      : std_logic := '0';
  signal mem_wdata     : std_logic_vector(127 downto 0) := (others => '0');
  signal write_en      : std_logic := '0';
  signal granted       : std_logic := '0';
  signal din           : std_logic_vector(127 downto 0) := (others => '0');
  signal dout          : std_logic_vector(NBH * CELL_SIZE - 1 downto 0);
  signal dvalid        : std_logic;
  signal cell          : std_logic_vector(CELL_SIZE - 1 downto 0);
  signal cell_vld      : std_logic;

  type bursts_t is array (0 to GRID_Y * NB - 1) of std_logic_vector(127 downto 0);
begin
  clk200 <= not clk200 after 2.5 ns;
  uiclk  <= not uiclk after 6.15 ns;

  i_buf : entity work.GRID_LINES_TOROIDAL_BUFFER
    generic map (CELL_SIZE => CELL_SIZE, BURST_SIZE => 128, GRID_X => GRID_X, GRID_Y => GRID_Y,
                 NUMBER_OF_BURSTS_PER_LINE => NB, NEIGHBORHOOD_SIZE => NBH, SPEED => 60)
    port map (CLK_200 => clk200, UI_CLK => uiclk, RST_UI_CLK => rst, RST_200 => rst,
              WRITE_BACK_COLUMN => 0, WRITE_BACK_ROW => 0, INIT_COLUMN => init_col, INIT_ROW => init_row,
              INIT_COMPLETE => init_complete, SIM_ENDED => '0', SPEED_COUNTER => 0, SPEED_SETTING => 0,
              MEM_WRITE_DATA => mem_wdata, APP_WDF_WREN => wdf_wren, WRITE_EN => write_en, DATA_IN => din,
              MEMORY_ACCESS_GRANTED => granted, DATA_OUT => dout, DATA_OUT_VALID => dvalid);

  i_eng : entity work.CA_ENGINE
    generic map (CELL_SIZE => CELL_SIZE, NEIGHBORHOOD_SIZE => NBH)
    port map (CLK => clk200, RST => rst, READ_EN => dvalid, DATA_IN => dout,
              DATA_OUT => cell, DATA_OUT_VALID => cell_vld);

  stimulus : process
    file f        : text open read_mode is IN_FILE;
    variable l    : line;
    variable bv   : std_logic_vector(127 downto 0);
    variable mem  : bursts_t;
  begin
    for i in mem'range loop
      readline(f, l);
      hread(l, bv);
      mem(i) := bv;
    end loop;
    wait for 100 ns;
    wait until rising_edge(uiclk);
    rst <= '0';
    for k in 1 to 10 loop wait until rising_edge(uiclk); end loop;
    -- Bottom halo through the initialisation path.
    for y in GRID_Y - R to GRID_Y - 1 loop
      for b in 0 to NB - 1 loop
        init_row  <= y;
        init_col  <= b;
        mem_wdata <= mem(y * NB + b);
        wdf_wren  <= '1';
        wait until rising_edge(uiclk);
      end loop;
    end loop;
    wdf_wren <= '0';
    wait until rising_edge(uiclk);
    init_complete <= '1';
    -- The frame, as returned by the legacy memory reads.
    granted <= '1';
    for y in 0 to GRID_Y - 1 loop
      for b in 0 to NB - 1 loop
        din      <= mem(y * NB + b);
        write_en <= '1';
        wait until rising_edge(uiclk);
      end loop;
      write_en <= '0';
      for k in 1 to PACE loop wait until rising_edge(clk200); end loop;
      wait until rising_edge(uiclk);
    end loop;
    wait;
  end process;

  columns : process
    file f     : text;
    variable l : line;
  begin
    if COL_FILE'length = 0 then
      wait;
    end if;
    file_open(f, COL_FILE, write_mode);
    loop
      wait until rising_edge(clk200);
      if dvalid = '1' and rst = '0' then
        for i in 0 to NBH - 1 loop
          hwrite(l, dout((i + 1) * CELL_SIZE - 1 downto i * CELL_SIZE));
          write(l, string'(" "));
        end loop;
        writeline(f, l);
      end if;
    end loop;
  end process;

  collect : process
    file f     : text open write_mode is OUT_FILE;
    variable l : line;
    variable n : integer := 0;
  begin
    wait until rising_edge(clk200);
    if cell_vld = '1' and rst = '0' then
      assert not is_x(dout) report "X in the neighbourhood column" severity failure;
      write(l, to_integer(unsigned(cell)));
      writeline(f, l);
      n := n + 1;
      if n = GRID_X * GRID_Y then
        report "TB_PASS cells=" & integer'image(n);
        std.env.finish;
      end if;
    end if;
  end process;
end sim;
